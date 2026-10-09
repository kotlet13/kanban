import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../l10n/l10n.dart';
import '../../state/collaboration_provider.dart';
import '../shared/sharing_errors.dart';
import '../shared/sharing_forms.dart';
import '../shared/sharing_session_boundary.dart';

Future<void> showFinancePermissions(
  BuildContext context,
  WidgetRef ref,
  String scopeId,
) {
  final guard = SharingSessionGuard(context, ref);
  return showDialog<void>(
    context: context,
    builder: (context) => SharingSessionBoundary(
      guard: guard,
      visibleWhen: (s) =>
          !s.sessionInvalid &&
          !s.deletionPending &&
          s.session?.expiresAt.isAfter(DateTime.now()) == true &&
          s.scopes.any((v) => v.id == scopeId && !v.revoked && v.canManage),
      child: AlertDialog(
        title: Text(context.l10n.financePermissions),
        content: SizedBox(
          width: 540,
          child: SingleChildScrollView(
            child: _FinancePermissions(guard: guard, scopeId: scopeId),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.close),
          ),
        ],
      ),
    ),
  );
}

class _FinancePermissions extends ConsumerStatefulWidget {
  const _FinancePermissions({required this.guard, required this.scopeId});
  final SharingSessionGuard guard;
  final String scopeId;
  @override
  ConsumerState<_FinancePermissions> createState() =>
      _FinancePermissionsState();
}

class _FinancePermissionsState extends ConsumerState<_FinancePermissions> {
  late Future<
    ({Map<String, SharedFinanceGrant> grants, List<SharedMember> members})
  >
  _future = _load();
  bool _busy = false;
  Future<({Map<String, SharedFinanceGrant> grants, List<SharedMember> members})>
  _load() async {
    final controller = widget.guard.controller;
    final members = await controller.members(widget.scopeId);
    final grants = await controller.financeGrants(widget.scopeId);
    if (!widget.guard.isCurrent) {
      throw const CollaborationException('session_changed');
    }
    return (grants: grants, members: members);
  }

  bool get _managed {
    final scope = ref
        .read(collaborationProvider)
        .valueOrNull
        ?.scopes
        .where((s) => s.id == widget.scopeId)
        .firstOrNull;
    final policy = ref
        .read(collaborationProvider)
        .valueOrNull
        ?.financePolicyForScope(widget.scopeId);
    return policy?.managedByOrganizationPolicy == true ||
        scope?.accessPolicyVersion == 2 &&
            (scope?.kind == SharedScopeKind.project ||
                scope?.kind == SharedScopeKind.organization);
  }

  String _label(SharedFinanceGrant grant) =>
      _managed && grant != SharedFinanceGrant.write
      ? context.l10n.financeMembershipRead
      : switch (grant) {
          SharedFinanceGrant.none => context.l10n.financeGrantNone,
          SharedFinanceGrant.read => context.l10n.financeGrantRead,
          SharedFinanceGrant.write => context.l10n.financeGrantWrite,
        };
  Future<void> _edit(SharedMember member, SharedFinanceGrant grant) async {
    setState(() => _busy = true);
    await showSharingForm(
      context,
      title: member.displayName.isEmpty ? member.username : member.displayName,
      description: _managed
          ? context.l10n.financeMembershipReadDescription
          : null,
      fields: [
        SharingField(
          id: 'grant',
          label: context.l10n.financePermissions,
          initialValue: _managed && grant != SharedFinanceGrant.write
              ? 'none'
              : grant.name,
          options: {
            'none': _label(SharedFinanceGrant.none),
            if (!_managed) 'read': _label(SharedFinanceGrant.read),
            if (member.role != SharedRole.viewer)
              'write': _label(SharedFinanceGrant.write),
          },
        ),
      ],
      submitLabel: context.l10n.save,
      errorMessage: (e) => sharingErrorMessage(context, e),
      wrap: (child) => SharingSessionBoundary(
        guard: widget.guard,
        visibleWhen: (s) =>
            !s.sessionInvalid &&
            !s.deletionPending &&
            s.session?.expiresAt.isAfter(DateTime.now()) == true &&
            s.scopes.any(
              (v) => v.id == widget.scopeId && !v.revoked && v.canManage,
            ),
        child: child,
      ),
      onSubmit: (values) async {
        await widget.guard.controller.grantFinance(
          scopeId: widget.scopeId,
          accountId: member.accountId,
          grant: SharedFinanceGrant.values.byName(values['grant']!),
        );
        if (mounted) {
          setState(() {
            _future = _load();
          });
        }
      },
    );
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(collaborationProvider).valueOrNull;
    return FutureBuilder<
      ({Map<String, SharedFinanceGrant> grants, List<SharedMember> members})
    >(
      future: _future,
      builder: (context, result) {
        if (result.hasError) {
          return Column(
            children: [
              Text(sharingErrorMessage(context, result.error!)),
              TextButton(
                onPressed: () => setState(() {
                  _future = _load();
                }),
                child: Text(context.l10n.organizerRetry),
              ),
            ],
          );
        }
        if (!result.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final cached =
            state?.membersForScope(widget.scopeId) ?? <SharedMember>[];
        final members = cached.isNotEmpty ? cached : result.data!.members;
        return Column(
          children: [
            if (_managed) Text(context.l10n.financeMembershipReadDescription),
            for (final member in members.where(
              (m) => m.active && m.accountId.isNotEmpty,
            ))
              ListTile(
                title: Text(
                  member.displayName.isEmpty
                      ? member.username
                      : member.displayName,
                ),
                subtitle: Text(sharingRoleLabel(context, member.role)),
                trailing: TextButton(
                  onPressed: _busy
                      ? null
                      : () => _edit(
                          member,
                          result.data!.grants[member.accountId] ??
                              SharedFinanceGrant.none,
                        ),
                  child: Text(
                    _label(
                      result.data!.grants[member.accountId] ??
                          SharedFinanceGrant.none,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
