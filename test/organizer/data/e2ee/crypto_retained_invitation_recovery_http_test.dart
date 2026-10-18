import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_repository.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/account_protection_ready.dart';
import 'package:kanban/organizer/data/e2ee/crypto_archive_cold_database.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_router.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_identity_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_migration_coordinator.dart';
import 'package:kanban/organizer/data/e2ee/crypto_scope_observations.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/data/e2ee/invite_crypto_repository.dart';
import 'package:kanban/organizer/data/e2ee/scope_crypto_manager.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:sodium/sodium.dart' show SodiumInit;

class _Secure implements AccountCryptoStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

class _ProtectionHttpClient extends http.BaseClient {
  _ProtectionHttpClient(this.owner);
  final _Http owner;
  final _wire = http.Client();
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = (request as http.Request).body;
    final command = jsonDecode(body) as Map;
    if (command['op'] == 'crypto2.account.protectionReady') {
      owner.protectionBodies.add(body);
      if (owner.pauseProtection) {
        owner.pauseProtection = false;
        // Exercise the production transport's HTTP429 decoding and pause zone.
        return http.StreamedResponse(
          Stream.value(
            utf8.encode(
              jsonEncode({
                'v': 1,
                'error': {
                  'code': 'rate_limited',
                  'details': {'retryAfter': 1},
                },
              }),
            ),
          ),
          429,
          headers: {'content-type': 'application/json'},
        );
      }
    }
    return _wire.send(request);
  }

  @override
  void close() => _wire.close();
}

class _Http implements CollaborationTransport {
  _Http() {
    inner = HttpCollaborationTransport(client: _ProtectionHttpClient(this));
  }
  late final HttpCollaborationTransport inner;
  @override
  void close() => inner.close();
  bool pauseProtection = false, loseProtection = false;
  String? _withheldRequestId, _withheldRequestHash;
  int withheldReceiptQueries = 0;
  final protectionBodies = <String>[];
  void resumeProtectionReceipt() {
    if (_withheldRequestId == null || _withheldRequestHash == null) {
      throw StateError('No exact protection receipt is waiting');
    }
    _withheldRequestId = null;
    _withheldRequestHash = null;
  }

  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    if (operation == 'crypto2.receipt.get' &&
        _withheldRequestId != null &&
        params['requestId'] == _withheldRequestId &&
        params['requestHash'] == _withheldRequestHash) {
      withheldReceiptQueries++;
      throw const CollaborationException('network');
    }
    final result = await inner.call(
      serverUrl: serverUrl,
      operation: operation,
      params: params,
      token: token,
      allowLocalHttp: allowLocalHttp,
    );
    if (operation == 'crypto2.account.protectionReady' && loseProtection) {
      loseProtection = false;
      final bytes = cryptoBase64(params['commandBase64']);
      final command = CryptoJson.decode(bytes) as Map;
      _withheldRequestId = command['requestId'] as String;
      _withheldRequestHash = await cryptoSha256(bytes);
      throw const CollaborationException('network');
    }
    return result;
  }
}

/// Opt-in, synthetic-loopback-only checkpoint for the unchanged postcommit
/// tail. Private snapshots are never imported into production or a live queue.
Future<Directory?> _retainedCheckpointDirectory() async {
  final path =
      Platform.environment['JIVIE_RETAINED_RECOVERY_DIAGNOSTIC_DIRECTORY'];
  if (path == null) return null;
  final target = Directory(path);
  if (!target.isAbsolute) throw StateError('Checkpoint path must be absolute');
  final parent = await target.parent.resolveSymbolicLinks(),
      repository = await Directory.current.resolveSymbolicLinks();
  if (parent == repository ||
      parent.startsWith('$repository/') ||
      (await Directory(parent).stat()).mode & 0x3f != 0) {
    throw StateError(
      'Checkpoint requires a private directory outside the repository',
    );
  }
  final output = Directory(
    '$parent/${target.uri.pathSegments.where((s) => s.isNotEmpty).last}',
  );
  // mkdir is exclusive; protect the new directory before any secret is written.
  final created = await Process.run('/bin/mkdir', ['-m', '700', output.path]);
  if (created.exitCode != 0) {
    throw StateError('Cannot create private checkpoint');
  }
  return output;
}

Future<void> _saveRetainedCheckpoint(
  Directory? directory,
  String role,
  AccountCryptoV2Workflow account,
  Uint8List recoveryFile,
) async {
  if (directory == null) return;
  Future<File> privateFile(String suffix) async {
    final output = File('${directory.path}/$role.$suffix');
    await output.create(exclusive: true);
    final permissions = await Process.run('/bin/chmod', ['600', output.path]);
    if (permissions.exitCode != 0) {
      throw StateError('Cannot protect checkpoint');
    }
    return output;
  }

  final secure = account.store.secure;
  if (secure is! _Secure) throw StateError('Synthetic secure store required');
  final database = await privateFile('sqlite');
  final quotedPath = database.path.replaceAll("'", "''");
  await account.store.database.execute("VACUUM INTO '$quotedPath'");
  final session = account.directory.session;
  await (await privateFile('session.json')).writeAsString(
    jsonEncode({'profile': session.profile.toJson(), 'token': session.token}),
    flush: true,
  );
  await (await privateFile(
    'secure.json',
  )).writeAsString(jsonEncode(secure.values), flush: true);
  await (await privateFile(
    'recovery.file',
  )).writeAsBytes(recoveryFile, flush: true);
}

void main() {
  final path = Platform.environment['JIVIE_RETAINED_RECOVERY_HTTP_FIXTURE'];
  test(
    'committed retained email invitation admits exact recipient; FILE owner rotates and protection resumes after Later and lost ACK',
    () async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final f = jsonDecode(await File(path!).readAsString()) as Map;
      if (f['synthetic'] != true ||
          Uri.parse(f['serverUrl']).host != '127.0.0.1') {
        throw StateError('Synthetic loopback only');
      }
      final http = _Http(), crypto = CryptoCodec(await SodiumInit.init());
      final temp = await Directory.systemTemp.createTemp(
        'synthetic-retained-final-',
      );
      final databases = <CollaborationDatabase>[];
      AccountCryptoV2Workflow workflow(Map wire) {
        final u = wire['user'] as Map, d = wire['device'] as Map;
        final login = DeviceSession(
          AccountSession(
            serverUrl: f['serverUrl'],
            serverId: wire['serverId'],
            accountId: u['accountId'],
            userId: u['id'],
            username: u['username'],
            displayName: u['displayName'],
            deviceId: d['id'],
            expiresAt: DateTime.fromMillisecondsSinceEpoch(
              d['expiresAt'] * 1000,
            ),
            allowLocalHttp: true,
          ),
          wire['token'],
        );
        final db = CollaborationDatabase(NativeDatabase.memory());
        databases.add(db);
        return AccountCryptoV2Workflow(
          AccountDirectoryRepository(
            reducer: AccountDirectoryV2(crypto),
            session: login,
            transport: http,
            store: CryptoIdentityStore(db, _Secure(), login.profile.partition),
            isCurrent: () => true,
          ),
        );
      }

      final checkpoint = await _retainedCheckpointDirectory();
      final owner = workflow(f['session']),
          guest = workflow(f['recipientSession']);
      Uint8List? file, guestFile;
      Future<T> readRetry<T>(Future<T> Function() action) =>
          withCollaborationRateLimitPause(
            action,
            pause: (s) => Future<void>.delayed(Duration(seconds: s)),
          );
      try {
        file = await owner.prepareRecoveryFile();
        await owner.verifyAndInitialize(file);
        guestFile = await guest.prepareRecoveryFile();
        await guest.verifyAndInitialize(guestFile);
        final coordinator = CryptoMigrationCoordinator(
          account: owner,
          coldDatabase: () => CryptoArchiveColdDatabase.create(parent: temp),
        );
        try {
          final prepared = await coordinator.prepare(f['scopeId']);
          final review = await coordinator.review(prepared.migrationId!);
          await coordinator.fence(
            prepared.migrationId!,
            reviewedInventoryHash: review.inventoryHash,
          );
          CryptoMigrationState? completed;
          for (var attempt = 0; attempt < 5; attempt++) {
            try {
              completed = await coordinator.archiveAndVerify(
                prepared.migrationId!,
                recoveryFile: file,
              );
              break;
            } on CollaborationApiException catch (e) {
              final seconds = e.details['retryAfter'];
              if (e.code != 'rate_limited' ||
                  seconds is! int ||
                  seconds < 1 ||
                  seconds > 60) {
                rethrow;
              }
              await Future<void>.delayed(Duration(seconds: seconds + 1));
            }
          }
          expect(completed?.phase, CryptoMigrationPhase.committed);
        } finally {
          await coordinator.close();
        }
        await _saveRetainedCheckpoint(
          checkpoint,
          'committedOwner',
          owner,
          file,
        );
        await _saveRetainedCheckpoint(
          checkpoint,
          'committedGuest',
          guest,
          guestFile,
        );
        final scope = f['scopeId'] as String,
            legacy = (f['legacyInvitations'] as List).first as Map;
        final ownerAccess = SessionCryptoAccess(account: owner),
            receiver = InviteCryptoRepository(
              SessionCryptoAccess(account: guest),
            );
        final inspected = await readRetry(
          () => receiver.inspect(token: legacy['token']),
        );
        expect(inspected.legacyEvidence, isNotNull);
        expect(inspected.invitation['recipient']['accountId'], isNull);
        await receiver.compareCreator(
          inspected,
          await ownerAccess.identities.publicCard(
            await owner.directory.cachedVerifiedDirectory(),
          ),
        );
        final accepted = await readRetry(
          () => receiver.accept(inspected, actionId: legacy['id']),
        );
        expect(accepted['state'], 'pendingKeys');
        final sender = InviteCryptoRepository(ownerAccess);
        final recipient = await readRetry(
          () => sender.acceptedRecipient(scope, legacy['id']),
        );
        await sender.compareCreator(
          recipient,
          await receiver.access.identities.publicCard(
            await guest.directory.cachedVerifiedDirectory(),
          ),
        );
        final rotation = await readRetry(
          () => ScopeCryptoManager(ownerAccess).reviewRotation(scope),
        );
        await readRetry(() => sender.admit(recipient, rotation));
        await _saveRetainedCheckpoint(checkpoint, 'admittedOwner', owner, file);
        await _saveRetainedCheckpoint(
          checkpoint,
          'admittedGuest',
          guest,
          guestFile,
        );
        // A fresh Session reopens a consumed email bridge whose original capsule
        // had no account ID. Its signed acceptance supplies that exact binding.
        expect(
          await readRetry(
            () => InviteCryptoRepository(
              SessionCryptoAccess(account: guest),
            ).resumeAccepted(legacy['id']),
          ),
          scope,
        );
        await readRetry(
          () => CryptoScopeObservations(owner).observe(ownerAccess, scope),
        );
        final login = await readRetry(
          () => http.call(
            serverUrl: f['serverUrl'],
            operation: 'auth.login',
            allowLocalHttp: true,
            params: {
              'username': f['username'],
              'password': f['password'],
              'deviceName': 'Synthetic recovered writable owner',
            },
          ),
        );
        final cold = workflow(login);
        await readRetry(() => cold.recover(file!));
        await readRetry(
          () => CryptoScopeObservations(cold).hydrateObservedScopes(file!),
        );
        final access = SessionCryptoAccess(account: cold);
        final before = await readRetry(
          () => access.currentHead(scope, online: true),
        );
        final oldHead = before.headHash;
        final manager = ScopeCryptoManager(access);
        final review = await readRetry(() => manager.reviewRotation(scope));
        expect(review.sourceHeadHash, oldHead);
        await _saveRetainedCheckpoint(checkpoint, 'reviewCold', cold, file);
        String? confirmedHead;
        http.pauseProtection = true;
        final canceled = AccountProtectionReady(cold);
        Future<void> cancelAfterExplicitReview() async {
          void later(int seconds) {
            if (seconds > 0) canceled.close();
          }

          try {
            await canceled.complete(onPause: later);
          } on CryptoAuthorityPending catch (error) {
            if (error.reason != 'protection_scope_action_required') rethrow;
            final action = await canceled.pendingScopeAction();
            if (action?['reason'] != 'scope_review_confirmation_required') {
              rethrow;
            }
            expect(review.historyBasis, 'reviewedRecoveryBaseline');
            final proposed = await manager.proposedMembers(review);
            final roster = proposed ?? before.members;
            final accountIds = roster.map((m) => m['accountId']).toSet();
            expect(
              accountIds.length == 2 &&
                  accountIds.containsAll({
                    (f['session']['user'] as Map)['accountId'],
                    (f['recipientSession']['user'] as Map)['accountId'],
                  }),
              isTrue,
              reason: 'Reviewed fixture roster is exact',
            );
            final count = review.domains.values.fold<int>(
              0,
              (n, value) => n + ((value as Map)['count'] as int),
            );
            expect(count, lessThanOrEqualTo(20));
            final preview = await manager.previewRotation(review, limit: 20);
            try {
              expect(preview, hasLength(count));
              Map? task;
              for (final row in preview) {
                if (row.plaintext == null) continue;
                final envelope = jsonDecode(utf8.decode(row.plaintext!)) as Map;
                if ((envelope['identity'] as Map)['canonicalId'] ==
                    f['taskId']) {
                  task = envelope['payload'] as Map;
                }
              }
              expect(
                equals(jsonDecode(f['payload'] as String)).matches(task, {}),
                isTrue,
                reason: 'Reviewed captured task content matches fixture',
              );
            } finally {
              for (final row in preview) {
                row.dispose();
              }
            }
            // Explicit synthetic acceptance of the same existing UI review.
            // Production ProtectionReady never accepts candidate history.
            final confirmed = await readRetry(
              () => manager.confirmRotation(
                review,
                acceptedCandidateHistory: true,
              ),
            );
            confirmedHead = confirmed.headHash;
            await _saveRetainedCheckpoint(
              checkpoint,
              'confirmedCold',
              cold,
              file!,
            );
            await canceled.complete(onPause: later);
          }
        }

        await expectLater(
          cancelAfterExplicitReview(),
          throwsA(
            isA<CryptoAuthorityPending>().having(
              (error) => error.reason,
              'reason',
              'protection_completion_cancelled',
            ),
          ),
        );
        http.loseProtection = true;
        await expectLater(
          AccountProtectionReady(cold).complete(),
          throwsA(isA<CollaborationException>()),
        );
        expect(http.withheldReceiptQueries, greaterThan(0));
        http.resumeProtectionReceipt();
        final done = AccountProtectionReady(cold);
        await done.complete();
        expect(await done.cachedCompletion(), isNotNull);
        expect(http.protectionBodies.toSet(), hasLength(1));
        final current = await access.currentHead(scope, online: true);
        if (confirmedHead != null) {
          expect(current.headHash, confirmedHead);
        }
        expect(current.headHash, isNot(oldHead));
        expect(
          current.member(cold.directory.accountId)['deviceSnapshotHash'],
          (await cold.directory.cachedVerifiedDirectory()).deviceSnapshotHash,
        );
        final runtime = CryptoBusinessSession(
              cold,
              access,
              cold.store.database,
            ),
            id = crypto.randomId();
        final date = DateTime.now().toUtc().toIso8601String();
        await runtime.publishRaw(
          scopeId: scope,
          id: id,
          type: 'shoppingList',
          operationId: crypto.randomId(),
          expectedRevision: 0,
          rawPayload: {
            'title': 'Recovered owner can write',
            'createdAt': date,
            'updatedAt': date,
          },
          localHash: 'a' * 64,
        );
        await runtime.pullVerified(scope, 'content');
        expect(
          await runtime.record(scope, 'content', id, type: 'shoppingList'),
          isNotNull,
        );
      } catch (_) {
        if (file != null) {
          try {
            await _saveRetainedCheckpoint(
              checkpoint,
              'failureOwner',
              owner,
              file,
            );
          } catch (_) {
            // Optional diagnostics must not replace the original failure.
          }
        }
        if (guestFile != null) {
          try {
            await _saveRetainedCheckpoint(
              checkpoint,
              'failureGuest',
              guest,
              guestFile,
            );
          } catch (_) {
            // Try both accounts, preserving the original failure and stack.
          }
        }
        rethrow;
      } finally {
        file?.fillRange(0, file.length, 0);
        guestFile?.fillRange(0, guestFile.length, 0);
        for (final db in databases) {
          await db.close();
        }
        http.inner.close();
        await temp.delete(recursive: true);
      }
    },
    skip: path == null,
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
