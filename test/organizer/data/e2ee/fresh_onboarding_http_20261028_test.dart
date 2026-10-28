import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/local_vault_keys.dart';
import 'package:kanban/organizer/data/recovery_bundle.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_repository.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/account_protection_ready.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_identity_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_router.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_scope_observations.dart';
import 'package:kanban/organizer/data/e2ee/invite_crypto_repository.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:sodium/sodium.dart';

class _PrivateSyntheticStore implements AccountCryptoStore {
  _PrivateSyntheticStore(this.file);
  final File file;
  Future<void> tail = Future.value();
  Future<Map<String, dynamic>> all() async => await file.exists()
      ? Map<String, dynamic>.from(jsonDecode(await file.readAsString()) as Map)
      : {};
  @override
  Future<String?> read(String partition) async {
    await tail;
    return (await all())[partition] as String?;
  }

  @override
  Future<void> write(String partition, String value) {
    final task = tail.then((_) async {
      final rows = await all();
      rows[partition] = value;
      await file.writeAsString(jsonEncode(rows), flush: true);
    });
    tail = task;
    return task;
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
      allowLocalHttp: true,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        device['expiresAt'] * 1000,
      ),
    ),
    wire['token'],
  );
}

/// Three distinct stages keep successful setup/sharing out of subsequent runs.
/// Only newly seeded loopback accounts and private disposable files are allowed.
void main() {
  final fixturePath = Platform.environment['JIVIE_FRESH_HTTP_FIXTURE'];
  final phase = Platform.environment['JIVIE_FRESH_HTTP_PHASE'] ?? 'setup';
  test(
    'fresh one-file signed HTTP $phase',
    () async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final fixtureFile = File(fixturePath!);
      final fixture = jsonDecode(await fixtureFile.readAsString()) as Map;
      final url = fixture['serverUrl'] as String;
      if (fixture['synthetic'] != true ||
          Uri.parse(url).host != '127.0.0.1' ||
          Uri.parse(url).port != 57881) {
        throw StateError('Dedicated fresh fixture only');
      }
      final stateDir = Directory('${fixtureFile.parent.path}/clients');
      await stateDir.create(recursive: true);
      final journal = File('${stateDir.path}/progress.json');
      final state = await journal.exists()
          ? Map<String, dynamic>.from(
              jsonDecode(await journal.readAsString()) as Map,
            )
          : <String, dynamic>{};
      Future<void> save() =>
          journal.writeAsString(jsonEncode(state), flush: true);
      expect(
        state['${phase}Passed'],
        isNot(true),
        reason: 'Do not repeat a passed stage',
      );
      final crypto = CryptoCodec(await SodiumInit.init());
      final http = HttpCollaborationTransport();
      final databases = <CollaborationDatabase>[];
      AccountCryptoV2Workflow make(String name, DeviceSession session) {
        final db = CollaborationDatabase(
          NativeDatabase(File('${stateDir.path}/$name.sqlite')),
        );
        databases.add(db);
        return AccountCryptoV2Workflow(
          AccountDirectoryRepository(
            reducer: AccountDirectoryV2(crypto),
            session: session,
            transport: http,
            store: CryptoIdentityStore(
              db,
              _PrivateSyntheticStore(File('${stateDir.path}/$name.keys')),
              session.profile.partition,
            ),
            isCurrent: () => true,
          ),
        );
      }

      final owner = make(
        'owner',
        _session(url, fixture['accounts']['owner']['session']),
      );
      final guest = make(
        'other',
        _session(url, fixture['accounts']['other']['session']),
      );
      try {
        if (phase == 'setup') {
          for (final entry in [('owner', owner), ('other', guest)]) {
            final (name, account) = entry;
            if (state['${name}Setup'] == true) continue;
            final saved = File('${stateDir.path}/$name.jivie-recovery');
            if (!await saved.exists()) {
              final accountBytes = await account.prepareRecoveryFile();
              final key = LocalVaultKey.generate();
              final localBytes = Uint8List.fromList(utf8.encode(key.encode()));
              final combined = RecoveryBundleCodec.wrap(
                localBytes,
                accountBytes,
              );
              try {
                await saved.writeAsBytes(combined, flush: true);
              } finally {
                accountBytes.fillRange(0, accountBytes.length, 0);
                localBytes.fillRange(0, localBytes.length, 0);
                key.bytes.fillRange(0, key.bytes.length, 0);
                combined.fillRange(0, combined.length, 0);
              }
            }
            final combined = await saved.readAsBytes();
            try {
              if (!await account.hasSavedSetup() &&
                  await account.localPhase() != 'ready') {
                await account.confirmSavedRecoveryFile(combined);
              }
              await account.resumeSavedSetup();
              expect(await account.localPhase(), 'ready');
              final completion = AccountProtectionReady(account);
              expect(await completion.completeFreshSetup(), true);
              expect(await completion.cachedCompletion(), isNotNull);
              completion.close();
              await account.finishSavedSetup();
              expect(await account.hasSavedSetup(), false);
            } finally {
              combined.fillRange(0, combined.length, 0);
            }
            state['${name}Setup'] = true;
            await save();
          }
        } else if (phase == 'sharing') {
          expect(state['setupPassed'], true);
          final ownerAccess = SessionCryptoAccess(account: owner);
          final guestAccess = SessionCryptoAccess(account: guest);
          final runtime = CryptoBusinessSession(
            owner,
            ownerAccess,
            owner.store.database,
          );
          final scope = (state['scope'] ??= crypto.randomId()) as String;
          if (state['scopeCreated'] != true) {
            await save();
            await runtime.createScope({
              'id': scope,
              'kind': 'household',
              'name': 'Fresh one-file household',
              'requestId': state['scopeRequest'] ??= crypto.randomId(),
            });
            state['scopeCreated'] = true;
            await save();
          }
          final id = (state['record'] ??= crypto.randomId()) as String;
          final raw =
              Map<String, dynamic>.from(
                  LocalProject(
                    id: id,
                    title: 'ONE-FILE-RECOVERY-CONTENT',
                    description: 'Synthetic content remains encrypted',
                    createdAt: DateTime.utc(2026, 10, 28),
                    updatedAt: DateTime.utc(2026, 10, 28),
                    area: ProjectArea.home,
                  ).toJson(),
                )
                ..remove('id')
                ..remove('revision')
                ..remove('createdByAccountId')
                ..remove('updatedByAccountId');
          if (state['published'] != true) {
            final operation =
                (state['publishRequest'] ??= crypto.randomId()) as String;
            await save();
            await runtime.publishRaw(
              scopeId: scope,
              id: id,
              type: 'project',
              operationId: operation,
              expectedRevision: 0,
              rawPayload: raw,
              localHash: await CryptoBusinessJson.hash(raw),
            );
            state['published'] = true;
            await save();
          }
          final sender = InviteCryptoRepository(ownerAccess),
              receiver = InviteCryptoRepository(guestAccess);
          if (state['invitation'] == null) {
            state['inviteRequest'] ??= crypto.randomId();
            await save();
            state['invitation'] = await sender.dispatch('invitations3.create', {
              'scopeId': scope,
              'recipient': fixture['accounts']['other']['username'],
              'role': 'member',
              'language': 'en',
              'requestId': state['inviteRequest'],
            });
            await save();
          }
          final invitation = state['invitation'] as Map;
          final inviteId = invitation['invitation']['id'] as String;
          if (state['accepted'] != true) {
            final preview = await receiver.inspect(
              token: invitation['localToken'],
            );
            await receiver.trustCreatorFromDirectory(preview);
            await receiver.accept(preview, actionId: inviteId);
            state['accepted'] = true;
            await save();
          }
          final approval = await sender.processForegroundAutoApprovals(
            isForegroundCurrent: () => true,
            invitationIds: {inviteId},
          );
          expect(approval.pending, 0);
          expect(await receiver.resumeAccepted(inviteId), scope);
          final guestRuntime = CryptoBusinessSession(
            guest,
            guestAccess,
            guest.store.database,
          );
          await guestRuntime.pullVerified(scope, 'content');
          final received = await guestRuntime.record(scope, 'content', id);
          final business = Map<String, dynamic>.from(
            jsonDecode(received!['raw_payload'] as String) as Map,
          )..remove('_recordPolicy');
          expect(business, raw);
          await CryptoScopeObservations(owner).observe(ownerAccess, scope);
        } else if (phase == 'recovery') {
          expect(state['sharingPassed'], true);
          if (state['coldSession'] == null) {
            final user = fixture['accounts']['owner'];
            state['coldSession'] = await http.call(
              serverUrl: url,
              operation: 'auth.login',
              params: {
                'username': user['username'],
                'password': user['password'],
                'deviceName': 'Fresh unified FILE recovery',
              },
              allowLocalHttp: true,
            );
            await save();
          }
          final cold = make('recovered', _session(url, state['coldSession']));
          final combined = await File(
            '${stateDir.path}/owner.jivie-recovery',
          ).readAsBytes();
          try {
            final local = LocalVaultKey.decode(utf8.decode(combined));
            expect(local.bytes.length, 32);
            local.bytes.fillRange(0, local.bytes.length, 0);
            await cold.recover(combined);
            await cold.restoreScopesFromFile(combined);
            final access = SessionCryptoAccess(account: cold);
            final restored = CryptoBusinessSession(
              cold,
              access,
              cold.store.database,
            );
            await restored.pullVerified(state['scope'], 'content');
            final row = await restored.record(
              state['scope'],
              'content',
              state['record'],
            );
            expect(
              (jsonDecode(row!['raw_payload'] as String) as Map)['title'],
              'ONE-FILE-RECOVERY-CONTENT',
            );
          } finally {
            combined.fillRange(0, combined.length, 0);
          }
        } else {
          throw StateError('Unknown stage');
        }
        state['${phase}Passed'] = true;
        await save();
      } finally {
        http.close();
        for (final db in databases) {
          await db.close();
        }
      }
    },
    skip: fixturePath == null,
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
