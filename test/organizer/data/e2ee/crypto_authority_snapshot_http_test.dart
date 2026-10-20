import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_repository.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_router.dart';
import 'package:kanban/organizer/data/e2ee/crypto_identity_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_lifecycle_evidence.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:sodium/sodium.dart';

class _Secure implements AccountCryptoStore {
  _Secure(this.file) {
    if (file.existsSync()) {
      values.addAll((jsonDecode(file.readAsStringSync()) as Map).cast());
    }
  }
  final File file;
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
    await file.writeAsString(jsonEncode(values), flush: true);
  }
}

class _MeasuredHttp extends HttpCollaborationTransport {
  bool snapshots = false, forgeHead = false;
  int forged = 0;
  final operations = <String>[];
  int resultBytes = 0, largestResult = 0;
  void reset() {
    operations.clear();
    resultBytes = 0;
    largestResult = 0;
  }

  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    // Models a pre-upgrade server without spending a synthetic HTTP request.
    if (!snapshots && operation == 'crypto2.authority.snapshot') {
      throw const CollaborationApiException('unsupported_operation');
    }
    operations.add(operation);
    final result = await super.call(
      serverUrl: serverUrl,
      operation: operation,
      params: params,
      token: token,
      allowLocalHttp: allowLocalHttp,
    );
    final bytes = utf8.encode(jsonEncode(result)).length;
    resultBytes += bytes;
    if (bytes > largestResult) largestResult = bytes;
    if (forgeHead && operation == 'crypto2.authority.snapshot') {
      for (final entry in result['entries'] as List) {
        if (entry['operation'] == 'crypto2.scope.headGet' &&
            entry['result'] is Map) {
          final authorization = entry['result']['authorization'] as Map;
          authorization['signatureBase64'] = base64Encode(List.filled(64, 0));
          forged++;
        }
      }
    }
    return result;
  }
}

DeviceSession _session(String url, Map wire) {
  final user = wire['user'] as Map, device = wire['device'] as Map;
  return DeviceSession(
    AccountSession(
      serverUrl: url,
      serverId: wire['serverId'],
      accountId: user['accountId'],
      userId: user['id'],
      username: user['username'],
      displayName: user['displayName'],
      deviceId: device['id'],
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        device['expiresAt'] * 1000,
      ),
      allowLocalHttp: true,
    ),
    wire['token'],
  );
}

void main() {
  final path = Platform.environment['JIVIE_AUTHORITY_SNAPSHOT_HTTP_FIXTURE'];
  test(
    'account and whole-space grouped HTTP reads retain proof verification',
    () async {
      final fixture = jsonDecode(await File(path!).readAsString()) as Map;
      final url = fixture['serverUrl'] as String;
      if (fixture['synthetic'] != true || Uri.parse(url).host != '127.0.0.1') {
        throw StateError('New isolated synthetic loopback fixture required');
      }
      final statePath =
          Platform.environment['JIVIE_AUTHORITY_SNAPSHOT_STATE_DIR'];
      if (statePath == null || !statePath.startsWith('/tmp/')) {
        throw StateError(
          'Private persistent synthetic state directory required',
        );
      }
      final db = CollaborationDatabase(
        NativeDatabase(File('$statePath/client.sqlite')),
      );
      final http = _MeasuredHttp();
      addTearDown(db.close);
      addTearDown(http.close);
      final crypto = CryptoCodec(await SodiumInit.init());
      final actor =
          Platform.environment['JIVIE_AUTHORITY_SNAPSHOT_ACTOR'] ?? 'owner';
      final session = _session(url, fixture['accounts'][actor]['session']);
      final account = AccountCryptoV2Workflow(
        AccountDirectoryRepository(
          reducer: AccountDirectoryV2(crypto),
          session: session,
          transport: http,
          store: CryptoIdentityStore(
            db,
            _Secure(File('$statePath/secure.json')),
            session.profile.partition,
          ),
          isCurrent: () => true,
        ),
      );
      final initialized = await db.rows(
        'SELECT 1 FROM crypto_identity_secrets WHERE partition=?',
        [session.profile.partition],
      );
      if (initialized.isEmpty) {
        final file = await account.prepareRecoveryFile();
        try {
          await account.verifyAndInitialize(file);
        } finally {
          file.fillRange(0, file.length, 0);
        }
      }
      final setupAccess = SessionCryptoAccess(account: account);
      final runtime = CryptoBusinessSession(account, setupAccess, db);
      CryptoBusinessRouter.configurePayloads(runtime);
      Future<Map<String, dynamic>> create(String kind, {Map? parent}) async {
        final key = 'authority_snapshot_fixture_$kind';
        final saved = await db.rows(
          'SELECT value FROM local_meta WHERE name=?',
          [key],
        );
        final params = saved.isEmpty
            ? <String, Object?>{
                'id': crypto.randomId(),
                'kind': kind,
                'name': 'Synthetic authority $kind',
                'requestId': crypto.randomId(),
                if (parent != null) 'parentScopeId': parent['id'],
              }
            : Map<String, Object?>.from(
                jsonDecode(saved.single['value'] as String) as Map,
              );
        if (saved.isEmpty) {
          await db.execute('INSERT INTO local_meta(name,value) VALUES(?,?)', [
            key,
            jsonEncode(params),
          ]);
        }
        final done = await db.rows(
          'SELECT value FROM local_meta WHERE name=?',
          ['$key:done'],
        );
        if (done.isNotEmpty) {
          return Map<String, dynamic>.from(
            jsonDecode(done.single['value'] as String) as Map,
          );
        }
        final response = await runtime.createScope(params);
        final scope = Map<String, dynamic>.from(response['scope'] as Map);
        await db.execute('INSERT INTO local_meta(name,value) VALUES(?,?)', [
          '$key:done',
          jsonEncode(scope),
        ]);
        return scope;
      }

      final parent = await create('organization');
      final child = await create('project', parent: parent);
      final scopes = [parent['id'] as String, child['id'] as String];
      Future<Map<String, dynamic>> verifiedRead() async {
        final access = SessionCryptoAccess(account: account);
        return access.withVerifiedOperation(() async {
          final own = await account.directory.requireFresh();
          final values = <String, dynamic>{'ownHead': own.headHash};
          for (final scope in scopes) {
            final head = await access.currentHead(scope, online: true);
            final lifecycle = await CryptoLifecycleEvidence(
              access,
            ).current(scope);
            values[scope] = {
              'head': head.headHash,
              'epoch': head.epoch,
              'revision': head.accessRevision,
              'lifecycle': lifecycle['headHash'],
            };
          }
          return values;
        });
      }

      http.reset();
      final baseline = await verifiedRead();
      final baselineRequests = http.operations.length;
      final baselineBytes = http.resultBytes;
      http.snapshots = true;
      http.reset();
      final grouped = await verifiedRead();
      expect(grouped, baseline);
      expect(http.operations, contains('crypto2.authority.snapshot'));
      expect(http.operations.length, lessThan(baselineRequests));
      expect(http.largestResult, lessThanOrEqualTo(1250000));
      debugPrint(
        jsonEncode({
          'authoritySnapshotHttp': 'PASS',
          'scopes': scopes.length,
          'baselineRequests': baselineRequests,
          'groupedRequests': http.operations.length,
          'baselineJsonResultBytes': baselineBytes,
          'groupedJsonResultBytes': http.resultBytes,
          'largestGroupedJsonResultBytes': http.largestResult,
        }),
      );

      final pinBefore = await account.store.secure.read(
        'scope2:${account.store.partition}:${scopes.first}',
      );
      http.forgeHead = true;
      await expectLater(verifiedRead(), throwsA(isA<FormatException>()));
      expect(http.forged, greaterThan(0));
      expect(
        await account.store.secure.read(
          'scope2:${account.store.partition}:${scopes.first}',
        ),
        pinBefore,
      );
    },
    skip: path == null ? 'New isolated HTTP fixture not requested' : false,
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
