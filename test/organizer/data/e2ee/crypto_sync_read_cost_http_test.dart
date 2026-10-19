import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_repository.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_router.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_identity_store.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:kanban/organizer/state/collaboration_sync_schedule.dart';
import 'package:sodium/sodium.dart';

import '../collaboration_repository_test.dart' show MemorySessionStore;

class _Secure implements AccountCryptoStore {
  _Secure(this.file) {
    if (file?.existsSync() == true) {
      values.addAll(
        (jsonDecode(file!.readAsStringSync()) as Map).cast<String, String>(),
      );
    }
  }
  final File? file;
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
    await file?.writeAsString(jsonEncode(values), flush: true);
  }
}

class _Router extends CryptoBusinessRouter {
  _Router({
    required super.database,
    required super.accountFor,
    required this.transport,
  });
  final _Transport transport;
  final segments = <Map<String, Object>>[];
  @override
  Future<Map<String, dynamic>> dispatch({
    required DeviceSession session,
    required String operation,
    required Map<String, Object?> params,
    required Set<String> protectedScopeIds,
  }) async {
    final start = transport.operations.length;
    try {
      return await super.dispatch(
        session: session,
        operation: operation,
        params: params,
        protectedScopeIds: protectedScopeIds,
      );
    } finally {
      if (!transport.setup) {
        final calls = transport.operations.skip(start).toList();
        segments.add({
          'dispatch': operation,
          'requests': calls.length,
          'pulls': calls.where((op) => op == 'crypto2.records.pull').length,
        });
      }
    }
  }
}

class _Transport extends HttpCollaborationTransport {
  final operations = <String>[];
  final issued = <DateTime>[];
  bool setup = true;
  int rateLimits = 0;
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    // Setup pacing keeps a synthetic fixture below the unchanged server quota.
    // The measured ordinary sync is neither paced nor retried here.
    final now = DateTime.now();
    issued.removeWhere((t) => now.difference(t).inSeconds > 60);
    if (setup && issued.length >= 450) {
      await Future<void>.delayed(
        const Duration(seconds: 61) - now.difference(issued.first),
      );
      issued.clear();
    }
    issued.add(DateTime.now());
    operations.add(operation);
    try {
      return await super.call(
        serverUrl: serverUrl,
        operation: operation,
        params: params,
        token: token,
        allowLocalHttp: allowLocalHttp,
      );
    } on CollaborationException catch (error) {
      if (error.code == 'rate_limited') rateLimits++;
      rethrow;
    }
  }
}

void main() {
  final fixturePath = Platform.environment['JIVIE_SYNC_COST_HTTP_FIXTURE'];
  test(
    'unchanged parent and child normal sync has counted verified reads',
    () async {
      final fixture =
          jsonDecode(await File(fixturePath!).readAsString()) as Map;
      final url = fixture['serverUrl'] as String;
      if (fixture['synthetic'] != true || Uri.parse(url).host != '127.0.0.1') {
        throw StateError('Isolated synthetic loopback fixture required');
      }
      final actor = Platform.environment['JIVIE_SYNC_COST_ACTOR'] ?? 'owner';
      final wire = fixture['accounts'][actor]['session'] as Map;
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
      final statePath = Platform.environment['JIVIE_SYNC_COST_STATE_DIR'];
      if (statePath != null &&
          !statePath.startsWith('${File(fixturePath).parent.path}/')) {
        throw StateError(
          'Persistent synthetic state must stay beside the private fixture',
        );
      }
      if (statePath != null) await Directory(statePath).create(recursive: true);
      final db = CollaborationDatabase(
        statePath == null
            ? NativeDatabase.memory()
            : NativeDatabase(File('$statePath/client.sqlite')),
      );
      final transport = _Transport();
      final codec = CryptoCodec(await SodiumInit.init());
      final account = AccountCryptoV2Workflow(
        AccountDirectoryRepository(
          reducer: AccountDirectoryV2(codec),
          session: session,
          transport: transport,
          store: CryptoIdentityStore(
            db,
            _Secure(statePath == null ? null : File('$statePath/secure.json')),
            session.profile.partition,
          ),
          isCurrent: () => true,
        ),
      );
      final initialized = (await db.rows(
        'SELECT 1 FROM crypto_identity_secrets WHERE partition=?',
        [session.profile.partition],
      )).isNotEmpty;
      if (!initialized) {
        final file = await account.prepareRecoveryFile();
        try {
          await account.verifyAndInitialize(file);
        } finally {
          file.fillRange(0, file.length, 0);
        }
      }
      final router = _Router(
        database: db,
        accountFor: (_) async => account,
        transport: transport,
      );
      final repository = CollaborationRepository(
        db,
        transport,
        MemorySessionStore()..value = session,
        cryptoRouter: router,
      );
      addTearDown(repository.close);
      await repository.initialize();
      final retained = await db.rows(
        'SELECT value FROM local_meta WHERE name=?',
        ['synthetic_sync_cost_scopes'],
      );
      late String parent, child;
      if (retained.isEmpty) {
        await repository.syncNow();
        final policy = await repository.sharedContentPolicy();
        if (!policy.accepted) {
          await repository.acceptSharedContentPolicy(policy);
        }
        parent = await repository.createScope(
          'Synthetic parent',
          kind: SharedScopeKind.organization,
        );
        child = await repository.createScope(
          'Synthetic child',
          kind: SharedScopeKind.project,
          parentScopeId: parent,
          organizationId: parent,
        );
        await repository.syncNow();
        await db.execute('INSERT INTO local_meta(name,value) VALUES(?,?)', [
          'synthetic_sync_cost_scopes',
          jsonEncode({'parent': parent, 'child': child}),
        ]);
      } else {
        final scopes = jsonDecode(retained.single['value'] as String) as Map;
        parent = scopes['parent'];
        child = scopes['child'];
      }
      expect(repository.state.lastError, isNull);
      expect(
        repository.state.scopes.map((s) => s.id),
        containsAll([parent, child]),
      );
      expect(repository.state.dataForScope(child).projects, hasLength(1));
      // Give the unchanged, separate fixture a fully fresh standard quota window.
      await Future<void>.delayed(const Duration(seconds: 61));
      transport.setup = false;
      final cycles = int.parse(
        Platform.environment['JIVIE_SYNC_COST_CYCLES'] ?? '1',
      );
      if (cycles < 1 || cycles > 3) {
        throw StateError('Bounded synthetic cycles required');
      }
      final measured = <Map<String, Object?>>[];
      for (var cycle = 0; cycle < cycles; cycle++) {
        if (cycle > 0 && measured.last['operationCount']! as int > 300) {
          await Future<void>.delayed(const Duration(seconds: 61));
        }
        transport.operations.clear();
        router.segments.clear();
        final watch = Stopwatch()..start();
        await repository.syncNow();
        watch.stop();
        final counts = <String, int>{};
        for (final operation in transport.operations) {
          counts[operation] = (counts[operation] ?? 0) + 1;
        }
        final completion = repository.lastSyncCompletion!;
        expect(completion.identity, repository.backgroundSyncIdentity);
        expect(completion.error, isNull);
        expect(completion.work.unresolved, isFalse);
        final schedule = CollaborationSyncSchedule()
          ..identity(completion.identity)
          ..complete(completion);
        final beforeIdle = transport.operations.length;
        var coalesced = 0;
        for (var second = 1; second < 60; second++) {
          final now = completion.at.add(Duration(seconds: second));
          schedule.resume(now); // Mac focus changes must retain this deadline.
          expect(schedule.due(now, busy: false), isFalse);
          coalesced++;
        }
        expect(
          schedule.due(
            completion.at.add(const Duration(seconds: 60)),
            busy: false,
          ),
          isTrue,
        );
        expect(transport.operations.length, beforeIdle);
        final metrics = <String, Object?>{
          'synthetic': true,
          'schedulerVirtualSeconds': 60,
          'coalescedFocusEvents': coalesced,
          'idleNetworkRequests': transport.operations.length - beforeIdle,
          'nextAttemptDueAt60Seconds': true,
          'actor': actor,
          'operationCount': transport.operations.length,
          'elapsedMilliseconds': watch.elapsedMilliseconds,
          'operations': counts,
          'rateLimits': transport.rateLimits,
          'lastErrorCode': repository.state.lastError?.code,
          'reusedClientState': initialized,
          'cycle': cycle + 1,
          'dispatches': List<Map<String, Object>>.of(router.segments),
        };
        measured.add(metrics);
        debugPrint('UNCHANGED_SYNC_COST ${jsonEncode(metrics)}');
        expect(repository.state.lastError, isNull);
        expect(transport.rateLimits, 0);
        expect(repository.state.dataForScope(child).projects, hasLength(1));
      }
      final output = Platform.environment['JIVIE_SYNC_COST_OUTPUT'];
      if (output != null) {
        await File(
          output,
        ).writeAsString(jsonEncode({'synthetic': true, 'cycles': measured}));
      }
    },
    skip: fixturePath == null,
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
