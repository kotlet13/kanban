import 'package:kanban/organizer/data/e2ee/crypto_inherited_invitation_grants.dart';
import 'package:kanban/organizer/data/e2ee/crypto_scope_observations.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'dart:convert';
import 'dart:typed_data';
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
import 'package:kanban/organizer/data/e2ee/scope_crypto_manager.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:sodium/sodium.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_router.dart';
import 'package:kanban/organizer/data/e2ee/invite_crypto_repository.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_json.dart';

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

class _InterruptedHttp extends HttpCollaborationTransport {
  final operations = <String>[];
  final attempts = <String, String>{};
  final sentAt = <DateTime>[];
  String? child;
  String? stop;
  int childGrants = 0;
  String? interruptedRequest;
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    Map? command;
    if (params['commandBase64'] is String) {
      command = CryptoJson.decode(cryptoBase64(params['commandBase64'])) as Map;
      final id = command['requestId'] as String;
      final hash = await cryptoSha256(CryptoJson.encode(params));
      expect(
        attempts[id] == null || attempts[id] == hash,
        isTrue,
        reason: 'A resumed mutation must retain its exact request bytes',
      );
      attempts[id] = hash;
    }
    final target = command?['payload']?['scopeId'];
    var interrupt =
        target == child &&
        stop == 'before-head' &&
        operation == 'crypto2.scope.headPut';
    if (target == child &&
        stop == 'during-grants' &&
        operation == 'crypto2.grants.put') {
      interrupt = ++childGrants == 2;
    }
    if (interrupt) {
      interruptedRequest = command!['requestId'];
      stop = null;
      throw const CollaborationApiException(
        'rate_limited',
        details: {'retryAfter': 1},
      );
    }
    // Natural pacing is confined to this disposable fixture. Production quota
    // is unchanged; interruption above reaches the real durable sender.
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
  test(
    'real inherited child resumes same draft before and after publication across directory appends',
    () async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final fixture = jsonDecode(await File(path!).readAsString()) as Map;
      final url = fixture['serverUrl'] as String;
      if (fixture['synthetic'] != true || Uri.parse(url).host != '127.0.0.1') {
        throw StateError('Disposable synthetic loopback required');
      }
      final dir = Directory(fixture['clientStateDir']);
      final journal = File('${dir.path}/interrupted.json');
      final state = await journal.exists()
          ? Map<String, dynamic>.from(
              jsonDecode(await journal.readAsString()) as Map,
            )
          : <String, dynamic>{};
      Future<void> save() =>
          journal.writeAsString(jsonEncode(state), flush: true);
      final codec = CryptoCodec(await SodiumInit.init()),
          http = _InterruptedHttp();
      final dbs = <CollaborationDatabase>[];
      AccountCryptoV2Workflow make(DeviceSession session) {
        final name = session.profile.deviceId;
        final db = CollaborationDatabase(
          NativeDatabase(File('${dir.path}/$name.sqlite')),
        );
        dbs.add(db);
        return AccountCryptoV2Workflow(
          AccountDirectoryRepository(
            reducer: AccountDirectoryV2(codec),
            session: session,
            transport: http,
            store: CryptoIdentityStore(
              db,
              _DiskSecure(File('${dir.path}/$name.secure.json')),
              session.profile.partition,
            ),
            isCurrent: () => true,
          ),
        );
      }

      final owner = make(
        _session(url, fixture['accounts']['owner']['session']),
      );
      final guest = make(
        _session(url, fixture['accounts']['other']['session']),
      );
      final oa = SessionCryptoAccess(account: owner),
          ga = SessionCryptoAccess(account: guest);
      final runtime = CryptoBusinessSession(owner, oa, owner.store.database);
      final sender = InviteCryptoRepository(oa),
          receiver = InviteCryptoRepository(ga),
          manager = ScopeCryptoManager(oa);
      Future<String> create(
        String kind,
        String name, {
        required String stateKey,
        String? parent,
      }) async {
        final id = (state[stateKey] ??= codec.randomId()) as String;
        state['${stateKey}Request'] ??= codec.randomId();
        await save();
        if (state['${stateKey}Created'] != true) {
          await runtime.createScope({
            'id': id,
            'kind': kind,
            'name': name,
            'requestId': state['${stateKey}Request'],
            if (parent != null) 'parentScopeId': parent,
          });
          state['${stateKey}Created'] = true;
          await save();
        }
        return id;
      }

      Future<Map<String, dynamic>> draft() async {
        final rows = await owner.store.database.rows(
          "SELECT payload FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND state='scopeRotationDraft'",
          [owner.store.partition, state['child']],
        );
        expect(rows, hasLength(1));
        return Map<String, dynamic>.from(
          CryptoJson.decode(
                Uint8List.fromList(
                  (rows.single['payload'] as List).cast<int>(),
                ),
              )
              as Map,
        );
      }

      Future<String> keyDigest() async => cryptoSha256(
        CryptoJson.encodeDerivedState(
          await owner.store.database.rows(
            'SELECT domain,epoch_id,key_id,key_bytes FROM crypto_scope_keys WHERE partition=? AND scope_id=? ORDER BY domain,epoch_id,key_id',
            [owner.store.partition, state['child']],
          ),
        ),
      );
      Future<void> appendObservation(
        AccountCryptoV2Workflow account,
        SessionCryptoAccess access,
      ) async {
        final parent = state['parent'] as String;
        await CryptoScopeObservations(account).observe(access, parent);
        final bundles = await CryptoScopeObservations(account).recover(parent);
        final head = await access.currentHead(parent, online: true);
        final observation = bundles.lastWhere(
          (b) => b['headHash'] == head.headHash,
        );
        final own = await account.directory.requireFresh();
        final token = await CryptoScopeObservations.token(
          own.serverId,
          own.accountId,
          parent,
        );
        final lease = await account.signingKey();
        try {
          await account.directory.stageAndSend(
            (previous) async => account.directory.reducer.prepare(
              previous: previous,
              requestId: codec.randomId(),
              serverId: own.serverId,
              accountId: own.accountId,
              deviceId: account.deviceId,
              identityEpochId: own.identityEpochId,
              operation: 'crypto2.account.scopeObserve',
              signer: 'device',
              payload: {
                'scopeToken': token,
                'headHash': head.headHash,
                'observationHash': observation['observationHash'],
              },
              pinnedRootFingerprint: own.rootFingerprint,
              signingKey: lease.key,
            ),
          );
        } finally {
          lease.release();
        }
        final after = await account.directory.requireFresh();
        expect(after.headHash != own.headHash, isTrue);
        expect(after.deviceSnapshotHash == own.deviceSnapshotHash, isTrue);
      }

      try {
        if (state['prepared'] != true) {
          for (final (label, account) in [('owner', owner), ('other', guest)]) {
            if (await account.localPhase() == 'ready') continue;
            final file = await account.prepareRecoveryFile();
            await File(
              '${dir.path}/$label.file',
            ).writeAsBytes(file, flush: true);
            try {
              await account.verifyAndInitialize(file);
            } finally {
              file.fillRange(0, file.length, 0);
            }
          }
          state['parent'] = await create(
            'organization',
            'Interrupted parent',
            stateKey: 'parent',
          );
          await save();
          state['child'] = await create(
            'project',
            'Interrupted child',
            stateKey: 'child',
            parent: state['parent'],
          );
          await save();
          state['record'] ??= codec.randomId();
          final now = DateTime.utc(2026, 10, 19);
          final raw =
              Map<String, dynamic>.from(
                  LocalProject(
                    id: state['record'],
                    title: 'Retained encrypted child history',
                    description: 'Original private child description',
                    createdAt: now,
                    updatedAt: now,
                    area: ProjectArea.home,
                  ).toJson(),
                )
                ..remove('id')
                ..remove('revision')
                ..remove('createdByAccountId')
                ..remove('updatedByAccountId');
          if (state['published'] != true) {
            state['recordOp'] ??= codec.randomId();
            await save();
            await runtime.publishRaw(
              scopeId: state['child'],
              id: state['record'],
              type: 'project',
              operationId: state['recordOp'],
              expectedRevision: 0,
              rawPayload: raw,
              localHash: await CryptoBusinessJson.hash(raw),
            );
            state['published'] = true;
            await save();
          }
          state['inviteRequest'] ??= codec.randomId();
          await save();
          state['invite'] ??= await sender.dispatch('invitations3.create', {
            'scopeId': state['parent'],
            'recipient': fixture['accounts']['other']['username'],
            'role': 'member',
            'language': 'en',
            'requestId': state['inviteRequest'],
          });
          await save();
          final invite = await receiver.inspect(
            token: state['invite']['localToken'],
          );
          await receiver.accept(invite, actionId: invite.invitation['id']);
          state['prepared'] = true;
          await save();
        }
        http.child = state['child'];
        final id = state['invite']['invitation']['id'] as String;
        if (state['stoppedBeforeHead'] != true) {
          final recipient = await sender.acceptedRecipient(state['parent'], id);
          final review = await manager.reviewRotation(state['parent']);
          http.stop = 'before-head';
          await expectLater(
            sender.admit(recipient, review),
            throwsA(
              isA<CollaborationApiException>().having(
                (e) => e.code,
                'code',
                'rate_limited',
              ),
            ),
          );
          expect(http.interruptedRequest, isNotNull);
          state['headRequest'] = http.interruptedRequest;
          final saved = await draft();
          state['draft'] = saved;
          state['keys'] = await keyDigest();
          state['stoppedBeforeHead'] = true;
          await save();
        }
        await receiver.resumeAccepted(
          id,
        ); // normal parent receipt/key admission
        if (state['advancedBeforePublication'] != true) {
          await appendObservation(owner, oa);
          await appendObservation(guest, ga);
          state['advancedBeforePublication'] = true;
          await save();
        }
        if (state['stoppedDuringGrants'] != true) {
          http.stop = 'during-grants';
          await expectLater(
            CryptoInheritedInvitationGrants(oa).finish(state['parent'], id),
            throwsA(
              isA<CollaborationApiException>().having(
                (e) => e.code,
                'code',
                'rate_limited',
              ),
            ),
          );
          state['grantRequest'] = http.interruptedRequest;
          expect(
            await cryptoSha256(CryptoJson.encode(await draft())) ==
                await cryptoSha256(CryptoJson.encode(state['draft'])),
            isTrue,
            reason: 'Original pending body/head must survive first resume',
          );
          expect(
            await keyDigest() == state['keys'],
            isTrue,
            reason: 'DEKs and key IDs must survive first resume',
          );
          state['stoppedDuringGrants'] = true;
          await save();
        }
        if (state['advancedAfterPublication'] != true) {
          await appendObservation(owner, oa);
          await appendObservation(guest, ga);
          state['advancedAfterPublication'] = true;
          await save();
        }
        final acceptsBefore = http.operations
            .where((op) => op == 'crypto2.invitations.accept')
            .length;
        final activationsBefore = http.operations
            .where((op) => op == 'crypto2.scope.activate')
            .length;
        await CryptoInheritedInvitationGrants(oa).finish(state['parent'], id);
        final active = await oa.currentHead(state['child'], online: true);
        expect(active.headHash == state['draft']['headHash'], isTrue);
        expect(active.member(guest.directory.accountId)['role'], 'member');
        expect(
          await keyDigest() == state['keys'],
          isTrue,
          reason: 'Final activation must keep the original DEKs/key IDs',
        );
        expect(
          await cryptoSha256(CryptoJson.encode(await draft())) ==
              await cryptoSha256(CryptoJson.encode(state['draft'])),
          isTrue,
        );
        expect(
          http.operations
              .where((op) => op == 'crypto2.invitations.accept')
              .length,
          acceptsBefore,
        );
        expect(
          http.operations.where((op) => op == 'crypto2.scope.activate').length -
              activationsBefore,
          1,
          reason: 'Only the child activates in final continuation',
        );
        final headProof =
            CryptoJson.decode(
                  cryptoBase64(active.authorization['commandBase64']),
                )
                as Map;
        expect(
          headProof['requestId'] == state['headRequest'],
          isTrue,
          reason: 'Original pending publication request is retained',
        );
        final guestRuntime = CryptoBusinessSession(
          guest,
          ga,
          guest.store.database,
        );
        await guestRuntime.pullVerified(state['child'], 'content');
        final record = await guestRuntime.record(
          state['child'],
          'content',
          state['record'],
          type: 'project',
        );
        expect(record, isNotNull);
        final decoded = jsonDecode(record!['raw_payload'] as String) as Map;
        expect(decoded['title'], 'Retained encrypted child history');
        expect(decoded['description'], 'Original private child description');
        state['complete'] = true;
        await save();
        debugPrint(
          'INTERRUPTED_CHILD_RESUME ${jsonEncode({'synthetic': true, 'beforeAndAfterPublication': true, 'sameHeadAndKeys': true, 'sameRequestBytes': true, 'noSecondAcceptOrParentActivation': true, 'normalGuestRead': true, 'operations': http.operations.length})}',
        );
      } finally {
        http.close();
        for (final db in dbs) {
          await db.close();
        }
      }
    },
    skip: path == null,
    timeout: const Timeout(Duration(minutes: 12)),
  );
}
