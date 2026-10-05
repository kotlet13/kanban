// Opt in against a private, explicitly synthetic loopback server fixture.
// KANBAN_SHARED_HTTP_FIXTURE=/absolute/private/fixture.json flutter test ...
import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'collaboration_repository_test.dart' show MemorySessionStore;

class OfflineHttpTransport implements CollaborationTransport {
  final inner = HttpCollaborationTransport();
  bool offline = false;
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) {
    if (offline) throw const CollaborationException('network');
    return inner.call(
      serverUrl: serverUrl,
      operation: operation,
      params: params,
      token: token,
      allowLocalHttp: allowLocalHttp,
    );
  }

  @override
  void close() => inner.close();
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final fixturePath =
      Platform.environment['KANBAN_LEGACY_HTTP_FIXTURE'] ??
      Platform.environment['KANBAN_SHARED_HTTP_FIXTURE'];
  test(
    'real native HTTP: two accounts, disk restart, conflict, copy and revocation',
    () async {
      // Never print the private fixture or request/response bodies.
      final fixture =
          jsonDecode(await File(fixturePath!).readAsString())
              as Map<String, dynamic>;
      final server = fixture['server'] as String;
      if (fixture['synthetic'] != true ||
          Uri.parse(server).host != '127.0.0.1') {
        throw StateError('Integration fixture must be synthetic loopback');
      }
      final owner = fixture['owner'] as Map<String, dynamic>;
      final directory = await Directory.systemTemp.createTemp('shared-http-');
      final repositories = <CollaborationRepository>[];
      final storeA = MemorySessionStore(), storeB = MemorySessionStore();
      Future<CollaborationRepository> open(
        String file,
        MemorySessionStore store,
        OfflineHttpTransport transport,
      ) async {
        final repo = CollaborationRepository(
          CollaborationDatabase(
            NativeDatabase(File('${directory.path}/$file.sqlite')),
          ),
          transport,
          store,
        );
        repositories.add(repo);
        await repo.initialize();
        return repo;
      }

      Future<void> sync(CollaborationRepository repository) async {
        await repository.syncNow();
        expect(
          repository.state.lastError,
          isNull,
          reason: 'HTTP sync must succeed before reading its projection',
        );
      }

      try {
        var transportA = OfflineHttpTransport();
        var a = await open('a', storeA, transportA);
        final transportB = OfflineHttpTransport();
        final b = await open('b', storeB, transportB);
        await a.login(
          serverUrl: server,
          username: owner['username'] as String,
          password: owner['password'] as String,
          allowLocalHttp: true,
        );
        expect(a.state.session, isNotNull);
        final scope = await a.createScope(
          'Synthetic Dart integration ${newSharedId()}',
        );
        final username =
            'dart_${newSharedId().replaceAll('-', '').substring(0, 16)}';
        final invite = await a.createInvitation(
          scopeId: scope,
          recipientUsername: username,
        );
        expect(invite.token, isNotNull);
        final preview = await b.previewInvitation(
          serverUrl: server,
          token: invite.token!,
          allowLocalHttp: true,
        );
        expect(preview.recipientUsername, username);
        expect(preview.registrationAllowed, true);
        await b.registerWithInvitation(
          serverUrl: server,
          invitationToken: invite.token!,
          username: username,
          name: 'Synthetic Dart member',
          password: 'Synthetic-${newSharedId()}',
          allowLocalHttp: true,
        );
        expect(b.state.scopes.any((r) => r.id == scope), true);
        final now = DateTime.now().toUtc();
        final personalProject = LocalProject(
          id: newSharedId(),
          title: 'Original personal project',
          description: 'Original retained',
          createdAt: now,
          updatedAt: now,
        );
        transportA.offline = true;
        final listId = await a.createShoppingList(
          scopeId: scope,
          title: 'Offline shopping',
        );
        final itemId = await a.createShoppingItem(
          scopeId: scope,
          listId: listId,
          title: 'Offline item',
          quantity: '2',
        );
        await a.setShoppingItemChecked(scope, itemId, true);
        final projectId = await a.publishProject(
          scopeId: scope,
          project: personalProject,
          tasks: [
            LocalTask(
              id: newSharedId(),
              title: 'Copied basic task',
              notes: '',
              projectId: personalProject.id,
              dueAt: null,
              isCompleted: false,
              createdAt: now,
              updatedAt: now,
            ),
          ],
        );
        expect(projectId, isNot(personalProject.id));
        expect(personalProject.title, 'Original personal project');
        final draftExport = await a.exportUnsentWork();
        expect(a.state.pendingCount, 5);
        await a.close();
        repositories.remove(a);
        transportA = OfflineHttpTransport()..offline = true;
        a = await open('a', storeA, transportA);
        expect(a.state.pendingCount, 5);
        expect(await a.exportUnsentWork(), draftExport);
        expect(
          a.state.dataForScope(scope).shoppingItems.single.isChecked,
          true,
        );
        transportA.offline = false;
        await sync(a);
        expect(a.state.lastError, isNull);
        expect(a.state.pendingCount, 0);
        await sync(b);
        expect(
          b.state.dataForScope(scope).shoppingItems.single.isChecked,
          true,
        );
        expect(b.state.dataForScope(scope).tasks.single.projectId, projectId);
        transportA.offline = true;
        final oldA = a.state.dataForScope(scope).shoppingLists.single;
        await a.updateShoppingList(
          scope,
          oldA.copyWith(title: 'Offline A candidate'),
        );
        final oldB = b.state.dataForScope(scope).shoppingLists.single;
        await b.updateShoppingList(
          scope,
          oldB.copyWith(title: 'Online B canonical'),
        );
        await sync(b);
        transportA.offline = false;
        await sync(a);
        expect(a.state.conflicts.length, 1);
        expect(
          a.state.dataForScope(scope).shoppingLists.single.title,
          'Offline A candidate',
        );
        await a.resolveConflict(
          conflictId: a.state.conflicts.single.id,
          keepLocal: false,
        );
        expect(
          a.state.dataForScope(scope).shoppingLists.single.title,
          'Online B canonical',
        );
        transportB.offline = true;
        await b.createShoppingItem(
          scopeId: scope,
          listId: listId,
          title: 'Unsent revoked draft',
        );
        await a.revokeMember(scopeId: scope, userId: b.state.session!.userId);
        transportB.offline = false;
        await sync(b);
        expect(b.state.blockedCount, 1);
        expect(b.state.scopes.singleWhere((r) => r.id == scope).revoked, true);
        expect(b.state.dataForScope(scope).shoppingItems, isEmpty);
        expect(await b.exportUnsentWork(), contains('Unsent revoked draft'));
        final reinvite = await a.createInvitation(
          scopeId: scope,
          recipientUsername: username,
        );
        await b.acceptInvitation(reinvite.token!);
        expect(b.state.blockedCount, 1);
        await b.resumeBlockedChanges(scope);
        expect(b.state.pendingCount, 0);
        await sync(a);
        expect(a.state.dataForScope(scope).shoppingItems.length, 2);
        await b.signOut();
        await expectLater(
          b.exportUnsentWork(),
          throwsA(isA<CollaborationException>()),
        );
        await a.signOut();
      } finally {
        for (final repo in repositories) {
          await repo.close();
        }
        await directory.delete(recursive: true);
      }
    },
    skip: fixturePath == null
        ? 'Explicit synthetic HTTP fixture required'
        : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
