import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../l10n/l10n.dart';
import '../../domain/organizer_models.dart';
import '../../state/collaboration_provider.dart';
import '../../state/local_spaces_provider.dart';
import '../../state/linked_payments_provider.dart';
import '../shared/sharing_errors.dart';
import '../shared/sharing_forms.dart';
import '../shared/sharing_session_boundary.dart';
import 'finance_access_guard.dart';
import 'finance_money.dart';

bool canWritePaymentSource(WidgetRef ref, PaymentSpaceRef source) =>
    _paymentSourceAllowed(
      source,
      ref.read(localSpacesProvider).valueOrNull,
      ref.read(collaborationProvider).valueOrNull,
    );
bool _paymentSourceAllowed(
  PaymentSpaceRef source,
  LocalSpacesState? local,
  CollaborationState? shared,
) {
  if (source.isLocal) {
    final space = local?.spaces.where((s) => s.id == source.id).firstOrNull;
    return space?.kind == LocalSpaceKind.organization &&
        space?.binding == null &&
        space?.financeRecoveryIncomplete != true;
  }
  final state = shared;
  final scope = state?.scopes.where((s) => s.id == source.id).firstOrNull;
  return state?.localAccessAllowed == true &&
      state?.session?.partition == source.partition &&
      scope != null &&
      !scope.revoked &&
      !scope.blocked &&
      !scope.archived &&
      (scope.kind == SharedScopeKind.organization ||
          scope.organizationId != null) &&
      state!.financePolicyForScope(scope.id).canWrite &&
      state.financeSnapshotComplete[scope.id] == true;
}

class _PaymentGuard {
  _PaymentGuard(BuildContext caller, WidgetRef ref, this.source)
    : context = Navigator.of(caller, rootNavigator: true).context,
      container = ProviderScope.containerOf(caller, listen: false),
      session = SharingSessionGuard(
        Navigator.of(caller, rootNavigator: true).context,
        ref,
        allowSignedOut: true,
      ),
      finance = source.isLocal
          ? null
          : FinanceAccessGuard(
              Navigator.of(caller, rootNavigator: true).context,
              ref,
              source.id,
              write: true,
            );
  final BuildContext context;
  final ProviderContainer container;
  final PaymentSpaceRef source;
  final SharingSessionGuard session;
  final FinanceAccessGuard? finance;
  bool get isCurrent =>
      context.mounted &&
      session.isCurrent &&
      _paymentSourceAllowed(
        source,
        container.read(localSpacesProvider).valueOrNull,
        container.read(collaborationProvider).valueOrNull,
      ) &&
      (finance?.isCurrent ?? true);
  Widget wrap(Widget child) => Consumer(
    builder: (context, ref, _) {
      ref.watch(localSpacesProvider);
      return SharingSessionBoundary(
        guard: session,
        visibleWhen: (_) => isCurrent,
        child: child,
      );
    },
  );
}

Future<void> showPersonalPaymentForm(
  BuildContext context,
  WidgetRef ref, {
  required PaymentSourceRef source,
  required String title,
  required int amountMinor,
  required String currency,
  DateTime? paidAt,
}) async {
  final guard = _PaymentGuard(context, ref, source.space);
  if (!guard.isCurrent) return;
  final l = context.l10n;
  final catalog = ref.read(localSpacesProvider).valueOrNull;
  final personal = catalog?.snapshots['local'];
  final shared = ref.read(collaborationProvider).valueOrNull;
  final private = personal?.workspaceKey.startsWith('private:') == true;
  final personalAllowed =
      !private ||
      shared?.localAccessAllowed == true &&
          shared?.session != null &&
          personal?.workspaceKey == 'private:${shared!.session!.partition}' &&
          shared
              .financePolicyForScope(shared.privateSync.scopeId ?? '')
              .canWrite &&
          shared.financeSnapshotComplete[shared.privateSync.scopeId] == true;
  final accounts = personalAllowed
      ? personal?.financeAccounts
                .where((a) => !a.archived && a.currency == currency)
                .toList() ??
            <LocalFinanceAccount>[]
      : <LocalFinanceAccount>[];
  if (accounts.isEmpty) {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.paymentPaidPersonally),
        content: Text(l.paymentNeedsPersonalAccount),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.close),
          ),
        ],
      ),
    );
    return;
  }
  final homes = <String, PaymentSpaceRef>{};
  final homeNames = <String, String>{'': l.paymentNoHousehold};
  for (final space in catalog?.spaces ?? <LocalSpace>[]) {
    if (space.kind == LocalSpaceKind.household &&
        space.binding == null &&
        !space.financeRecoveryIncomplete) {
      homes[space.id] = PaymentSpaceRef(space.id);
      homeNames[space.id] = '${space.name} · ${l.spaceLocalShort}';
    }
  }
  if (shared?.localAccessAllowed == true) {
    for (final scope in shared!.scopes.where(
      (s) =>
          s.kind == SharedScopeKind.household &&
          !s.revoked &&
          !s.blocked &&
          !s.archived,
    )) {
      if (shared.financePolicyForScope(scope.id).canWrite &&
          shared.financeSnapshotComplete[scope.id] == true) {
        homes['remote:${scope.id}'] = PaymentSpaceRef(
          scope.id,
          partition: shared.session!.partition,
        );
        homeNames['remote:${scope.id}'] = '${scope.name} · ${l.sharingShared}';
      }
    }
  }
  await showSharingForm(
    context,
    title: l.paymentPaidPersonally,
    description:
        '$title · ${sharedMoneyLabel(context, BigInt.from(amountMinor), currency)}\n${l.paymentSourceExpenseOnly}',
    fields: [
      SharingField(
        id: 'personal-account',
        label: l.paymentMyAccount,
        validator: (value, _) => value.isEmpty ? l.sharingRequired : null,
        options: {
          '': l.paymentChooseAccount,
          for (final a in accounts) a.id: '${a.name} · ${a.currency}',
        },
      ),
      SharingField(
        id: 'payment-date',
        label: l.paymentPaidAt,
        dateTime: true,
        initialValue: (paidAt ?? DateTime.now()).toUtc().toIso8601String(),
        readOnly: paidAt != null,
      ),
      SharingField(
        id: 'expect-reimbursement',
        label: l.paymentExpectRefund,
        initialValue: 'yes',
        options: {
          'yes': l.paymentExpectRefundYes,
          'no': l.paymentExpectRefundNo,
        },
      ),
      SharingField(
        id: 'household',
        label: l.paymentHouseholdInclusion,
        required: false,
        options: homeNames,
      ),
    ],
    submitLabel: l.paymentRecord,
    wrap: guard.wrap,
    errorMessage: (error) => sharingErrorMessage(context, error),
    onSubmit: (values) async {
      if (!guard.isCurrent) {
        throw const CollaborationException('session_changed');
      }
      final repo = await guard.container.read(
        linkedPaymentsRepositoryProvider.future,
      );
      try {
        await repo.recordPersonalPayment(
          source,
          personal: const PaymentSpaceRef('local'),
          personalAccountId: values['personal-account']!,
          household: homes[values['household']],
          paidAt: DateTime.parse(values['payment-date']!),
          expectReimbursement: values['expect-reimbursement'] == 'yes',
        );
      } catch (error) {
        final current = await repo.read(source.space);
        if (current.pendingCount == 0) rethrow;
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(l.paymentPending)));
        }
      }
      guard.container.invalidate(
        linkedPaymentsProvider(paymentSpaceKey(source.space)),
      );
    },
  );
}

class _RefundAccount {
  const _RefundAccount(this.space, this.id, this.label);
  final PaymentSpaceRef space;
  final String id, label;
}

Future<void> showPaymentRefundForm(
  BuildContext context,
  WidgetRef ref, {
  required PaymentSpaceRef source,
  required PaymentEvent event,
}) async {
  final guard = _PaymentGuard(context, ref, source);
  if (!guard.isCurrent ||
      !event.expectReimbursement ||
      event.receivableMinor <= 0) {
    return;
  }
  final l = context.l10n;
  final options = <_RefundAccount>[];
  if (source.isLocal) {
    final catalog = ref.read(localSpacesProvider).valueOrNull;
    final snapshot = catalog?.snapshots[source.id];
    for (final a in snapshot?.financeAccounts ?? <LocalFinanceAccount>[]) {
      if (!a.archived && a.currency == event.currency) {
        options.add(_RefundAccount(source, a.id, a.name));
      }
    }
  } else {
    final shared = ref.read(collaborationProvider).requireValue;
    final scope = shared.scopes.firstWhere((s) => s.id == source.id);
    final allowed = [source.id];
    if (scope.organizationId != null &&
        shared.scopes.any(
          (s) =>
              s.id == scope.organizationId &&
              !s.revoked &&
              !s.blocked &&
              !s.archived,
        ) &&
        shared.financePolicyForScope(scope.organizationId!).canWrite &&
        shared.financeSnapshotComplete[scope.organizationId!] == true) {
      allowed.add(scope.organizationId!);
    }
    for (final id in allowed) {
      final name = shared.scopes.firstWhere((s) => s.id == id).name;
      for (final account in shared.dataForScope(id).financeAccounts) {
        if (!account.archived && account.currency == event.currency) {
          options.add(
            _RefundAccount(
              PaymentSpaceRef(id, partition: source.partition),
              account.id,
              '${account.name} · $name',
            ),
          );
        }
      }
    }
  }
  await showSharingForm(
    context,
    title: l.paymentRefundAction,
    description: l.paymentRefundDescription(
      sharedMoneyLabel(
        context,
        BigInt.from(event.receivableMinor),
        event.currency,
      ),
    ),
    fields: [
      SharingField(
        id: 'refund-account',
        label: l.financeFromAccount,
        validator: (value, _) => value.isEmpty ? l.sharingRequired : null,
        options: {
          '': l.paymentChooseAccount,
          for (var i = 0; i < options.length; i++) '$i': options[i].label,
        },
      ),
      SharingField(
        id: 'refund-amount',
        label: '${l.amount} · ${event.currency}',
        initialValue: formatMoneyMinor(event.receivableMinor),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        validator: (value, _) {
          try {
            if (parseMoneyMinor(value) > event.receivableMinor) {
              return l.paymentRefundTooHigh;
            }
          } catch (_) {
            return l.amountMustBeAValidNumber;
          }
          return null;
        },
      ),
      SharingField(
        id: 'refund-date',
        label: l.paymentRefundAt,
        dateTime: true,
        initialValue: DateTime.now().toUtc().toIso8601String(),
        validator: (value, _) =>
            DateTime.tryParse(value)?.isBefore(event.paidAt) == true
            ? l.paymentRefundAfterPayment
            : null,
      ),
    ],
    submitLabel: l.paymentRefundAction,
    wrap: guard.wrap,
    errorMessage: (error) => sharingErrorMessage(context, error),
    onSubmit: (values) async {
      if (!guard.isCurrent) {
        throw const CollaborationException('session_changed');
      }
      final selected = options[int.parse(values['refund-account']!)];
      final repo = await guard.container.read(
        linkedPaymentsRepositoryProvider.future,
      );
      try {
        await repo.reimburse(
          source,
          event.eventId,
          expectedRevision: event.revision,
          amountMinor: parseMoneyMinor(values['refund-amount']!),
          paidAt: DateTime.parse(values['refund-date']!),
          organizationAccountId: selected.id,
          organizationAccountScope: selected.space,
        );
      } catch (error) {
        final current = await repo.read(source);
        if (current.pendingCount == 0) rethrow;
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(l.paymentPending)));
        }
      }
      guard.container.invalidate(
        linkedPaymentsProvider(paymentSpaceKey(source)),
      );
    },
  );
}
