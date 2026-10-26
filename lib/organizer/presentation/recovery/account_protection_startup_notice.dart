import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../data/e2ee/account_crypto_v2_workflow.dart';
import '../../data/e2ee/account_protection_ready.dart';
import '../../data/e2ee/crypto_migration_coordinator.dart';
import '../../state/account_crypto_provider.dart';
import '../../state/account_summary_refresh_provider.dart';
import '../../state/collaboration_provider.dart';
import 'account_crypto_startup.dart';
import 'account_protection_completion.dart';
import 'crypto_migration_wizard.dart';

/// Builds the existing explicit review flow; reading this provider performs no
/// migration, completion, signature or rotation.
final accountProtectionReviewActionProvider =
    Provider<AccountCryptoStartupAction?>((ref) {
      final identity = ref.watch(accountCryptoStartupIdentityProvider);
      final preview = ref.watch(accountCryptoPreviewProvider);
      final workflow = preview.valueOrNull;
      if (preview.isLoading ||
          preview.hasError ||
          workflow is! AccountCryptoV2Workflow ||
          identity != '${workflow.store.partition}:${workflow.deviceId}') {
        return null;
      }
      final labels = <String, String>{
        for (final scope
            in ref.read(collaborationProvider).valueOrNull?.scopes ?? [])
          scope.id: scope.name,
      };
      return AccountCryptoStartupAction(
        identity: identity!,
        builder: (context) => CryptoMigrationWizard(
          controller: AccountMigrationController(
            CryptoMigrationCoordinator(account: workflow),
          ),
          cachedLabels: labels,
          onFinished: () => finishAccountProtection(context, workflow),
        ),
      );
    });

/// A catalog change offers a review without interrupting the current workspace.
/// The assessment remains shared with startup, and is refreshed only explicitly.
class AccountProtectionStartupNotice extends ConsumerStatefulWidget {
  const AccountProtectionStartupNotice({super.key});
  @override
  ConsumerState<AccountProtectionStartupNotice> createState() =>
      _AccountProtectionStartupNoticeState();
}

class _AccountProtectionStartupNoticeState
    extends ConsumerState<AccountProtectionStartupNotice> {
  bool _retrying = false, _reviewing = false;
  Route<void>? _reviewRoute;
  NavigatorState? _reviewNavigator;
  String? _reviewIdentity, _retryIdentity;

  void _removeOwnedReview(Route<void>? route, NavigatorState? navigator) {
    if (route == null || navigator == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Exact route ownership matters when another route has since been pushed.
      // Removing this review must never pop the navigator's current unrelated UI.
      if (navigator.mounted && route.isActive && route.navigator == navigator) {
        navigator.removeRoute(route);
      }
    });
  }

  @override
  void dispose() {
    final route = _reviewRoute, navigator = _reviewNavigator;
    _reviewRoute = null;
    _reviewNavigator = null;
    _reviewIdentity = null;
    _removeOwnedReview(route, navigator);
    super.dispose();
  }

  Future<void> _retry(String identity) async {
    if ((_retrying && _retryIdentity == identity) ||
        ref.read(accountCryptoStartupIdentityProvider) != identity) {
      return;
    }
    setState(() {
      _retrying = true;
      _retryIdentity = identity;
    });
    try {
      final request = ref.refresh(
        accountProtectionStartupAssessmentProvider.future,
      );
      await request;
    } catch (_) {
      // The shared assessment exposes the unavailable state without an extra
      // request or a second modal error.
    } finally {
      if (mounted && _retryIdentity == identity) {
        setState(() => _retrying = false);
      }
    }
  }

  Future<void> _review(AccountCryptoStartupAction action) async {
    final assessment = ref.read(accountProtectionStartupAssessmentProvider);
    if (_reviewing ||
        assessment.isLoading ||
        assessment.hasError ||
        ref.read(accountCryptoStartupIdentityProvider) != action.identity ||
        assessment.valueOrNull?.status !=
            AccountProtectionStartupStatus.catalogChanged) {
      return;
    }
    final session = ref.read(collaborationProvider).valueOrNull?.session;
    final completionIdentity = session == null
        ? null
        : (session.partition, session.deviceId);
    final completionRevision = completionIdentity == null
        ? null
        : ref.read(accountSummaryRefreshProvider(completionIdentity));
    setState(() => _reviewing = true);
    final navigator = Navigator.of(context);
    final child = action.builder(context);
    final route = MaterialPageRoute<void>(builder: (_) => child);
    _reviewIdentity = action.identity;
    _reviewRoute = route;
    _reviewNavigator = navigator;
    try {
      await navigator.push(route);
    } finally {
      _reviewRoute = null;
      _reviewNavigator = null;
      _reviewIdentity = null;
      if (mounted) {
        setState(() => _reviewing = false);
        if (ref.read(accountCryptoStartupIdentityProvider) == action.identity) {
          // One read after explicit review, including when the user simply
          // returns. Closing a review does not claim completion.
          // Completion already refreshes the shared assessment. A simple
          // return still needs one read, without a duplicate post-Finish read.
          if (completionIdentity == null ||
              ref.read(accountSummaryRefreshProvider(completionIdentity)) ==
                  completionRevision) {
            ref.invalidate(accountProtectionStartupAssessmentProvider);
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final identity = ref.watch(accountCryptoStartupIdentityProvider);
    if (_reviewIdentity != null && _reviewIdentity != identity) {
      final route = _reviewRoute, navigator = _reviewNavigator;
      _reviewRoute = null;
      _reviewNavigator = null;
      _reviewIdentity = null;
      _removeOwnedReview(route, navigator);
    }
    if (identity == null) return const SizedBox.shrink();
    final value = ref.watch(accountProtectionStartupAssessmentProvider);
    final assessment = value.valueOrNull;
    final checking =
        value.isLoading || (_retrying && _retryIdentity == identity);
    final changed =
        !checking &&
        !value.hasError &&
        assessment?.status == AccountProtectionStartupStatus.catalogChanged;
    final pending =
        value.hasError ||
        assessment?.status == AccountProtectionStartupStatus.pending;
    if (!checking && !changed && !pending) return const SizedBox.shrink();
    final l = context.l10n;
    final action = changed
        ? ref.watch(accountProtectionReviewActionProvider)
        : null;
    return Padding(
      key: const ValueKey('account-protection-startup-notice'),
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                checking
                    ? l.cryptoProtectionChecking
                    : changed
                    ? l.cryptoProtectionCatalogChanged
                    : l.cryptoProtectionUnavailable,
              ),
              if (!checking)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    key: ValueKey(
                      changed
                          ? 'account-protection-review'
                          : 'account-protection-retry',
                    ),
                    onPressed: changed
                        ? _reviewing || action?.identity != identity
                              ? null
                              : () => _review(action!)
                        : () => _retry(identity),
                    child: Text(
                      changed
                          ? l.cryptoProtectionReview
                          : l.cryptoProtectionRetry,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
