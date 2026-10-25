import 'dart:async';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium.dart';
import 'package:kanban/organizer/data/account_work_coordinator.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_repository.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_repository.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/account_protection_ready.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_documents.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_router.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_identity_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_migration_coordinator.dart';
import 'package:kanban/organizer/data/e2ee/invite_crypto_repository.dart';
import 'package:kanban/organizer/data/e2ee/scope_crypto_manager.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';

const _server = '10000000-0000-4000-8000-000000000001';
const _account = '10000000-0000-4000-8000-000000000002';
const _scope = '10000000-0000-4000-8000-000000000003';
const _device = '10000000-0000-4000-8000-000000000004';
const _invitation = '10000000-0000-4000-8000-000000000005';
const _stop = CollaborationApiException('synthetic_first_rpc_stop');

class _Wire implements CollaborationTransport {
  final requests =
      <({String operation, Completer<Map<String, dynamic>> reply})>[];
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) {
    final reply = Completer<Map<String, dynamic>>();
    requests.add((operation: operation, reply: reply));
    return reply.future;
  }

  @override
  void close() {}
}

class _Store implements CryptoIdentityStore {
  _Store(this.partition, this.database);
  @override
  final String partition;
  @override
  final CollaborationDatabase database;
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'No signing, journal or secret mutation in attribution fixture',
  );
}

class _Secure implements AccountCryptoStore {
  @override
  Future<String?> read(String key) async => null;
  @override
  Future<void> write(String key, String value) async =>
      throw StateError('No legacy mutation in attribution fixture');
}

/// This seam selects the first document RPC only. The production dispatch and
/// attribution wrappers run; this is not a proof/decryption/projector test.
class _DocumentContext extends CryptoBusinessSession {
  _DocumentContext(super.account, super.access, super.db);
  @override
  Future<void> pullVerified(
    String scopeId,
    String domain, {
    bool attest = true,
  }) async {
    await account.directory.call('crypto2.records.pull', {
      'scopeId': scopeId,
      'domain': domain,
    });
  }
}

class _Fixture {
  _Fixture(this.database, this.account, this.transport, this.work, this.wire);
  final CollaborationDatabase database;
  final AccountCryptoV2Workflow account;
  final CoordinatedCollaborationTransport transport;
  final AccountWorkCoordinator work;
  final _Wire wire;
  final errors = <Object>[];

  Future<void> catchStop(Future<Object?> operation) async {
    try {
      await operation;
      fail('Expected first-RPC stop');
    } catch (error) {
      errors.add(error);
      expect(identical(error, _stop), isTrue);
    }
  }

  Future<void> stopRequests(int count) async {
    var released = 0;
    for (var turn = 0; turn < 100 && released < count; turn++) {
      await Future<void>.delayed(Duration.zero);
      for (final request in wire.requests) {
        if (!request.reply.isCompleted) {
          request.reply.completeError(_stop);
          released++;
        }
      }
    }
    expect(released, count);
  }
}

Future<_Fixture> _fixture() async {
  final db = CollaborationDatabase(NativeDatabase.memory());
  final session = DeviceSession(
    AccountSession(
      serverUrl: 'https://synthetic.invalid/',
      serverId: _server,
      accountId: _account,
      userId: 1,
      username: 'synthetic',
      displayName: 'Synthetic',
      deviceId: _device,
      expiresAt: DateTime.utc(2030),
    ),
    'synthetic-token',
  );
  final wire = _Wire();
  final work = AccountWorkCoordinator();
  final owner = AccountWorkOwner(
    serverUrl: session.profile.serverUrl,
    identity: Object(),
    isCurrent: () => true,
  );
  final transport = CoordinatedCollaborationTransport(
    inner: wire,
    coordinator: work,
    ownerFor: (_, _, _, _) => owner,
  );
  final account = AccountCryptoV2Workflow(
    AccountDirectoryRepository(
      reducer: AccountDirectoryV2(CryptoCodec(await SodiumInit.init())),
      session: session,
      transport: transport,
      store: _Store(session.profile.partition, db),
      isCurrent: () => true,
    ),
  );
  addTearDown(() async {
    work.close();
    await db.close();
  });
  return _Fixture(db, account, transport, work, wire);
}

void main() {
  test(
    'direct invitation protection document and FILE recovery RPCs keep distinct jobs',
    () async {
      final f = await _fixture();
      final protection = AccountProtectionReady(f.account);
      addTearDown(protection.close);
      final access = SessionCryptoAccess(account: f.account);
      final documents = CryptoBusinessDocuments(
        _DocumentContext(f.account, access, f.database),
      );
      final material = f.account.files.create(
        serverId: _server,
        accountId: _account,
      );
      try {
        final tasks = [
          f.catchStop(
            InviteCryptoRepository(access).inspect(invitationId: _invitation),
          ),
          f.catchStop(protection.catalog()),
          f.catchStop(documents.dispatch('tables.list', {'scopeId': _scope})),
          f.catchStop(f.account.recover(material.file)),
        ];
        await f.stopRequests(4);
        await Future.wait(tasks);
      } finally {
        material.dispose();
      }
      final started = f.work.events
          .where((event) => event.event == AccountWorkEventKind.started)
          .toList();
      expect(started.map((event) => event.kind).toSet(), {
        AccountWorkKind.invitation,
        AccountWorkKind.protection,
        AccountWorkKind.documents,
        AccountWorkKind.recovery,
      });
      expect(started.length, 4);
      expect(f.wire.requests.length, 4);
      expect(f.errors.length, 4);
      expect(started.every((event) => event.activeReads <= 2), isTrue);
    },
  );

  test(
    'foreground scope fallback is nonlocking across caller await and preserves parent job',
    () async {
      final f = await _fixture();
      final dialog = Completer<void>();
      final manager = ScopeCryptoManager(
        SessionCryptoAccess(account: f.account),
      );
      final suspended = f.catchStop(
        withAccountWorkJob(
          f.transport,
          AccountWorkKind.foregroundInvitation,
          () => manager.serialize(_scope, () async {
            await dialog.future;
            return f.account.directory.call('crypto2.scope.headGet', {
              'scopeId': _scope,
            });
          }),
          priority: AccountWorkPriority.background,
        ),
      );
      final other = f.catchStop(AccountProtectionReady(f.account).catalog());
      await f.stopRequests(1);
      await other;
      expect(
        f.work.events
            .where((event) => event.event == AccountWorkEventKind.started)
            .single
            .kind,
        AccountWorkKind.protection,
      );
      dialog.complete();
      await f.stopRequests(1);
      await suspended;
      final last = f.work.events
          .where((event) => event.event == AccountWorkEventKind.started)
          .last;
      expect(last.kind, AccountWorkKind.foregroundInvitation);
      expect(last.priority, AccountWorkPriority.background);
      expect(f.errors.length, 2);
    },
  );

  test(
    'migration direct account and legacy callers inherit the same scheduled boundary',
    () async {
      final f = await _fixture();
      final migration = CryptoMigrationCoordinator(account: f.account);
      addTearDown(migration.close);
      final legacy = AccountCryptoRepository(
        crypto: f.account.directory.reducer.crypto,
        session: f.account.directory.session,
        transport: f.transport,
        store: _Secure(),
        isCurrent: () => true,
      );
      final tasks = [
        f.catchStop(migration.discoverAvailable()),
        f.catchStop(
          f.account.directory.call('crypto2.directory.status', {
            'scopeId': _scope,
            'accountId': _account,
          }),
        ),
        f.catchStop(legacy.status()),
      ];
      await f.stopRequests(3);
      await Future.wait(tasks);
      expect(
        f.work.events
            .where((event) => event.event == AccountWorkEventKind.started)
            .map((event) => event.kind)
            .toSet(),
        {
          AccountWorkKind.migration,
          AccountWorkKind.account,
          AccountWorkKind.legacyCrypto,
        },
      );
      expect(f.wire.requests.length, 3);
      expect(f.errors.length, 3);
    },
  );
}
