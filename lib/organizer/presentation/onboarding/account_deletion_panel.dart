import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../l10n/l10n.dart';
import '../../state/collaboration_provider.dart';
import '../backup/backup_wizard.dart';
import '../backup/personal_json_export.dart';
import '../finance/finance_money.dart';
import '../shared/sharing_errors.dart';
import '../shared/sharing_session_boundary.dart';

class AccountDeletionPanel extends ConsumerStatefulWidget {
  const AccountDeletionPanel({super.key});
  @override
  ConsumerState<AccountDeletionPanel> createState() =>
      _AccountDeletionPanelState();
}

class _AccountDeletionPanelState extends ConsumerState<AccountDeletionPanel> {
  Future<List<PendingAccountDeletion>>? _pending;
  bool _busy = false;
  String? _message;
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(collaborationProvider).valueOrNull;
    if (state == null) return const SizedBox.shrink();
    _pending ??= ref
        .read(collaborationProvider.notifier)
        .pendingAccountDeletions();
    final l = context.l10n;
    final session = state.session;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.deletionAccountSettings,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (session == null)
              Text(l.deletionLocalOnly)
            else ...[
              SelectableText('${session.username}\n${session.serverUrl}'),
              const SizedBox(height: 8),
              Text(l.deletionWarning),
              TextButton.icon(
                onPressed: _busy || state.sessionInvalid
                    ? null
                    : () async {
                        final guard = SharingSessionGuard(context, ref);
                        await showDialog<void>(
                          context: context,
                          barrierDismissible: false,
                          builder: (_) => SharingSessionBoundary(
                            guard: guard,
                            child: AccountDeletionDialog(guard: guard),
                          ),
                        );
                        if (mounted) {
                          setState(() {
                            _pending = null;
                          });
                        }
                      },
                icon: const Icon(Icons.person_remove_outlined),
                label: Text(l.deletionPreview),
              ),
            ],
            FutureBuilder<List<PendingAccountDeletion>>(
              future: _pending,
              builder: (context, snapshot) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (snapshot.hasError)
                    Text(sharingErrorMessage(context, snapshot.error!)),
                  for (final request
                      in snapshot.data ?? <PendingAccountDeletion>[]) ...[
                    const Divider(),
                    Text(
                      request.serverAccepted
                          ? l.deletionServerCleanup
                          : l.deletionUnknown,
                    ),
                    SelectableText(
                      '${request.profile.username}\n${request.profile.serverUrl}',
                    ),
                    if (!request.serverAccepted &&
                        session?.partition == request.profile.partition &&
                        request.review.isNotEmpty)
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () async {
                                final guard = SharingSessionGuard(context, ref);
                                await showDialog<void>(
                                  context: context,
                                  barrierDismissible: false,
                                  builder: (_) => SharingSessionBoundary(
                                    guard: guard,
                                    child: AccountDeletionDialog(
                                      guard: guard,
                                      pending: request,
                                    ),
                                  ),
                                );
                                if (mounted) {
                                  setState(() {
                                    _pending = null;
                                  });
                                }
                              },
                        child: Text(l.deletionRetry),
                      ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () async {
                              setState(() {
                                _busy = true;
                                _message = null;
                              });
                              try {
                                final controller = ref.read(
                                  collaborationProvider.notifier,
                                );
                                final deleted = await controller
                                    .checkAccountDeletion(request);
                                final remaining = await controller
                                    .pendingAccountDeletions();
                                final cancelled =
                                    !deleted &&
                                    remaining.every(
                                      (r) =>
                                          r.operationId != request.operationId,
                                    );
                                final accepted = remaining.any(
                                  (r) =>
                                      r.operationId == request.operationId &&
                                      r.serverAccepted,
                                );
                                if (mounted) {
                                  setState(() {
                                    _message = deleted
                                        ? l.deletionSuccess
                                        : cancelled
                                        ? l.deletionCancelled
                                        : accepted
                                        ? l.deletionServerCleanup
                                        : l.deletionNotConfirmed;
                                    _pending = null;
                                  });
                                }
                              } catch (e) {
                                if (mounted) {
                                  setState(() {
                                    _message = sharingErrorMessage(context, e);
                                  });
                                }
                              } finally {
                                if (mounted) {
                                  setState(() {
                                    _busy = false;
                                  });
                                }
                              }
                            },
                      child: Text(l.deletionCheckStatus),
                    ),
                    if (!request.serverAccepted)
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () async {
                                setState(() {
                                  _busy = true;
                                });
                                try {
                                  final controller = ref.read(
                                    collaborationProvider.notifier,
                                  );
                                  final cancelled = await controller
                                      .cancelPendingAccountDeletion(request);
                                  final remaining = await controller
                                      .pendingAccountDeletions();
                                  final completed = remaining.every(
                                    (r) => r.operationId != request.operationId,
                                  );
                                  if (mounted) {
                                    setState(() {
                                      _pending = null;
                                      _message = cancelled
                                          ? l.deletionCancelled
                                          : completed
                                          ? l.deletionSuccess
                                          : l.deletionServerCleanup;
                                    });
                                  }
                                } catch (e) {
                                  if (mounted) {
                                    setState(() {
                                      _message = sharingErrorMessage(
                                        context,
                                        e,
                                      );
                                    });
                                  }
                                } finally {
                                  if (mounted) {
                                    setState(() {
                                      _busy = false;
                                    });
                                  }
                                }
                              },
                        child: Text(l.deletionCancelPending),
                      ),
                  ],
                ],
              ),
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_message != null) Text(_message!),
          ],
        ),
      ),
    );
  }
}

class AccountDeletionDialog extends ConsumerStatefulWidget {
  const AccountDeletionDialog({super.key, required this.guard, this.pending});
  final PendingAccountDeletion? pending;
  final SharingSessionGuard guard;
  @override
  ConsumerState<AccountDeletionDialog> createState() =>
      _AccountDeletionDialogState();
}

class _AccountDeletionDialogState extends ConsumerState<AccountDeletionDialog> {
  late Future<Map<String, dynamic>> _preview = widget.pending == null
      ? widget.guard.controller.previewAccountDeletion()
      : Future.value(widget.pending!.review);
  late final Map<String, String> _owners = {
    for (final t
        in widget.pending?.ownershipTransfers ?? <Map<String, Object?>>[])
      t['scopeId'] as String: t['successorAccountId'] as String,
    for (final id in widget.pending?.ownedScopeDeletions ?? <String>[])
      id: 'delete',
  };
  late final Set<String> _preserved = {
    for (final r in widget.pending?.resolutions ?? <Map<String, Object?>>[])
      '${r['scopeId']}:${r['recordId']}',
  };
  bool _canResolve(Map<String, dynamic> p) {
    final blockers = (p['blockers'] as List).cast<Map>();
    if (blockers.any(
      (b) => !const {
        'shared_scope_owner',
        'shared_structure_resolution',
      }.contains(b['code']),
    )) {
      return false;
    }
    return (p['ownedScopes'] as List? ?? []).every(
          (s) => _owners.containsKey((s as Map)['id']),
        ) &&
        (p['resolutions'] as List? ?? []).every(
          (r) =>
              (r as Map)['type'] == 'financeEntry' &&
                  _owners[r['scopeId']] == 'delete' ||
              r['action'] == 'detachOrganization' &&
                  (_owners[r['scopeId']] != 'delete' ||
                      _owners[r['childScopeId']] == 'delete') ||
              _preserved.contains('${r['scopeId']}:${r['recordId']}'),
        );
  }

  final _password = TextEditingController(),
      _otp = TextEditingController(),
      _confirmation = TextEditingController();
  bool _acknowledged = false, _busy = false;
  late bool _retryingOriginal = widget.pending != null;
  int _previewGeneration = 0;
  String? _error;
  @override
  void dispose() {
    _password.dispose();
    _otp.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _confirm(Map<String, dynamic> preview) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final password = _password.text, otp = _otp.text.trim();
    final controller = widget.guard.controller;
    final messenger = ScaffoldMessenger.of(context);
    final l = context.l10n;
    _password.clear();
    _otp.clear();
    try {
      await controller.confirmAccountDeletion(
        previewHash: preview['previewHash'] as String,
        password: password,
        otp: otp.isEmpty ? null : otp,
        review: preview,
        ownershipTransfers: [
          for (final o in _owners.entries.where((o) => o.value != 'delete'))
            {'scopeId': o.key, 'successorAccountId': o.value},
        ],
        ownedScopeDeletions: _owners.entries
            .where((o) => o.value == 'delete')
            .map((o) => o.key)
            .toList(),
        resolutions: [
          for (final r in preview['resolutions'] as List? ?? [])
            if (_preserved.contains(
                  '${(r as Map)['scopeId']}:${r['recordId']}',
                ) &&
                !(r['type'] == 'financeEntry' &&
                    _owners[r['scopeId']] == 'delete'))
              {
                'scopeId': r['scopeId'],
                'recordId': r['recordId'],
                'action': r['action'],
              },
        ],
      );
      final pending = await controller.pendingAccountDeletions();
      final accepted = pending.any(
        (r) =>
            r.profile.partition == widget.guard.session!.partition &&
            r.serverAccepted,
      );
      if (messenger.mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              accepted ? l.deletionServerCleanup : l.deletionSuccess,
            ),
          ),
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error =
              e is CollaborationException &&
                  const {
                    'network',
                    'invalid_response',
                    'device_revoked',
                    'auth_required',
                  }.contains(e.code)
              ? context.l10n.deletionUnknown
              : sharingErrorMessage(context, e);
          if (!_retryingOriginal &&
              e is CollaborationException &&
              const {
                'deletion_preview_stale',
                'deletion_blocked',
              }.contains(e.code)) {
            _preview = widget.guard.controller.previewAccountDeletion();
            _acknowledged = false;
            _owners.clear();
            _preserved.clear();
            _confirmation.clear();
            _retryingOriginal = false;
            _previewGeneration++;
          }
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(l.deletionTitle),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: FutureBuilder<Map<String, dynamic>>(
              future: _preview,
              builder: (context, snapshot) {
                final p = snapshot.data;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SelectableText(
                      '${widget.guard.session!.username}\n${widget.guard.session!.serverUrl}',
                    ),
                    const SizedBox(height: 12),
                    Text(l.deletionWarning),
                    const SizedBox(height: 12),
                    Text(l.deletionLocalConsequences),
                    const SizedBox(height: 12),
                    Text(l.deletionRetainedEdits),
                    const SizedBox(height: 12),
                    Text(l.deletionLegacyLocal),
                    TextButton.icon(
                      onPressed: _busy
                          ? null
                          : () => showBackupWizard(context, restore: false),
                      icon: const Icon(Icons.lock_outline),
                      label: Text(l.backupCreate),
                    ),
                    Text(l.deletionExportLimit),
                    TextButton.icon(
                      onPressed: _busy || _retryingOriginal
                          ? null
                          : () =>
                                exportPersonalJsonForLocalRestore(context, ref),
                      icon: const Icon(Icons.file_download_outlined),
                      label: Text(l.deletionPersonalExport),
                    ),
                    if (_retryingOriginal) Text(l.deletionRetryReview),
                    if (snapshot.hasError) ...[
                      const SizedBox(height: 12),
                      Text(sharingErrorMessage(context, snapshot.error!)),
                      TextButton(
                        onPressed: () => setState(() {
                          _preview = widget.guard.controller
                              .previewAccountDeletion();
                        }),
                        child: Text(l.organizerRetry),
                      ),
                    ] else if (p == null)
                      const LinearProgressIndicator()
                    else ...[
                      const Divider(),
                      Text(
                        l.deletionImpact,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      for (final entry in (p['impact'] as Map).entries)
                        Text(
                          '${deletionImpactLabel(context, entry.key.toString())}: ${entry.value}',
                        ),
                      for (final scope in p['sharedScopes'] as List)
                        Text(
                          '${(scope as Map)['name']} · ${_owners[scope['id']] == 'delete' ? l.deletionSpaceDeleted : l.deletionSharedRemains}',
                        ),
                      if (p['policyVersion'] == 3 &&
                          (p['linkedFinancialFacts'] as List).isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          l.deletionLinkedFinancialFacts,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(l.deletionLinkedFinancialRetention),
                        for (final raw in p['linkedFinancialFacts'] as List)
                          Builder(
                            builder: (context) {
                              final fact = raw as Map;
                              String? name;
                              for (final value in p['sharedScopes'] as List) {
                                final scope = value as Map;
                                if (scope['id'] == fact['scopeId']) {
                                  name = scope['name'] as String;
                                  break;
                                }
                              }
                              return Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  l.deletionLinkedScopeCounts(
                                    name ?? l.deletionLinkedUnavailableScope,
                                    fact['eventsRetainedIfScopeKept'] as int,
                                    fact['eventsDeletedIfScopeDeleted'] as int,
                                    fact['refundLegs'] as int,
                                  ),
                                ),
                              );
                            },
                          ),
                      ],
                      for (final value in p['ownedScopes'] as List? ?? [])
                        Builder(
                          builder: (context) {
                            final scope = value as Map;
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: DropdownButtonFormField<String>(
                                key: ValueKey(
                                  'deletion-owner-${scope['id']}-$_previewGeneration',
                                ),
                                initialValue: _owners[scope['id']],
                                isExpanded: true,
                                decoration: InputDecoration(
                                  labelText:
                                      '${l.deletionOwnedScopes}: ${scope['name']}',
                                ),
                                items: [
                                  for (final member
                                      in scope['eligibleSuccessors'] as List)
                                    DropdownMenuItem(
                                      value:
                                          (member as Map)['accountId']
                                              as String,
                                      child: Text(
                                        member['displayName'] as String,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  if (scope['canDeleteScope'] == true)
                                    DropdownMenuItem(
                                      value: 'delete',
                                      child: Text(
                                        l.deletionDeleteOwnedScope,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                ],
                                onChanged: _busy || _retryingOriginal
                                    ? null
                                    : (v) => setState(() {
                                        if (v != null) {
                                          _owners[scope['id'] as String] = v;
                                        }
                                      }),
                              ),
                            );
                          },
                        ),
                      for (final value in p['resolutions'] as List? ?? [])
                        Builder(
                          builder: (context) {
                            final r = value as Map;
                            if (r['type'] == 'financeEntry' &&
                                _owners[r['scopeId']] == 'delete') {
                              return const SizedBox.shrink();
                            }
                            if (r['action'] == 'detachOrganization' &&
                                (_owners[r['scopeId']] != 'delete' ||
                                    _owners[r['childScopeId']] == 'delete')) {
                              return const SizedBox.shrink();
                            }
                            final id =
                                '${value['scopeId']}:${value['recordId']}';
                            return CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              value: _preserved.contains(id),
                              onChanged: _busy || _retryingOriginal
                                  ? null
                                  : (v) => setState(() {
                                      if (v == true) {
                                        _preserved.add(id);
                                      } else {
                                        _preserved.remove(id);
                                      }
                                    }),
                              title: Text(
                                r['name'] as String? ??
                                    l.deletionUnnamedStructure,
                              ),
                              subtitle: Text(
                                r['action'] == 'detachOrganization'
                                    ? l.deletionDetachOrganization
                                    : r['type'] == 'financeEntry'
                                    ? l.deletionRetainedExpenseResolution
                                    : '${l.deletionStructure}${r['currency'] == null || r['openingBalanceMinor'] == null ? '' : '\n${sharedMoneyLabel(context, BigInt.from(r['openingBalanceMinor'] as int), r['currency'] as String)}'}',
                              ),
                            );
                          },
                        ),
                      if (!_canResolve(p)) ...[
                        const SizedBox(height: 12),
                        Text(l.deletionBlocked),
                        for (final b in p['blockers'] as List)
                          Text(
                            '${deletionBlockerLabel(context, (b as Map)['code'] as String)}: ${b['count']}',
                          ),
                      ] else ...[
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _acknowledged,
                          onChanged: _busy
                              ? null
                              : (v) => setState(() {
                                  _acknowledged = v == true;
                                }),
                          title: Text(l.deletionAcknowledge),
                        ),
                        TextField(
                          key: const ValueKey('deletion-password'),
                          controller: _password,
                          obscureText: true,
                          enableSuggestions: false,
                          autocorrect: false,
                          enableIMEPersonalizedLearning: false,
                          enabled: !_busy,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(labelText: l.password),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _otp,
                          enableSuggestions: false,
                          autocorrect: false,
                          enableIMEPersonalizedLearning: false,
                          enabled: !_busy,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: l.sharingTwoFactorCode,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          key: const ValueKey('deletion-confirmation'),
                          controller: _confirmation,
                          enabled: !_busy,
                          autocorrect: false,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            labelText: l.deletionTypeDelete,
                          ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          key: const ValueKey('deletion-confirm'),
                          onPressed:
                              _busy ||
                                  !_acknowledged ||
                                  _confirmation.text != 'DELETE' ||
                                  _password.text.isEmpty
                              ? null
                              : () => _confirm(p),
                          child: Text(l.deletionConfirm),
                        ),
                      ],
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!),
                    ],
                    if (_busy) const LinearProgressIndicator(),
                  ],
                );
              },
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: Text(l.close),
          ),
        ],
      ),
    );
  }
}

String deletionImpactLabel(BuildContext context, String key) {
  final l = context.l10n;
  return switch (key) {
    'personalScopes' => l.deletionPersonalScopes,
    'personalRecords' => l.deletionPersonalRecords,
    'personalFinanceRecords' => l.deletionPersonalFinance,
    'memberships' || 'sharedMemberships' => l.deletionMemberships,
    'sharedRecordsDeleted' => l.deletionSharedRecordsDeleted,
    'sharedRecordsUpdated' => l.deletionSharedRecordsUpdated,
    'sharedFinanceRecordsDeleted' => l.deletionSharedFinanceDeleted,
    'sharedFinanceRecordsUpdated' => l.deletionSharedFinanceUpdated,
    'privatePaymentProjectionsDeleted' => l.deletionPrivatePaymentProjections,
    'sharedPaymentReceiptsRetained' => l.deletionSharedPaymentReceipts,
    'kanboardTasksDeleted' => l.deletionLegacyTasks,
    'kanboardCommentsDeleted' => l.deletionLegacyComments,
    'kanboardFilesDeleted' => l.deletionLegacyFiles,
    'kanboardAssignedTasks' => l.deletionAssignedTasks,
    'kanboardAssignedSubtasks' => l.deletionAssignedSubtasks,
    'devices' || 'sessions' => l.deletionDevices,
    'pushDevices' || 'pushTokens' => l.deletionPush,
    'emailTokens' => l.deletionEmailTokens,
    _ => l.deletionRelatedData,
  };
}

String deletionBlockerLabel(BuildContext context, String code) =>
    switch (code) {
      'shared_scope_owner' ||
      'shared_scope_without_successor' => context.l10n.deletionOwnedScopes,
      'last_admin' => context.l10n.deletionLastAdmin,
      'legacy_shared_private_project' => context.l10n.deletionLegacyPrivate,
      'shared_structure_resolution' => context.l10n.deletionStructure,
      _ => context.l10n.deletionContributions,
    };
