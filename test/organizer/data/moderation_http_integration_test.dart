import '../support/synthetic_content_route_guard.dart';
// Opt-in, synthetic loopback fixture only. Never use live accounts or servers.
// JIVIE_MODERATION_HTTP_FIXTURE=/private/fixture.json flutter test this file
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';

import 'collaboration_repository_test.dart' show MemorySessionStore;

class _ReportHttpTransport implements CollaborationTransport {
  final inner = HttpCollaborationTransport();
  bool loseNextReportReply = false;
  String? deliveredReportId;
  int submissions = 0;

  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    if (operation == 'moderation.report') submissions++;
    final reply = await inner.call(
      serverUrl: serverUrl,
      operation: operation,
      params: params,
      token: token,
      allowLocalHttp: allowLocalHttp,
    );
    if (operation == 'moderation.report' && loseNextReportReply) {
      loseNextReportReply = false;
      deliveredReportId = reply['reportId'] as String;
      throw const CollaborationException('network');
    }
    return reply;
  }

  @override
  void close() => inner.close();
}

void main() {
  final fixturePath = Platform.environment['JIVIE_MODERATION_HTTP_FIXTURE'];
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  test(
    'real PHP HTTP: explicit consent, reporting without consent, replay, stale preview and identity boundary',
    () async {
      final fixture =
          jsonDecode(await File(fixturePath!).readAsString())
              as Map<String, dynamic>;
      final server = fixture['server'] as String;
      final uri = Uri.parse(server);
      if (fixture['synthetic'] != true ||
          uri.scheme != 'http' ||
          uri.host != '127.0.0.1' ||
          uri.userInfo.isNotEmpty) {
        throw StateError('A synthetic loopback fixture is required');
      }
      final directory = await Directory.systemTemp.createTemp(
        'moderation-http-',
      );
      final repos = <CollaborationRepository>[];
      Future<CollaborationRepository> open(
        String name,
        _ReportHttpTransport transport,
      ) async {
        final repo = CollaborationRepository(
          CollaborationDatabase(
            NativeDatabase(File('${directory.path}/$name.sqlite')),
          ),
          transport,
          MemorySessionStore(),
          contentRouteGuard: const SyntheticContentRouteGuard(),
        );
        repos.add(repo);
        await repo.initialize();
        final account = fixture[name] as Map<String, dynamic>;
        await repo.login(
          serverUrl: server,
          username: account['username'] as String,
          password: account['password'] as String,
          allowLocalHttp: true,
        );
        return repo;
      }

      Matcher failure(String code) => throwsA(
        isA<CollaborationException>().having((e) => e.code, 'code', code),
      );
      try {
        final a = await open('owner', _ReportHttpTransport());
        final initial = await a.sharedContentPolicy();
        expect(initial.accepted, false);
        expect(initial.policyVersion, 1);
        expect(initial.textSl, isNotEmpty);
        expect(initial.textEn, isNotEmpty);
        await expectLater(
          a.createScope('Before explicit acceptance'),
          failure('policy_acceptance_required'),
        );
        await a.acceptSharedContentPolicy(initial);
        expect((await a.sharedContentPolicy()).accepted, true);
        final scope = await a.createScope('Synthetic moderation space');
        final id = await a.createTask(
          scopeId: scope,
          title: 'Reported synthetic task',
          notes: '<script>synthetic text</script>',
        );
        await a.syncNow();
        expect(a.state.pendingCount, 0);
        expect(a.state.lastError, isNull);
        final reportTransport = _ReportHttpTransport();
        final b = await open('member', reportTransport);
        expect((await b.sharedContentPolicy()).accepted, false);
        // The fixture seeds a current policy3 membership without requiring
        // unrelated SMTP setup or the obsolete username invitation contract.
        final fixtureContainer = fixture['container'] as String;
        if (fixtureContainer != 'kanban-moderation16-sqlite') {
          throw StateError('Dedicated moderation fixture required');
        }
        final joined = await Process.run('docker', [
          'exec',
          fixtureContainer,
          'php',
          '/familyhub-tests/moderation-http-join.php',
          scope,
          b.state.session!.accountId,
        ]);
        expect(joined.exitCode, 0, reason: 'Synthetic membership setup');
        await b.syncNow();
        expect(
          b.state.dataForScope(scope).tasks.single.title,
          'Reported synthetic task',
        );
        final preview = await b.previewContentReport(
          scopeId: scope,
          targetType: 'record',
          targetId: id,
        );
        expect(preview.evidence['notes'], '<script>synthetic text</script>');
        expect(preview.evidence.containsKey('token'), false);
        reportTransport.loseNextReportReply = true;
        await expectLater(
          b.submitContentReport(
            preview: preview,
            reason: 'other',
            details: 'Synthetic report',
          ),
          failure('network'),
        );
        final receipt = await b.submitContentReport(
          preview: preview,
          reason: 'other',
          details: 'Synthetic report',
        );
        expect(receipt.reportId, reportTransport.deliveredReportId);
        expect(receipt.status, 'submitted');
        expect((await b.sharedContentPolicy()).accepted, false);

        final c = await open('outsider', _ReportHttpTransport());
        await expectLater(
          c.previewContentReport(
            scopeId: scope,
            targetType: 'record',
            targetId: id,
          ),
          failure('permission_revoked'),
        );
        final stale = await b.previewContentReport(
          scopeId: scope,
          targetType: 'record',
          targetId: id,
        );
        await a.updateTask(
          scope,
          a.state
              .dataForScope(scope)
              .tasks
              .single
              .copyWith(title: 'New revision'),
        );
        await a.syncNow();
        await expectLater(
          b.submitContentReport(preview: stale, reason: 'other'),
          failure('report_preview_changed'),
        );

        final submissions = reportTransport.submissions;
        final outsider = fixture['outsider'] as Map<String, dynamic>;
        await b.login(
          serverUrl: server,
          username: outsider['username'] as String,
          password: outsider['password'] as String,
          allowLocalHttp: true,
        );
        await expectLater(
          b.submitContentReport(preview: preview, reason: 'other'),
          failure('session_changed'),
        );
        expect(reportTransport.submissions, submissions);
      } finally {
        for (final repo in repos) {
          await repo.close();
        }
        await directory.delete(recursive: true);
      }
    },
    skip: fixturePath == null
        ? 'Opt-in synthetic HTTP fixture required'
        : false,
  );
}
