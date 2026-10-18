import 'account_crypto_store.dart';
import 'dart:convert';

import '../collaboration_database.dart';
import '../device_session_store.dart';
import '../../domain/collaboration_models.dart';
import 'account_directory_v2.dart' show cryptoSha256;
import 'crypto_sync_repository.dart';

/// An original installation's unfinished upload, never a general plaintext
/// route. Only the original begin ID/body and its bounded continuation qualify.
class CryptoLegacyUploadDrain {
  CryptoLegacyUploadDrain._(
    this.db,
    this.secure,
    this.session,
    this.scope,
    this.name,
    this.id,
    this.body,
  );
  final CollaborationDatabase db;
  final AccountCryptoStore secure;
  final DeviceSession session;
  final String scope, name, id;
  final Map<String, Object?> body;
  int? _offset;
  static String _marker(String p, String scope) =>
      'migration_legacy_uploads:$p:$scope';

  /// This runs before a new capture exists. Missing old bytes require the user
  /// to reselect the exact original file through the ordinary upload picker.
  static Future<void> beforeCapture(
    CollaborationDatabase db,
    DeviceSession session,
    String scope,
    AccountCryptoStore secure,
  ) async {
    if (await secure.read('scope2:${session.profile.partition}:$scope') !=
        null) {
      throw const CryptoAuthorityPending(
        'crypto_migration_legacy_drain_forbidden',
      );
    }
    final p = session.profile.partition,
        prefix =
            'document_request:$p:${session.profile.deviceId}:$scope:attachments.begin:';
    final rows = await db.rows(
      'SELECT name,value FROM local_meta WHERE substr(name,1,?)=? ORDER BY name LIMIT 257',
      [prefix.length, prefix],
    );
    if (rows.isEmpty) return;
    if (rows.length > 256) {
      throw const CryptoAuthorityPending('crypto_migration_pending_upload');
    }
    final active = await db.rows(
      'SELECT 1 FROM crypto_capture_runs WHERE partition=? AND root_scope_id=?',
      [p, scope],
    );
    if (active.isNotEmpty) {
      throw const CryptoAuthorityPending('crypto_migration_pending_upload');
    }
    final encoded = jsonEncode({
      'version': 1,
      'scopeId': scope,
      'requests': rows,
    });
    await db.execute(
      'INSERT INTO local_meta VALUES(?,?) ON CONFLICT(name) DO UPDATE SET value=excluded.value',
      [_marker(p, scope), encoded],
    );
    throw const CryptoAuthorityPending('crypto_migration_pending_upload');
  }

  static Future<CryptoLegacyUploadDrain?> begin(
    CollaborationDatabase db,
    DeviceSession session,
    String scope,
    Map<String, Object?> params,
    Future<AccountCryptoStore> Function() secureStore,
  ) async {
    final p = session.profile.partition;
    final markers = await db.rows('SELECT value FROM local_meta WHERE name=?', [
      _marker(p, scope),
    ]);
    if (markers.length != 1) return null;
    final body = {
      for (final e in params.entries)
        if (e.key != 'id' && e.key != 'requestId') e.key: e.value,
    };
    final hash = await cryptoSha256(utf8.encode(jsonEncode(body)));
    final name =
        'document_request:$p:${session.profile.deviceId}:$scope:attachments.begin:$hash';
    final marker = jsonDecode(markers.single['value'] as String) as Map;
    if (marker['version'] != 1 ||
        marker['scopeId'] != scope ||
        marker['requests'] is! List) {
      return null;
    }
    final matches = (marker['requests'] as List)
        .where(
          (r) => r is Map && r['name'] == name && r['value'] == params['id'],
        )
        .toList();
    if (matches.length != 1 ||
        params['id'] != params['requestId'] ||
        body['size'] is! int ||
        body['size'] as int <= 0 ||
        body['size'] as int > 20 * 1024 * 1024 ||
        body['sha256'] is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(body['sha256'] as String)) {
      return null;
    }
    final secure = await secureStore();
    final result = CryptoLegacyUploadDrain._(
      db,
      secure,
      session,
      scope,
      name,
      params['id'] as String,
      Map.unmodifiable(body),
    );
    await result.authorize('attachments.begin', params);
    return result;
  }

  Future<void> authorize(String operation, Map<String, Object?> params) async {
    final p = session.profile.partition;
    if (await secure.read('scope2:$p:$scope') != null) {
      throw const CryptoAuthorityPending(
        'crypto_migration_legacy_drain_forbidden',
      );
    }
    final pending = await db.rows('SELECT value FROM local_meta WHERE name=?', [
      name,
    ]);
    final floors = await db.rows(
      "SELECT 1 FROM crypto_scope_state WHERE partition=? AND scope_id=? AND (floor>0 OR state IN ('active','committed','retired','fenced','verified')) LIMIT 1",
      [p, scope],
    );
    final captures = await db.rows(
      'SELECT 1 FROM crypto_capture_runs WHERE partition=? AND root_scope_id=?',
      [p, scope],
    );
    final fences = await db.rows(
      "SELECT 1 FROM crypto_restore_fences WHERE partition=? AND state<>'verified' LIMIT 1",
      [p],
    );
    if (pending.length != 1 ||
        pending.single['value'] != id ||
        floors.isNotEmpty ||
        captures.isNotEmpty ||
        fences.isNotEmpty ||
        params['scopeId'] != scope ||
        params['id'] != id) {
      throw const CryptoAuthorityPending(
        'crypto_migration_legacy_drain_forbidden',
      );
    }
    for (final key in ['targetType', 'targetId']) {
      if (params[key] != body[key]) {
        throw const FormatException('crypto_migration_legacy_drain_binding');
      }
    }
    if (operation == 'attachments.begin') {
      final original = {
        for (final e in params.entries)
          if (e.key != 'id' && e.key != 'requestId') e.key: e.value,
      };
      if (jsonEncode(original) != jsonEncode(body) ||
          params['requestId'] != id) {
        throw const FormatException('crypto_migration_legacy_drain_binding');
      }
    } else if (operation == 'attachments.chunk') {
      const keys = {
        'scopeId',
        'targetType',
        'targetId',
        'id',
        'offset',
        'dataBase64',
      };
      final bytes = base64Decode(params['dataBase64'] as String);
      try {
        if (params.length != keys.length ||
            !params.keys.every(keys.contains) ||
            _offset == null ||
            params['offset'] != _offset ||
            bytes.isEmpty ||
            bytes.length > 256 * 1024 ||
            _offset! + bytes.length > (body['size'] as int)) {
          throw const FormatException('crypto_migration_legacy_drain_chunk');
        }
      } finally {
        bytes.fillRange(0, bytes.length, 0);
      }
    } else if (operation == 'attachments.complete') {
      const keys = {'scopeId', 'targetType', 'targetId', 'id', 'requestId'};
      if (params.length != keys.length ||
          !params.keys.every(keys.contains) ||
          _offset != body['size']) {
        throw const FormatException('crypto_migration_legacy_drain_binding');
      }
      final suffix = await cryptoSha256(utf8.encode(jsonEncode({'id': id})));
      final original = await db.rows(
        'SELECT value FROM local_meta WHERE name=?',
        [
          'document_request:$p:${session.profile.deviceId}:$scope:attachments.complete:$suffix',
        ],
      );
      if (original.length != 1 ||
          original.single['value'] != params['requestId']) {
        throw const FormatException('crypto_migration_legacy_drain_binding');
      }
    } else {
      throw const FormatException('crypto_migration_legacy_drain_operation');
    }
  }

  void accept(Map<String, dynamic> result) {
    final a = result['attachment'];
    if (a is! Map ||
        a['id'] != id ||
        a['sha256'] != body['sha256'] ||
        a['size'] != body['size'] ||
        a['offset'] is! int ||
        a['offset'] < 0 ||
        a['offset'] > body['size']) {
      throw const CollaborationException('invalid_response');
    }
    _offset = a['offset'];
  }
}
