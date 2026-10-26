import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_repository.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/account_protection_ready.dart';
import 'package:kanban/organizer/data/e2ee/crypto_identity_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:kanban/organizer/presentation/recovery/account_crypto_startup.dart';
import 'package:kanban/organizer/state/account_crypto_provider.dart';
import 'package:kanban/organizer/state/account_summary_refresh_provider.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import '../sharing_ui_fixture.dart';

class _Directory implements AccountDirectoryRepository {
  bool active = true;
  @override
  bool Function() get isCurrent =>
      () => active;
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'No transport, signing, migration or key action allowed',
  );
}

class _Store implements CryptoIdentityStore {
  _Store(this.partition);
  @override
  final String partition;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('No mutable store action allowed');
}

class _Workflow implements AccountCryptoV2Workflow {
  _Workflow(this.session) : store = _Store(session.partition);
  final AccountSession session;
  String phase = 'ready';
  bool incomplete = false;
  int phaseReads = 0;
  @override
  final directory = _Directory();
  @override
  final CryptoIdentityStore store;
  @override
  String get deviceId => session.deviceId;
  @override
  Future<String> localPhase() async {
    phaseReads++;
    return phase;
  }

  @override
  Future<bool> hasIncompleteScopeRecovery() async => incomplete;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('No account mutation');
}

// The signed completion/catalog verifiers are existing, independent boundaries.
// Control their outcomes while running the actual new decision algorithm.
class _Service extends AccountProtectionReady {
  _Service(this.workflow) : super(workflow);
  final _Workflow workflow;
  Map<String, dynamic>? completion = {'signed': 'existing-verifier-result'};
  bool matches = false, closed = false;
  int completionReads = 0, catalogReads = 0;
  Object? error;
  Completer<bool>? held;
  void Function()? afterCatalog;
  @override
  Future<Map<String, dynamic>?> cachedCompletion() async {
    completionReads++;
    return completion;
  }

  @override
  Future<bool> matchesCurrentCatalog(Map<String, dynamic> completion) async {
    catalogReads++;
    if (error != null) throw error!;
    final result = held == null ? matches : await held!.future;
    afterCatalog?.call();
    return result;
  }

  bool deviceMatches = true;
  @override
  Future<bool> completionMatchesCurrentDevice(
    Map<String, dynamic> completion,
  ) async => deviceMatches;
  @override
  void close() {
    closed = true;
    super.close();
  }

  @override
  Future<void> complete({
    Map<String, dynamic>? reviewedUnavailable,
    void Function(int)? onPause,
  }) => throw StateError('Startup must never complete/sign/rotate');
}

Future<ProviderContainer> _container(
  _Workflow workflow,
  List<_Service> services, {
  Future<AccountCryptoV2Workflow>? preview,
  SharingUiController? controller,
}) async {
  final shared =
      controller ??
      SharingUiController(
        initial: CollaborationState(session: workflow.session),
      );
  final container = ProviderContainer(
    overrides: [
      collaborationProvider.overrideWith(() => shared),
      accountCryptoPreviewProvider.overrideWith(
        (ref) async => preview == null ? workflow : await preview,
      ),
      accountProtectionStartupServiceProvider.overrideWithValue((_) {
        final s = services.isEmpty ? _Service(workflow) : services.last;
        return s;
      }),
    ],
  );
  await container.read(collaborationProvider.future);
  return container;
}

void main() {
  test('new completion event retires stale startup drift once', () async {
    final w = _Workflow(sharingSession());
    final before = _Service(w);
    final services = [before];
    final c = await _container(w, services);
    addTearDown(c.dispose);
    final subscription = c.listen(
      accountProtectionStartupAssessmentProvider,
      (_, _) {},
    );
    addTearDown(subscription.close);
    expect(
      (await c.read(accountProtectionStartupAssessmentProvider.future))!.status,
      AccountProtectionStartupStatus.catalogChanged,
    );
    final after = _Service(w)..matches = true;
    services.add(after);
    expect(
      refreshAccountSummaries(
        c,
        partition: w.store.partition,
        deviceId: w.deviceId,
      ),
      isTrue,
    );
    expect(
      (await c.read(accountProtectionStartupAssessmentProvider.future))!.status,
      AccountProtectionStartupStatus.current,
    );
    expect(before.closed, isTrue);
    expect(before.catalogReads, 1);
    expect(after.catalogReads, 1);
    await c.read(accountProtectionStartupAssessmentProvider.future);
    expect(after.catalogReads, 1);
    expect(await c.read(accountCryptoStartupActionProvider.future), isNull);
  });
  test(
    'new completion event cannot refresh a different startup identity',
    () async {
      final w = _Workflow(sharingSession());
      final s = _Service(w);
      final c = await _container(w, [s]);
      addTearDown(c.dispose);
      final subscription = c.listen(
        accountProtectionStartupAssessmentProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);
      expect(
        (await c.read(
          accountProtectionStartupAssessmentProvider.future,
        ))!.status,
        AccountProtectionStartupStatus.catalogChanged,
      );
      expect(
        refreshAccountSummaries(
          c,
          partition: 'other-account',
          deviceId: w.deviceId,
        ),
        isFalse,
      );
      expect(
        (await c.read(
          accountProtectionStartupAssessmentProvider.future,
        ))!.status,
        AccountProtectionStartupStatus.catalogChanged,
      );
      expect(s.catalogReads, 1);
      expect(s.closed, isFalse);
    },
  );
  test(
    'catalog drift keeps app route accessible and does not repeat reads on sync emissions',
    () async {
      final w = _Workflow(sharingSession()),
          s = _Service(_Workflow(sharingSession()));
      final service = _Service(w);
      final controller = SharingUiController(
        initial: CollaborationState(session: w.session),
      );
      final c = await _container(w, [service], controller: controller);
      addTearDown(c.dispose);
      final sub = c.listen(
        accountProtectionStartupAssessmentProvider,
        (_, _) {},
      );
      addTearDown(sub.close);
      expect(
        (await c.read(
          accountProtectionStartupAssessmentProvider.future,
        ))!.status,
        AccountProtectionStartupStatus.catalogChanged,
      );
      expect(await c.read(accountCryptoStartupActionProvider.future), isNull);
      for (var i = 0; i < 12; i++) {
        controller.replace(
          CollaborationState(session: w.session, pendingCount: i),
        );
        await c.read(accountProtectionStartupAssessmentProvider.future);
      }
      expect(service.catalogReads, 1);
      expect(service.completionReads, 1);
      expect(s.catalogReads, 0);
    },
  );
  test(
    'missing initial signed completion retains required review route',
    () async {
      final w = _Workflow(sharingSession());
      final s = _Service(w)..completion = null;
      final c = await _container(w, [s]);
      addTearDown(c.dispose);
      expect(
        (await c.read(
          accountProtectionStartupAssessmentProvider.future,
        ))!.status,
        AccountProtectionStartupStatus.reviewRequired,
      );
      expect(
        await c.read(accountCryptoStartupActionProvider.future),
        isNotNull,
      );
      expect(s.catalogReads, 0);
    },
  );
  test(
    'initial setup pending and incomplete recovery skip catalog work',
    () async {
      for (final value in [
        ('missing', false, AccountProtectionStartupStatus.setupRequired),
        ('pending', false, AccountProtectionStartupStatus.setupRequired),
        (
          'recoveryRequired',
          false,
          AccountProtectionStartupStatus.recoveryRequired,
        ),
        ('ready', true, AccountProtectionStartupStatus.recoveryRequired),
      ]) {
        final w = _Workflow(sharingSession())
          ..phase = value.$1
          ..incomplete = value.$2;
        final s = _Service(w);
        expect(
          (await s.assessStartupReview(isCurrent: () => true)).status,
          value.$3,
        );
        expect(s.catalogReads, 0);
        expect(s.completionReads, 0);
      }
    },
  );
  test(
    'locked local setup ignores copied completion acknowledgement',
    () async {
      final w = _Workflow(sharingSession())..phase = 'locked';
      final s = _Service(w)..matches = true;
      expect(
        (await s.assessStartupReview(isCurrent: () => true)).status,
        AccountProtectionStartupStatus.setupRequired,
      );
      expect(s.completionReads, 0);
      expect(s.catalogReads, 0);
    },
  );
  test('exact current catalog is the only current review result', () async {
    final w = _Workflow(sharingSession());
    final s = _Service(w)..matches = true;
    final result = await s.assessStartupReview(isCurrent: () => true);
    expect(result.status, AccountProtectionStartupStatus.current);
    expect(result.reason, AccountProtectionStartupReason.none);
    expect(s.catalogReads, 1);
  });
  test(
    'network rate limit and unavailable proof remain visible pending',
    () async {
      for (final value in [
        (
          const CollaborationException('network'),
          AccountProtectionStartupReason.network,
        ),
        (
          const CollaborationException('rate_limited'),
          AccountProtectionStartupReason.rateLimited,
        ),
        (
          const CryptoAuthorityPending('directory_proof_pending'),
          AccountProtectionStartupReason.proofUnavailable,
        ),
      ]) {
        final w = _Workflow(sharingSession());
        final s = _Service(w)..error = value.$1;
        final result = await s.assessStartupReview(isCurrent: () => true);
        expect(result.status, AccountProtectionStartupStatus.pending);
        expect(result.reason, value.$2);
      }
    },
  );
  test(
    'fresh verified device revocation remains required account recovery',
    () async {
      final w = _Workflow(sharingSession());
      final s = _Service(w)
        ..error = const CryptoDirectoryException('directory_device_revoked');
      final result = await s.assessStartupReview(isCurrent: () => true);
      expect(result.status, AccountProtectionStartupStatus.recoveryRequired);
      expect(result.reason, AccountProtectionStartupReason.accountRecovery);
    },
  );
  test(
    'recovery appearing during catalog read wins over a matching review',
    () async {
      final w = _Workflow(sharingSession());
      final s = _Service(w)
        ..matches = true
        ..afterCatalog = () => w.incomplete = true;
      final result = await s.assessStartupReview(isCurrent: () => true);
      expect(result.status, AccountProtectionStartupStatus.recoveryRequired);
      expect(result.reason, AccountProtectionStartupReason.scopeRecovery);
    },
  );
  test('closed or stale assessment never publishes catalog success', () async {
    for (final dispose in [false, true]) {
      final w = _Workflow(sharingSession());
      final s = _Service(w)..held = Completer<bool>();
      var current = true;
      final future = s.assessStartupReview(isCurrent: () => current);
      await Future<void>.delayed(Duration.zero);
      if (dispose) {
        s.close();
      } else {
        current = false;
      }
      s.held!.complete(true);
      await expectLater(future, throwsA(isA<CryptoAuthorityPending>()));
    }
  });
  test(
    'disposing while workflow loads starts no service or late ref reads',
    () async {
      final w = _Workflow(sharingSession());
      final waiting = Completer<AccountCryptoV2Workflow>();
      final s = _Service(w);
      final c = await _container(w, [s], preview: waiting.future);
      final future = c.read(accountProtectionStartupAssessmentProvider.future);
      await Future<void>.delayed(Duration.zero);
      c.dispose();
      waiting.complete(w);
      expect(await future, isNull);
      expect(s.completionReads, 0);
      expect(s.catalogReads, 0);
      expect(w.phaseReads, 0);
    },
  );
  test(
    'fresh device snapshot change requires completion review instead of catalog-only drift',
    () async {
      final w = _Workflow(sharingSession());
      final s = _Service(w)..deviceMatches = false;
      final result = await s.assessStartupReview(isCurrent: () => true);
      expect(result.status, AccountProtectionStartupStatus.reviewRequired);
      expect(result.reason, AccountProtectionStartupReason.completionMissing);
      expect(s.catalogReads, 1);
    },
  );
  test('account switch cancels outstanding old catalog assessment', () async {
    final w = _Workflow(sharingSession());
    final s = _Service(w)..held = Completer<bool>();
    final controller = SharingUiController(
      initial: CollaborationState(session: w.session),
    );
    final c = await _container(w, [s], controller: controller);
    addTearDown(c.dispose);
    c.listen(accountProtectionStartupAssessmentProvider, (_, _) {});
    final old = c.read(accountProtectionStartupAssessmentProvider.future);
    await Future<void>.delayed(Duration.zero);
    controller.replace(
      CollaborationState(session: sharingSession(second: true)),
    );
    expect(
      await c.read(accountProtectionStartupAssessmentProvider.future),
      isNull,
    );
    s.held!.complete(true);
    expect(await old, isNull);
    expect(s.closed, isTrue);
  });
}
