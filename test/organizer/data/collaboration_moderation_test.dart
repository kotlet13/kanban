import '../support/synthetic_content_route_guard.dart';
import 'dart:async';
import 'dart:io';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'collaboration_repository_test.dart'
    show FakeServer, FakeTransport, MemorySessionStore;

class ModerationServer extends FakeServer {
  int reports = 0;
  String? lastRequestId;
  bool loseReportReply = false;
  @override
  Future<Map<String, dynamic>> call(
    String operation,
    Map<String, Object?> params,
    String? token,
  ) async {
    if (!operation.startsWith('moderation.report')) {
      return super.call(operation, params, token);
    }
    calls.add((operation: operation, token: token, params: params));
    await beforeCall?.call(operation, token, params);
    final user = tokens[token];
    if (user == null) throw const CollaborationApiException('auth_required');
    if (members[params['scopeId']]?[user] == null) {
      throw const CollaborationApiException('permission_revoked');
    }
    if (operation == 'moderation.reportPreview') {
      return {
        'serverId': serverId,
        'accountId': accountIds[user],
        ...params,
        'targetRevision': 1,
        'subject': {'title': 'Selected record', 'type': 'task'},
        'evidence': {'title': 'Selected record'},
        'recipient': {
          'kind': 'serverAdministrator',
          'name': 'FamilyHub server administrator',
        },
        'previewHash': 'a' * 64,
      };
    }
    if (lastRequestId != params['requestId']) reports++;
    lastRequestId = params['requestId'] as String;
    if (loseReportReply) {
      loseReportReply = false;
      throw const CollaborationException('network');
    }
    return {
      'reportId': '12345678-1234-4234-8234-123456789abc',
      'status': 'submitted',
      'createdAt': '2026-10-12T12:00:00Z',
      'serverId': serverId,
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Directory directory;
  late ModerationServer server;
  late FakeTransport transport;
  late MemorySessionStore store;
  late CollaborationRepository repo;
  late ProviderContainer container;
  late CollaborationController controller;
  Future<void> open() async {
    repo = CollaborationRepository(
      CollaborationDatabase(
        NativeDatabase(File('${directory.path}/test.sqlite')),
      ),
      transport,
      store,
      contentRouteGuard: const SyntheticContentRouteGuard(),
    );
    await repo.initialize();
    container = ProviderContainer(
      overrides: [
        collaborationRepositoryProvider.overrideWith((ref) async => repo),
      ],
    );
    container.listen(collaborationProvider, (_, __) {}, fireImmediately: true);
    await container.read(collaborationProvider.future);
    controller = container.read(collaborationProvider.notifier);
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }

  Future<void> login([String user = 'alice']) => controller.login(
    serverUrl: 'https://synthetic.invalid/',
    username: user,
    password: 'synthetic-password',
  );
  Matcher code(String value) =>
      isA<CollaborationException>().having((e) => e.code, 'code', value);
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('moderation-tests-');
    server = ModerationServer();
    transport = FakeTransport(server);
    store = MemorySessionStore();
    await open();
    await login();
    await Future<void>.delayed(const Duration(milliseconds: 20));
  });
  tearDown(() async {
    container.dispose();
    await repo.close();
    await directory.delete(recursive: true);
  });

  test(
    'explicit checked policy acceptance gates shared publication; rejection never accepts',
    () async {
      server.moderationAccepted = false;
      await repo.syncNow();
      final policy = await controller.sharedContentPolicy();
      expect(policy.accepted, false);
      expect(policy.serverId, server.serverId);
      expect(policy.recipientName, 'FamilyHub server administrator');
      await expectLater(
        controller.createScope('Not published'),
        throwsA(code('policy_acceptance_required')),
      );
      expect(server.scopes, isEmpty);
      server.rejectPolicyAcceptance = true;
      await expectLater(
        controller.acceptSharedContentPolicy(policy),
        throwsA(code('policy_acceptance_required')),
      );
      expect(repo.state.sharedContentPolicy?.accepted, false);
      server.rejectPolicyAcceptance = false;
      await controller.acceptSharedContentPolicy(policy);
      expect(repo.state.sharedContentPolicy?.accepted, true);
      await controller.createScope('Published');
      expect(server.scopes.length, 1);
    },
  );

  test(
    'offline shared edit survives SQLite restart and export; consent preserves pending and pulls reads',
    () async {
      final scope = await controller.createScope('Household');
      transport.offline = true;
      await repo.createShoppingList(scopeId: scope, title: 'Offline draft');
      final before = await controller.exportUnsentWork();
      expect(before, contains('Offline draft'));
      container.dispose();
      await repo.close();
      await open();
      expect(repo.state.pendingCount, 1);
      expect(await controller.exportUnsentWork(), before);
      server.moderationAccepted = false;
      transport.offline = false;
      server.calls.clear();
      await controller.syncNow();
      expect(repo.state.pendingCount, 1);
      expect(repo.state.blockedCount, 0);
      expect(repo.state.lastError?.code, 'policy_acceptance_required');
      expect(server.calls.any((c) => c.operation == 'sync.push'), false);
      expect(server.calls.any((c) => c.operation == 'sync.pull'), true);
      expect(await controller.exportUnsentWork(), before);
      await controller.acceptSharedContentPolicy(
        await controller.sharedContentPolicy(),
      );
      expect(repo.state.pendingCount, 1);
      await controller.syncNow();
      expect(repo.state.pendingCount, 0);
    },
  );

  test(
    'old plugin keeps reads/local editing and export; new publication/upload/report require upgrade',
    () async {
      final scope = await controller.createScope('Household');
      server.moderationSupported = false;
      await expectLater(
        controller.createScope('Stale cached capabilities cannot publish'),
        throwsA(code('moderation_upgrade_required')),
      );
      await repo.createShoppingList(scopeId: scope, title: 'Kept locally');
      server.calls.clear();
      await controller.syncNow();
      expect(repo.state.pendingCount, 1);
      expect(repo.state.blockedCount, 0);
      expect(repo.state.lastError?.code, 'moderation_upgrade_required');
      expect(server.calls.any((c) => c.operation == 'sync.pull'), true);
      expect(server.calls.any((c) => c.operation == 'sync.push'), false);
      expect(await controller.exportUnsentWork(), contains('Kept locally'));
      await expectLater(
        controller.createScope('No new shared publication'),
        throwsA(code('moderation_upgrade_required')),
      );
      await expectLater(
        controller.previewContentReport(
          scopeId: scope,
          targetType: 'record',
          targetId: newSharedId(),
        ),
        throwsA(code('moderation_upgrade_required')),
      );
      expect(
        server.calls.any((c) => c.operation == 'moderation.reportPreview'),
        false,
      );
    },
  );

  test(
    'batch upload verifies policy once; queued operation bodies and IDs stay unchanged',
    () async {
      final scope = await controller.createScope('Household');
      transport.offline = true;
      await repo.createShoppingList(scopeId: scope, title: 'First');
      await repo.createShoppingList(scopeId: scope, title: 'Second');
      await repo.createShoppingList(scopeId: scope, title: 'Third');
      final queued = await repo.database.rows(
        'SELECT op_id,request FROM outbox ORDER BY sequence',
      );
      transport.offline = false;
      server.calls.clear();
      await controller.syncNow();
      expect(repo.state.pendingCount, 0);
      expect(
        server.calls
            .where((c) => c.operation == 'moderation.policyStatus')
            .length,
        1,
      );
      expect(
        server.calls.where((c) => c.operation == 'capabilities').length,
        1,
      );
      final pushed = server.calls
          .where((c) => c.operation == 'sync.push')
          .toList();
      expect(pushed.length, 3);
      for (var i = 0; i < 3; i++) {
        expect(
          (pushed[i].params['operation'] as Map)['opId'],
          queued[i]['op_id'],
        );
      }
    },
  );

  test(
    'report preview cancellation sends nothing; explicit retry uses same requestId without queue',
    () async {
      final scope = await controller.createScope('Household');
      server.moderationAccepted = false;
      final preview = await controller.previewContentReport(
        scopeId: scope,
        targetType: 'record',
        targetId: newSharedId(),
      );
      expect(preview.evidence, {'title': 'Selected record'});
      expect(server.reports, 0);
      expect(repo.state.pendingCount, 0);
      server.loseReportReply = true;
      await expectLater(
        controller.submitContentReport(
          preview: preview,
          reason: 'privacy',
          details: 'Selected concern',
        ),
        throwsA(code('network')),
      );
      expect(repo.state.pendingCount, 0);
      final result = await controller.submitContentReport(
        preview: preview,
        reason: 'privacy',
        details: 'Selected concern',
      );
      expect(result.status, 'submitted');
      expect(server.reports, 1);
      expect(server.lastRequestId, preview.requestId);
      transport.offline = true;
      await expectLater(
        controller.submitContentReport(preview: preview, reason: 'privacy'),
        throwsA(code('network')),
      );
      expect(server.reports, 1);
    },
  );

  test(
    'old policy and preview cannot accept/send under another account',
    () async {
      final scope = await controller.createScope('Household');
      final policy = await controller.sharedContentPolicy();
      final preview = await controller.previewContentReport(
        scopeId: scope,
        targetType: 'record',
        targetId: newSharedId(),
      );
      await login('bob');
      server.calls.clear();
      await expectLater(
        controller.acceptSharedContentPolicy(policy),
        throwsA(code('session_changed')),
      );
      await expectLater(
        controller.submitContentReport(preview: preview, reason: 'other'),
        throwsA(code('session_changed')),
      );
      expect(server.calls, isEmpty);
      expect(repo.state.sharedContentPolicy, isNull);
    },
  );

  test(
    'late acceptance and late preview cannot leak success into new session',
    () async {
      final scope = await controller.createScope('Household');
      final policy = await controller.sharedContentPolicy();
      final started = Completer<void>(), release = Completer<void>();
      server.beforeCall = (op, token, params) async {
        if (op == 'moderation.acceptPolicy') {
          started.complete();
          await release.future;
        }
      };
      final accepting = controller.acceptSharedContentPolicy(policy);
      final rejected = expectLater(accepting, throwsA(code('session_changed')));
      await started.future;
      await login('bob');
      release.complete();
      await rejected;
      expect(repo.state.session?.username, 'bob');
      expect(repo.state.sharedContentPolicy, isNull);
      await login();
      final startedPreview = Completer<void>(),
          releasePreview = Completer<void>();
      server.beforeCall = (op, token, params) async {
        if (op == 'moderation.reportPreview') {
          startedPreview.complete();
          await releasePreview.future;
        }
      };
      final previewing = controller.previewContentReport(
        scopeId: scope,
        targetType: 'record',
        targetId: newSharedId(),
      );
      final discarded = expectLater(
        previewing,
        throwsA(code('session_changed')),
      );
      await startedPreview.future;
      await controller.signOut();
      releasePreview.complete();
      await discarded;
      expect(repo.state.session, isNull);
      expect(server.reports, 0);
    },
  );

  test(
    'server identity swap rejects report before bearer/evidence transmission',
    () async {
      final scope = await controller.createScope('Household');
      final preview = await controller.previewContentReport(
        scopeId: scope,
        targetType: 'record',
        targetId: newSharedId(),
      );
      server.serverId = newSharedId();
      server.calls.clear();
      await expectLater(
        controller.submitContentReport(preview: preview, reason: 'other'),
        throwsA(code('server_identity_changed')),
      );
      expect(server.calls.map((c) => c.operation), ['capabilities']);
    },
  );
}
