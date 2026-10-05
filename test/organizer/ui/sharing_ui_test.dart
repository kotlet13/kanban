import 'package:kanban/organizer/state/portable_backup_provider.dart';
import 'backup_ui_fixture.dart';
import 'package:kanban/organizer/platform/backup_preferences_replay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kanban/app.dart';
import 'package:kanban/app_router.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'package:kanban/organizer/state/organizer_provider.dart';
import 'package:kanban/organizer/presentation/shared/sharing_status.dart';

import 'organizer_ui_test.dart' as personal;
import 'sharing_ui_fixture.dart';

Future<void> pumpSharing(
  WidgetTester tester,
  SharingUiController controller, {
  double width = 390,
  String locale = 'sl',
  String theme = 'light',
  personal.MemoryOrganizerStorage? storage,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({
    'app_locale_code': locale,
    'app_theme_mode': theme,
  });
  appRouter.go('/');
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        portableBackupProvider.overrideWith(EmptyBackupUiController.new),
        backupPreferencesReplayProvider.overrideWith((ref) async => {}),
        organizerStorageProvider.overrideWithValue(
          () async => storage ?? personal.MemoryOrganizerStorage(),
        ),
        collaborationProvider.overrideWith(() => controller),
      ],
      child: const KanbanApp(),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> openAccount(
  WidgetTester tester, {
  double width = 390,
  String locale = 'sl',
}) async {
  if (width < 900) {
    await personal.mobileTab(tester, locale == 'sl' ? 'Več' : 'More');
  }
  await tester.tap(
    find.widgetWithText(
      ListTile,
      locale == 'sl' ? 'Račun in deljenje' : 'Account and sharing',
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> openSharedShopping(
  WidgetTester tester, {
  double width = 390,
  String locale = 'sl',
}) async {
  if (width < 900) {
    await personal.mobileTab(tester, locale == 'sl' ? 'Nakupi' : 'Shopping');
  } else {
    await tester.tap(
      find.widgetWithText(ListTile, locale == 'sl' ? 'Nakupi' : 'Shopping'),
    );
    await tester.pumpAndSettle();
  }
  await tester.tap(
    find.widgetWithText(ChoiceChip, locale == 'sl' ? 'Deljeno' : 'Shared'),
  );
  await tester.pumpAndSettle();
}

Future<void> enterSharing(WidgetTester tester, String id, String value) async {
  final field = find.byKey(ValueKey('sharing-$id'));
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.enterText(field, value);
}

Future<void> tapSharing(WidgetTester tester, String key) async {
  final target = find.byKey(ValueKey(key));
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> openMembers(WidgetTester tester) async {
  await openAccount(tester);
  await tester.ensureVisible(
    find.widgetWithText(ListTile, sharingScope().name),
  );
  await tester.tap(find.widgetWithText(ListTile, sharingScope().name));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Člani'));
  await tester.tap(find.widgetWithText(ChoiceChip, 'Člani'));
  await tester.pumpAndSettle();
}

void main() {
  for (final width in [320.0, 390.0, 1280.0]) {
    for (final locale in ['sl', 'en']) {
      for (final theme in ['light', 'dark']) {
        testWidgets(
          'shared shopping and account layout $width $locale $theme',
          (tester) async {
            final controller = SharingUiController();
            await pumpSharing(
              tester,
              controller,
              width: width,
              locale: locale,
              theme: theme,
            );
            await openSharedShopping(tester, width: width, locale: locale);
            expect(
              find.text('Skupna trgovina'),
              findsNWidgets(width >= 900 ? 2 : 1),
            );
            expect(find.text('Mleko za skupno gospodinjstvo'), findsOneWidget);
            expect(
              tester.getSize(find.byType(SharingStatus)).height,
              lessThanOrEqualTo(64),
            );
            expect(
              find.byTooltip(locale == 'sl' ? 'Uskladi zdaj' : 'Sync now'),
              findsOneWidget,
            );
            expect(tester.takeException(), isNull);
            await openAccount(tester, width: width, locale: locale);
            expect(find.text('Prva oseba'), findsOneWidget);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  testWidgets(
    'sign-in asks for OTP after challenge; normal HTTPS hides development UI',
    (tester) async {
      final controller = SharingUiController(initial: CollaborationState())
        ..requireOtp = true;
      await pumpSharing(tester, controller, width: 320);
      await openAccount(tester, width: 320);
      expect(
        find.text('Lokalna razvojna povezava (HTTP na tem računalniku)'),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('sharing-otp')), findsNothing);
      await enterSharing(tester, 'server', 'https://sharing.example.test');
      await enterSharing(tester, 'username', 'first');
      await enterSharing(tester, 'password', 'synthetic-password');
      await tapSharing(tester, 'sharing-connect');
      expect(
        find.text('Vpiši kodo iz aplikacije za dvostopenjsko prijavo.'),
        findsOneWidget,
      );
      await enterSharing(tester, 'otp', '123456');
      await tapSharing(tester, 'sharing-connect');
      expect(controller.loginAttempts, [null, '123456']);
      expect(find.text('Prva oseba'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'invitation registration uses preset username and never claims email verification',
    (tester) async {
      final controller = SharingUiController(initial: CollaborationState());
      await pumpSharing(tester, controller, width: 320);
      await openAccount(tester, width: 320);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Imam povabilo'));
      await tester.pumpAndSettle();
      await enterSharing(tester, 'server', 'https://sharing.example.test');
      await enterSharing(tester, 'invitation-token', 'synthetic-token');
      final tokenField = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const ValueKey('sharing-invitation-token')),
          matching: find.byType(TextField),
        ),
      );
      expect(tokenField.enableSuggestions, false);
      expect(tokenField.enableIMEPersonalizedLearning, false);
      await tapSharing(tester, 'sharing-preview-invite');
      final username = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const ValueKey('sharing-username')),
          matching: find.byType(TextField),
        ),
      );
      expect(username.readOnly, true);
      expect(username.controller!.text, 'second');
      expect(find.text('E-pošta'), findsNothing);
      await enterSharing(tester, 'display-name', 'Druga oseba');
      await enterSharing(tester, 'password', 'synthetic-password');
      await enterSharing(tester, 'confirm-password', 'synthetic-password');
      await tapSharing(tester, 'sharing-connect');
      expect(controller.registeredUsername, 'second');
      expect(controller.registeredName, 'Druga oseba');
      expect(controller.calls.where((call) => call == 'accept'), isEmpty);
      expect(find.text('Druga oseba'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'shared shopping edits use shared controller and show durable pending state',
    (tester) async {
      final controller = SharingUiController();
      final storage = personal.MemoryOrganizerStorage();
      await pumpSharing(tester, controller, storage: storage);
      await openSharedShopping(tester);
      await tester.ensureVisible(
        find.byKey(const ValueKey('shopping-item-field')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('shopping-item-field')),
        'Kruh',
      );
      await tester.tap(find.byTooltip('Dodaj izdelek'));
      await tester.pumpAndSettle();
      expect(controller.calls, contains('item:Kruh'));
      expect(find.text('Kruh'), findsOneWidget);
      expect(find.text('1 · Čaka na uskladitev'), findsOneWidget);
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      expect(controller.calls, contains('check:true'));
      expect(find.text('Kupljeno (1)'), findsOneWidget);
      expect(storage.writes, 0);
      expect(storage.snapshot.shoppingItems, isEmpty);
    },
  );

  testWidgets(
    'personal shopping copy retains original and does not copy finance/events',
    (tester) async {
      final controller = SharingUiController();
      final storage = personal.MemoryOrganizerStorage();
      storage.snapshot = OrganizerSnapshot(
        shoppingLists: [
          LocalShoppingList(
            id: 'personal',
            title: 'Osebna trgovina',
            createdAt: sharingTestNow,
            updatedAt: sharingTestNow,
          ),
        ],
        shoppingItems: [
          LocalShoppingItem(
            id: 'personal-item',
            listId: 'personal',
            title: 'Jabolka',
            quantity: '1 kg',
            isChecked: false,
            createdAt: sharingTestNow,
            updatedAt: sharingTestNow,
          ),
        ],
        financeEntries: [
          FinanceEntry(
            id: 'money',
            title: 'Osebni strošek',
            amountMinor: 12345,
            currency: 'EUR',
            kind: FinanceEntryKind.expense,
            occurredAt: sharingTestNow,
            projectId: null,
            notes: '',
            createdAt: sharingTestNow,
            updatedAt: sharingTestNow,
          ),
        ],
      );
      await pumpSharing(tester, controller, storage: storage);
      await personal.mobileTab(tester, 'Nakupi');
      await tester.tap(find.text('Ustvari skupno kopijo'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Poznejše spremembe osebnega izvirnika'),
        findsOneWidget,
      );
      await tapSharing(tester, 'sharing-submit');
      expect(controller.copiedList?.id, 'personal');
      expect(controller.copiedItems?.single.title, 'Jabolka');
      expect(storage.writes, 0);
      expect(storage.snapshot.shoppingLists.single.id, 'personal');
      expect(storage.snapshot.financeEntries.single.id, 'money');
      expect(find.text('Skupna trgovina'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'account switch closes invitation form and hides cached members',
    (tester) async {
      final controller = SharingUiController();
      await pumpSharing(tester, controller);
      await openMembers(tester);
      expect(find.text('Member Alpha'), findsOneWidget);
      await tester.ensureVisible(find.text('Povabi osebo'));
      await tester.tap(find.text('Povabi osebo'));
      await tester.pumpAndSettle();
      await enterSharing(tester, 'recipient', 'second');
      controller.switchAccount();
      await tester.pumpAndSettle();
      expect(find.text('Member Alpha'), findsNothing);
      expect(find.byKey(const ValueKey('sharing-recipient')), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      expect(controller.calls.where((call) => call == 'invite'), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('members refresh reveals newly accepted recipient', (
    tester,
  ) async {
    final controller = SharingUiController()..includeSecondMember = false;
    await pumpSharing(tester, controller, width: 320);
    await openMembers(tester);
    expect(find.text('Member Alpha'), findsOneWidget);
    expect(find.text('Member Beta'), findsNothing);
    expect(controller.memberLoads, 1);
    controller.includeSecondMember = true;
    await tapSharing(tester, 'sharing-refresh-members');
    expect(find.text('Member Beta'), findsOneWidget);
    expect(controller.memberLoads, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('account switch closes nested member revoke confirmation', (
    tester,
  ) async {
    final controller = SharingUiController();
    await pumpSharing(tester, controller);
    await openMembers(tester);
    await tester.ensureVisible(find.byTooltip('Odstrani člana'));
    await tester.tap(find.byTooltip('Odstrani člana'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    controller.switchAccount();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(
      controller.calls.where((call) => call.startsWith('remove:')),
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('account switch closes one-time token display', (tester) async {
    final controller = SharingUiController();
    await pumpSharing(tester, controller);
    await openMembers(tester);
    await tester.ensureVisible(find.text('Povabi osebo'));
    await tester.tap(find.text('Povabi osebo'));
    await tester.pumpAndSettle();
    await enterSharing(tester, 'recipient', 'second');
    await tapSharing(tester, 'sharing-submit');
    expect(find.text('synthetic-invitation-token'), findsOneWidget);
    controller.switchAccount();
    await tester.pumpAndSettle();
    expect(find.text('synthetic-invitation-token'), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'viewer and revoked access cannot edit; revoked cached contents hidden',
    (tester) async {
      final controller = SharingUiController(
        initial: CollaborationState(
          session: sharingSession(),
          scopes: [sharingScope(role: SharedRole.viewer)],
          data: {sharingScopeId: sharingData()},
        ),
      );
      await pumpSharing(tester, controller);
      await openSharedShopping(tester);
      expect(find.text('Samo za branje'), findsOneWidget);
      expect(find.byKey(const ValueKey('shopping-item-field')), findsNothing);
      expect(
        tester.widget<Checkbox>(find.byType(Checkbox).first).onChanged,
        isNull,
      );
      controller.replace(
        CollaborationState(
          session: sharingSession(),
          scopes: [sharingScope(revoked: true, blocked: true)],
          data: {sharingScopeId: sharingData()},
          blockedCount: 1,
          lastError: const CollaborationException('permission_revoked'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Mleko za skupno gospodinjstvo'), findsNothing);
      expect(find.text('Shrani moje neusklajene spremembe'), findsWidgets);
      expect(
        controller.calls.where((call) => call.startsWith('check:')),
        isEmpty,
      );
    },
  );

  testWidgets(
    'conflict comparison resolves explicit choice and closes on account switch',
    (tester) async {
      final conflict = SharedConflict(
        id: 'conflict',
        scopeId: sharingScopeId,
        recordId: 'item',
        recordType: SharedRecordType.shoppingItem,
        reason: 'conflict',
        localPayload: {'title': 'Moje mleko', 'quantity': '1 l'},
        remotePayload: {'title': 'Drugo mleko', 'quantity': '2 l'},
      );
      final controller = SharingUiController(
        initial: CollaborationState(
          session: sharingSession(),
          scopes: [sharingScope()],
          data: {sharingScopeId: sharingData()},
          conflicts: [conflict],
        ),
      );
      await pumpSharing(tester, controller, width: 320);
      await openSharedShopping(tester, width: 320);
      await tester.tap(find.text('Preglej spremembe (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Moje mleko'), findsOneWidget);
      expect(find.text('Drugo mleko'), findsOneWidget);
      await tester.ensureVisible(find.text('Obdrži mojo različico'));
      await tester.tap(find.text('Obdrži mojo različico'));
      await tester.pumpAndSettle();
      expect(controller.calls, contains('resolve:true'));
      controller.switchAccount();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
