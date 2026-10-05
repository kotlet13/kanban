import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../l10n/l10n.dart';
import '../../state/collaboration_provider.dart';
import '../shared/sharing_errors.dart';
import 'finance_access_guard.dart';
import 'finance_snapshot_view.dart';

Future<void> showFinanceConflicts(
  BuildContext context,
  WidgetRef ref,
  String scopeId,
) {
  final guard = FinanceAccessGuard(context, ref, scopeId);
  return showDialog<void>(
    context: context,
    builder: (context) => guard.wrap(
      AlertDialog(
        title: Text(context.l10n.financeConflicts),
        content: SizedBox(
          width: 680,
          child: SingleChildScrollView(child: _FinanceConflicts(guard: guard)),
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

class _FinanceConflicts extends ConsumerStatefulWidget {
  const _FinanceConflicts({required this.guard});
  final FinanceAccessGuard guard;
  @override
  ConsumerState<_FinanceConflicts> createState() => _FinanceConflictsState();
}

class _FinanceConflictsState extends ConsumerState<_FinanceConflicts> {
  bool _busy = false;
  Future<void> _resolve(SharedFinanceConflict conflict, bool keepLocal) async {
    setState(() => _busy = true);
    try {
      await widget.guard.controller.resolveFinanceConflict(
        conflictId: conflict.id,
        keepLocal: keepLocal,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(sharingErrorMessage(context, e))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(collaborationProvider).valueOrNull;
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.sharingConflictDescription),
        for (final conflict
            in state?.financeConflicts.where(
                  (c) => c.scopeId == widget.guard.scopeId,
                ) ??
                <SharedFinanceConflict>[])
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    sharingErrorMessage(
                      context,
                      CollaborationException(conflict.reason),
                    ),
                  ),
                  ExpansionTile(
                    title: Text(l.sharingLocalVersion),
                    children: [
                      FinanceSnapshotView(
                        scopeId: widget.guard.scopeId,
                        value: conflict.localPayload,
                      ),
                    ],
                  ),
                  ExpansionTile(
                    title: Text(l.sharingRemoteVersion),
                    children: [
                      FinanceSnapshotView(
                        scopeId: widget.guard.scopeId,
                        value: conflict.remotePayload,
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      if (state
                                  ?.financePolicyForScope(widget.guard.scopeId)
                                  .canWrite ==
                              true &&
                          !conflict.remoteDeleted)
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _resolve(conflict, true),
                          child: Text(l.sharingKeepLocal),
                        ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _resolve(conflict, false),
                        child: Text(l.sharingKeepRemote),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
