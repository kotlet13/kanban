import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/presentation/onboarding/first_time_guide.dart';

void main() {
  for (final width in [320.0, 390.0, 1280.0]) {
    for (final language in ['sl', 'en']) {
      for (final dark in [false, true]) {
        testWidgets('guide completes without overflow $width $language $dark', (
          tester,
        ) async {
          SharedPreferences.setMockInitialValues({});
          tester.view.physicalSize = Size(width, 850);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            ProviderScope(
              child: MaterialApp(
                locale: Locale(language),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                theme: ThemeData(
                  brightness: dark ? Brightness.dark : Brightness.light,
                ),
                home: Scaffold(
                  body: Consumer(
                    builder: (context, ref, _) => TextButton(
                      onPressed: () => showFirstTimeGuide(context, ref),
                      child: const Text('Open'),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          for (var step = 0; step < 5; step++) {
            expect(
              find.text(
                language == 'sl' ? '${step + 1} od 5' : '${step + 1} of 5',
              ),
              findsOneWidget,
            );
            expect(tester.takeException(), null);
            await tester.ensureVisible(
              find.byKey(const ValueKey('guide-next')),
            );
            await tester.tap(find.byKey(const ValueKey('guide-next')));
            await tester.pumpAndSettle();
          }
          expect(find.byType(AlertDialog), findsNothing);
          expect(
            (await SharedPreferences.getInstance()).getBool(
              'jivie_guide_seen_v1',
            ),
            true,
          );
          // Acknowledgement does not disable intentional re-opening from settings.
          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('guide-skip')));
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsNothing);
          expect(tester.takeException(), null);
        });
      }
    }
  }
}
