import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_repository.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_router.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_identity_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_lifecycle_evidence.dart';
import 'package:kanban/organizer/data/e2ee/crypto_scope_observations.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:sodium/sodium.dart';

class _Secure implements AccountCryptoStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

class _ObservedTransport implements CollaborationTransport {
  final http = HttpCollaborationTransport();
  bool omitArchived = false;
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    late Map<String, dynamic> result;
    for (var attempt = 0; ; attempt++) {
      try {
        result = await http.call(
          serverUrl: serverUrl,
          operation: operation,
          params: params,
          token: token,
          allowLocalHttp: allowLocalHttp,
        );
        break;
      } on CollaborationApiException catch (e) {
        if (e.code != 'rate_limited' || attempt >= 3) rethrow;
        final retry = e.details['retryAfter'];
        await Future<void>.delayed(
          Duration(seconds: retry is int ? retry.clamp(1, 60) : 15),
        );
      }
    }
    if (omitArchived && operation == 'crypto2.scope.lifecycle.list') {
      return {
        'states': <Object>[],
        'hasMore': false,
        'nextAfterRevision': null,
        'currentRevision': 0,
      };
    }
    return result;
  }

  @override
  void close() => http.close();
}

DeviceSession _session(Map wire, String url) {
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
  final path =
      Platform.environment['JIVIE_CRYPTO2_LIFECYCLE_OBSERVATION_FIXTURE'];
  test(
    'file-only cold lifecycle uses own observed archived tail without later scope epoch',
    () async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final fixture = jsonDecode(await File(path!).readAsString()) as Map;
      final url = fixture['serverUrl'] as String;
      if (fixture['synthetic'] != true || Uri.parse(url).host != '127.0.0.1') {
        throw StateError('Synthetic loopback only');
      }
      final person = fixture['accounts']['owner'] as Map,
          session = _session(person['session'], url);
      final db = CollaborationDatabase(NativeDatabase.memory()),
          transport = _ObservedTransport(),
          crypto = CryptoCodec(await SodiumInit.init());
      addTearDown(db.close);
      addTearDown(transport.close);
      AccountCryptoV2Workflow account(
        CollaborationDatabase database,
        DeviceSession auth,
      ) => AccountCryptoV2Workflow(
        AccountDirectoryRepository(
          reducer: AccountDirectoryV2(crypto),
          session: auth,
          transport: transport,
          store: CryptoIdentityStore(
            database,
            _Secure(),
            auth.profile.partition,
          ),
          isCurrent: () => true,
        ),
      );
      final first = account(db, session),
          file = await first.prepareRecoveryFile();
      try {
        await first.verifyAndInitialize(file);
        print('Lifecycle observation stage: initialized');
        final access = SessionCryptoAccess(account: first),
            runtime = CryptoBusinessSession(first, access, db),
            scope = crypto.randomId();
        await runtime.createScope({
          'id': scope,
          'kind': 'household',
          'name': 'PRIVATE_OBSERVED_ARCHIVE',
          'requestId': crypto.randomId(),
        });
        print('Lifecycle observation stage: scope initialized');
        final head = await access.currentHead(scope, online: true),
            own = await first.directory.requireFresh();
        Future<Map<String, dynamic>> sign(
          String op,
          Map<String, dynamic> payload,
        ) async {
          final lease = await first.signingKey();
          try {
            return crypto.signDomain(
              {
                'version': 2,
                'operation': op,
                'requestId': crypto.randomId(),
                'serverId': own.serverId,
                'accountId': own.accountId,
                'deviceId': session.profile.deviceId,
                'signer': 'device',
                'payload': payload,
              },
              lease.key,
              cryptoDirectoryDomain,
            );
          } finally {
            lease.release();
          }
        }

        final action = crypto.randomId(),
            prepare = await sign('crypto2.scope.lifecycle.prepare', {
              'scopeId': scope,
              'parentActionId': action,
              'expectedLifecycleRevision': 0,
              'previousLifecycleHash': cryptoZeroHash,
              'membershipHeadHash': head.headHash,
              'expectedAccessRevision': head.accessRevision,
              'authorDirectoryHeadHash': own.headHash,
              'archived': true,
            });
        await first.directory.call('crypto2.scope.lifecycle.prepare', prepare);
        final finalProof = await sign('crypto2.scope.archive', {
          'scopeId': scope,
          'parentActionId': action,
          'intentProofHash': await CryptoLifecycleEvidence(
            access,
          ).proofHash(prepare),
          'childCount': 0,
          'childrenHash': await cryptoSha256([]),
        });
        final applied = await first.directory.call(
              'crypto2.scope.archive',
              finalProof,
            ),
            archivedHash = applied['lifecycle']['headHash'];
        await CryptoScopeObservations(first).observe(access, scope);
        print('Lifecycle observation stage: archived and observed');
        expect((await access.currentHead(scope, online: true)).epoch, 1);
        final login = await transport.call(
          serverUrl: url,
          operation: 'auth.login',
          params: {
            'username': person['username'],
            'password': person['password'],
            'deviceName': 'Observed lifecycle blank recovery',
          },
          allowLocalHttp: true,
        );
        final blank = CollaborationDatabase(NativeDatabase.memory());
        addTearDown(blank.close);
        final recovered = account(blank, _session(login, url));
        await recovered.recover(file);
        print('Lifecycle observation stage: recovered account into blank DB');
        await CryptoScopeObservations(recovered).hydrateObservedScopes(file);
        print('Lifecycle observation stage: hydrated observed scope');
        final coldAccess = SessionCryptoAccess(account: recovered),
            cold = CryptoLifecycleEvidence(coldAccess);
        final life = await cold.current(scope);
        expect(life['headHash'], archivedHash);
        expect(life['ownArchived'], true);
        expect(
          (await coldAccess.currentHead(scope, online: true)).epoch,
          1,
          reason: 'no membership successor can supply this lifecycle anchor',
        );
        await expectLater(
          coldAccess.writeContext(scope, 'content', online: true),
          throwsA(isA<CryptoAuthorityPending>()),
          reason:
              'an observed historical head admits reads, never fresh device writes',
        );
        transport.omitArchived = true;
        await expectLater(
          cold.current(scope),
          throwsA(isA<CryptoAuthorityPending>()),
        );
        final floor = await recovered.store.secure.read(
          'lifecycle2:${recovered.store.partition}:$scope',
        );
        expect(floor, contains(archivedHash));
        transport.omitArchived = false;
        expect((await cold.current(scope))['ownArchived'], true);
      } finally {
        file.fillRange(0, file.length, 0);
      }
    },
    skip: path == null ? 'Synthetic loopback fixture not requested' : false,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
