import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/presentation/recovery/account_crypto_wizard.dart';
import 'package:kanban/organizer/state/account_summary_refresh_provider.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import '../../ui/sharing_ui_fixture.dart';

class _Workflow implements AccountCryptoV2Workflow {
  @override
  Future<Map<String, dynamic>> status() async => {'initialized': false};
  @override
  Future<String> localPhase() async => 'locked';
  @override
  Future<bool> hasSavedSetup() async => false;
  @override
  Future<bool> hasIncompleteScopeRecovery() async => false;
  @override
  Future<bool> canRebindLocalDevice() async => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Controller extends SharingUiController {
  _Controller()
    : super(
        initial: CollaborationState(
          session: sharingSession(),
          emailVerificationSupported: true,
        ),
      );
  bool verified = false, fail = false;
  int reads = 0;
  @override
  Future<AccountStatus> accountStatus() async {
    reads++;
    if (fail) throw const CollaborationException('offline');
    return AccountStatus(
      email: verified ? 'test@example.test' : null,
      pendingEmail: verified ? null : 'test@example.test',
      emailVerified: verified,
      resetAvailable: verified,
    );
  }
}

void main() {
  testWidgets(
    'one email read gates export then same wizard observes confirmation and failure',
    (tester) async {
      final controller = _Controller();
      final container = ProviderContainer(
        overrides: [
          ...await sharingUiInfrastructureOverrides(tester, controller),
          collaborationProvider.overrideWith(() => controller),
          accountCombinedRecoveryAvailableProvider.overrideWithValue(true),
        ],
      );
      addTearDown(container.dispose);
      await container.read(collaborationProvider.future);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            locale: const Locale('sl'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: AccountCryptoWizard(workflow: _Workflow()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(controller.reads, 1);
      expect(find.byKey(const ValueKey('account_crypto_save')), findsNothing);
      final session = sharingSession();
      controller.verified = true;
      refreshAccountSummaries(
        container,
        partition: session.partition,
        deviceId: session.deviceId,
      );
      await tester.pumpAndSettle();
      expect(controller.reads, 2);
      expect(find.byKey(const ValueKey('account_crypto_save')), findsOneWidget);
      controller.fail = true;
      refreshAccountSummaries(
        container,
        partition: session.partition,
        deviceId: session.deviceId,
      );
      await tester.pumpAndSettle();
      expect(controller.reads, 3);
      expect(find.byKey(const ValueKey('account_crypto_save')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
