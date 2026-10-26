import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/domain/all_spaces_projection.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:kanban/organizer/presentation/planning/shared_agenda_page.dart';
import 'package:kanban/organizer/presentation/planning/utrip_overview.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  required String language,
}) async {
  tester.view.physicalSize = const Size(320, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        locale: Locale(language),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(padding: const EdgeInsets.all(20), child: child),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const _scope = SharedScope(
  id: 'scope',
  name: 'Space',
  kind: SharedScopeKind.project,
  role: SharedRole.owner,
);

void main() {
  for (final language in ['sl', 'en']) {
    final label = language == 'sl' ? 'Dodaj dogodek' : 'Add event';
    testWidgets(
      'pulse event action stays readable and tappable at 320px 2x $language',
      (tester) async {
        var calls = 0;
        final semantics = tester.ensureSemantics();
        try {
          await _pump(
            tester,
            OrganizerUtripOverview(
              snapshot: AllSpacesSnapshot([]),
              now: DateTime(2026, 10, 25),
              onCreateEvent: () => calls++,
            ),
            language: language,
          );
          final button = find.widgetWithText(TextButton, label);
          expect(button, findsOneWidget);
          await tester.ensureVisible(button);
          expect(button.hitTestable(), findsOneWidget);
          expect(tester.getSemantics(button).label, label);
          expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
          final textRect = tester.getRect(find.text(label));
          expect(tester.getRect(button).contains(textRect.topLeft), isTrue);
          expect(
            textRect.right,
            lessThanOrEqualTo(tester.getRect(button).right + 0.01),
          );
          expect(
            textRect.bottom,
            lessThanOrEqualTo(tester.getRect(button).bottom + 0.01),
          );
          await tester.tap(button);
          await tester.pump();
          expect(calls, 1);
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
    );
    testWidgets(
      'shared agenda event action stays readable and tappable at 320px 2x $language',
      (tester) async {
        var calls = 0;
        final semantics = tester.ensureSemantics();
        try {
          await _pump(
            tester,
            SharedAgendaPage(
              scope: _scope,
              data: SharedScopeData(),
              people: const [],
              onOpen: (_) {},
              onAddEvent: () => calls++,
            ),
            language: language,
          );
          final button = find.widgetWithText(FilledButton, label);
          expect(button, findsOneWidget);
          expect(button.hitTestable(), findsOneWidget);
          expect(tester.getSemantics(button).label, label);
          expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
          final textRect = tester.getRect(find.text(label));
          expect(tester.getRect(button).contains(textRect.topLeft), isTrue);
          expect(
            textRect.right,
            lessThanOrEqualTo(tester.getRect(button).right + 0.01),
          );
          expect(
            textRect.bottom,
            lessThanOrEqualTo(tester.getRect(button).bottom + 0.01),
          );
          await tester.tap(button);
          await tester.pump();
          expect(calls, 1);
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
    );
  }
}
