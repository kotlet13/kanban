import 'package:kanban/organizer/data/e2ee/crypto_finance_account_choices.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:flutter/foundation.dart' show debugPrint;
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
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_identity_store.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:sodium/sodium.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_router.dart';

class _DiskSecure implements AccountCryptoStore {
  _DiskSecure(this.file);
  final File file;
  Future<Map<String, dynamic>> _read() async => await file.exists()
      ? Map<String, dynamic>.from(jsonDecode(await file.readAsString()) as Map)
      : {};
  Future<void> _tail = Future<void>.value();
  @override
  Future<String?> read(String partition) async {
    await _tail;
    return (await _read())[partition] as String?;
  }

  @override
  Future<void> write(String partition, String value) {
    final task = _tail.then((_) async {
      final rows = await _read();
      rows[partition] = value;
      await file.writeAsString(jsonEncode(rows), flush: true);
    });
    _tail = task;
    return task;
  }
}

DeviceSession _session(String url, Map<String, dynamic> wire) {
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

class _ChoiceHttp extends HttpCollaborationTransport {
  final operations = <String>[];
  final attempts = <String, String>{};
  final sentAt = <DateTime>[];
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    if (params['commandBase64'] is String) {
      final command =
          CryptoJson.decode(cryptoBase64(params['commandBase64'])) as Map;
      final id = command['requestId'] as String;
      final hash = await cryptoSha256(CryptoJson.encode(params));
      expect(
        attempts[id] == null || attempts[id] == hash,
        isTrue,
        reason: 'A resumed mutation must retain its exact request bytes',
      );
      attempts[id] = hash;
    }
    // Only this disposable HTTP fixture paces its own requests. Production
    // quotas, scheduling, and verification remain unchanged.
    var now = DateTime.now();
    sentAt.removeWhere((t) => now.difference(t).inSeconds > 60);
    if (sentAt.length >= 440) {
      await Future<void>.delayed(
        const Duration(seconds: 61) - now.difference(sentAt.first),
      );
      now = DateTime.now();
      sentAt.clear();
    }
    sentAt.add(now);
    operations.add(operation);
    return super.call(
      serverUrl: serverUrl,
      operation: operation,
      params: params,
      token: token,
      allowLocalHttp: allowLocalHttp,
    );
  }
}

void main() {
  final path = Platform.environment['JIVIE_INTERRUPTED_SHARING_FIXTURE'];
  final baseline =
      Platform.environment['JIVIE_EXPECT_CHOICE_CONTEXT_FAILURE'] == '1';
  test(
    'same retained account-choice record refresh uses physical crypto revision',
    () async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final fixture = jsonDecode(await File(path!).readAsString()) as Map;
      final url = fixture['serverUrl'] as String;
      if (fixture['synthetic'] != true || Uri.parse(url).host != '127.0.0.1') {
        throw StateError('Disposable synthetic loopback required');
      }
      final dir = Directory(fixture['clientStateDir']);
      final inherited =
          jsonDecode(await File('${dir.path}/interrupted.json').readAsString())
              as Map;
      expect(
        inherited['complete'],
        isTrue,
        reason: 'Continue the completed fixture; never repeat its setup',
      );
      final journal = File('${dir.path}/choice-refresh.json');
      final state = await journal.exists()
          ? Map<String, dynamic>.from(
              jsonDecode(await journal.readAsString()) as Map,
            )
          : <String, dynamic>{};
      Future<void> save() =>
          journal.writeAsString(jsonEncode(state), flush: true);
      final codec = CryptoCodec(await SodiumInit.init()), http = _ChoiceHttp();
      final session = _session(url, fixture['accounts']['owner']['session']);
      final db = CollaborationDatabase(
        NativeDatabase(File('${dir.path}/${session.profile.deviceId}.sqlite')),
      );
      final account = AccountCryptoV2Workflow(
        AccountDirectoryRepository(
          reducer: AccountDirectoryV2(codec),
          session: session,
          transport: http,
          store: CryptoIdentityStore(
            db,
            _DiskSecure(
              File('${dir.path}/${session.profile.deviceId}.secure.json'),
            ),
            session.profile.partition,
          ),
          isCurrent: () => true,
        ),
      );
      final access = SessionCryptoAccess(account: account);
      final runtime = CryptoBusinessSession(account, access, db);
      CryptoBusinessRouter.configurePayloads(runtime);
      final choices = CryptoFinanceAccountChoices(runtime),
          child = inherited['child'] as String;
      Future<Map<String, dynamic>> certified(String label) async {
        if (state[label] != null) {
          return Map<String, dynamic>.from(state[label] as Map);
        }
        state['${label}Action'] ??= codec.randomId();
        state['${label}Approve'] ??= codec.randomId();
        state['${label}Certify'] ??= codec.randomId();
        await save();
        final prepared = await choices.prepare(
          child,
          actionId: state['${label}Action'],
        );
        final offer = Map<String, dynamic>.from(
          prepared['offerAuthorization'] as Map,
        );
        final approved = await choices.approve(
          child,
          offer,
          actionId: state['${label}Approve'],
          recipientAccountId: account.directory.accountId,
          recipientDeviceId: account.deviceId,
        );
        final delegation = Map<String, dynamic>.from(
          approved['delegationAuthorization'] as Map,
        );
        final certificate = await choices.certify(
          child,
          selectionActionId: state['${label}Action'],
          offerAuthorization: offer,
          delegationAuthorization: delegation,
          actionId: state['${label}Certify'],
        );
        final proof = Map<String, dynamic>.from(
          certificate['certificateAuthorization'] as Map,
        );
        final hash = await cryptoSha256(CryptoJson.encode(proof));
        state[label] = {
          'offer': offer,
          'delegation': delegation,
          'certificate': proof,
          'operationId': await runtime.reservedRecordId(
            child,
            'accountChoiceSelection:materialize:$hash',
          ),
        };
        await save();
        return Map<String, dynamic>.from(state[label] as Map);
      }

      Future<void> materialize(Map<String, dynamic> proof) async {
        await choices.materialize(
          child,
          offerAuthorization: Map<String, dynamic>.from(proof['offer'] as Map),
          delegationAuthorization: Map<String, dynamic>.from(
            proof['delegation'] as Map,
          ),
          certificateAuthorization: Map<String, dynamic>.from(
            proof['certificate'] as Map,
          ),
          operationId: proof['operationId'],
        );
      }

      try {
        if (state['localCatalog'] != true) {
          await db.execute(
            'INSERT OR IGNORE INTO accounts(partition,profile) VALUES(?,?)',
            [account.store.partition, jsonEncode(session.profile.toJson())],
          );
          final catalog = await runtime.scopes();
          for (final value in catalog['scopes'] as List) {
            final scope = SharedScope.fromJson(
              Map<String, dynamic>.from(value as Map),
            );
            await db.execute(
              'INSERT INTO scopes(partition,id,data) VALUES(?,?,?) ON CONFLICT(partition,id) DO UPDATE SET data=excluded.data',
              [account.store.partition, scope.id, jsonEncode(scope.toJson())],
            );
          }
          state['localCatalog'] = true;
          await save();
        }
        final first = await certified('first');
        if (state['firstPublished'] != true) {
          await materialize(first);
          state['firstPublished'] = true;
          await save();
        }
        final manifestId = await choices.manifestId(child);
        final before = (await runtime.record(
          child,
          'finance',
          manifestId,
          type: CryptoFinanceAccountChoices.type,
        ))!;
        expect(before['legacy_revision'], 0);
        expect(before['crypto_revision'], 1);
        expect(before['record_proof_hash'], isNot('0' * 64));
        final next = await certified('next');
        final mutationStart = http.operations.length;
        if (baseline) {
          await expectLater(
            materialize(next),
            throwsA(
              isA<FormatException>().having(
                (e) => e.message,
                'message',
                'crypto_record_context',
              ),
            ),
          );
          expect(
            http.operations
                .skip(mutationStart)
                .where((op) => op == 'crypto2.records.batch'),
            isEmpty,
          );
          state['baselineContextFailure'] = true;
          await save();
        } else {
          expect(
            state['baselineContextFailure'],
            isTrue,
            reason: 'Use the exact preserved failed certificate/operation',
          );
          await materialize(next);
          final after = (await runtime.record(
            child,
            'finance',
            manifestId,
            type: CryptoFinanceAccountChoices.type,
          ))!;
          expect(after['legacy_revision'], 0);
          expect(after['crypto_revision'], 2);
          final wireRows = await db.rows(
            'SELECT wire FROM crypto_received WHERE partition=? AND scope_id=? AND domain=? AND record_id=? AND revision=2',
            [account.store.partition, child, 'finance', after['id']],
          );
          final wire = jsonDecode(wireRows.single['wire'] as String) as Map;
          final body =
              CryptoJson.decode(
                    cryptoBase64(
                      wire['authorization']['recordProof']['commandBase64'],
                    ),
                  )
                  as Map;
          expect(body['expectedRevision'], before['crypto_revision']);
          expect(body['previousRecordHash'], before['record_proof_hash']);
          expect(body['operationId'], next['operationId']);
          expect(
            body['membershipHeadHash'],
            (await access.currentHead(child, online: true)).headHash,
          );
          expect(await choices.read(child), containsPair('accounts', isEmpty));
          final beforeReplay = http.operations
              .where((op) => op == 'crypto2.records.batch')
              .length;
          await materialize(next);
          expect(
            http.operations.where((op) => op == 'crypto2.records.batch').length,
            beforeReplay,
            reason:
                'Replay consumes the original journal without another mutation',
          );
          state['complete'] = true;
          await save();
        }
        expect(
          http.operations.where(
            (op) => [
              'crypto2.invitations.accept',
              'crypto2.scope.create',
              'crypto2.scope.activate',
              'crypto2.grants.put',
            ].contains(op),
          ),
          isEmpty,
        );
        debugPrint(
          'CHOICE_REFRESH ${jsonEncode({'baseline': baseline, 'expectedContextFailure': baseline, 'physicalRevisionAndPredecessorVerified': !baseline, 'sameRetainedCertificateAndOperation': true, 'noNewActorsScopesInviteOrGrant': true, 'operations': http.operations.length})}',
        );
      } finally {
        http.close();
        await db.close();
      }
    },
    skip: path == null,
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
