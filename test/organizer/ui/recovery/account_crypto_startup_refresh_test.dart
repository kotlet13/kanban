import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/crypto_identity_store.dart';
import 'package:kanban/organizer/presentation/recovery/account_crypto_startup.dart';
import 'package:kanban/organizer/state/account_crypto_provider.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';

import '../sharing_ui_fixture.dart';

class _Store implements CryptoIdentityStore {
  _Store(this.partition);
  @override
  final String partition;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Workflow implements AccountCryptoV2Workflow {
  _Workflow(this.session) : store = _Store(session.partition);
  final AccountSession session;
  int phaseReads = 0;
  @override
  final CryptoIdentityStore store;
  @override
  String get deviceId => session.deviceId;
  @override
  Future<String> localPhase() async {
    phaseReads++;
    return 'missing';
  }

  @override
  Future<bool> hasIncompleteScopeRecovery() async => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'startup readiness runs once across ordinary sync state emissions',
    () async {
      final session = sharingSession();
      final controller = SharingUiController(
        initial: CollaborationState(session: session),
      );
      final workflow = _Workflow(session);
      final container = ProviderContainer(
        overrides: [
          collaborationProvider.overrideWith(() => controller),
          accountCryptoPreviewProvider.overrideWith((ref) async => workflow),
        ],
      );
      addTearDown(container.dispose);
      await container.read(collaborationProvider.future);
      final subscription = container.listen(
        accountCryptoStartupActionProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);
      expect(
        (await container.read(
          accountCryptoStartupActionProvider.future,
        ))?.identity,
        '${session.partition}:${session.deviceId}',
      );
      expect(workflow.phaseReads, 1);
      // Simulate the real controller's periodic refreshLocal and sync progress.
      for (var i = 0; i < 12; i++) {
        controller.replace(
          CollaborationState(session: session, pendingCount: i),
        );
        await container.read(accountCryptoStartupActionProvider.future);
      }
      expect(
        workflow.phaseReads,
        1,
        reason:
            'Unchanged startup must not repeat directory/catalog readiness checks',
      );
      container.invalidate(accountCryptoStartupActionProvider);
      await container.read(accountCryptoStartupActionProvider.future);
      expect(
        workflow.phaseReads,
        2,
        reason: 'Explicit readiness refresh remains available',
      );
    },
  );

  test(
    'account change rechecks startup and rejects the old workflow',
    () async {
      final first = sharingSession(), second = sharingSession(second: true);
      final controller = SharingUiController(
        initial: CollaborationState(session: first),
      );
      final workflow = _Workflow(first);
      final container = ProviderContainer(
        overrides: [
          collaborationProvider.overrideWith(() => controller),
          accountCryptoPreviewProvider.overrideWith((ref) async => workflow),
        ],
      );
      addTearDown(container.dispose);
      await container.read(collaborationProvider.future);
      container.listen(accountCryptoStartupActionProvider, (_, _) {});
      expect(
        await container.read(accountCryptoStartupActionProvider.future),
        isNotNull,
      );
      controller.replace(CollaborationState(session: second));
      expect(
        await container.read(accountCryptoStartupActionProvider.future),
        isNull,
      );
      expect(
        workflow.phaseReads,
        1,
        reason: 'Old workflow must not be inspected for the new account',
      );
      controller.replace(CollaborationState(session: first));
      expect(
        await container.read(accountCryptoStartupActionProvider.future),
        isNotNull,
      );
      expect(workflow.phaseReads, 2);
    },
  );
}
