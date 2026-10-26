import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/presentation/recovery/account_devices_page.dart';

class _Access implements SessionCryptoAccess {
  _Access(this.reject);
  final bool reject;
  final calls = <(String, String, String)>[];
  @override
  Future<void> verifyContactCard(
    String scope,
    String account,
    String card,
  ) async {
    calls.add((scope, account, card));
    if (reject) throw const FormatException('invalid public card');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected identity action: $invocation');
}

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final action in ['verify', 'reject', 'back']) {
      testWidgets(
        'active contact page ${platform.name}: $action with keyboard',
        (tester) async {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetViewInsets);
          final access = _Access(action == 'reject');
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(platform: platform),
              locale: const Locale('sl'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ContactIdentityVerificationPage(
                          access: access,
                          scopeId: 'exact-scope',
                          accountId: 'exact-account',
                          displayName: 'Known contact',
                        ),
                      ),
                    ),
                    child: const Text('Open contact'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Open contact'));
          await tester.pumpAndSettle();
          final field = find.byType(TextField);
          await tester.enterText(field, '  synthetic public card  ');
          await tester.showKeyboard(field);
          tester.view.viewInsets = const FakeViewPadding(bottom: 280);
          await tester.pump();
          final l = AppLocalizations.of(tester.element(field))!;
          if (action == 'back') {
            await tester.binding.handlePopRoute();
            tester.view.viewInsets = const FakeViewPadding();
            await tester.pumpAndSettle();
            expect(find.text('Open contact'), findsOneWidget);
            expect(access.calls, isEmpty);
          } else {
            final button = find.widgetWithText(
              FilledButton,
              l.cryptoCompareContact,
            );
            await tester.ensureVisible(button);
            await tester.tap(button);
            await tester.pumpAndSettle();
            expect(access.calls, [
              ('exact-scope', 'exact-account', 'synthetic public card'),
            ]);
            expect(
              find.text(
                action == 'reject'
                    ? l.accountRecoveryFailed
                    : l.cryptoContactVerified,
              ),
              findsOneWidget,
            );
            expect(
              find.byType(TextField),
              action == 'reject' ? findsOneWidget : findsNothing,
            );
          }
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
