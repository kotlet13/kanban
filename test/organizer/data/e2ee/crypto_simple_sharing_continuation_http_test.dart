import 'package:kanban/organizer/data/e2ee/crypto_inherited_invitation_grants.dart';
import 'package:kanban/organizer/data/e2ee/crypto_scope_observations.dart';
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

class _TrackedHttp extends HttpCollaborationTransport {
  final operations = <String>[];
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
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

// Each phase targets the SAME private synthetic clients and server state.
// Never run this against retained QA or a non-loopback endpoint.
void main() {
  final path = Platform.environment['JIVIE_SIMPLE_SHARING_HTTP_FIXTURE'];
  final phase = Platform.environment['JIVIE_SIMPLE_SHARING_PHASE'] ?? 'prepare';
  test(
    'real parent existing-child simplified sharing $phase',
    () async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final fixture = jsonDecode(await File(path!).readAsString()) as Map;
      final url = fixture['serverUrl'] as String;
      if (fixture['synthetic'] != true || Uri.parse(url).host != '127.0.0.1') {
        throw StateError('Synthetic loopback only');
      }
      final stateDir = Directory(fixture['clientStateDir'] as String);
      final journal = File('${stateDir.path}/continuation.json');
      final state = await journal.exists()
          ? Map<String, dynamic>.from(
              jsonDecode(await journal.readAsString()) as Map,
            )
          : <String, dynamic>{};
      Future<void> save() async =>
          journal.writeAsString(jsonEncode(state), flush: true);
      final crypto = CryptoCodec(await SodiumInit.init()),
          http = _TrackedHttp();
      final databases = <CollaborationDatabase>[];
      AccountCryptoV2Workflow make(DeviceSession session) {
        final id = session.profile.deviceId;
        final db = CollaborationDatabase(
          NativeDatabase(File('${stateDir.path}/$id.sqlite')),
        );
        databases.add(db);
        return AccountCryptoV2Workflow(
          AccountDirectoryRepository(
            reducer: AccountDirectoryV2(crypto),
            session: session,
            transport: http,
            store: CryptoIdentityStore(
              db,
              _DiskSecure(File('${stateDir.path}/$id.secure.json')),
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
      final ownerAccess = SessionCryptoAccess(account: owner);
      final guestAccess = SessionCryptoAccess(account: guest);
      final ownerRuntime = CryptoBusinessSession(
        owner,
        ownerAccess,
        owner.store.database,
      );
      final manager = ScopeCryptoManager(ownerAccess),
          sender = InviteCryptoRepository(ownerAccess),
          receiver = InviteCryptoRepository(guestAccess);
      Future<Map<String, dynamic>> invite(String scopeId) =>
          sender.dispatch('invitations3.create', {
            'scopeId': scopeId,
            'recipient': fixture['accounts']['other']['username'],
            'role': 'member',
            'language': 'en',
            'requestId': crypto.randomId(),
          });
      Future<String> createScope(
        String kind,
        String name, {
        String? parent,
      }) async {
        final id = crypto.randomId();
        await ownerRuntime.createScope({
          'id': id,
          'kind': kind,
          'name': name,
          'requestId': crypto.randomId(),
          if (parent != null) 'parentScopeId': parent,
        });
        return id;
      }

      try {
        if (phase == 'prepare') {
          expect(
            state['prepared'],
            isNot(true),
            reason: 'Never repeat successful preparation',
          );
          for (final (who, account) in [('owner', owner), ('other', guest)]) {
            if (await account.localPhase() == 'ready') continue;
            final savedFile = File('${stateDir.path}/$who.file');
            final file = await savedFile.exists()
                ? await savedFile.readAsBytes()
                : await account.prepareRecoveryFile();
            await File(
              '${stateDir.path}/$who.file',
            ).writeAsBytes(file, flush: true);
            try {
              await account.verifyAndInitialize(file);
            } finally {
              file.fillRange(0, file.length, 0);
            }
          }
          state['parent'] ??= await createScope(
            'organization',
            'Synthetic inherited parent',
          );
          state['child'] ??= await createScope(
            'project',
            'Synthetic existing child',
            parent: state['parent'],
          );
          final record = (state['record'] ??= crypto.randomId()) as String,
              now = DateTime.utc(2026, 10, 19);
          final raw =
              Map<String, dynamic>.from(
                  LocalProject(
                    id: record,
                    title: 'Existing child private history',
                    description: 'Synthetic history before parent invite',
                    createdAt: now,
                    updatedAt: now,
                    area: ProjectArea.home,
                  ).toJson(),
                )
                ..remove('id')
                ..remove('revision')
                ..remove('createdByAccountId')
                ..remove('updatedByAccountId');
          state['record'] = record;
          state['raw'] = raw;
          if (state['recordPublished'] != true) {
            await ownerRuntime.publishRaw(
              scopeId: state['child'],
              id: record,
              type: 'project',
              operationId:
                  (state['recordOperation'] ??= crypto.randomId()) as String,
              expectedRevision: 0,
              rawPayload: raw,
              localHash: await CryptoBusinessJson.hash(raw),
            );
          }
          state['recordPublished'] = true;
          state['parentInvitation'] ??= await invite(state['parent']);
          final pending = await receiver.inspect(
            token: state['parentInvitation']['localToken'],
          );
          await receiver.trustCreatorFromDirectory(pending);
          state['guard'] ??= await createScope(
            'household',
            'Synthetic changed root guard',
          );
          state['guardInvitation'] ??= await invite(state['guard']);
          await CryptoScopeObservations(
            owner,
          ).observe(ownerAccess, state['guard']);
          state['freshGuardInvitation'] ??= await invite(state['guard']);
          final later = await receiver.inspect(
            token: state['freshGuardInvitation']['localToken'],
          );
          expect(
            later.creator.generation,
            greaterThan(pending.creator.generation),
          );
          expect(
            later.creator.deviceSnapshotHash,
            pending.creator.deviceSnapshotHash,
          );
          await receiver.trustCreatorFromDirectory(later);
          final newer = (await guest.store.anchor(owner.directory.accountId))!;
          final id = state['parentInvitation']['invitation']['id'] as String;
          final before = http.operations
              .where((v) => v == 'crypto2.invitations.accept')
              .length;
          expect(
            (await receiver.accept(pending, actionId: id))['state'],
            'pendingKeys',
          );
          expect(
            (await receiver.accept(pending, actionId: id))['state'],
            'pendingKeys',
          );
          expect(
            http.operations
                .where((v) => v == 'crypto2.invitations.accept')
                .length,
            before + 1,
          );
          expect(
            (await guest.store.anchor(owner.directory.accountId))!['headHash'],
            newer['headHash'],
          );
          state['prepared'] = true;
          await save();
          debugPrint(
            'PASS: same original parent invite accepted idempotently under newer signed same-device directory; existing child remains pre-grant',
          );
        } else if (phase == 'grant') {
          expect(state['prepared'], true);
          expect(state['granted'], isNot(true));
          final id = state['parentInvitation']['invitation']['id'] as String;
          final status = await guest.directory.call(
            'crypto2.invitations.status',
            {'invitationId': id},
          );
          if (status['state'] == 'consumed') {
            await CryptoInheritedInvitationGrants(
              ownerAccess,
            ).finish(state['parent'], id);
          } else {
            final recipient = await sender.acceptedRecipient(
              state['parent'],
              id,
            );
            await sender.admit(
              recipient,
              await manager.reviewRotation(state['parent']),
            );
          }
          state['parentGranted'] = true;
          await save();
        } else if (phase == 'read-child') {
          expect(state['parentGranted'], true);
          expect(state['granted'], isNot(true));
          final id = state['parentInvitation']['invitation']['id'] as String;
          expect(await receiver.resumeAccepted(id), state['parent']);
          final guestRuntime = CryptoBusinessSession(
            guest,
            guestAccess,
            guest.store.database,
          );
          await guestRuntime.pullVerified(state['child'], 'content');
          final restored = await guestRuntime.record(
            state['child'],
            'content',
            state['record'],
          );
          expect(jsonDecode(restored!['raw_payload'] as String), state['raw']);
          final child = await guestAccess.currentHead(
            state['child'],
            online: true,
          );
          expect(child.member(guest.directory.accountId)['role'], 'member');
          state['granted'] = true;
          await save();
          debugPrint(
            'PASS: parent owner grant also unlocks pre-existing child encrypted history',
          );
        } else if (phase == 'changed-root') {
          expect(state['prepared'], true);
          expect(state['changedRootTested'], isNot(true));
          final id = state['guardInvitation']['invitation']['id'] as String;
          final pending = await receiver.inspect(
            token: state['guardInvitation']['localToken'],
          );
          expect(
            (await receiver.accept(pending, actionId: id))['state'],
            'pendingKeys',
          );
          final accepted = await sender.acceptedRecipient(state['guard'], id);
          await sender.trustCreatorFromDirectory(accepted);
          final pin = (await owner.store.anchor(guest.directory.accountId))!;
          final review = await manager.reviewRotation(state['guard']);
          final wire = await http.call(
            serverUrl: url,
            operation: 'auth.login',
            params: {
              'username': fixture['accounts']['other']['username'],
              'password': fixture['accounts']['other']['password'],
              'deviceName': 'Synthetic signed replacement boundary',
            },
            allowLocalHttp: true,
          );
          state['replacementSession'] = wire;
          await save();
          final replacement = make(_session(url, wire));
          final oldFile = await File(
            '${stateDir.path}/other.file',
          ).readAsBytes();
          final newFile = await replacement.prepareRootReplacement(oldFile);
          await File(
            '${stateDir.path}/replacement.file',
          ).writeAsBytes(newFile, flush: true);
          try {
            await replacement.verifyAndRotateRoot(
              oldExternalFile: oldFile,
              newExternalFile: newFile,
            );
          } finally {
            oldFile.fillRange(0, oldFile.length, 0);
            newFile.fillRange(0, newFile.length, 0);
          }
          expect(
            (await replacement.directory.cachedVerifiedDirectory())
                .rootFingerprint,
            isNot(pin['fingerprint']),
          );
          final before = http.operations.length;
          Object? denied;
          try {
            await sender.admit(accepted, review);
          } catch (error, stack) {
            denied = error;
            debugPrint('Changed-root primary denial: $error\n$stack');
          }
          expect(
            denied,
            isA<CollaborationException>().having(
              (e) => e.code,
              'code',
              'crypto_invitation_acceptance_required',
            ),
          );
          expect(
            http.operations
                .skip(before)
                .every((v) => v == 'crypto2.invitations.acceptance'),
            true,
          );
          expect(
            (await owner.store.anchor(
              guest.directory.accountId,
            ))!['fingerprint'],
            pin['fingerprint'],
          );
          state['changedRootTested'] = true;
          await save();
          debugPrint(
            'PASS: actual signed root replacement blocks owner admission before any key/head write; old pin retained',
          );
        } else if (phase == 'root-denial') {
          expect(state['replacementSession'], isNotNull);
          expect(state['changedRootTested'], isNot(true));
          final replacement = make(
            _session(
              url,
              Map<String, dynamic>.from(state['replacementSession'] as Map),
            ),
          );
          final pin = (await owner.store.anchor(guest.directory.accountId))!;
          final current = await replacement.directory.cachedVerifiedDirectory();
          expect(current.rootFingerprint, isNot(pin['fingerprint']));
          final before = http.operations.length;
          await expectLater(
            sender.acceptedRecipient(
              state['guard'],
              state['guardInvitation']['invitation']['id'],
            ),
            throwsA(
              isA<CollaborationException>().having(
                (e) => e.code,
                'code',
                'crypto_invitation_acceptance_required',
              ),
            ),
          );
          expect(http.operations.skip(before), [
            'crypto2.invitations.acceptance',
          ]);
          expect(
            (await owner.store.anchor(
              guest.directory.accountId,
            ))!['fingerprint'],
            pin['fingerprint'],
          );
          state['changedRootTested'] = true;
          await save();
          debugPrint(
            'PASS: same already-rotated recipient denied at server acceptance guard; original owner pin unchanged; one read request and no key/head writes',
          );
        } else {
          throw StateError('Unknown targeted phase');
        }
      } catch (error, stack) {
        await save();
        debugPrint('Primary $phase failure: $error\n$stack');
        rethrow;
      } finally {
        final counts = <String, int>{};
        for (final operation in http.operations) {
          counts.update(operation, (n) => n + 1, ifAbsent: () => 1);
        }
        debugPrint(
          'HTTP operation counts ($phase): ${jsonEncode(counts)}; total=${http.operations.length}',
        );
        http.close();
        for (final db in databases) {
          await db.close();
        }
      }
    },
    skip: path == null,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
