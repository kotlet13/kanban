import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kanban/ai/ai_models.dart';
import 'package:kanban/models/kanboard_models.dart';
import 'package:kanban/storage/account_scope.dart';
import 'package:kanban/storage/ai_chat_store.dart';
import 'package:kanban/storage/ai_consent_store.dart';

KanboardCredentials credentials(String server, String user) =>
    KanboardCredentials(
      serverUrl: server,
      username: user,
      token: 'not-a-real-token',
    );
AiChatThread thread(String id, {String text = 'private message'}) =>
    AiChatThread(
      id: id,
      projectId: 1,
      projectName: 'Project',
      createdAtMs: 1,
      updatedAtMs: 2,
      messages: [AiChatMessage(role: 'user', content: text)],
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'history and consent isolate identical project ids across server and user',
    () async {
      final a = accountScopeKey(
        credentials('https://one.example/kanboard', 'Alice'),
      );
      final otherServer = accountScopeKey(
        credentials('https://two.example/kanboard', 'Alice'),
      );
      final otherUser = accountScopeKey(
        credentials('https://one.example/kanboard', 'Bob'),
      );
      final chat = AiChatStore(scope: a);
      final consent = AiConsentStore(scope: a);
      await chat.saveThread(thread('a'));
      await consent.setAcceptedProjectCostWarning(
        projectId: 1,
        username: 'Alice',
        accepted: true,
      );
      for (final other in [otherServer, otherUser]) {
        expect(await AiChatStore(scope: other).readByProject(1), isEmpty);
        expect(
          await AiConsentStore(
            scope: other,
          ).hasAcceptedProjectCostWarning(projectId: 1, username: 'Alice'),
          false,
        );
      }
      expect((await chat.readByProject(1)).single.id, 'a');
      expect(
        await consent.hasAcceptedProjectCostWarning(
          projectId: 1,
          username: 'Alice',
        ),
        true,
      );
    },
  );

  test('canonical equivalent endpoints have one identity without secrets', () {
    final a = accountScopeKey(
      credentials('https://EXAMPLE.com:443/kanboard/', 'Alice'),
    );
    final b = accountScopeKey(
      credentials('https://example.com/kanboard', 'Alice'),
    );
    expect(a, b);
    expect(
      utf8.decode(base64Url.decode(a)),
      isNot(contains('not-a-real-token')),
    );
  });

  test('legacy global records remain preserved and unclaimed', () async {
    final raw = jsonEncode([thread('legacy').toJson()]);
    SharedPreferences.setMockInitialValues({
      'ai_chat_threads_v1': raw,
      'ai_cost_consent_1_alice': true,
    });
    final scope = accountScopeKey(credentials('https://one.example', 'Alice'));
    final chat = AiChatStore(scope: scope);
    final consent = AiConsentStore(scope: scope);
    expect(await chat.readAll(), isEmpty);
    expect(
      await consent.hasAcceptedProjectCostWarning(
        projectId: 1,
        username: 'Alice',
      ),
      false,
    );
    await chat.clearScope();
    await consent.clearScope();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('ai_chat_threads_v1'), raw);
    expect(prefs.getBool('ai_cost_consent_1_alice'), true);
  });

  test(
    'concurrent saves and deletes serialize across instances of one account',
    () async {
      final scope = accountScopeKey(
        credentials('https://writes.example', 'Alice'),
      );
      final a = AiChatStore(scope: scope);
      final b = AiChatStore(scope: scope);
      await Future.wait([
        a.saveThread(thread('first')),
        b.saveThread(thread('second')),
      ]);
      expect((await a.readAll()).map((t) => t.id).toSet(), {'first', 'second'});
      await Future.wait([
        a.deleteThread('first'),
        b.saveThread(thread('third')),
      ]);
      expect((await b.readAll()).map((t) => t.id).toSet(), {'second', 'third'});
    },
  );

  test(
    'logout clears only one scope and rejects captured in-flight writers',
    () async {
      final scope = accountScopeKey(
        credentials('https://logout.example', 'Alice'),
      );
      final a = AiChatStore(scope: scope);
      final captured = AiChatStore(scope: scope);
      final other = AiChatStore(
        scope: accountScopeKey(credentials('https://logout.example', 'Bob')),
      );
      await a.saveThread(thread('old'));
      await other.saveThread(thread('other'));
      final staleWrite = captured.saveThread(thread('late'));
      final rejected = expectLater(staleWrite, throwsStateError);
      await a.clearScope();
      await rejected;
      expect(await captured.readAll(), isEmpty);
      await expectLater(captured.saveThread(thread('later')), throwsStateError);
      final signedInAgain = AiChatStore(scope: scope);
      expect(await signedInAgain.readAll(), isEmpty);
      await signedInAgain.saveThread(thread('new'));
      expect((await other.readAll()).single.id, 'other');
    },
  );

  test(
    'unauthenticated stores cannot grant consent or persist history',
    () async {
      final chat = AiChatStore();
      final consent = AiConsentStore();
      expect(await chat.readAll(), isEmpty);
      expect(
        await consent.hasAcceptedProjectCostWarning(
          projectId: 1,
          username: 'Alice',
        ),
        false,
      );
      await expectLater(chat.saveThread(thread('a')), throwsStateError);
      await expectLater(
        consent.setAcceptedProjectCostWarning(
          projectId: 1,
          username: 'Alice',
          accepted: true,
        ),
        throwsStateError,
      );
    },
  );

  test(
    'logout revokes stale consent and fresh sign-in requires consent again',
    () async {
      final scope = accountScopeKey(
        credentials('https://consent.example', 'Alice'),
      );
      final old = AiConsentStore(scope: scope);
      await old.setAcceptedProjectCostWarning(
        projectId: 1,
        username: 'Alice',
        accepted: true,
      );
      await old.clearScope();
      await expectLater(
        old.setAcceptedProjectCostWarning(
          projectId: 1,
          username: 'Alice',
          accepted: true,
        ),
        throwsStateError,
      );
      expect(
        await AiConsentStore(
          scope: scope,
        ).hasAcceptedProjectCostWarning(projectId: 1, username: 'Alice'),
        false,
      );
    },
  );

  test(
    'corrupt scoped history throws and is never silently replaced',
    () async {
      final scope = accountScopeKey(
        credentials('https://corrupt.example', 'Alice'),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('ai_chat_threads_v2_$scope', 'broken-json');
      final store = AiChatStore(scope: scope);
      await expectLater(store.saveThread(thread('new')), throwsFormatException);
      expect(prefs.getString('ai_chat_threads_v2_$scope'), 'broken-json');
    },
  );
}
