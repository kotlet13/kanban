import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../l10n/l10n.dart';
import '../../state/collaboration_provider.dart';
import '../../state/local_spaces_provider.dart';
import '../shared/sharing_errors.dart';
import '../shared/sharing_session_boundary.dart';

class LocalSpaceConnectionPanel extends ConsumerStatefulWidget {
  const LocalSpaceConnectionPanel({super.key});
  @override
  ConsumerState<LocalSpaceConnectionPanel> createState() =>
      _LocalSpaceConnectionPanelState();
}

class _LocalSpaceConnectionPanelState
    extends ConsumerState<LocalSpaceConnectionPanel> {
  final _selected = <String>{};
  bool _busy = false, _previewOpen = false;
  String? _error;
  bool _online(CollaborationState state) =>
      state.session != null &&
      !state.sessionInvalid &&
      !state.deletionPending &&
      state.session!.expiresAt.isAfter(DateTime.now());
  Future<void> _connect() async {
    if (_busy || _selected.isEmpty) return;
    final guard = SharingSessionGuard(context, ref);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final preview = await guard.controller.previewLocalSpacesPublication(
        _selected.toList()..sort(),
      );
      if (!mounted || !guard.isCurrent) return;
      setState(() => _previewOpen = true);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => SharingSessionBoundary(
          guard: guard,
          visibleWhen: _online,
          child: AlertDialog(
            scrollable: true,
            title: Text(context.l10n.localSpaceLinkAction),
            content: SizedBox(
              width: 540,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    preview.accountName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(preview.serverUrl),
                  const SizedBox(height: 16),
                  Text(context.l10n.localSpaceConnectionPreview),
                  for (final item in preview.spaces) ...[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(item.space.name),
                      subtitle: Text(
                        context.l10n.localSpaceConnectionCounts(
                          item.recordCount,
                          item.gardenCount,
                        ),
                      ),
                    ),
                    if (item.linkedPaymentCount > 0)
                      Text(
                        context.l10n.paymentPublicationCount(
                          item.linkedPaymentCount,
                        ),
                      ),
                    for (final project in item.projects)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(start: 16),
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.folder_outlined),
                          title: Text(project.name),
                          subtitle: Text(
                            context.l10n.localSpaceConnectionProjectCounts(
                              project.taskCount,
                              project.financeCount,
                              project.personCount,
                              project.accountCount,
                            ),
                          ),
                        ),
                      ),
                    if (item.space.kind == LocalSpaceKind.organization &&
                        item.projects.isNotEmpty)
                      Text(context.l10n.organizationProjectFinanceVisibility),
                  ],
                  for (final issue in preview.issues)
                    Text(
                      sharingErrorMessage(
                        context,
                        CollaborationException(issue),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(context.l10n.cancel),
              ),
              FilledButton(
                key: const ValueKey('confirm-space-connection'),
                onPressed: preview.canPublish
                    ? () => Navigator.pop(context, true)
                    : null,
                child: Text(context.l10n.localSpaceLinkAction),
              ),
            ],
          ),
        ),
      );
      if (confirmed == true &&
          mounted &&
          guard.isCurrent &&
          _online(ref.read(collaborationProvider).requireValue)) {
        await guard.controller.publishLocalSpaces(preview);
        if (mounted) setState(_selected.clear);
      }
    } catch (error) {
      if (mounted) setState(() => _error = sharingErrorMessage(context, error));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _previewOpen = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final shared = ref.watch(collaborationProvider).valueOrNull;
    final catalog = ref.watch(localSpacesProvider).valueOrNull;
    if (shared == null || !_online(shared) || catalog == null) {
      return const SizedBox.shrink();
    }
    final available = catalog.spaces
        .where(
          (space) =>
              space.kind != LocalSpaceKind.personal && space.binding == null,
        )
        .toList();
    if (available.isEmpty) return const SizedBox.shrink();
    _selected.removeWhere((id) => !available.any((space) => space.id == id));
    final l = context.l10n;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l.localSpaceLinkAction,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(l.localSpaceConnectionChoose),
            for (final space in available)
              CheckboxListTile(
                key: ValueKey('connect-local-space-${space.id}'),
                contentPadding: EdgeInsets.zero,
                title: Text(space.name),
                value: _selected.contains(space.id),
                onChanged: _busy
                    ? null
                    : (value) => setState(() {
                        if (value == true) {
                          _selected.add(space.id);
                        } else {
                          _selected.remove(space.id);
                        }
                      }),
              ),
            if (_error != null) Text(_error!),
            if (_busy && !_previewOpen) const LinearProgressIndicator(),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                key: const ValueKey('preview-space-connection'),
                onPressed: _busy || _selected.isEmpty ? null : _connect,
                icon: const Icon(Icons.cloud_upload_outlined),
                label: Text(l.localSpaceLinkAction),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
