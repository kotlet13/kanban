import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../domain/organizer_projections.dart';
import '../state/collaboration_provider.dart';
import '../state/organizer_provider.dart';
import 'local_notification_scheduler.dart';
import 'notification_providers.dart';

/// Watches committed data, not network requests. Platform errors stay visible
/// in notification settings and never prevent the personal workspace loading.
class LocalNotificationCoordinator extends ConsumerStatefulWidget {
  const LocalNotificationCoordinator({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<LocalNotificationCoordinator> createState() =>
      _LocalNotificationCoordinatorState();
}

class _LocalNotificationCoordinatorState
    extends ConsumerState<LocalNotificationCoordinator>
    with WidgetsBindingObserver {
  Future<void>? _initializing;
  bool _ready = false;
  int _generation = 0;
  Timer? _timer;
  String? _locale;
  String? _financeMaterializedKey;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _reconcile());
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _reconcile();
  }

  Future<void> _start() => _initializing ??= _initialize();
  Future<void> _initialize() async {
    try {
      final adapter = await ref.read(localNotificationAdapterProvider.future);
      if (!mounted) return;
      _ready = true;
      ref.read(localNotificationDeviceStatusProvider.notifier).state =
          AsyncData(adapter.status);
      await _reconcile();
    } catch (error, stack) {
      _initializing = null;
      if (mounted) {
        ref.read(localNotificationDeviceStatusProvider.notifier).state =
            AsyncError(error, stack);
      }
    }
  }

  Future<void> _reconcile() async {
    final generation = ++_generation;
    if (!_ready || !mounted) return;
    final sharedState = ref.read(collaborationProvider);
    // Wait for the cached SQLite identity before removing shared alarms.
    if (sharedState.isLoading) return;
    final personal = ref.read(organizerProvider).valueOrNull;
    final shared = sharedState.valueOrNull;
    final identity =
        '${shared?.session?.partition}:${shared?.session?.deviceId}';
    final settings = ref.read(localReminderSettingsProvider).valueOrNull;
    if (settings == null || personal == null) return;
    final clock = ref.read(organizerClockProvider)().toLocal();
    final financeKey = '${personal.workspaceKey}:${clock.year}-${clock.month}';
    final privateScope = shared?.privateSync.scopeId;
    final canMaterialize =
        personal.workspaceKey == 'local' ||
        (shared?.financeContractVersion == 2 &&
            shared?.sessionInvalid != true &&
            privateScope != null &&
            shared!.financePolicyForScope(privateScope).canWrite &&
            shared.financeSnapshotComplete[privateScope] == true);
    final localRules = personal.financeRecurrenceRules
        .where(
          (r) =>
              r.active &&
              shared?.privateRecordIds.values.contains(r.id) != true,
        )
        .map((r) => r.id)
        .toSet();
    final sameWorkspace =
        personal.workspaceKey == 'local' ||
        (shared?.session != null &&
            shared?.sessionInvalid != true &&
            personal.workspaceKey == 'private:${shared!.session!.partition}');
    if (sameWorkspace &&
        (canMaterialize || localRules.isNotEmpty) &&
        personal.financeRecurrenceRules.any((r) => r.active) &&
        _financeMaterializedKey != financeKey) {
      _financeMaterializedKey = financeKey;
      try {
        await ref
            .read(organizerProvider.notifier)
            .materializeFinanceOccurrences(
              expectedWorkspaceKey: personal.workspaceKey,
              ruleIds: canMaterialize ? null : localRules,
            );
      } catch (error, stack) {
        if (mounted) {
          ref.read(localNotificationDeviceStatusProvider.notifier).state =
              AsyncError(error, stack);
        }
      }
      if (!mounted || generation != _generation) return;
      return _reconcile();
    }
    final l = context.l10n;
    final plans = desiredReminderPlans(
      personal: personal,
      shared: shared ?? CollaborationState(),
    );
    final requests = settings.enabled
        ? [
            for (final plan in plans)
              LocalNotificationRequest(
                plan: plan,
                title: l.organizerAppName,
                body: plan.reason == 'salary_check'
                    ? l.financePlanReminderBody
                    : plan.reason == 'income_check'
                    ? l.financePlanIncomeReminderBody
                    : plan.reason == 'finance_due'
                    ? l.financePlanExpenseReminderBody
                    : plan.reason == 'event_start'
                    ? l.inboxDeviceEventReminder
                    : l.inboxDeviceReminder,
                sound:
                    settings.sound &&
                    (plan.target.isPersonal ||
                        shared?.notificationPreferences[plan.target.scopeId]
                                ?.forCategory('reminders')
                                .sound ==
                            true),
              ),
          ]
        : <LocalNotificationRequest>[];
    try {
      final adapter = await ref.read(localNotificationAdapterProvider.future);
      if (!mounted || generation != _generation) return;
      final current = ref.read(collaborationProvider);
      if (current.isLoading ||
          '${current.valueOrNull?.session?.partition}:${current.valueOrNull?.session?.deviceId}' !=
              identity) {
        return;
      }
      final status = await adapter.reconcile(requests);
      if (mounted && generation == _generation) {
        ref.read(localNotificationDeviceStatusProvider.notifier).state =
            AsyncData(status);
      }
    } catch (error, stack) {
      if (mounted) {
        ref.read(localNotificationDeviceStatusProvider.notifier).state =
            AsyncError(error, stack);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(localNotificationAdapterProvider, (_, next) {
      _ready = next.hasValue;
      if (_ready) _reconcile();
    });
    ref.listen(organizerProvider, (_, _) => _reconcile());
    ref.listen(collaborationProvider, (_, _) => _reconcile());
    ref.listen(
      localReminderSettingsProvider,
      (_, _) => _ready ? _reconcile() : _start(),
    );
    final locale = Localizations.localeOf(context).toLanguageTag();
    if (_locale != locale) {
      _locale = locale;
      WidgetsBinding.instance.addPostFrameCallback((_) => _reconcile());
    }
    ref.watch(localReminderSettingsProvider);
    return widget.child;
  }
}
