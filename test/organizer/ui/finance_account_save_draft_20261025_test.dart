import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/presentation/finance/shared_finance_actions.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'sharing_ui_fixture.dart';

class _Controller extends SharingUiController {
  _Controller()
    : super(
        initial: CollaborationState(
          session: sharingSession(),
          scopes: [sharingScope()],
          financeSupported: true,
          financePolicies: {
            sharingScopeId: const SharedFinancePolicy(
              enabled: true,
              grant: SharedFinanceGrant.write,
              revision: 1,
            ),
          },
          financeSnapshotComplete: {sharingScopeId: true},
        ),
      );
  int creates = 0;
  String? name, scopeId;
  @override
  Future<String> createFinanceAccount({
    required String scopeId,
    required String name,
    required String currency,
    int openingBalanceMinor = 0,
    String? ownerAccountId,
  }) async {
    creates++;
    this.name = name;
    this.scopeId = scopeId;
    throw const CryptoAuthorityPending('crypto_stale_identity');
  }
}

void main() {
  testWidgets(
    'account save failure retains typed draft and does not duplicate attempt',
    (tester) async {
      final controller = _Controller();
      final infrastructure = await sharingUiInfrastructureOverrides(
        tester,
        controller,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...infrastructure,
            collaborationProvider.overrideWith(() => controller),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  final state = ref.watch(collaborationProvider).valueOrNull;
                  return TextButton(
                    onPressed: state == null
                        ? null
                        : () => SharedFinanceActions(
                            context,
                            ref,
                            state.scopes.single,
                            state,
                          ).account(),
                    child: const Text('Open account'),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open account'));
      await tester.pumpAndSettle();
      final title = find.widgetWithText(TextFormField, 'Title');
      await tester.enterText(title, 'Synthetic retained bank');
      await tester.tap(find.byTooltip('Save'));
      await tester.pumpAndSettle();
      expect(controller.creates, 1);
      expect(controller.name, 'Synthetic retained bank');
      expect(controller.scopeId, sharingScopeId);
      expect(find.text('Synthetic retained bank'), findsOneWidget);
      expect(find.text('Add account'), findsOneWidget);
      final l = AppLocalizations.of(tester.element(find.text('Open account')))!;
      expect(find.text(l.sharingAccountChanged), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
