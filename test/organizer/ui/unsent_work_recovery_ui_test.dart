import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/data/unsent_work_recovery.dart';
import 'package:kanban/organizer/presentation/shared/unsent_work_recovery_view.dart';

void main() {
  testWidgets(
    'file-only recovery displays copyable own expense at 320/2x and closes without importing',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final recovery = await UnsentWorkRecovery.decode(
        jsonEncode({
          'format': 'vsakdan-unsent-work',
          'schemaVersion': 1,
          'account': {
            'serverUrl': 'https://synthetic.invalid',
            'serverId': 'server',
            'accountId': 'account',
          },
          'operations': [],
          'financeOperations': [
            {
              'scopeId': 'revoked',
              'operation': {
                'type': 'financeEntry',
                'payload': {'title': 'Own unsent expense', 'amountMinor': 100},
              },
            },
          ],
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => UnsentWorkRecoveryDialog(recovery: recovery),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Own unsent expense'),
        160,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Own unsent expense'));
      await tester.pumpAndSettle();
      expect(find.byType(SelectableText), findsOneWidget);
      expect(find.textContaining('does not restore access'), findsOneWidget);
      expect(find.text('Save'), findsNothing);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(UnsentWorkRecoveryDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
