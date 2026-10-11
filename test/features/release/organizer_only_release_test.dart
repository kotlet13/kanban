import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/app_router.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'package:kanban/organizer/presentation/shared/sharing_account_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../organizer/ui/sharing_ui_fixture.dart';
import '../../organizer/ui/organizer_ui_test.dart'
    show MemoryOrganizerStorage, pumpOrganizer, mobileTab, saveTitle;

const retiredValues = <String, Object>{
  'kanboard_server_url': 'https://retired.invalid',
  'kanboard_username': 'retired-account',
  'kanboard_token': 'retired-test-token',
  'kanboard_auth_mode': 'apiToken',
  'project_defaults_columns': <String>['Stara kolona'],
  'project_defaults_swimlane': 'Stara steza',
  'project_defaults_currency': 'EUR',
  'ai_enabled': true,
  'ai_model': 'previous-model',
  'ai_api_key': 'retired-test-key',
  'ai_chat_threads_v1': 'unparsed legacy history',
  'ai_chat_threads_v2_old-account': 'unparsed scoped history',
  'ai_cost_consent_v2_old-account_1': true,
};

Future<void> expectRetiredValuesPreserved() async {
  final prefs = await SharedPreferences.getInstance();
  for (final item in retiredValues.entries) {
    expect(prefs.get(item.key), item.value, reason: item.key);
  }
}

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.macOS]) {
    testWidgets('all retired routes are rejected on $platform', (tester) async {
      tester.view.physicalSize = Size(
        platform == TargetPlatform.android ? 390 : 1280,
        900,
      );
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues(retiredValues);
      const paths = [
        '/launch',
        '/connect',
        '/projects',
        '/settings/project-defaults',
        '/settings/ai',
        '/board/1',
        '/board/1/structure',
        '/board/1/task?taskId=41',
        '/board/1/expenses',
        '/board/1/finance-table',
        '/board/1/ai-chat',
        '/board/1/unknown',
      ];
      appRouter.go(paths.first);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(
            theme: ThemeData(platform: platform),
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: appRouter,
          ),
        ),
      );
      for (final path in paths) {
        appRouter.go(path);
        await tester.pumpAndSettle();
        expect(find.text('Route error'), findsOneWidget, reason: path);
        expect(find.byType(TextField), findsNothing, reason: path);
        expect(tester.takeException(), isNull, reason: path);
        await expectRetiredValuesPreserved();
      }
    });
  }

  for (final width in [390.0, 1280.0]) {
    testWidgets(
      'local tasks finances settings and FamilyHub remain usable with retired data $width',
      (tester) async {
        const channel = MethodChannel(
          'plugins.it_nomads.com/flutter_secure_storage',
        );
        final secureCalls = <String>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              final arguments = Map<String, dynamic>.from(
                call.arguments as Map,
              );
              final key = arguments['key'] as String;
              secureCalls.add(key);
              expect(key, isNot(startsWith('kanboard_')));
              expect(key, isNot(startsWith('ai_')));
              return null;
            });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null);
        });
        final storage = MemoryOrganizerStorage();
        await pumpOrganizer(
          tester,
          storage,
          width: width,
          initialPreferences: retiredValues,
          collaborationController: SharingUiController(
            initial: CollaborationState(),
          ),
        );
        await expectRetiredValuesPreserved();
        expect(find.text('Začni z enim opravilom.'), findsOneWidget);
        await tester.tap(
          find.widgetWithText(TextButton, 'Dodaj opravilo').first,
        );
        await tester.pumpAndSettle();
        await saveTitle(tester, 'Novo lokalno opravilo');
        expect(storage.snapshot.tasks.single.title, 'Novo lokalno opravilo');
        expect(find.byIcon(Icons.smart_toy_outlined), findsNothing);

        Future<void> area(String label) async {
          if (width < 900) {
            await mobileTab(tester, label);
          } else {
            await tester.tap(find.widgetWithText(ListTile, label));
            await tester.pumpAndSettle();
          }
        }

        await area('Finance');
        await tester.tap(find.text('Dodaj zapis').first);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('organizer-title-field')),
          'Nov lokalni strošek',
        );
        final amount = find.byKey(const ValueKey('personal-finance-amount'));
        await tester.ensureVisible(amount);
        await tester.enterText(amount, '12,34');
        await tester.ensureVisible(
          find.byKey(const ValueKey('organizer-save')),
        );
        await tester.tap(find.byKey(const ValueKey('organizer-save')));
        await tester.pumpAndSettle();
        expect(storage.snapshot.financeEntries.single.amountMinor, 1234);
        expect(
          storage.snapshot.financeEntries.single.title,
          'Nov lokalni strošek',
        );

        await area('Nastavitve');
        expect(find.text('Obstoječi Kanboard'), findsNothing);
        expect(find.text('Odpri Kanboard'), findsNothing);
        expect(find.text('Varnostna kopija'), findsOneWidget);
        await tester.ensureVisible(find.text('Temna tema'));
        await tester.tap(find.text('Temna tema'));
        await tester.pumpAndSettle();
        expect(
          (await SharedPreferences.getInstance()).getString('app_theme_mode'),
          'dark',
        );
        await expectRetiredValuesPreserved();

        await area('Račun in deljenje');
        expect(find.byType(SharingAccountPage), findsOneWidget);
        expect(find.byIcon(Icons.smart_toy_outlined), findsNothing);
        expect(storage.snapshot.tasks, hasLength(1));
        expect(storage.snapshot.financeEntries, hasLength(1));
        expect(
          secureCalls.where(
            (key) => key.startsWith('kanboard_') || key.startsWith('ai_'),
          ),
          isEmpty,
        );
        await expectRetiredValuesPreserved();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
