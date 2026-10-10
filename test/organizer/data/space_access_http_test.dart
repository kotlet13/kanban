// Opt in against a private synthetic loopback fixture. Never log its credentials.
// KANBAN_SPACE_HTTP_FIXTURE=/absolute/private/fixture.json flutter test ...
import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/pending_invitation_store.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'collaboration_repository_test.dart' show MemorySessionStore;

class SpaceHttpTransport implements CollaborationTransport {
  final inner = HttpCollaborationTransport();
  bool offline = false;
  String? loseNext;
  final extractionRequests = <Map<String, Object?>>[];
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    if (offline) throw const CollaborationException('network');
    if (operation == 'scopes.projectSharingApply') {
      extractionRequests.add(Map.of(params));
    }
    final result = await inner.call(
      serverUrl: serverUrl,
      operation: operation,
      params: params,
      token: token,
      allowLocalHttp: allowLocalHttp,
    );
    if (loseNext == operation) {
      loseNext = null;
      throw const CollaborationException('network');
    }
    return result;
  }

  @override
  void close() => inner.close();
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final fixturePath = Platform.environment['KANBAN_SPACE_HTTP_FIXTURE'];
  test(
    'actual HTTP policy3 household and organization full/project-only ACL, finance, extraction and disk offline recovery',
    () async {
      final fixture =
          jsonDecode(await File(fixturePath!).readAsString())
              as Map<String, dynamic>;
      final server = fixture['server'] as String;
      if (fixture['synthetic'] != true ||
          Uri.parse(server).host != '127.0.0.1') {
        throw StateError('Synthetic loopback fixture required');
      }
      final directory = await Directory.systemTemp.createTemp('space-http-');
      final repos = <CollaborationRepository>[];
      Future<CollaborationRepository> open(
        String name,
        MemorySessionStore sessions,
        SpaceHttpTransport transport,
      ) async {
        final repo = CollaborationRepository(
          CollaborationDatabase(
            NativeDatabase(File('${directory.path}/$name.sqlite')),
          ),
          transport,
          sessions,
          invitationStore: MemoryPendingInvitationStore(),
        );
        repos.add(repo);
        await repo.initialize();
        return repo;
      }

      Future<void> login(CollaborationRepository repo, String actor) async {
        final identity = fixture[actor] as Map<String, dynamic>;
        await repo.login(
          serverUrl: server,
          username: identity['username'] as String,
          password: identity['password'] as String,
          allowLocalHttp: true,
        );
        expect(repo.state.session, isNotNull);
      }

      Future<void> sync(CollaborationRepository repo) async {
        await repo.syncNow();
        expect(repo.state.lastError, isNull);
      }

      Matcher failure(String code) => throwsA(
        isA<CollaborationException>().having((e) => e.code, 'code', code),
      );
      Future<void> invite(
        CollaborationRepository owner,
        CollaborationRepository recipient,
        String scope,
        String actor,
        String access,
      ) async {
        final sent = await owner.createEmailInvitation(
          scopeId: scope,
          recipientEmail: (fixture[actor] as Map)['email'] as String,
          accessScope: access,
        );
        expect(sent.contractVersion, 3);
        expect(sent.accessScope, access);
        final pending = await recipient.pendingInvitations();
        final selected = pending.singleWhere((p) => p.invitationId == sent.id);
        expect(selected.contractVersion, 3);
        await recipient.acceptEmailInvitation(
          invitationId: sent.id,
          contractVersion: 3,
        );
        await sync(recipient);
      }

      try {
        final aStore = MemorySessionStore(),
            bStore = MemorySessionStore(),
            cStore = MemorySessionStore();
        final aTransport = SpaceHttpTransport(),
            bTransport = SpaceHttpTransport(),
            cTransport = SpaceHttpTransport();
        final a = await open('owner', aStore, aTransport);
        var b = await open('member', bStore, bTransport);
        final c = await open('project', cStore, cTransport);
        await login(a, 'owner');
        await login(b, 'member');
        await login(c, 'projectMember');
        for (final kind in [
          SharedScopeKind.household,
          SharedScopeKind.organization,
        ]) {
          final root = await a.createScope(
            'Synthetic ${kind.name} ${newSharedId()}',
            kind: kind,
          );
          final child = await a.createScope(
            'Initial project',
            kind: SharedScopeKind.project,
            parentScopeId: root,
          );
          final sibling = await a.createScope(
            'Private sibling',
            kind: SharedScopeKind.project,
            parentScopeId: root,
          );
          await sync(a);
          final account = await a.createFinanceAccount(
            scopeId: child,
            name: 'Project ledger',
            currency: 'EUR',
          );
          await a.createFinanceEntry(
            scopeId: child,
            accountId: account,
            kind: FinanceEntryKind.expense,
            amountMinor: 123,
            currency: 'EUR',
            title: 'Shared project fact',
            occurredAt: DateTime.now().toUtc(),
          );
          await sync(a);
          await invite(a, b, root, 'member', 'space');
          await invite(a, c, child, 'projectMember', 'project');
          expect(
            b.state.scopes
                .where((s) => {root, child, sibling}.contains(s.id))
                .length,
            3,
          );
          expect(c.state.scopes.any((s) => s.id == child), true);
          expect(
            c.state.scopes.any((s) => s.id == root || s.id == sibling),
            false,
          );
          expect(c.state.financePolicyForScope(child).canWrite, true);
          expect(
            c.state.dataForScope(child).financeEntries.single.title,
            'Shared project fact',
          );
          for (final denied in [root, sibling]) {
            await expectLater(
              cTransport.call(
                serverUrl: server,
                operation: 'scopes.members',
                params: {'scopeId': denied},
                token: cStore.value!.token,
                allowLocalHttp: true,
              ),
              failure('permission_revoked'),
            );
          }
          final future = await b.createScope(
            'Future project',
            kind: SharedScopeKind.project,
            parentScopeId: root,
          );
          await sync(b);
          await sync(a);
          await sync(c);
          expect(b.state.scopes.any((s) => s.id == future), true);
          expect(c.state.scopes.any((s) => s.id == future), false);
          final task = await c.createTask(
            scopeId: child,
            title: 'Project-only editing',
          );
          await c.createFinanceEntry(
            scopeId: child,
            accountId: account,
            kind: FinanceEntryKind.expense,
            amountMinor: 45,
            currency: 'EUR',
            title: 'Project-only finance edit',
            occurredAt: DateTime.now().toUtc(),
          );
          await sync(c);
          await sync(a);
          expect(
            a.state.dataForScope(child).tasks.any((t) => t.id == task),
            true,
          );
          expect(
            b.state.scopes.singleWhere((s) => s.id == root).canManage,
            true,
          );
          expect(
            c.state.scopes.singleWhere((s) => s.id == child).canManage,
            true,
          );
          await a.revokeMember(scopeId: root, userId: b.state.session!.userId);
          await sync(b);
          await sync(c);
          expect(b.state.scopes.singleWhere((s) => s.id == root).revoked, true);
          expect(
            c.state.scopes.singleWhere((s) => s.id == child).revoked,
            false,
          );
        }
        final home = await a.createScope('Inline extraction');
        final project = await a.createProject(
          scopeId: home,
          title: 'Original UUID',
        );
        final before = await a.database.rows('SELECT * FROM outbox');
        await expectLater(
          a.previewProjectSharing(home, project),
          failure('project_sharing_pending_changes'),
        );
        expect(
          jsonEncode(await a.database.rows('SELECT * FROM outbox')),
          jsonEncode(before),
        );
        await sync(a);
        final stale = await a.previewProjectSharing(home, project);
        await a.createTask(
          scopeId: home,
          projectId: project,
          title: 'New child after preview',
        );
        await sync(a);
        await expectLater(
          a.applyProjectSharing(stale),
          failure('project_sharing_preview_changed'),
        );
        expect(
          a.state.dataForScope(home).projects.any((p) => p.id == project),
          true,
        );
        final fresh = await a.previewProjectSharing(home, project);
        expect(fresh.canApply, true);
        aTransport.loseNext = 'scopes.projectSharingApply';
        await expectLater(a.applyProjectSharing(fresh), failure('network'));
        await expectLater(
          a.createShoppingList(scopeId: home, title: 'Wait'),
          failure('project_sharing_pending_changes'),
        );
        final extracted = await a.resumeProjectSharing(home);
        expect(extracted!.id, project);
        expect(extracted.parentSpaceId, home);
        expect(
          jsonEncode(
            aTransport.extractionRequests[aTransport.extractionRequests.length -
                2],
          ),
          jsonEncode(aTransport.extractionRequests.last),
        );
        expect(a.state.dataForScope(project).projects.single.id, project);
        final offlineHome = await a.createScope('Offline retained');
        await invite(a, b, offlineHome, 'member', 'space');
        await a.createTask(scopeId: offlineHome, title: 'Retained offline');
        await sync(a);
        await sync(b);
        await b.close();
        repos.remove(b);
        final offline = SpaceHttpTransport()..offline = true;
        b = await open('member', bStore, offline);
        expect(
          b.state.dataForScope(offlineHome).tasks.single.title,
          'Retained offline',
        );
        await b.createTask(scopeId: offlineHome, title: 'New offline');
        expect(b.state.dataForScope(offlineHome).tasks.length, 2);
      } finally {
        for (final repo in repos) {
          await repo.close();
        }
        await directory.delete(recursive: true);
      }
    },
    skip: fixturePath == null,
  );
}
