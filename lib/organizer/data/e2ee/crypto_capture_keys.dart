import 'dart:convert';
import 'dart:typed_data';

import 'package:sodium/sodium.dart' show KeyPair;

import 'account_crypto_v2_workflow.dart';
import 'account_directory_v2.dart' show cryptoSha256, VerifiedAccountDirectory;
import 'crypto_account_archive.dart';
import 'crypto_inventory_json.dart';
import 'crypto_json.dart';
import 'crypto_record_address.dart';
import 'crypto_sync_repository.dart';

class CryptoCaptureKeyDescriptor {
  CryptoCaptureKeyDescriptor({
    required this.captureId,
    required this.migrationId,
    required this.keyId,
    required this.rootScopeId,
    required this.componentId,
    required List<String> scopeIds,
    required List<Map<String, dynamic>> receiptSelections,
  }) : scopeIds = List.unmodifiable(scopeIds),
       receiptSelections = List.unmodifiable(
         receiptSelections.map((s) => Map<String, dynamic>.unmodifiable(s)),
       ) {
    if (![
          captureId,
          migrationId,
          keyId,
          rootScopeId,
          componentId,
        ].every(isCryptoCanonicalUuid) ||
        scopeIds.length > 1000 ||
        receiptSelections.length > 2000 ||
        scopeIds.any((id) => !isCryptoCanonicalUuid(id))) {
      throw const FormatException('crypto_capture_key_context');
    }
    for (var i = 1; i < scopeIds.length; i++) {
      if (scopeIds[i - 1].compareTo(scopeIds[i]) >= 0) {
        throw const FormatException('crypto_capture_key_context');
      }
    }
    String? previous;
    for (final selection in receiptSelections) {
      if (selection.length != 2 ||
          !isCryptoCanonicalUuid(selection['scopeId']) ||
          !const ['content', 'finance'].contains(selection['domain'])) {
        throw const FormatException('crypto_capture_receipt_selection');
      }
      final order = '${selection['scopeId']}/${selection['domain']}';
      if (previous != null && previous.compareTo(order) >= 0) {
        throw const FormatException('crypto_capture_receipt_selection');
      }
      previous = order;
    }
  }
  factory CryptoCaptureKeyDescriptor.fromJson(Map value) {
    try {
      if ((value.containsKey('captureVersion') &&
              value['captureVersion'] != 3) ||
          (value.containsKey('version') && value['version'] != 3)) {
        throw const FormatException('crypto_capture_version');
      }
      return CryptoCaptureKeyDescriptor(
        captureId: value['captureId'] as String,
        migrationId: value['migrationId'] as String,
        keyId: value['keyId'] as String,
        rootScopeId: value['rootScopeId'] as String,
        componentId: value['componentId'] as String,
        scopeIds: (value['scopeIds'] as List).cast<String>(),
        receiptSelections: (value['receiptSelections'] as List)
            .map((s) => Map<String, dynamic>.from(s as Map))
            .toList(),
      );
    } on TypeError {
      throw const FormatException('crypto_capture_key_context');
    }
  }
  final String captureId, migrationId, keyId, rootScopeId, componentId;
  final List<String> scopeIds;
  final List<Map<String, dynamic>> receiptSelections;
  Map<String, dynamic> toJson() => {
    'captureVersion': 3,
    'captureId': captureId,
    'migrationId': migrationId,
    'keyId': keyId,
    'rootScopeId': rootScopeId,
    'componentId': componentId,
    'scopeIds': scopeIds,
    'receiptSelections': receiptSelections,
  };
}

/// Capture comparison secrets are account-private, physically protected locally,
/// and recovery-wrapped BEFORE any source binding is allowed onto the network.
/// A copied SQL `wrapped` flag is never proof: the signed account directory must
/// contain the exact device and recovery envelopes on every resumed ensure.
class CryptoCaptureKeyService {
  CryptoCaptureKeyService(this.account);
  final AccountCryptoV2Workflow account;
  static final _pending = <String, Future<void>>{};

  Future<Map<String, dynamic>> context(
    CryptoCaptureKeyDescriptor value,
  ) async => {
    'version': 3,
    'kind': 'accountCaptureKey',
    'serverId': account.directory.session.profile.serverId,
    'accountId': account.directory.accountId,
    'captureId': value.captureId,
    'migrationId': value.migrationId,
    'keyId': value.keyId,
    'rootScopeId': value.rootScopeId,
    'componentId': value.componentId,
    'selectionContextHash': await cryptoSha256([
      ...utf8.encode('JivieCaptureKeyContext/v3\n'),
      ...CryptoInventoryJson.encode(value.toJson()),
    ]),
  };

  Future<CryptoCaptureKeyDescriptor> ensure({
    required String captureId,
    required String migrationId,
  }) => _serializedEnsure(captureId, migrationId, null);

  /// Only a genuinely new random capture may generate key material. Resuming
  /// an existing capture after losing SQL must use its original descriptor and
  /// open(), never silently replace the HMAC key and comparison salts.
  Future<CryptoCaptureKeyDescriptor> create({
    required String migrationId,
    required String rootScopeId,
    required String componentId,
    required List<String> scopeIds,
    required List<Map<String, dynamic>> receiptSelections,
  }) {
    final crypto = account.directory.reducer.crypto;
    final descriptor = CryptoCaptureKeyDescriptor(
      captureId: crypto.randomId(),
      migrationId: migrationId,
      keyId: crypto.randomId(),
      rootScopeId: rootScopeId,
      componentId: componentId,
      scopeIds: scopeIds,
      receiptSelections: receiptSelections,
    );
    return _serializedEnsure(descriptor.captureId, migrationId, descriptor);
  }

  Future<CryptoCaptureKeyDescriptor> _serializedEnsure(
    String captureId,
    String migrationId,
    CryptoCaptureKeyDescriptor? creation,
  ) async {
    final partition = account.store.partition;
    final prior = _pending[partition] ?? Future<void>.value();
    final operation = prior.then(
      (_) => _ensure(captureId, migrationId, creation),
    );
    final marker = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    _pending[partition] = marker;
    try {
      return await operation;
    } finally {
      if (identical(_pending[partition], marker)) {
        _pending.remove(partition);
      }
    }
  }

  Future<CryptoCaptureKeyDescriptor> _ensure(
    String captureId,
    String migrationId,
    CryptoCaptureKeyDescriptor? creation,
  ) async {
    if (!isCryptoCanonicalUuid(captureId) ||
        !isCryptoCanonicalUuid(migrationId)) {
      throw const FormatException('crypto_capture_key_context');
    }
    final db = account.store.database, partition = account.store.partition;
    final crypto = account.directory.reducer.crypto;
    var rows = await db.rows(
      'SELECT * FROM crypto_capture_keys WHERE partition=? AND capture_id=?',
      [partition, captureId],
    );
    if (rows.isEmpty) {
      if (creation == null) {
        throw const CryptoAuthorityPending(
          'crypto_capture_original_key_required',
        );
      }
      final descriptor = creation;
      final raw = crypto.sodium.randombytes.buf(32);
      try {
        await db.execute(
          "INSERT INTO crypto_capture_keys(partition,capture_id,migration_id,key_id,key_bytes,context,state) VALUES(?,?,?,?,?,?,'draft')",
          [
            partition,
            captureId,
            migrationId,
            descriptor.keyId,
            raw,
            CryptoInventoryJson.canonical(descriptor.toJson()),
          ],
        );
      } finally {
        raw.fillRange(0, raw.length, 0);
      }
      rows = await db.rows(
        'SELECT * FROM crypto_capture_keys WHERE partition=? AND capture_id=?',
        [partition, captureId],
      );
    }
    final row = rows.single;
    final descriptor = CryptoCaptureKeyDescriptor.fromJson(
      jsonDecode(row['context'] as String) as Map,
    );
    if (row['migration_id'] != migrationId ||
        row['context'] !=
            CryptoInventoryJson.canonical(descriptor.toJson())) {
      throw const FormatException('crypto_capture_key_conflict');
    }
    final directory = await account.directory.requireFresh();
    late List<Map<String, dynamic>> envelopes;
    if (row['envelopes'] != null) {
      envelopes = (jsonDecode(row['envelopes'] as String) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } else {
      if (row['key_bytes'] == null) {
        throw const CryptoAuthorityPending('crypto_capture_key_missing');
      }
      final raw = Uint8List.fromList((row['key_bytes'] as List).cast<int>());
      final key = crypto.sodium.secureCopy(raw);
      raw.fillRange(0, raw.length, 0);
      try {
        envelopes = [
          for (final recipient in [
            {
              'kind': 'device',
              'id': account.deviceId,
              'public': directory.activeDevice(
                account.deviceId,
              )['encryptionKeyBase64'],
            },
            {
              'kind': 'recovery',
              'id': directory.snapshot['recoveryRootEpochId'],
              'public': directory.snapshot['rootEncryptionKeyBase64'],
            },
          ])
            {
              'id': descriptor.keyId,
              'recipientKind': recipient['kind'],
              'recipientId': recipient['id'],
              'recipientPublicKeyBase64': recipient['public'],
              'sealedEnvelopeBase64': crypto.sealKey(
                key: key,
                recipientPublicKey: cryptoBase64(
                  recipient['public'],
                  length: 32,
                ),
                context: await context(descriptor),
              ),
            },
        ];
        // Random sealed boxes are durable before the first append. A timeout
        // resumes these exact bytes and never creates a second capture key.
        await db.execute(
          'UPDATE crypto_capture_keys SET envelopes=? WHERE partition=? AND capture_id=? AND envelopes IS NULL',
          [jsonEncode(envelopes), partition, captureId],
        );
      } finally {
        key.dispose();
      }
    }
    final hashes = <String, String>{};
    for (final envelope in envelopes) {
      hashes[envelope['sealedEnvelopeBase64'] as String] = await cryptoSha256(
        cryptoBase64(envelope['sealedEnvelopeBase64']),
      );
    }
    bool included(value) => envelopes.every(
      (e) => value.keyringEntries.any(
        (known) =>
            known['id'] == descriptor.keyId &&
            known['recipientKind'] == e['recipientKind'] &&
            known['recipientId'] == e['recipientId'] &&
            known['recipientPublicKeyBase64'] ==
                e['recipientPublicKeyBase64'] &&
            known['envelopeHash'] == hashes[e['sealedEnvelopeBase64']],
      ),
    );
    if (!included(directory)) {
      await account.appendKeyringEntries(envelopes);
    }
    if (!included(await account.directory.cachedVerifiedDirectory())) {
      throw const CryptoAuthorityPending('crypto_capture_recovery_pending');
    }
    await db.execute(
      "UPDATE crypto_capture_keys SET key_bytes=NULL,state='wrapped' WHERE partition=? AND capture_id=?",
      [partition, captureId],
    );
    return descriptor;
  }

  /// Works with a fresh encrypted SQL installation and only an authenticated
  /// account directory plus transient keys opened from the original file.
  Future<CryptoKeyLease> open(
    CryptoCaptureKeyDescriptor value, {
    Future<KeyPair?> Function(String publicKeyBase64)? recoveryKey,
    bool recoveryOnly = false,
    VerifiedAccountDirectory? recoveryDirectory,
  }) async {
    final rows = await account.store.database.rows(
      'SELECT envelopes FROM crypto_capture_keys WHERE partition=? AND capture_id=? AND migration_id=? AND key_id=?',
      [
        account.store.partition,
        value.captureId,
        value.migrationId,
        value.keyId,
      ],
    );
    return CryptoAccountArchiveKeyService(account).openBoundKey(
      keyId: value.keyId,
      expectedContext: await context(value),
      localEnvelopes: [
        if (rows.isNotEmpty && rows.single['envelopes'] != null)
          ...(jsonDecode(rows.single['envelopes'] as String) as List).map(
            (e) => Map<String, dynamic>.from(e as Map),
          ),
      ],
      recoveryKey: recoveryKey,
      recoveryOnly: recoveryOnly,
      recoveryDirectory: recoveryDirectory,
    );
  }
}
