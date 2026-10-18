import 'account_protection_completion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/e2ee/account_crypto_v2_workflow.dart';
import '../../data/e2ee/account_protection_ready.dart';
import '../../domain/collaboration_models.dart' show CollaborationException;
import '../../data/e2ee/crypto_migration_coordinator.dart';
import '../../state/account_crypto_provider.dart';
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

/// Runs only after the installation vault is open and the saved session has
/// loaded. Missing server support leaves connected writes held by the domain
/// guard, while the local application remains accessible.
final accountCryptoStartupActionProvider =
    FutureProvider<AccountCryptoStartupAction?>((ref) async {
      final workflow = await ref.watch(accountCryptoPreviewProvider.future);
      if (workflow is! AccountCryptoV2Workflow) return null;
      final session = ref.watch(collaborationProvider).valueOrNull?.session;
      if (session == null ||
          session.partition != workflow.store.partition ||
          session.deviceId != workflow.deviceId)
        return null;
      var phase = await workflow.localPhase();
      final incompleteScopes = await workflow.hasIncompleteScopeRecovery();
      if (phase == 'ready' && !incompleteScopes) {
        try {
          final completion = await AccountProtectionReady(
            workflow,
          ).cachedCompletion();
          if (completion != null) {
            try {
              if (await AccountProtectionReady(
                workflow,
              ).matchesCurrentCatalog(completion))
                return null;
            } on CollaborationException catch (error) {
              if (['network', 'rate_limited'].contains(error.code)) return null;
              rethrow;
            }
          }
        } catch (_) {
          phase = await workflow.localPhase();
        }
      }
      return AccountCryptoStartupAction(
        identity: '${session.partition}:${session.deviceId}',
        builder: (context) {
          if (phase != 'ready' || incompleteScopes)
            return AccountCryptoWizard(workflow: workflow);
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
