import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/collaboration_provider.dart';
import '../shared/sharing_session_boundary.dart';

class FinanceAccessGuard {
  FinanceAccessGuard(
    BuildContext context,
    WidgetRef ref,
    this.scopeId, {
    this.write = false,
  }) : session = SharingSessionGuard(context, ref),
       _container = ProviderScope.containerOf(context, listen: false),
       _revision = ref
           .read(collaborationProvider)
           .valueOrNull
           ?.financePolicyForScope(scopeId)
           .revision;
  final SharingSessionGuard session;
  final ProviderContainer _container;
  final String scopeId;
  final bool write;
  final int? _revision;
  bool allows(CollaborationState state) {
    final policy = state.financePolicyForScope(scopeId);
    return state.localAccessAllowed &&
        state.scopes.any(
          (scope) =>
              scope.id == scopeId &&
              !scope.revoked &&
              (!write || !scope.blocked && !scope.archived),
        ) &&
        state.financeSnapshotComplete[scopeId] == true &&
        (!write || !state.deletionPending) &&
        policy.revision == _revision &&
        (write ? policy.canWrite : policy.canRead);
  }

  bool get isCurrent {
    if (!session.isCurrent) return false;
    final state = _container.read(collaborationProvider).valueOrNull;
    return state != null && allows(state);
  }

  CollaborationController get controller {
    if (!isCurrent) throw const CollaborationException('finance_forbidden');
    return session.controller;
  }

  Widget wrap(Widget child) =>
      SharingSessionBoundary(guard: session, visibleWhen: allows, child: child);
}
