import 'dart:convert';
import 'dart:typed_data';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/collaboration_sync_diagnostics.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_repository.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_router.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_domain_router.dart';
import 'package:kanban/organizer/data/e2ee/crypto_identity_store.dart';
import '../../support/synthetic_content_route_guard.dart';
import '../collaboration_repository_test.dart'
    show FakeServer, FakeTransport, MemorySessionStore;

class _Secure implements AccountCryptoStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

// The new production directory method runs unchanged. Other E2EE capabilities
// are deliberately absent: business CRUD below uses the explicit legacy seam.
class _DirectoryRouter
    implements CryptoDomainRouter, CryptoAccountDirectoryChanges {
  _DirectoryRouter(this.delegate);
  final CryptoBusinessRouter delegate;
  @override
  Future<bool> refreshAccountDirectory({required DeviceSession session}) =>
      delegate.refreshAccountDirectory(session: session);
  @override
  Future<Map<String, dynamic>> dispatch({
    required DeviceSession session,
    required String operation,
    required Map<String, Object?> params,
    required Set<String> protectedScopeIds,
  }) async => throw StateError('Unexpected protected business dispatch');
}

class _Transport extends FakeTransport {
  _Transport(super.server, this.sessions);
  final MemorySessionStore sessions;
  final operations = <String>[];
  final entries = <Map<String, dynamic>>[];
  final probeCursors = <Object?>[];
  VerifiedAccountDirectory? remote;
  Object? directoryHintsVersion = 1;
  bool corruptSignature = false;
  Future<void> Function()? beforeDirectory;
  Future<void> Function(Object?)? onProbe;
  List<String> accountDomains = [];
  Map<String, List<String>> scopes = {};
  String cursor = 'initial';
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    operations.add(operation);
    if (operation == 'account.changes') {
      probeCursors.add(params['cursor']);
      await onProbe?.call(params['cursor']);
      final p = sessions.value!.profile;
      final reset = params['cursor'] == null;
      return {
        'version': 1,
        if (directoryHintsVersion != null)
          'directoryHintsVersion': directoryHintsVersion,
        'serverId': p.serverId,
        'accountId': p.accountId,
        'deviceId': p.deviceId,
        'cursor': cursor,
        'changed': reset || accountDomains.isNotEmpty || scopes.isNotEmpty,
        'resetRequired': reset,
        'hasMore': false,
        'accountDomains': accountDomains,
        'scopes': [
          for (final e in scopes.entries)
            {'scopeId': e.key, 'domains': e.value},
        ],
      };
    }
    if (operation == 'crypto2.account.status') {
      return {
        'serverId': remote!.serverId,
        'accountId': remote!.accountId,
        'initialized': true,
        'generation': remote!.generation,
        'headHash': remote!.headHash,
        'snapshotHash': remote!.snapshotHash,
        'deviceSnapshotHash': remote!.deviceSnapshotHash,
        'snapshotIncluded': true,
        'snapshot': remote!.snapshot,
      };
    }
    if (operation == 'crypto2.account.directory') {
      await beforeDirectory?.call();
      final page = entries
          .where((e) => e['generation'] > (params['afterGeneration'] as int))
          .map((e) => jsonDecode(jsonEncode(e)) as Map<String, dynamic>)
          .toList();
      if (corruptSignature) {
        page.first['authorization']['signatureBase64'] = base64Encode(
          Uint8List(64),
        );
      }
      return {
        'generation': remote!.generation,
        'headHash': remote!.headHash,
        'entries': page,
        'nextGeneration': remote!.generation,
      };
    }
    if (operation.startsWith('crypto2.')) {
      throw StateError('Directory lane must not send $operation');
    }
    final result = await super.call(
      serverUrl: serverUrl,
      operation: operation,
      params: params,
      token: token,
      allowLocalHttp: allowLocalHttp,
    );
    return operation == 'capabilities'
        ? {
            ...result,
            'accountChangeVersions': [1],
          }
        : result;
  }
}

class _Fixture {
  _Fixture(this.crypto, {CollaborationSyncDiagnostics? diagnostics})
    : diagnostics = diagnostics ?? CollaborationSyncDiagnostics();
  final CryptoCodec crypto;
  final server = FakeServer(), sessions = MemorySessionStore();
  late final _Transport transport = _Transport(server, sessions);
  late final db = CollaborationDatabase(NativeDatabase.memory());
  late final identity = CryptoIdentityStore(db, _Secure(), profile.partition);
  late final reducer = AccountDirectoryV2(crypto);
  late final directory = AccountDirectoryRepository(
    reducer: reducer,
    session: sessions.value!,
    transport: transport,
    store: identity,
    isCurrent: () => true,
  );
  final CollaborationSyncDiagnostics diagnostics;
  late final repo = CollaborationRepository(
    db,
    transport,
    sessions,
    contentRouteGuard: const SyntheticContentRouteGuard(),
    syncDiagnostics: diagnostics,
    cryptoRouter: _DirectoryRouter(
      CryptoBusinessRouter(
        database: db,
        accountFor: (_) async => AccountCryptoV2Workflow(directory),
      ),
    ),
  );
  final keys = <KeyPair>[];
  late String a, b, epoch, peer;
  late KeyPair root, box, device, peerKey;
  get profile => sessions.value!.profile;

  Future<void> initialize() async {
    await repo.initialize();
    await repo.login(
      serverUrl: 'https://synthetic.invalid/',
      username: 'alice',
      password: 'synthetic',
    );
    a = await repo.createScope('Affected');
    b = await repo.createScope('Unrelated');
    await repo.syncNow();
    expect(
      repo.state.lastError,
      isNull,
      reason: 'legacy business fixture setup',
    );
    root = crypto.sodium.crypto.sign.keyPair();
    device = crypto.sodium.crypto.sign.keyPair();
    peerKey = crypto.sodium.crypto.sign.keyPair();
    box = crypto.sodium.crypto.box.keyPair();
    keys.addAll([root, device, peerKey, box]);
    epoch = crypto.randomId();
    peer = crypto.randomId();
    final genesis = await reducer.prepare(
      previous: null,
      serverId: profile.serverId,
      accountId: profile.accountId,
      deviceId: profile.deviceId,
      identityEpochId: epoch,
      operation: 'crypto2.account.initialize',
      signer: 'root',
      signingKey: root.secretKey,
      pinnedRootFingerprint: crypto.fingerprint(root.publicKey, box.publicKey),
      payload: {
        'rootSigningKeyBase64': base64Encode(root.publicKey),
        'rootEncryptionKeyBase64': base64Encode(box.publicKey),
        'deviceSigningKeyBase64': base64Encode(device.publicKey),
        'deviceEncryptionKeyBase64': base64Encode(box.publicKey),
        'keyringCiphertextBase64': base64Encode(Uint8List(48)),
      },
    );
    transport.remote = genesis.result;
    transport.entries.add(genesis.entry);
    await append('crypto2.device.add', {
      'deviceId': peer,
      'signingKeyBase64': base64Encode(peerKey.publicKey),
      'encryptionKeyBase64': base64Encode(box.publicKey),
      'keyringWrite': true,
      'manageDevices': true,
    });
    for (final entry in transport.entries) {
      await identity.append(profile.accountId, entry);
    }
    await identity.pinRoot(
      profile.accountId,
      profile.serverId,
      genesis.result.rootFingerprint,
      genesisFingerprint: genesis.result.genesisRootFingerprint,
    );
    await identity.pinComparedIdentity(
      transport.remote!,
      transport.remote!.rootFingerprint,
    );
    await identity.remember(transport.remote!, 'verified');
    await directory.cachedVerifiedDirectory();
    transport.operations.clear();
    transport.probeCursors.clear();
    server.calls.clear();
  }

  Future<void> append(
    String operation,
    Map<String, dynamic> payload, {
    bool byPeer = false,
  }) async {
    final prepared = await reducer.prepare(
      previous: transport.remote!,
      serverId: profile.serverId,
      accountId: profile.accountId,
      deviceId: byPeer ? peer : profile.deviceId,
      identityEpochId: epoch,
      operation: operation,
      signer: 'device',
      signingKey: (byPeer ? peerKey : device).secretKey,
      pinnedRootFingerprint: crypto.fingerprint(root.publicKey, box.publicKey),
      payload: payload,
    );
    transport.remote = prepared.result;
    transport.entries.add(prepared.entry);
  }

  Future<void> observation() async {
    await append('crypto2.account.scopeObserve', {
      'scopeToken': 'a' * 64,
      'headHash': 'b' * 64,
      'observationHash': 'c' * 64,
    });
    transport.accountDomains = ['directory'];
    transport.cursor = 'observed';
  }

  Future<String?> cursor() async =>
      (await db.rows('SELECT value FROM local_meta WHERE name=?', [
            'account_changes_v1:${profile.partition}:${profile.deviceId}',
          ])).firstOrNull?['value']
          as String?;

  Future<void> close() async {
    await repo.close();
    for (final key in keys) {
      key.secretKey.dispose();
    }
  }
}

void main() {
  late CryptoCodec crypto;
  setUpAll(() async => crypto = CryptoCodec(await SodiumInit.init()));
  Future<_Fixture> setup({CollaborationSyncDiagnostics? diagnostics}) async {
    final f = _Fixture(crypto, diagnostics: diagnostics);
    addTearDown(f.close);
    await f.initialize();
    return f;
  }

  test(
    'signed observation is durably replayed then idle without full sync',
    () async {
      final f = await setup();
      await f.observation();
      // An exact unsent setup/account journal must not be auto-delivered.
      final pending = await f.reducer.prepare(
        previous: f.transport.remote!,
        serverId: f.profile.serverId,
        accountId: f.profile.accountId,
        deviceId: f.profile.deviceId,
        identityEpochId: f.epoch,
        operation: 'crypto2.account.scopeObserve',
        signer: 'device',
        signingKey: f.device.secretKey,
        pinnedRootFingerprint: f.transport.remote!.rootFingerprint,
        payload: {
          'scopeToken': 'd' * 64,
          'headHash': 'e' * 64,
          'observationHash': 'f' * 64,
        },
      );
      await f.identity.stage(pending.authorization, 'pending');
      final original = await f.db.rows(
        'SELECT * FROM crypto_identity_requests',
      );
      final state = f.repo.state, completion = f.repo.lastSyncCompletion;
      var publications = 0;
      final sub = f.repo.changes.listen((_) => publications++);
      addTearDown(sub.cancel);
      await f.repo.syncNow();
      expect(f.transport.operations, [
        'account.changes',
        'crypto2.account.status',
        'crypto2.account.directory',
      ]);
      expect(await f.cursor(), 'observed');
      expect(
        (await f.directory.cachedVerifiedDirectory()).headHash,
        f.transport.remote!.headHash,
      );
      expect(
        await f.db.rows('SELECT * FROM crypto_identity_requests'),
        original,
      );
      expect(identical(f.repo.state, state), isTrue);
      expect(identical(f.repo.lastSyncCompletion, completion), isTrue);
      f.transport.operations.clear();
      f.transport.accountDomains = [];
      await f.repo.syncNow();
      await Future<void>.delayed(Duration.zero);
      expect(f.transport.operations, ['account.changes']);
      expect(publications, 0);
      expect(
        f.diagnostics.events.map((e) => e.kind),
        contains(CollaborationSyncDiagnosticKind.verifiedJournalOnly),
      );
    },
  );

  test('signed journal plus task hint pulls only affected content', () async {
    final f = await setup();
    final id = await f.repo.createTask(scopeId: f.a, title: 'Before');
    await f.repo.syncNow();
    final row = f.server.records[f.a]![id]!;
    row['payload']['title'] = 'After';
    row['revision'] = (row['revision'] as int) + 1;
    row['sequence'] = f.server.sequence[f.a] = f.server.sequence[f.a]! + 1;
    final unrelated = f.repo.state.data[f.b];
    await f.observation();
    f.transport.scopes = {
      f.a: ['content'],
    };
    f.transport.operations.clear();
    f.server.calls.clear();
    await f.repo.syncNow();
    expect(f.repo.state.lastError, isNull);
    expect(f.transport.operations, isNot(contains('scopes.list')));
    expect(
      f.transport.operations.where((o) => o.startsWith('finance')),
      isEmpty,
    );
    expect(
      f.server.calls
          .where((c) => c.operation == 'sync.pull')
          .map((c) => c.params['scopeId']),
      [f.a],
    );
    expect(
      f.repo.state.data[f.a]!.tasks.singleWhere((t) => t.id == id).title,
      'After',
    );
    expect(identical(f.repo.state.data[f.b], unrelated), isTrue);
    expect(await f.cursor(), 'observed');
  });

  test(
    'valid signed own-device revoke fails active-device guard without ACK',
    () async {
      final f = await setup();
      await f.append('crypto2.device.revoke', {
        'deviceId': f.profile.deviceId,
      }, byPeer: true);
      // Deliberately incomplete host hint: signed authority still wins.
      f.transport.accountDomains = ['directory'];
      f.transport.cursor = 'revoked';
      await expectLater(
        f.repo.syncNow(),
        throwsA(isA<CryptoDirectoryException>()),
      );
      expect(await f.cursor(), 'initial');
      expect(f.transport.operations, [
        'account.changes',
        'crypto2.account.status',
        'crypto2.account.directory',
      ]);
      expect(
        f.diagnostics.events.map((e) => e.kind),
        contains(CollaborationSyncDiagnosticKind.directoryVerificationFailed),
      );
      expect(
        f.diagnostics.events.last.kind,
        isNot(CollaborationSyncDiagnosticKind.cursorAcknowledged),
      );
    },
  );

  test(
    'guard: invalid signed prefix cannot acknowledge account cursor',
    () async {
      final f = await setup();
      final before = await f.identity.anchor(f.profile.accountId);
      await f.observation();
      f.transport.corruptSignature = true;
      await expectLater(f.repo.syncNow(), throwsA(isA<Exception>()));
      expect(await f.cursor(), 'initial');
      expect(await f.identity.anchor(f.profile.accountId), before);
      expect(f.transport.operations, [
        'account.changes',
        'crypto2.account.status',
        'crypto2.account.directory',
      ]);
    },
  );

  test(
    'guard: directory-await invalidation cannot restore the old cursor',
    () async {
      final f = await setup();
      await f.observation();
      f.transport.beforeDirectory = () async {
        f.transport.beforeDirectory = null;
        await f.repo.invalidateAccountChangesCursor();
        expect(await f.cursor(), isNull);
      };
      f.transport.onProbe = (cursor) async {
        if (f.transport.probeCursors.length == 2) {
          expect(cursor, isNull);
          expect(await f.cursor(), isNull);
        }
      };
      await f.repo.syncNow();
      expect(f.transport.probeCursors, ['initial', null]);
      expect(f.repo.state.lastError, isNull);
      expect(await f.cursor(), 'observed');
      expect(
        f.diagnostics.events.map((e) => e.kind),
        contains(CollaborationSyncDiagnosticKind.cursorInvalidated),
      );
    },
  );

  test(
    'guard: missing and future directory hints retain legacy access work',
    () async {
      for (final version in [null, 2]) {
        final f = await setup();
        await f.observation();
        f.transport.directoryHintsVersion = version;
        await f.repo.syncNow();
        expect(f.repo.state.lastError, isNull);
        expect(f.transport.operations, contains('scopes.list'));
        expect(
          f.transport.operations,
          isNot(contains('crypto2.account.status')),
        );
        // Legacy directory access selects the catalog. Domain pulls still
        // require scope hints; the old behavior is not a full-domain reset.
        expect(
          f.server.calls.where((c) => c.operation == 'sync.pull'),
          isEmpty,
        );
        expect(await f.cursor(), 'observed');
      }
    },
  );

  test(
    'guard: diagnostic ring bounds values and failing observer cannot affect sync',
    () async {
      final diagnostics = CollaborationSyncDiagnostics(
        onEvent: (_) {
          throw StateError('synthetic observer failure');
        },
      );
      for (var i = 0; i < 100; i++) {
        diagnostics.record(
          CollaborationSyncDiagnosticKind.probe,
          scopeCount: i * 1000,
          contentScopeCount: -1,
        );
      }
      expect(diagnostics.events, hasLength(64));
      expect(diagnostics.events.every((e) => e.scopeCount <= 10000), isTrue);
      expect(diagnostics.events.every((e) => e.contentScopeCount == 0), isTrue);
      final f = await setup(diagnostics: diagnostics);
      await f.observation();
      await f.repo.syncNow();
      expect(await f.cursor(), 'observed');
      expect(f.repo.state.lastError, isNull);
      expect(diagnostics.events, hasLength(64));
      expect(
        diagnostics.events.last.kind,
        CollaborationSyncDiagnosticKind.cursorAcknowledged,
      );
    },
  );
}
