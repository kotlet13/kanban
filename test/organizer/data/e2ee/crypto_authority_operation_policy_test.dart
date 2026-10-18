import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/e2ee/crypto_authority_operation_policy.dart';

void main() {
  test(
    'read reuse requires online evidence, monotonic age and every unchanged authority boundary',
    () {
      bool check({
        Duration age = const Duration(seconds: 1),
        bool identity = true,
        bool lifecycle = true,
        bool pins = true,
        bool online = true,
        bool active = true,
      }) => canReuseCryptoReadAuthority(
        age: age,
        identityCurrent: identity,
        lifecycleMatches: lifecycle,
        pinsMatch: pins,
        onlineVerified: online,
        active: active,
      );
      expect(check(), true);
      expect(check(online: false), false);
      expect(check(age: const Duration(seconds: 5)), false);
      expect(check(age: const Duration(seconds: -1)), false);
      expect(check(identity: false), false);
      expect(check(lifecycle: false), false);
      expect(check(pins: false), false);
      expect(check(active: false), false);
    },
  );
}
