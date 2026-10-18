import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_repository.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_identity_store.dart';
import 'package:kanban/organizer/state/account_crypto_provider.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'package:sodium/sodium.dart';

import '../collaboration_repository_test.dart' show MemorySessionStore;

const _serverId = '10000000-0000-4000-8000-000000000001';
const _accountId = '20000000-0000-4000-8000-000000000001';
const _deviceId = '30000000-0000-4000-8000-000000000001';

DeviceSession _session() => DeviceSession(
  AccountSession(
    serverUrl: 'https://startup.invalid/',
    serverId: _serverId,
    accountId: _accountId,
    userId: 1,
    username: 'synthetic',
    displayName: 'Synthetic',
    deviceId: _deviceId,
    expiresAt: DateTime.utc(2030),
  ),
  'synthetic-session',
);

class _Transport implements CollaborationTransport {
  List<int> versions = [1, 2];
  bool initialized = false;
  Completer<void>? releaseCapabilities;
  final capabilitiesEntered = Completer<void>();
  final calls = <String>[];
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    calls.add(operation);
    if (operation == 'capabilities') {
      // Hold only the preview request; sign-out has its own capability cleanup.
      if (!capabilitiesEntered.isCompleted) {
        capabilitiesEntered.complete();
        await releaseCapabilities?.future;
      }
      return {'serverId': _serverId, 'cryptoTransportVersions': versions};
    }
    if (operation == 'crypto2.account.status') {
      return {
        'serverId': _serverId,
        'accountId': _accountId,
        'initialized': initialized,
      };
    }
    if (operation == 'auth.revoke') return {'revoked': true};
    throw StateError('Unexpected synthetic operation: $operation');
  }

  @override
  void close() {}
}

class _Secure implements AccountCryptoStore {
  final values = <String, String>{};
  int writes = 0;
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    writes++;
    values[key] = value;
  }
}

// Keep the actual preview provider and repository while making publication
// deterministic, without a background timer or any host session/Keychain.
class _Controller extends CollaborationController {
  _Controller(this.repository);
  final CollaborationRepository repository;
  @override
  Future<CollaborationState> build() async => repository.state;
  @override
  Future<AccountCryptoV2Workflow?> accountCryptoPreview() async =>
      await repository.accountCryptoPreview() as AccountCryptoV2Workflow?;
  void publish(CollaborationState value) => state = AsyncData(value);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CryptoCodec crypto;
  setUpAll(() async => crypto = CryptoCodec(await SodiumInit.init()));

  Future<CollaborationRepository> open(_Transport transport) async {
    final repository = CollaborationRepository(
      CollaborationDatabase(NativeDatabase.memory()),
      transport,
      MemorySessionStore()..value = _session(),
    );
    await repository.initialize();
    addTearDown(repository.close);
    return repository;
  }

  test(
    'fresh session preview fetches capabilities before cached negotiation',
    () async {
      final transport = _Transport()..releaseCapabilities = Completer<void>();
      final repository = await open(transport);
      final controller = _Controller(repository);
      final container = ProviderContainer(
        overrides: [collaborationProvider.overrideWith(() => controller)],
      );
      addTearDown(container.dispose);
      await container.read(collaborationProvider.future);
      final pending = container.read(accountCryptoPreviewProvider.future);
      var finished = false;
      unawaited(pending.then((_) => finished = true));
      await Future<void>.delayed(Duration.zero);
      expect(transport.capabilitiesEntered.isCompleted, true);
      expect(finished, false);
      transport.releaseCapabilities!.complete();
      final workflow = await pending;
      expect(workflow, isA<AccountCryptoV2Workflow>());
      controller.publish(
        CollaborationState(session: repository.state.session, isSyncing: true),
      );
      await Future<void>.delayed(Duration.zero);
      controller.publish(CollaborationState(session: repository.state.session));
      await Future<void>.delayed(Duration.zero);
      expect(
        await container.read(accountCryptoPreviewProvider.future),
        same(workflow),
      );
      expect(transport.calls, ['capabilities']);
    },
  );

  test(
    'unsupported fresh capabilities return null without crypto requests',
    () async {
      final transport = _Transport()..versions = [];
      final repository = await open(transport);
      expect(await repository.accountCryptoPreview(), isNull);
      expect(transport.calls, ['capabilities']);
      expect(
        await repository.database.rows('SELECT * FROM crypto_identity_secrets'),
        isEmpty,
      );
    },
  );

  test('identity change rejects a delayed preview capability result', () async {
    final transport = _Transport()..releaseCapabilities = Completer<void>();
    final repository = await open(transport);
    final pending = repository.accountCryptoPreview();
    await transport.capabilitiesEntered.future.timeout(
      const Duration(seconds: 1),
    );
    final rejected = expectLater(
      pending,
      throwsA(
        isA<CollaborationException>().having(
          (e) => e.code,
          'code',
          'session_changed',
        ),
      ),
    );
    await repository.signOut();
    transport.releaseCapabilities!.complete();
    await rejected;
    expect(
      await repository.database.rows('SELECT * FROM crypto_identity_secrets'),
      isEmpty,
    );
  });

  for (final initialized in [false, true]) {
    test(
      initialized
          ? 'fresh device of initialized account has no local rebind authority'
          : 'fresh account wizard eligibility does not require an existing anchor',
      () async {
        final transport = _Transport()..initialized = initialized;
        final database = CollaborationDatabase(NativeDatabase.memory());
        addTearDown(database.close);
        final secure = _Secure(), session = _session();
        final workflow = AccountCryptoV2Workflow(
          AccountDirectoryRepository(
            reducer: AccountDirectoryV2(crypto),
            session: session,
            transport: transport,
            store: CryptoIdentityStore(
              database,
              secure,
              session.profile.partition,
            ),
            isCurrent: () => true,
          ),
        );
        expect((await workflow.status())['initialized'], initialized);
        expect(await workflow.localPhase(), 'missing');
        expect(await workflow.canRebindLocalDevice(), false);
        expect(transport.calls, ['crypto2.account.status']);
        expect(secure.writes, 0);
        expect(
          await database.rows('SELECT * FROM crypto_identity_secrets'),
          isEmpty,
        );
      },
    );
  }

  for (final trust in ['observed', 'verified']) {
    test('$trust anchor preserves the rebind trust boundary', () async {
      final database = CollaborationDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final secure = _Secure(), transport = _Transport(), session = _session();
      secure.values['directory2:${session.profile.partition}:$_accountId'] =
          jsonEncode({'trustState': trust});
      final workflow = AccountCryptoV2Workflow(
        AccountDirectoryRepository(
          reducer: AccountDirectoryV2(crypto),
          session: session,
          transport: transport,
          store: CryptoIdentityStore(
            database,
            secure,
            session.profile.partition,
          ),
          isCurrent: () => true,
        ),
      );
      if (trust == 'verified') {
        await expectLater(
          workflow.canRebindLocalDevice(),
          throwsA(
            isA<CryptoDirectoryException>().having(
              (e) => e.code,
              'code',
              'directory_identity_unverified',
            ),
          ),
        );
      } else {
        expect(await workflow.canRebindLocalDevice(), false);
      }
      expect(transport.calls, isEmpty);
      expect(secure.writes, 0);
      expect(
        await database.rows('SELECT * FROM crypto_identity_secrets'),
        isEmpty,
      );
    });
  }
}
