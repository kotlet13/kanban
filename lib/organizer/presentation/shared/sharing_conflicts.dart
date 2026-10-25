import '../ideas/idea_conflict_preview.dart';
import '../../domain/idea_models.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../state/collaboration_provider.dart';
import '../../domain/shared_record_permissions.dart';
import '../organizer_widgets.dart';
import 'sharing_errors.dart';
import 'sharing_recovery.dart';
import 'sharing_session_boundary.dart';
import 'sharing_member_label.dart';

Future<void> showSharingConflicts(BuildContext context, WidgetRef ref) {
  final guard = SharingSessionGuard(context, ref);
  return showDialog<void>(
    context: context,
    builder: (context) => SharingSessionBoundary(
      guard: guard,
      child: AlertDialog(
        title: Text(context.l10n.sharingConflicts),
        content: SizedBox(
          width: 760,
          child: SingleChildScrollView(
            child: SharingConflictsPage(guard: guard),
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

class SharingConflictsPage extends ConsumerStatefulWidget {
  const SharingConflictsPage({super.key, required this.guard});
  final SharingSessionGuard guard;
  @override
  ConsumerState<SharingConflictsPage> createState() =>
      _SharingConflictsPageState();
}

class _SharingConflictsPageState extends ConsumerState<SharingConflictsPage> {
  String? _busyId;
  final Map<String, bool> _ideaPreviews = {};
  String _previewKey(SharedConflict conflict, bool local) =>
      '${conflict.id}:${local ? 'local' : 'remote'}:${jsonEncode((local ? conflict.localPayload : conflict.remotePayload)?['elements'] ?? []).hashCode}';
  bool _ready(SharedConflict conflict) =>
      conflict.recordType != SharedRecordType.idea ||
      (conflict.localPayload == null ||
              _ideaPreviews[_previewKey(conflict, true)] == true) &&
          (conflict.remotePayload == null ||
              _ideaPreviews[_previewKey(conflict, false)] == true);

  bool _canKeepLocal(CollaborationState state, SharedConflict conflict) {
    final scope = state.scopes
        .where((s) => s.id == conflict.scopeId)
        .firstOrNull;
    final account = state.session?.accountId;
    if (!state.localAccessAllowed || scope == null || account == null) {
      return false;
    }
    final creator =
        state
            .dataForScope(scope.id)
            .recordCreators['content:${conflict.recordId}'] ??
        conflict.createdByAccountId;
    if (conflict.remoteDeleted) {
      return scope.recordPolicyVersion == 1 &&
          conflict.localPayload != null &&
          SharedRecordPermissions.canDelete(
            scope: scope,
            accountId: account,
            creator: creator,
          );
    }
    if (conflict.localPayload == null) {
      return SharedRecordPermissions.canDelete(
        scope: scope,
        accountId: account,
        creator: creator,
      );
    }
    if (conflict.recordType == SharedRecordType.shoppingItem &&
        conflict.remotePayload != null &&
        SharedRecordPermissions.onlyShoppingCheck(
          conflict.remotePayload!,
          conflict.localPayload!,
        )) {
      return SharedRecordPermissions.canCheckShopping(scope);
    }
    return SharedRecordPermissions.canEdit(
      scope: scope,
      accountId: account,
      creator: creator,
      type: conflict.recordType.name,
      assignees:
          (conflict.remotePayload?['assigneeAccountIds'] as List? ?? const [])
              .whereType<String>(),
    );
  }

  bool _canKeepRemote(CollaborationState state, SharedConflict conflict) =>
      state.localAccessAllowed &&
      state.scopes.any(
        (scope) =>
            scope.id == conflict.scopeId && scope.canRead && !scope.deleted,
      );

  String _remoteLabel(CollaborationState state, SharedConflict conflict) {
    final actor = conflict.remoteUpdatedByAccountId;
    final member = state
        .membersForScope(conflict.scopeId)
        .where((row) => row.accountId == actor)
        .firstOrNull;
    return member == null
        ? context.l10n.sharingRemoteVersion
        : '${context.l10n.sharingRemoteVersion} · ${sharingMemberLabel(context, member)}';
  }

  Future<void> _resolve(SharedConflict conflict, bool keepLocal) async {
    setState(() => _busyId = conflict.id);
    try {
      await widget.guard.controller.resolveConflict(
        conflictId: conflict.id,
        keepLocal: keepLocal,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(sharingErrorMessage(context, error))),
        );
      }
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Widget _version(
    String title,
    Map<String, dynamic>? payload, {
    SharedConflict? conflict,
    bool local = false,
  }) {
    final l = context.l10n;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 10),
            if (payload == null)
              Text(l.sharingDeletedVersion)
            else if (conflict?.recordType == SharedRecordType.idea)
              IdeaConflictPreview(
                key: ValueKey(_previewKey(conflict!, local)),
                board: IdeaBoard.fromJson(payload),
                scopeId: conflict.scopeId,
                onReady: (value) {
                  final key = _previewKey(conflict, local);
                  if (mounted && _ideaPreviews[key] != value) {
                    setState(() => _ideaPreviews[key] = value);
                  }
                },
              )
            else ...[
              Text(
                '${payload['title'] ?? ''}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (payload['notes'] != null) Text('${payload['notes']}'),
              if (payload['description'] != null)
                Text('${payload['description']}'),
              if (payload['quantity'] != null)
                Text('${l.organizerQuantity}: ${payload['quantity']}'),
              if (payload['isChecked'] is bool)
                Text(
                  payload['isChecked'] == true
                      ? l.organizerBought
                      : l.organizerShopping,
                ),
              if (payload['isCompleted'] is bool)
                Text(
                  payload['isCompleted'] == true
                      ? l.organizerCompleted
                      : l.organizerTasks,
                ),
              if (payload['dueAt'] is String &&
                  DateTime.tryParse(payload['dueAt'] as String) != null)
                Text(
                  organizerDate(
                    context,
                    DateTime.parse(payload['dueAt'] as String),
                  ),
                ),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(l.sharingMoreDetails),
                children: [
                  SelectableText(
                    const JsonEncoder.withIndent('  ').convert(payload),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return ref
        .watch(collaborationProvider)
        .when(
          loading: () => const CircularProgressIndicator(),
          error: (error, _) => Text(sharingErrorMessage(context, error)),
          data: (state) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l.sharingConflictDescription),
              if (state.conflicts.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(l.sharingNoConflicts),
                ),
              for (final conflict in state.conflicts) ...[
                const SizedBox(height: 24),
                Text(
                  state.scopes
                          .where((scope) => scope.id == conflict.scopeId)
                          .firstOrNull
                          ?.name ??
                      l.sharingShared,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                LayoutBuilder(
                  builder: (context, constraints) => constraints.maxWidth >= 600
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _version(
                                l.sharingLocalVersion,
                                conflict.localPayload,
                                conflict: conflict,
                                local: true,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _version(
                                _remoteLabel(state, conflict),
                                conflict.remotePayload,
                                conflict: conflict,
                              ),
                            ),
                          ],
                        )
                      : Column(
                          children: [
                            _version(
                              l.sharingLocalVersion,
                              conflict.localPayload,
                              conflict: conflict,
                              local: true,
                            ),
                            _version(
                              _remoteLabel(state, conflict),
                              conflict.remotePayload,
                              conflict: conflict,
                            ),
                          ],
                        ),
                ),
                if (conflict.remoteDeleted ||
                    conflict.reason == 'record_deleted')
                  Text(l.sharingDeletedConflict)
                else if ({
                  'parent_missing',
                  'live_children',
                  'requires_remote_resolution',
                }.contains(conflict.reason))
                  Text(l.sharingRelatedConflict),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    FilledButton(
                      onPressed:
                          _busyId != null ||
                              !_ready(conflict) ||
                              {
                                'parent_missing',
                                'live_children',
                                'requires_remote_resolution',
                              }.contains(conflict.reason) ||
                              !_canKeepLocal(state, conflict)
                          ? null
                          : () => _resolve(conflict, true),
                      child: Text(
                        conflict.remoteDeleted
                            ? l.sharingRestoreRecord
                            : l.sharingKeepLocal,
                      ),
                    ),
                    OutlinedButton(
                      onPressed:
                          _busyId != null ||
                              !_ready(conflict) ||
                              !_canKeepRemote(state, conflict)
                          ? null
                          : () => _resolve(conflict, false),
                      child: Text(l.sharingKeepRemote),
                    ),
                  ],
                ),
              ],
              if (state.pendingCount > 0 ||
                  state.conflicts.isNotEmpty ||
                  state.blockedCount > 0) ...[
                const SizedBox(height: 24),
                Text(l.sharingSaveDraftsDescription),
                TextButton.icon(
                  onPressed: () => exportSharingDrafts(context, ref),
                  icon: const Icon(Icons.file_download_outlined, size: 18),
                  label: Text(l.sharingSaveDrafts),
                ),
              ],
            ],
          ),
        );
  }
}
