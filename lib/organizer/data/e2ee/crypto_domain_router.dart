import '../collaboration_database.dart';
import '../device_session_store.dart';
import '../../domain/collaboration_models.dart';

/// A production implementation requires independently verified crypto2
/// reconciliation and an explicit pre-migration drain authorization. Mere
/// capability absence, unsigned server metadata or missing local rows cannot
/// authorize plaintext content. Synthetic implementations live only in tests.
abstract interface class ContentRouteGuard {
  /// Explicit fixture policy only. Production supplies no permissive guard;
  /// connected edits require current account verification evidence instead.
  Future<void> authorizeConnectedEntry({required DeviceSession session});
  Future<void> authorizeLegacy({
    required DeviceSession session,
    required String operation,
    required Map<String, Object?> params,
  });
}

/// The active-domain adapter must finish all identity, domain and aggregate
/// checks before returning the canonical response expected by existing actions.
/// No handler may forward the original legacy body to the transport.
abstract interface class CryptoDomainRouter {
  Future<Map<String, dynamic>> dispatch({
    required DeviceSession session,
    required String operation,
    required Map<String, Object?> params,
    required Set<String> protectedScopeIds,
  });
}

/// Client-owned background permission queries do not also refresh aggregate
/// finance snapshots. This is not a server response flag or an authority cache.
abstract interface class CryptoFinancePolicyReadContext {
  Future<CryptoFinancePolicyReadResult<T>> withFinancePolicyOnly<T>(
    Future<T> Function() read,
  );
}

class CryptoFinancePolicyReadResult<T> {
  const CryptoFinancePolicyReadResult(this.value, {required this.policyOnly});
  final T value;

  /// Set by the local adapter after actual crypto policy dispatch, never wire.
  final bool policyOnly;
}

/// Repairs only the absent canonical root of an authenticated native project.
/// Called before an explicit local edit, outside the ordinary SQL transaction.
abstract interface class CryptoNativeProjectRootRepair {
  Future<Map<String, dynamic>?> ensureNativeProjectRoot({
    required DeviceSession session,
    required String scopeId,
    required String? parentScopeId,
  });
}

/// Distinguishes a verified native origin from a legacy transport transition.
/// Null means there is no verified encrypted boundary yet; callers must not
/// persist a checkpoint that would suppress a later migration rebase.
enum CryptoProjectionCursorOrigin { nativeOrigin, legacyMigration }

abstract interface class CryptoProjectionCursorTransition {
  Future<CryptoProjectionCursorOrigin?> verifyProjectionCursorOrigin({
    required DeviceSession session,
    required String scopeId,
  });
}

/// The persistent floor is consulted on the actual authenticated request path,
/// independently of server capabilities. No router means a retained local queue
/// and explicit refusal, never downgrade to a plaintext content endpoint.
Future<Map<String, dynamic>?> routeProtectedCryptoDomain({
  required CollaborationDatabase database,
  required DeviceSession session,
  required String operation,
  required Map<String, Object?> params,
  required CryptoDomainRouter? router,
  ContentRouteGuard? contentGuard,
  required void Function() checkCurrent,
}) async {
  if (operation.startsWith('crypto2.') ||
      operation.startsWith('auth.') ||
      operation == 'account.status' ||
      operation.startsWith('account.email.') ||
      operation.startsWith('moderation.policy') ||
      operation == 'moderation.acceptPolicy' ||
      operation.startsWith('push.')) {
    return null;
  }
  final fences = await database.rows(
    "SELECT partition FROM crypto_restore_fences WHERE partition=? AND state<>'verified'",
    [session.profile.partition],
  );
  checkCurrent();
  if (fences.isNotEmpty) {
    throw const CollaborationException('crypto_reconciliation_required');
  }
  final rows = await database.rows(
    "SELECT DISTINCT scope_id FROM crypto_scope_state WHERE partition=? AND (floor>0 OR state IN ('active','committed','retired','fenced','verified'))",
    [session.profile.partition],
  );
  checkCurrent();
  if (rows.isEmpty) {
    if (contentGuard == null && router != null) {
      final result = await router.dispatch(
        session: session,
        operation: operation,
        params: params,
        protectedScopeIds: const {},
      );
      checkCurrent();
      return result;
    }
    if (contentGuard == null) {
      throw const CollaborationException('crypto_reconciliation_required');
    }
    await contentGuard.authorizeLegacy(
      session: session,
      operation: operation,
      params: params,
    );
    checkCurrent();
    return null;
  }
  final protected = rows.map((r) => r['scope_id'] as String).toSet();
  final scope = params['scopeId'];
  if (scope is String && !protected.contains(scope)) {
    if (contentGuard == null && router != null) {
      final result = await router.dispatch(
        session: session,
        operation: operation,
        params: params,
        protectedScopeIds: protected,
      );
      checkCurrent();
      return result;
    }
    if (contentGuard == null) {
      throw const CollaborationException('crypto_reconciliation_required');
    }
    await contentGuard.authorizeLegacy(
      session: session,
      operation: operation,
      params: params,
    );
    checkCurrent();
    return null;
  }
  if (router == null) {
    throw const CollaborationException('crypto_transport_required');
  }
  final result = await router.dispatch(
    session: session,
    operation: operation,
    params: params,
    protectedScopeIds: protected,
  );
  checkCurrent();
  return result;
}
