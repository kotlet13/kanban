import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kanban/features/ai/project_ai_chat_page.dart';
import 'package:kanban/l10n/l10n.dart';
import 'package:kanban/state/providers.dart';
import 'package:kanban/storage/account_scope.dart';
import 'package:kanban/storage/ai_chat_store.dart';

import '../../storage/ai_account_isolation_test.dart' show credentials, thread;

class DelayedChatStore extends AiChatStore {
  DelayedChatStore(String scope) : super(scope: scope);
  final pending = Completer<List<AiChatThread>>();
  @override
  Future<List<AiChatThread>> readByProject(int projectId) => pending.future;
}

Widget page(ProviderContainer container) => UncontrolledProviderScope(
  container: container,
  child: const MaterialApp(
    locale: Locale('en'),
    localizationsDelegates: [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: ProjectAiChatPage(projectId: 1, projectName: 'Project'),
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'changing accounts immediately hides the previous chat in an open page',
    (tester) async {
      final alice = credentials('https://one.example', 'Alice');
      final bob = credentials('https://one.example', 'Bob');
      final store = AiChatStore(scope: accountScopeKey(alice));
      await store.saveThread(
        thread('alice-private', text: 'Alice private conversation'),
      );
      final container = ProviderContainer(
        overrides: [kanboardApiProvider.overrideWithValue(null)],
      );
      addTearDown(container.dispose);
      container.read(sessionCredentialsProvider.notifier).state = alice;
      await tester.pumpWidget(page(container));
      await tester.pumpAndSettle();
      expect(find.text('Alice private conversation'), findsOneWidget);
      container.read(sessionCredentialsProvider.notifier).state = bob;
      await tester.pumpAndSettle();
      expect(find.text('Alice private conversation'), findsNothing);
      expect(
        find.text(
          'The account changed. This chat belongs to the previous session; reopen AI help from your project.',
        ),
        findsOneWidget,
      );
      expect(
        await container.read(aiChatStoreProvider).readByProject(1),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a delayed old-account load cannot appear or persist under the new account',
    (tester) async {
      final alice = credentials('https://late.example', 'Alice');
      final bob = credentials('https://late.example', 'Bob');
      final slow = DelayedChatStore(accountScopeKey(alice));
      final container = ProviderContainer(
        overrides: [
          kanboardApiProvider.overrideWithValue(null),
          aiChatStoreProvider.overrideWith((ref) {
            final current = ref.watch(sessionCredentialsProvider);
            return identical(current, alice)
                ? slow
                : AiChatStore(
                    scope: current == null ? null : accountScopeKey(current),
                  );
          }),
        ],
      );
      addTearDown(container.dispose);
      container.read(sessionCredentialsProvider.notifier).state = alice;
      await tester.pumpWidget(page(container));
      await tester.pump();
      container.read(sessionCredentialsProvider.notifier).state = bob;
      await tester.pump();
      slow.pending.complete([
        thread('late-private', text: 'Old account response'),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Old account response'), findsNothing);
      expect(
        await container.read(aiChatStoreProvider).readByProject(1),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
