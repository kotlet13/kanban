import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../state/collaboration_provider.dart';
import '../organizer_widgets.dart';
import 'sharing_errors.dart';
import 'sharing_recovery.dart';
import 'sharing_session_boundary.dart';

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

  Widget _version(String title, Map<String, dynamic>? payload) {
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
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _version(
                                l.sharingRemoteVersion,
                                conflict.remotePayload,
                              ),
                            ),
                          ],
                        )
                      : Column(
                          children: [
                            _version(
                              l.sharingLocalVersion,
                              conflict.localPayload,
                            ),
                            _version(
                              l.sharingRemoteVersion,
                              conflict.remotePayload,
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
                              conflict.remoteDeleted ||
                              {
                                'record_deleted',
                                'parent_missing',
                                'live_children',
                                'requires_remote_resolution',
                              }.contains(conflict.reason) ||
                              !(state.scopes
                                      .where(
                                        (scope) => scope.id == conflict.scopeId,
                                      )
                                      .firstOrNull
                                      ?.canEdit ??
                                  false)
                          ? null
                          : () => _resolve(conflict, true),
                      child: Text(l.sharingKeepLocal),
                    ),
                    OutlinedButton(
                      onPressed:
                          _busyId != null ||
                              !(state.scopes
                                      .where(
                                        (scope) => scope.id == conflict.scopeId,
                                      )
                                      .firstOrNull
                                      ?.canEdit ??
                                  false)
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
