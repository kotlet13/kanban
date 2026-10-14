import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';

import 'collaboration_repository_test.dart' show FakeServer, FakeTransport, MemorySessionStore, code;

class LifecycleServer extends FakeServer {
  final deleted = <String>{};
  final deleteRequests = <Map<String, Object?>>[];
  final receipts = <String, Map<String, dynamic>>{};
  bool loseDeleteReply = false;
  int revision = 1, commits = 0;
  String get hash => '$revision'.padLeft(64, '0');

  @override
  Future<Map<String, dynamic>> call(String op, Map<String, Object?> params, String? token) async {
    if (op == 'scopes.deletionPreview') {
      final sid = params['scopeId'] as String;
      return {'scopeId': sid, 'projectId': null, 'name': scopes[sid]!['name'], 'scopeNames': [scopes[sid]!['name']], 'counts': {'spaces': 1, 'projects': 0, 'tasks': 0, 'events': 0, 'ideas': 0, 'photos': 0, 'finance': 0, 'other': records[sid]!.length}, 'canDelete': true, 'blockers': [], 'previewHash': hash};
    }
    if (op == 'scopes.delete') {
      deleteRequests.add(Map.of(params));
      final request = params['requestId'] as String;
      if (receipts[request] case final reply?) return reply;
      if (params['previewHash'] != hash) throw const CollaborationApiException('scope_deletion_preview_changed');
      final sid = params['scopeId'] as String;
      final user = tokens[token];
      if (members[sid]?[user] != 'owner') throw const CollaborationApiException('permission_revoked');
      for (final username in members[sid]!.keys.toList()) { confirmRevocation(sid, username); }
      deleted.add(sid);
      commits++;
      final reply = receipts[request] = {'deleted': true, 'scopeId': sid, 'projectId': null, 'deletedScopeIds': [sid], 'records': [], 'financeRecords': [], 'cleanupPending': false};
      if (loseDeleteReply) { loseDeleteReply = false; throw const CollaborationException('network'); }
      return reply;
    }
    final reply = await super.call(op, params, token);
    if (op == 'capabilities') {
      (reply['features'] as Map).addAll(<String, bool>{'scopeDeletion': true, 'scopeArchiving': true});
    }
    if (op == 'scopes.list') {
      reply['deletedScopeIds'] = deleted.where((id) => confirmedRevocations[tokens[token]]?.contains(id) == true).toList();
    }
    return reply;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Directory dir;
  late LifecycleServer server;
  final repos = <CollaborationRepository>[];
  Future<CollaborationRepository> open(String name, MemorySessionStore store, {FakeTransport? transport}) async {
    final repo = CollaborationRepository(CollaborationDatabase(NativeDatabase(File('${dir.path}/$name.sqlite'))), transport ?? FakeTransport(server), store);
    await repo.initialize(); repos.add(repo); return repo;
  }
  Future<void> login(CollaborationRepository repo, String name) => repo.login(serverUrl: 'https://synthetic.invalid/', username: name, password: 'synthetic-password');
  setUp(() async { dir = await Directory.systemTemp.createTemp('scope-lifecycle-'); server = LifecycleServer(); });
  tearDown(() async { for (final repo in repos) { await repo.close(); } repos.clear(); await dir.delete(recursive: true); });

  test('confirmed deletion hides revoked graph, retains offline drafts and unrelated scope', () async {
    final owner = await open('owner', MemorySessionStore()), transport = FakeTransport(server);
    final member = await open('member', MemorySessionStore(), transport: transport);
    await login(owner, 'alice'); await login(member, 'bob');
    final sid = await owner.createScope('Deleted household'), unrelated = await member.createScope('Own household');
    server.members[sid]!['bob'] = 'member';
    await owner.createShoppingList(scopeId: sid, title: 'Shared'); await owner.syncNow(); await member.syncNow();
    transport.offline = true;
    await member.updateShoppingList(sid, member.state.dataForScope(sid).shoppingLists.single.copyWith(title: 'Own unsent draft'));
    final before = await member.exportUnsentWork();
    final cached = await member.database.rows('SELECT payload FROM records WHERE partition=? AND scope_id=?', [member.state.session!.partition, sid]);
    await owner.deleteScopeContents(await owner.previewScopeDeletion(sid));
    transport.offline = false; await member.syncNow();
    expect(member.state.scopes.singleWhere((s) => s.id == sid).deleted, true);
    expect(member.state.dataForScope(sid).shoppingLists, isEmpty);
    expect(member.state.scopes.singleWhere((s) => s.id == unrelated).canEdit, true);
    expect(member.state.sessionInvalid, false);
    expect(await member.database.rows('SELECT payload FROM records WHERE partition=? AND scope_id=?', [member.state.session!.partition, sid]), cached);
    final after = jsonDecode(await member.exportUnsentWork()) as Map;
    expect(after['operations'][0]['operation'], jsonDecode(before)['operations'][0]['operation']);
    expect(after['operations'][0]['state'], 'blocked');
    expect(member.state.blockedCount, 1);
    await expectLater(member.resumeBlockedChanges(sid), throwsA(code('permission_revoked')));
  });

  test('ordinary revocation keeps cached history and does not invent deletion', () async {
    final owner = await open('owner', MemorySessionStore()), member = await open('member', MemorySessionStore());
    await login(owner, 'alice'); await login(member, 'bob');
    final sid = await owner.createScope('Revoked household'); server.members[sid]!['bob'] = 'member';
    await owner.createShoppingList(scopeId: sid, title: 'Original'); await owner.syncNow(); await member.syncNow();
    await member.updateShoppingList(sid, member.state.dataForScope(sid).shoppingLists.single.copyWith(title: 'Retained draft'));
    server.confirmRevocation(sid, 'bob'); await member.syncNow();
    expect(member.state.scopes.singleWhere((s) => s.id == sid).revoked, true);
    expect(member.state.scopes.singleWhere((s) => s.id == sid).deleted, false);
    expect(member.state.dataForScope(sid).shoppingLists, isEmpty);
    expect((await member.exportUnsentWork()).toString(), contains('Retained draft'));
  });

  test('uncertain delete survives restart and retries original approved request exactly once', () async {
    final store = MemorySessionStore(); var repo = await open('owner', store); await login(repo, 'alice');
    final sid = await repo.createScope('Retry household'); final preview = await repo.previewScopeDeletion(sid);
    server.loseDeleteReply = true;
    await expectLater(repo.deleteScopeContents(preview), throwsA(code('network')));
    expect(server.commits, 1);
    final original = jsonEncode(server.deleteRequests.single);
    await repo.close(); repos.remove(repo); repo = await open('owner', store);
    final retryPreview = await repo.previewScopeDeletion(sid);
    expect(retryPreview, preview);
    await repo.deleteScopeContents(retryPreview);
    expect(server.commits, 1);
    expect(jsonEncode(server.deleteRequests.last), original);
    expect(repo.state.scopes.singleWhere((s) => s.id == sid).deleted, true);
    expect(await repo.database.rows("SELECT value FROM local_meta WHERE name LIKE 'scope_deletion_pending:%'"), isEmpty);
  });

  test('stale approved preview clears only definitively rejected request', () async {
    final repo = await open('owner', MemorySessionStore()); await login(repo, 'alice');
    final sid = await repo.createScope('Changed household'), preview = await repo.previewScopeDeletion(sid);
    server.revision++;
    await expectLater(repo.deleteScopeContents(preview), throwsA(code('scope_deletion_preview_changed')));
    expect(server.commits, 0);
    final fresh = await repo.previewScopeDeletion(sid);
    expect(fresh['previewHash'], isNot(preview['previewHash']));
    await repo.deleteScopeContents(fresh); expect(server.commits, 1);
  });
}
