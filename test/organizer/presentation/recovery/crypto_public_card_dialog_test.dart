import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/presentation/recovery/crypto_public_card_dialog.dart';

enum _Dismiss { confirm, cancel, barrier, back }

const _publicCard =
    '{"accountId":"11111111-1111-4111-8111-111111111111",'
    '"generation":2,"headHash":"$_digest",'
    '"purpose":"identityVerification",'
    '"safetyCode":"synthetic public comparison code",'
    '"serverId":"22222222-2222-4222-8222-222222222222","version":2}';
const _digest =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final dismissal in _Dismiss.values) {
      testWidgets(
        'public card dialog closes with keyboard: ${platform.name} ${dismissal.name}',
        (tester) async {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetViewInsets);

          var completed = false;
          String? result;
          final explanation =
              platform == TargetPlatform.android &&
                  dismissal == _Dismiss.confirm
              ? 'The inviter public card must come from the known direct channel.'
              : null;
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(platform: platform),
              locale: const Locale('sl'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () async {
                      result = await showCryptoPublicCardDialog(
                        context,
                        explanation: explanation,
                      );
                      completed = true;
                    },
                    child: const Text('open public comparison'),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('open public comparison'));
          await tester.pumpAndSettle();
          final field = find.byType(TextField);
          expect(field, findsOneWidget);
          if (explanation != null) {
            expect(find.text(explanation), findsOneWidget);
          }
          final input = tester.widget<TextField>(field);
          expect(input.autocorrect, isFalse);
          expect(input.enableSuggestions, isFalse);
          expect(input.smartQuotesType, SmartQuotesType.disabled);
          expect(input.smartDashesType, SmartDashesType.disabled);
          expect(input.textCapitalization, TextCapitalization.none);
          await tester.showKeyboard(field);
          await tester.enterText(field, _publicCard);
          tester.view.viewInsets = const FakeViewPadding(bottom: 280);
          await tester.pump(const Duration(milliseconds: 32));
          expect(tester.testTextInput.isVisible, isTrue);
          final localizations = AppLocalizations.of(tester.element(field))!;

          // Retain the first framework stack rather than obscuring it with later
          // dependent/unmount assertions from the same closing transition.
          final errors = <FlutterErrorDetails>[];
          final previousErrorHandler = FlutterError.onError;
          FlutterError.onError = errors.add;
          try {
            switch (dismissal) {
              case _Dismiss.confirm:
                await tester.tap(
                  find.widgetWithText(
                    FilledButton,
                    localizations.cryptoCompareContact,
                  ),
                );
              case _Dismiss.cancel:
                await tester.tap(find.text(localizations.cancel));
              case _Dismiss.barrier:
                await tester.tapAt(const Offset(4, 4));
              case _Dismiss.back:
                await tester.binding.handlePopRoute();
            }
            await tester.pump();
            // A real IME closes while the popped route is still animating out.
            tester.view.viewInsets = const FakeViewPadding();
            for (final milliseconds in [16, 32, 64, 200]) {
              await tester.pump(Duration(milliseconds: milliseconds));
            }
          } finally {
            FlutterError.onError = previousErrorHandler;
          }
          if (errors.isNotEmpty) {
            Error.throwWithStackTrace(
              errors.first.exception,
              errors.first.stack ?? StackTrace.empty,
            );
          }
          expect(tester.takeException(), isNull);
          expect(completed, isTrue);
          expect(result, dismissal == _Dismiss.confirm ? _publicCard : isNull);
          expect(find.byType(AlertDialog), findsNothing);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
