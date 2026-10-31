import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/presentation/onboarding/getting_started.dart';
import 'package:kanban/organizer/presentation/recovery/recovery_file_explanation.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _app(Widget child) => ProviderScope(
  child: MaterialApp(
    locale: const Locale('sl'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('first Pulse hint stays for one visit then stays dismissed', (
    tester,
  ) async {
    var invitations = 0;
    final hint = GettingStartedHint(
      onStart: () {},
      onInvitation: () => invitations++,
    );
    await tester.pumpWidget(_app(hint));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('first-launch-invitation')),
      findsOneWidget,
    );
    expect(
      (await SharedPreferences.getInstance()).getBool(
        'organizer_getting_started_seen_v1',
      ),
      isTrue,
    );
    await tester.tap(find.byKey(const ValueKey('first-launch-invitation')));
    await tester.pumpAndSettle();
    expect(invitations, 1);
    expect(find.byKey(const ValueKey('first-launch-invitation')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(_app(hint));
    await tester.pumpAndSettle();
    // An unread guide does not resurrect the first-visit card.
    expect(find.byKey(const ValueKey('first-launch-invitation')), findsNothing);
  });

  testWidgets(
    'existing use suppresses the first-use card without deleting data',
    (tester) async {
      SharedPreferences.setMockInitialValues({'unrelated_preference': 'keep'});
      await tester.pumpWidget(
        _app(GettingStartedHint(onStart: () {}, alreadyStarted: true)),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('first-launch-invitation')),
        findsNothing,
      );
      expect(
        (await SharedPreferences.getInstance()).getString(
          'unrelated_preference',
        ),
        'keep',
      );
    },
  );

  for (final scope in RecoveryFileScope.values) {
    testWidgets(
      'recovery help $scope explains limits and preserves open form',
      (tester) async {
        final controller = TextEditingController(text: 'unchanged draft');
        await tester.pumpWidget(
          _app(
            Column(
              children: [
                TextField(controller: controller),
                RecoveryFileExplanation(scope: scope),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('recovery-file-explanation')),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('ne kopije tvojih vnosov'), findsOneWidget);
        await tester.tap(find.text('Zapri'));
        await tester.pumpAndSettle();
        expect(controller.text, 'unchanged draft');
        expect(find.byType(AlertDialog), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      },
    );
  }
}
