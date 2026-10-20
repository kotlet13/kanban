import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_repository.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/crypto_authority_snapshot.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_identity_store.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:sodium/sodium.dart';

class _Secure implements AccountCryptoStore {
  _Secure(File source)
    : values = (jsonDecode(source.readAsStringSync()) as Map)
          .cast<String, String>();
  final Map<String, String> values;
  Completer<void>? pause, entered;
  String? pauseKey;

  @override
  Future<String?> read(String key) async {
    if (key == pauseKey && pause != null) {
      final gate = pause!;
      pause = null;
      entered!.complete();
      await gate.future;
    }
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class _ReadTransport extends HttpCollaborationTransport {
  int snapshots = 0, blockedMutations = 0;
  final calls = <String>[];

  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    // This guard fixture must never write to its preserved HTTP server.
    if (operation != 'capabilities' &&
        operation != 'crypto2.authority.snapshot' &&
        !CryptoAuthoritySnapshot.bundledReads.contains(operation) &&
        operation != 'crypto2.account.scopeObservations') {
      blockedMutations++;
      throw StateError('Synthetic mutation intercepted before HTTP');
    }
    calls.add(operation);
    if (operation == 'crypto2.authority.snapshot') snapshots++;
    return super.call(
      serverUrl: serverUrl,
      operation: operation,
      params: params,
      token: token,
      allowLocalHttp: allowLocalHttp,
    );
  }
}

class _Fixture {
  _Fixture(this.db, this.secure, this.transport, this.account, this.scopes);
  final CollaborationDatabase db;
  final _Secure secure;
  final _ReadTransport transport;
  final AccountCryptoV2Workflow account;
  final List<String> scopes;
  bool current = true;
  late final access = SessionCryptoAccess(account: account);
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  // Keep the real lifecycle observer while opting this explicitly synthetic
  // loopback fixture out of the widget binding's automatic HTTP400 stub.
  HttpOverrides.global = null;
  final fixturePath = Platform.environment['JIVIE_RETAINED_AUTHORITY_FIXTURE'];
  final seedPath = Platform.environment['JIVIE_RETAINED_AUTHORITY_SEED'];
  final enabled = fixturePath != null && seedPath != null;

  Future<_Fixture> setup() async {
    final input = jsonDecode(await File(fixturePath!).readAsString()) as Map;
    final url = input['serverUrl'] as String;
    if (input['synthetic'] != true ||
        Uri.parse(url).host != '127.0.0.1' ||
        Uri.parse(url).port != 59776 ||
        !seedPath!.startsWith('/tmp/')) {
      throw StateError('Preserved synthetic loopback59776 seed required');
    }
    final temporary = await Directory.systemTemp.createTemp(
      'jivie-retained-authority-guard-',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final copy = await File(
      '$seedPath/client.sqlite',
    ).copy('${temporary.path}/client.sqlite');
    final db = CollaborationDatabase(NativeDatabase(copy));
    addTearDown(db.close);
    final secure = _Secure(File('$seedPath/secure.json'));
    final wire = input['accounts']['owner']['session'] as Map;
    final user = wire['user'] as Map, device = wire['device'] as Map;
    final session = DeviceSession(
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
    final transport = _ReadTransport();
    addTearDown(transport.close);
    addTearDown(() {
      final counts = <String, int>{};
      for (final operation in transport.calls) {
        counts.update(operation, (n) => n + 1, ifAbsent: () => 1);
      }
      debugPrint(
        jsonEncode({
          'signedRetainedGuardReadCalls': counts,
          'blockedBeforeHttp': transport.blockedMutations,
        }),
      );
    });
    final crypto = CryptoCodec(await SodiumInit.init());
    late _Fixture fixture;
    final account = AccountCryptoV2Workflow(
      AccountDirectoryRepository(
        reducer: AccountDirectoryV2(crypto),
        session: session,
        transport: transport,
        store: CryptoIdentityStore(db, secure, session.profile.partition),
        isCurrent: () => fixture.current,
      ),
    );
    final scopes = await db.rows(
      r"SELECT DISTINCT h.scope_id,CASE json_extract(s.data,'$.kind') WHEN 'organization' THEN 0 ELSE 1 END AS ordering FROM crypto_scope_heads h JOIN scopes s ON s.partition=h.partition AND s.id=h.scope_id WHERE h.partition=? ORDER BY ordering,h.scope_id",
      [session.profile.partition],
    );
    if (scopes.length < 2) {
      throw StateError('Two preserved signed scopes required');
    }
    fixture = _Fixture(
      db,
      secure,
      transport,
      account,
      scopes.map((row) => row['scope_id'] as String).toList(),
    );
    return fixture;
  }

  void guard(String description, Future<void> Function() body) {
    test(
      description,
      body,
      skip: enabled ? false : 'Preserved signed HTTP fixture not requested',
      timeout: const Timeout(Duration(seconds: 40)),
    );
  }

  guard('signed heads retain the union of pins from separate scopes', () async {
    final f = await setup();
    final retained = f.access.createReadOperation();
    addTearDown(retained.close);
    final first = await retained.run(() async {
      await f.access.currentHead(f.scopes[0], online: true);
      return f.access.verifiedReadLease();
    });
    final second = await retained.run(() async {
      await f.access.currentHead(f.scopes[1], online: true);
      return f.access.verifiedReadLease();
    });
    expect(first, isNotNull);
    expect(second, isNotNull);
    final snapshots = f.transport.snapshots;
    final key = 'scope2:${f.account.store.partition}:${f.scopes[1]}';
    final original = f.secure.values[key]!;
    // Semantically identical JSON still changes the exact secure pin bytes.
    f.secure.values[key] = '$original ';
    // The first copied lease predates the second scope's pin. A union failure
    // must also advance authority generation so this older lease cannot live on.
    expect(await f.access.isVerifiedReadLeaseCurrent(first!), true);
    expect(await f.access.isVerifiedReadLeaseCurrent(second!), false);
    await retained.run(() => f.access.currentHead(f.scopes[0], online: true));
    expect(f.transport.snapshots, greaterThan(snapshots));
    expect(await f.access.isVerifiedReadLeaseCurrent(first), false);
    expect(await f.access.isVerifiedReadLeaseCurrent(second), false);
  });

  guard(
    'fresh write boundary retires signed memo and original lease',
    () async {
      final f = await setup();
      final retained = f.access.createReadOperation();
      addTearDown(retained.close);
      final lease = await retained.run(() async {
        await f.access.currentHead(f.scopes[0], online: true);
        return f.access.verifiedReadLease();
      });
      expect(lease, isNotNull);
      final before = f.transport.snapshots;
      await retained.run(
        () => f.access.withVerifiedOperation(
          () => f.access.currentHead(f.scopes[0], online: true),
          freshBoundary: true,
        ),
      );
      expect(f.transport.snapshots, greaterThan(before));
      expect(await f.access.isVerifiedReadLeaseCurrent(lease!), false);
      final after = f.transport.snapshots;
      await retained.run(() => f.access.currentHead(f.scopes[0], online: true));
      expect(f.transport.snapshots, greaterThan(after));
    },
  );

  guard(
    'lifecycle boundary prevents reuse of signed heads and lease',
    () async {
      final f = await setup();
      final retained = f.access.createReadOperation();
      addTearDown(retained.close);
      final lease = await retained.run(() async {
        await f.access.currentHead(f.scopes[0], online: true);
        return f.access.verifiedReadLease();
      });
      expect(lease, isNotNull);
      final before = f.transport.snapshots;
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(await f.access.isVerifiedReadLeaseCurrent(lease!), false);
      await retained.run(() => f.access.currentHead(f.scopes[0], online: true));
      expect(f.transport.snapshots, greaterThan(before));
    },
  );

  guard(
    'identity change while awaiting secure pin rejects late reuse',
    () async {
      final f = await setup();
      final retained = f.access.createReadOperation();
      addTearDown(retained.close);
      await retained.run(() => f.access.currentHead(f.scopes[0], online: true));
      f.secure.pauseKey = 'scope2:${f.account.store.partition}:${f.scopes[0]}';
      f.secure.entered = Completer<void>();
      final gate = Completer<void>();
      f.secure.pause = gate;
      final before = f.transport.calls.length;
      final late = retained.run(
        () => f.access.currentHead(f.scopes[0], online: true),
      );
      final assertion = expectLater(
        late,
        throwsA(
          isA<CryptoDirectoryException>().having(
            (error) => error.code,
            'code',
            'directory_stale_identity',
          ),
        ),
      );
      await f.secure.entered!.future;
      f.current = false;
      gate.complete();
      await assertion;
      expect(f.transport.calls.length, before);
    },
  );

  guard(
    'intercepted unsigned mutation retires signed memo without server write',
    () async {
      final f = await setup();
      final retained = f.access.createReadOperation();
      addTearDown(retained.close);
      final lease = await retained.run(() async {
        await f.access.currentHead(f.scopes[0], online: true);
        return f.access.verifiedReadLease();
      });
      expect(lease, isNotNull);
      final before = f.transport.snapshots;
      await expectLater(
        retained.run(
          () =>
              f.account.directory.call('crypto2.account.scopeObservation.put'),
        ),
        throwsStateError,
      );
      expect(f.transport.blockedMutations, 1);
      expect(await f.access.isVerifiedReadLeaseCurrent(lease!), false);
      await retained.run(() => f.access.currentHead(f.scopes[0], online: true));
      expect(f.transport.snapshots, greaterThan(before));
    },
  );
}
