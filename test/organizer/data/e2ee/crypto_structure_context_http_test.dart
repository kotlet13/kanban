import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_repository.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/crypto_archive_cold_database.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_router.dart';
import 'package:kanban/organizer/data/e2ee/crypto_capture_archive.dart';
import 'package:kanban/organizer/data/e2ee/crypto_capture_coordinator.dart';
import 'package:kanban/organizer/data/e2ee/crypto_capture_keys.dart';
import 'package:kanban/organizer/data/e2ee/crypto_capture_v3.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_identity_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_migration_canonical_stage.dart';
import 'package:kanban/organizer/data/e2ee/crypto_migration_cold_business.dart';
import 'package:kanban/organizer/data/e2ee/crypto_migration_record_source.dart';
import 'package:kanban/organizer/data/e2ee/crypto_migration_structure_context.dart';
import 'package:kanban/organizer/data/e2ee/crypto_migration_structure_producer.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/data/e2ee/scope_crypto_manager.dart';
import 'package:sodium/sodium.dart' show SodiumInit;

class _Secure implements AccountCryptoStore {
  final _data = <String, String>{};
  @override
  Future<String?> read(String key) async => _data[key];
  @override
  Future<void> write(String key, String value) async {
    _data[key] = value;
  }
}

class _Http implements CollaborationTransport {
  final _http = HttpCollaborationTransport();
  String? lostOperation;
  String? blockedReceiptId;
  var retries = 0;
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    if(operation=='crypto2.receipt.get' && params['requestId']==blockedReceiptId && blockedReceiptId!=null) {
      throw const CollaborationApiException('synthetic_receipt_unavailable');
    }
    try {
      final result = await _http.call(
        serverUrl: serverUrl,
        operation: operation,
        params: params,
        token: token,
        allowLocalHttp: allowLocalHttp,
      );
      if (lostOperation == operation) {
        lostOperation = null;
        final command=jsonDecode(utf8.decode(base64Decode(params['commandBase64'] as String))) as Map;
        blockedReceiptId=command['requestId'];
        throw const CollaborationApiException('synthetic_lost_ack');
      }
      return result;
    } on CollaborationApiException catch (error) {
      stderr.writeln(
        'synthetic context operation=$operation error=${error.code}',
      );
      final seconds = error.details['retryAfter'];
      if (Platform.environment['JIVIE_TEST_RETRY_RATE_LIMITS'] == '1' &&
          error.code == 'rate_limited' &&
          seconds is int &&
          seconds > 0 &&
          seconds <= 60 &&
          retries++ < 3) {
        await Future<void>.delayed(Duration(seconds: seconds));
        return call(
          serverUrl: serverUrl,
          operation: operation,
          params: params,
          token: token,
          allowLocalHttp: allowLocalHttp,
        );
      }
      rethrow;
    }
  }

  @override
  void close() => _http.close();
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

Future<void> _stage(
  CryptoBusinessSession runtime,
  CryptoCaptureCoordinator coordinator,
  CryptoCaptureKeyDescriptor capture,
  String root,
  String table,
) async {
  final rows = await runtime.db.rows(
    'SELECT * FROM crypto_capture_sources WHERE partition=? AND capture_id=? ORDER BY binding_id',
    [runtime.partition, capture.captureId],
  );
  for (final row in rows) {
    final c = CryptoCaptureSourceContext.fromJson(
      jsonDecode(row['context'] as String),
    );
    if (c.sourceTable != table) continue;
    final binding = CryptoCaptureBinding.fromJson(
      jsonDecode(row['binding'] as String),
    );
    final source = await CryptoMigrationRecordSource.decode(
      table: table,
      domain: c.domain,
      row: jsonDecode(row['typed_row'] as String),
      serverId: runtime.account.directory.session.profile.serverId,
      reservedId: runtime.reservedRecordId,
    );
    final key = await coordinator.keys.open(capture);
    final salt = await CryptoCaptureV3.salt(key.key, c);
    key.release();
    try {
      await CryptoMigrationCanonicalStage(runtime).stageCaptured(
        capture: capture,
        sourceInventoryRoot: root,
        binding: binding,
        witness: {
          'version': 3,
          'context': c.toJson(),
          'typedRow': source.typedRow,
          'saltBase64': base64Encode(salt),
        },
        source: source,
      );
    } finally {
      salt.fillRange(0, salt.length, 0);
    }
  }
}

void main() {
  final path = Platform.environment['JIVIE_STRUCTURE_CONTEXT_HTTP_FIXTURE'];
  test(
    'NONE owner source context and nonmanager READ materializer survive FILE cold and exact lostACK retry',
    () async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final f = jsonDecode(await File(path!).readAsString()) as Map,
          url = f['serverUrl'] as String;
      if (f['synthetic'] != true || Uri.parse(url).host != '127.0.0.1') {
        throw StateError('Loopback synthetic only');
      }
      final http = _Http(), crypto = CryptoCodec(await SodiumInit.init());
      final dbs = [
        for (var i = 0; i < 2; i++)
          CollaborationDatabase(NativeDatabase.memory()),
      ];
      final sessions = [
        _session(url, f['owner']['session']),
        _session(url, f['reader']['session']),
      ];
      final accounts = [
        for (var i = 0; i < 2; i++)
          AccountCryptoV2Workflow(
            AccountDirectoryRepository(
              reducer: AccountDirectoryV2(crypto),
              session: sessions[i],
              transport: http,
              store: CryptoIdentityStore(
                dbs[i],
                _Secure(),
                sessions[i].profile.partition,
              ),
              isCurrent: () => true,
            ),
          ),
      ];
      final files = <Uint8List>[];
      final dir = await Directory.systemTemp.createTemp('context-cold-');
      try {
        for (final a in accounts) {
          final file = await a.prepareRecoveryFile();
          files.add(file);
          await a.verifyAndInitialize(file);
        }
        final accesses = [
          for (final a in accounts) SessionCryptoAccess(account: a),
        ];
        final scope = f['scopeId'] as String;
        final own = [
          for (final a in accounts) await a.directory.requireFresh(),
        ];
        for (var i = 0; i < 2; i++) {
          final other = 1 - i;
          await accesses[i].verifyContactCard(
            scope,
            own[other].accountId,
            await accesses[other].identities.publicCard(own[other]),
          );
        }
        final coordinators = [
          for (final a in accounts) CryptoCaptureCoordinator(a),
        ];
        final captures = [
          await coordinators[0].prepare(scope),
          await coordinators[1].prepare(scope),
        ];
        stderr.writeln('synthetic context captures prepared');
        final seals = [
          for (var i = 0; i < 2; i++)
            await coordinators[i].captureSources(captures[i]),
        ];
        for (var i = 0; i < 2; i++) {
          await coordinators[i].fence(
            captures[i],
            reviewedInventoryRoot: seals[i]['inventoryRoot'],
          );
        }
        stderr.writeln('synthetic context both fences complete');
        final catalog = await accounts[0].directory.call(
          'crypto2.scopes.catalog',
          {'limit': 50},
        );
        final metadata =
            (catalog['scopes'] as List).singleWhere((s) => s['id'] == scope)
                as Map;
        final managers = [for (final a in accesses) ScopeCryptoManager(a)];
        Future<dynamic> genesis() => managers[0].initializeEmptyScope(
          scopeId: scope,
          accessRevision: metadata['accessRevision'],
          members: (metadata['members'] as List).cast<Map<String, dynamic>>(),
        );
        await expectLater(genesis(), throwsA(isA<CryptoAuthorityPending>()));
        stderr.writeln('synthetic context genesis finance draft ready');
        final draft =
            (await managers[1].financeDrafts(scope)).single['draftId']
                as String;
        await managers[1].contributeFinanceDraft(scope, draft);
        stderr.writeln('synthetic context finance key contribution ready');
        await expectLater(genesis(), throwsA(isA<CryptoAuthorityPending>()));
        final contribution=(await dbs[1].rows(
          "SELECT payload FROM crypto_membership_intents WHERE state='financeContributionDraft'",
        ));
        expect(contribution,hasLength(1));
        if(contribution.isNotEmpty) {
          final saved=jsonDecode(utf8.decode((contribution.single['payload'] as List).cast<int>())) as Map;
          final candidate=await accounts[1].directory.call('crypto2.scope.headGet',{'scopeId':scope,'headHash':saved['headHash']});
          expect(await accesses[1].verifiedCandidatePolicyVersion(scope,candidate),isNull);
          expect(await accounts[1].store.secure.read('scope2:${accounts[1].store.partition}:$scope'),isNull);
          final changed=Map<String,dynamic>.from(jsonDecode(jsonEncode(candidate)) as Map);
          changed['payload']['financePolicyIntentProof']={};
          changed['headHash']=await accesses[1].codec.headHash(Map<String,dynamic>.from(changed['payload'] as Map));
          await expectLater(accesses[1].verifiedCandidatePolicyVersion(scope,changed),throwsFormatException);
        }
        await managers[1].publishFinanceGrants(scope, draft);
        stderr.writeln('synthetic context finance grants published');
        final head = await genesis();
        stderr.writeln('synthetic context genesis active');
        await accesses[1].currentHead(scope, online: true);
        await accesses[1].hydrateScopeKeys(scope);
        expect(head.member(own[0].accountId)['financeRole'], 'none');
        expect(head.member(own[1].accountId)['financeRole'], 'read');
        expect(head.member(own[1].accountId)['manageKeys'], false);
        expect(
          await dbs[0].rows(
            "SELECT * FROM crypto_scope_keys WHERE domain='finance'",
          ),
          isEmpty,
        );
        final runtimes = [
          for (var i = 0; i < 2; i++)
            CryptoBusinessSession(accounts[i], accesses[i], dbs[i]),
        ];
        final archives = [
          for (final a in accounts)
            CryptoCaptureArchive(
              a,
              coldDatabase: () => CryptoArchiveColdDatabase.create(parent: dir),
            ),
        ];
        final manifests = [
          for (var i = 0; i < 2; i++)
            await archives[i].stageAndUpload(captures[i]),
        ];
        final verified = [
          for (var i = 0; i < 2; i++)
            await archives[i].verifyFromFile(
              capture: captures[i],
              manifest: manifests[i],
              externalFile: files[i],
            ),
        ];
        stderr.writeln('synthetic context source archives FILE verified');
        await _stage(
          runtimes[0],
          coordinators[0],
          captures[0],
          verified[0].sourceInventoryRoot,
          'familyhub_scopes',
        );
        await _stage(
          runtimes[1],
          coordinators[1],
          captures[1],
          verified[1].sourceInventoryRoot,
          'familyhub_finance_records',
        );
        stderr.writeln('synthetic context both canonical records staged');
        final source =
            await CryptoMigrationColdBusiness(
              accounts[0],
              coldDatabase: () => CryptoArchiveColdDatabase.create(parent: dir),
            ).verifyStructureSource(
              archive: archives[0],
              capture: captures[0],
              manifest: manifests[0],
              externalFile: files[0],
              scopeId: scope,
            );
        final card = await CryptoMigrationStructureProducer(runtimes[0])
            .publishContext(
              source: source,
              purpose: 'scopeContext',
              targetScopeId: scope,
              targetMembershipHeadHash: head.headHash,
            );
        final originalCard = CryptoMigrationStructureContexts.body(
          card['authorization'],
        );
        for (final badKind in [
          'changedRevision',
          'omittedRevision',
          'changedRole',
        ]) {
          final changed = Map<String, dynamic>.from(
            jsonDecode(jsonEncode(originalCard)) as Map,
          );
          if (badKind == 'changedRevision') {
            changed['facts']['financePolicy']['revision'] = 5;
          }
          if (badKind == 'omittedRevision') {
            (changed['facts']['financePolicy'] as Map).remove('revision');
          }
          if (badKind == 'changedRole') {
            (changed['facts']['members'] as List).singleWhere(
              (m) => m['accountId'] == own[1].accountId,
            )['role'] = 'viewer';
          }
          final lease = await accounts[0].signingKey();
          late Map<String, dynamic> outer;
          try {
            final inner = crypto.signDomain(
              changed,
              lease.key,
              CryptoMigrationStructureContexts.contextDomain,
            );
            outer = crypto.signDomain(
              {
                'version': 2,
                'operation': 'crypto2.migration.structure.context',
                'requestId': crypto.randomId(),
                'serverId': own[0].serverId,
                'accountId': own[0].accountId,
                'deviceId': accounts[0].deviceId,
                'signer': 'device',
                'payload': {
                  for (final k in [
                    'migrationId',
                    'captureId',
                    'sourceInventoryRoot',
                  ])
                    k: originalCard[k],
                  'authorization': inner,
                },
              },
              lease.key,
              cryptoDirectoryDomain,
            );
          } finally {
            lease.release();
          }
          await expectLater(
            accounts[0].directory.call(
              'crypto2.migration.structure.context',
              outer,
            ),
            throwsA(
              isA<CollaborationApiException>().having(
                (e) => e.code,
                'code',
                'crypto_structure_context_facts',
              ),
            ),
          );
        }
        final issuer = await accesses[1].directoryAt(
          scopeId: scope,
          scopeHeadHash: head.headHash,
          accountId: own[0].accountId,
          directoryHeadHash: CryptoMigrationStructureContexts.body(
            card['authorization'],
          )['authorDirectoryHeadHash'],
          online: true,
        );
        var reviews = 0;
        Future<bool> review(
          Map<String, dynamic> facts,
          List<Map<String, dynamic>> members,
        ) async {
          reviews++;
          expect(facts['financePolicy']['revision'], 4);
          expect(facts['financePolicy'].containsKey('grants'), false);
          expect(
            members.singleWhere(
              (m) => m['accountId'] == own[1].accountId,
            )['manageKeys'],
            false,
          );
          return true;
        }

        final producer = CryptoMigrationStructureProducer(runtimes[1]);
        http.lostOperation = 'crypto2.migration.structure.contextApprove';
        await expectLater(
          producer.approve(
            archive: verified[1],
            cardEvidence: card,
            issuer: issuer,
            review: review,
          ),
          throwsA(anything),
        );
        expect(http.lostOperation, isNull);
        final beforeRetry=(await dbs[1].rows(
          "SELECT signed_body,request_hash FROM crypto_outbox WHERE operation='crypto2.migration.structure.contextApprove'",
        )).single;
        final after = await accounts[0].attestMigration(
          migrationId: captures[0].migrationId,
          scopeToken: '8' * 64,
          domain: 'content',
          attestationHash: '9' * 64,
        );
        expect(after['generation'], greaterThan(issuer.generation));
        http.blockedReceiptId=null;
        await producer.approve(
          archive: verified[1],
          cardEvidence: card,
          issuer: await accounts[0].directory.requireFresh(),
          review: review,
        );
        expect(reviews, 1);
        expect((await dbs[1].rows(
          "SELECT signed_body,request_hash FROM crypto_outbox WHERE operation='crypto2.migration.structure.contextApprove'",
        )).single,beforeRetry);
        final result =
            await CryptoMigrationColdBusiness(
              accounts[1],
              coldDatabase: () => CryptoArchiveColdDatabase.create(parent: dir),
            ).verifyStructureControl(
              archive: archives[1],
              capture: captures[1],
              manifest: manifests[1],
              externalFile: files[1],
              scopeId: scope,
            );
        expect(result['kind'], 'structure');
        expect(result['count'], 0);
        expect(
          await dbs[0].rows(
            "SELECT * FROM crypto_scope_keys WHERE domain='finance'",
          ),
          isEmpty,
        );
        expect(
          await dbs[1].rows('SELECT * FROM crypto_business_records'),
          isEmpty,
        );
      } finally {
        for (final file in files) {
          file.fillRange(0, file.length, 0);
        }
        for (final db in dbs) {
          await db.close();
        }
        http.close();
        await dir.delete(recursive: true);
      }
    },
    skip: path == null,
    timeout: const Timeout(Duration(minutes:4)),
  );
}
