import 'account_protection_completion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/e2ee/account_crypto_v2_workflow.dart';
import '../../data/e2ee/account_protection_ready.dart';
import '../../data/e2ee/crypto_migration_coordinator.dart';
import '../../state/account_crypto_provider.dart';
import '../../state/account_summary_refresh_provider.dart';
import '../../state/collaboration_provider.dart';
import 'account_crypto_wizard.dart';
import 'crypto_migration_wizard.dart';

class AccountCryptoStartupAction {
  const AccountCryptoStartupAction({
    required this.identity,
    required this.builder,
  });
  final String identity;
  final WidgetBuilder builder;
}

final accountCryptoStartupIdentityProvider = Provider<String?>((ref) {
  final session = ref.watch(collaborationProvider).valueOrNull?.session;
  return session == null ? null : '${session.partition}:${session.deviceId}';
});

bool matchesStartupAcknowledgment(
  Map ack, {
  required String phase,
  required String deviceId,
  required String identityEpochId,
  required String headHash,
}) =>
    phase == 'ready' &&
    ack['version'] == 2 &&
    ack['deviceId'] == deviceId &&
    ack['identityEpochId'] == identityEpochId &&
    ack['headHash'] == headHash &&
    ack['components'] is List &&
    (ack['components'] as List).isNotEmpty;

/// Shared by the required startup route and the nonblocking review status.
/// Ordinary sync/projection emissions do not rerun account/catalog reads.
final accountProtectionStartupServiceProvider =
    Provider<AccountProtectionReady Function(AccountCryptoV2Workflow)>(
      (ref) => AccountProtectionReady.new,
    );

final accountProtectionStartupAssessmentProvider =
    FutureProvider<AccountProtectionStartupAssessment?>((ref) async {
      var active = true;
      AccountProtectionReady? service;
      ref.onDispose(() {
        active = false;
        service?.close();
      });
      final identity = ref.watch(accountCryptoStartupIdentityProvider);
      final session = ref.read(collaborationProvider).valueOrNull?.session;
      if (session != null) {
        // Successful explicit completion refreshes the shared assessment once.
        // Sync emissions and failed/cancelled reviews do not advance this event.
        ref.watch(
          accountSummaryRefreshProvider((session.partition, session.deviceId)),
        );
      }
      final workflow = await ref.watch(accountCryptoPreviewProvider.future);
      if (!active || workflow is! AccountCryptoV2Workflow) return null;
      bool current() {
        if (!active) return false;
        final session = ref.read(collaborationProvider).valueOrNull?.session;
        return session != null &&
            identity == '${session.partition}:${session.deviceId}' &&
            session.partition == workflow.store.partition &&
            session.deviceId == workflow.deviceId;
      }

      if (!current()) return null;
      service = ref.read(accountProtectionStartupServiceProvider)(workflow);
      try {
        final assessment = await service.assessStartupReview(
          isCurrent: current,
        );
        return current() ? assessment : null;
      } catch (_) {
        if (!current()) return null;
        rethrow;
      }
    });

/// Only actual initial setup/recovery or an unestablished completion opens a
/// required route. Catalog drift and unavailable review evidence remain visible
/// in the nonblocking status; all connected-write guards stay independent.
final accountCryptoStartupActionProvider =
    FutureProvider<AccountCryptoStartupAction?>((ref) async {
      var active = true;
      ref.onDispose(() => active = false);
      final identity = ref.watch(accountCryptoStartupIdentityProvider);
      final assessment = await ref.watch(
        accountProtectionStartupAssessmentProvider.future,
      );
      if (!active ||
          assessment == null ||
          !const {
            AccountProtectionStartupStatus.setupRequired,
            AccountProtectionStartupStatus.recoveryRequired,
            AccountProtectionStartupStatus.reviewRequired,
          }.contains(assessment.status)) {
        return null;
      }
      final workflow = await ref.watch(accountCryptoPreviewProvider.future);
      if (!active || workflow is! AccountCryptoV2Workflow) return null;
      final session = ref.read(collaborationProvider).valueOrNull?.session;
      if (session == null ||
          identity != '${session.partition}:${session.deviceId}' ||
          session.partition != workflow.store.partition ||
          session.deviceId != workflow.deviceId) {
        return null;
      }
      return AccountCryptoStartupAction(
        identity: '${session.partition}:${session.deviceId}',
        builder: (context) {
          if (assessment.status !=
              AccountProtectionStartupStatus.reviewRequired) {
            return AccountCryptoWizard(workflow: workflow);
          }
          final labels = <String, String>{
            for (final scope
                in ref.read(collaborationProvider).valueOrNull?.scopes ?? [])
              scope.id: scope.name,
          };
          return CryptoMigrationWizard(
            controller: AccountMigrationController(
              CryptoMigrationCoordinator(account: workflow),
            ),
            cachedLabels: labels,
            onFinished: () => finishAccountProtection(context, workflow),
          );
        },
      );
    });

class AccountCryptoStartupCoordinator extends ConsumerStatefulWidget {
  const AccountCryptoStartupCoordinator({required this.child, super.key});
  final Widget child;
  @override
  ConsumerState<AccountCryptoStartupCoordinator> createState() =>
      _AccountCryptoStartupCoordinatorState();
}

class _AccountCryptoStartupCoordinatorState
    extends ConsumerState<AccountCryptoStartupCoordinator> {
  final _shown = <String>{};
  Route<void>? _route;
  String? _routeIdentity, _observedIdentity;
  int _generation = 0;
  void _schedule(AccountCryptoStartupAction action) {
    if (_shown.contains(action.identity)) return;
    final generation = _generation;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted ||
          generation != _generation ||
          ref.read(accountCryptoStartupIdentityProvider) != action.identity)
        return;
      final current = ref.read(accountCryptoStartupActionProvider).valueOrNull;
      if (current?.identity != action.identity || !_shown.add(action.identity))
        return;
      final navigator = Navigator.of(context);
      if (_route?.isActive == true) navigator.removeRoute(_route!);
      final route = MaterialPageRoute<void>(builder: action.builder);
      _route = route;
      _routeIdentity = action.identity;
      await navigator.push(route);
      if (_route == route) {
        _route = null;
        _routeIdentity = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final identity = ref.watch(accountCryptoStartupIdentityProvider);
    if (identity != _observedIdentity) {
      final previous = _observedIdentity;
      _observedIdentity = identity;
      _generation++;
      if (previous != null) _shown.remove(previous);
      if (_routeIdentity != null && _routeIdentity != identity) {
        final old = _route;
        _route = null;
        _routeIdentity = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && old?.isActive == true)
            Navigator.of(context).removeRoute(old!);
        });
      }
    }
    final action = ref.watch(accountCryptoStartupActionProvider).valueOrNull;
    if (action != null && action.identity == identity) _schedule(action);
    return widget.child;
  }
}
