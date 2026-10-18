import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_domain_router.dart';

/// Explicit opt-in for existing synthetic legacy protocol regressions.
/// Production has no default plaintext permit or capability-based fallback.
/// This does not bypass active-scope crypto floors or restore fences.
class SyntheticContentRouteGuard implements ContentRouteGuard {
  const SyntheticContentRouteGuard();
  @override
  Future<void> authorizeConnectedEntry({
    required DeviceSession session,
  }) async {}
  @override
  Future<void> authorizeLegacy({
    required DeviceSession session,
    required String operation,
    required Map<String, Object?> params,
  }) async {}
}
