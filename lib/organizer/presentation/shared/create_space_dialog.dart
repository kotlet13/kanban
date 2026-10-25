import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../data/collaboration_repository.dart' show newSharedId;
import '../../data/space_creation_draft.dart';
import '../../domain/shared_payload_validation.dart' show validateSharedText;
import '../../state/local_database_provider.dart';
import '../../state/collaboration_provider.dart';
import '../../state/local_spaces_provider.dart';
import 'content_moderation.dart';
import 'sharing_errors.dart';
import 'sharing_session_boundary.dart';

/// The result describes one destination; cloud creation never creates a second
/// local row. Keep unknown outcomes immutable and retry the same server IDs.
class CreatedOrganizerSpace {
  const CreatedOrganizerSpace(this.id, {required this.connected});
  final String id;
  final bool connected;
}

Future<CreatedOrganizerSpace?> showCreateOrganizerSpace(
  BuildContext context, {
  Future<bool> Function()? onAuthenticate,
}) async {
  try {
    final container = ProviderScope.containerOf(context, listen: false);
    final store = SpaceCreationDraftStore(
      await container.read(localDatabaseProvider.future),
    );
    final draft = await store.read();
    if (!context.mounted) return null;
    var resume = true;
    if (draft != null) {
      final choice = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.l10n.spaceFlowPendingCreation),
          content: Text(context.l10n.spaceFlowPendingCreationDescription),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.l10n.cancel),
            ),
            TextButton(
              key: const ValueKey('space-flow-new-local'),
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.l10n.spaceFlowCreateOtherLocal),
            ),
            FilledButton(
              key: const ValueKey('space-flow-resume-create'),
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.l10n.spaceFlowResumeCreate),
            ),
          ],
        ),
      );
      if (!context.mounted || choice == null) return null;
      resume = choice;
    }
    return await showDialog<CreatedOrganizerSpace>(
      context: context,
      barrierDismissible: false,
      builder: (_) => UncontrolledProviderScope(
        container: container,
        child: _CreateSpaceDialog(
          onAuthenticate: onAuthenticate,
          store: store,
          draft: resume ? draft : null,
          allowCloud: resume,
        ),
      ),
    );
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(sharingErrorMessage(context, error))),
      );
    }
    return null;
  }
}

class _CreateSpaceDialog extends ConsumerStatefulWidget {
  const _CreateSpaceDialog({
    this.onAuthenticate,
    required this.store,
    this.draft,
    this.allowCloud = true,
  });
  final SpaceCreationDraftStore store;
  final bool allowCloud;
  final Map<String, dynamic>? draft;
  final Future<bool> Function()? onAuthenticate;
  @override
  ConsumerState<_CreateSpaceDialog> createState() => _CreateSpaceDialogState();
}

class _CreateSpaceDialogState extends ConsumerState<_CreateSpaceDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(), _address = TextEditingController();
  LocalSpaceKind _kind = LocalSpaceKind.household;
  bool _cloud = false, _busy = false, _submitted = false;
  String? _error;
  late final _id = widget.draft?['id'] as String? ?? newSharedId();
  late final _requestId =
      widget.draft?['requestId'] as String? ?? newSharedId();
  @override
  void initState() {
    super.initState();
    final draft = widget.draft;
    if (draft != null) {
      _name.text = draft['name'] as String;
      _address.text = draft['address'] as String;
      _kind = LocalSpaceKind.values.byName(draft['kind'] as String);
      _cloud = true;
      _submitted = true;
    }
  }

  SharingSessionGuard? _guard;
  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    super.dispose();
  }

  String? _cloudTextError(String? value, int limit, {bool empty = false}) {
    if (!_cloud) return null;
    try {
      validateSharedText(value?.trim() ?? '', limit, empty: empty);
      return null;
    } on CollaborationException {
      return context.l10n.sharingValidationError;
    }
  }

  Future<void> _create() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!_cloud) {
        final result = await ref
            .read(localSpacesProvider.notifier)
            .createSpace(
              kind: _kind,
              name: _name.text.trim(),
              address: _address.text.trim(),
            );
        if (mounted) {
          Navigator.pop(
            context,
            CreatedOrganizerSpace(result.id, connected: false),
          );
        }
        return;
      }
      var state = ref.read(collaborationProvider).valueOrNull;
      if (state?.session == null ||
          state!.sessionInvalid ||
          !state.session!.expiresAt.isAfter(DateTime.now())) {
        if (widget.onAuthenticate == null || !await widget.onAuthenticate!()) {
          return;
        }
        if (!mounted) return;
        state = ref.read(collaborationProvider).valueOrNull;
      }
      if (state?.session == null ||
          state!.sessionInvalid ||
          state.deletionPending ||
          !state.session!.expiresAt.isAfter(DateTime.now())) {
        throw const CollaborationException('auth_required');
      }
      if (widget.draft != null &&
          widget.draft!['partition'] != state.session!.partition) {
        throw const CollaborationException('space_creation_wrong_account');
      }
      _guard ??= SharingSessionGuard(context, ref);
      if (!_guard!.isCurrent) {
        throw const CollaborationException('session_changed');
      }
      if (!await showSharedContentPolicy(context)) return;
      if (!mounted || !_guard!.isCurrent) {
        throw const CollaborationException('session_changed');
      }
      // Definite local rejections must leave an editable form and must never
      // become an unresolved, immutable server attempt.
      validateSharedText(_name.text.trim(), 200);
      validateSharedText(_address.text.trim(), 1000, empty: true);
      if (_kind == LocalSpaceKind.organization &&
          ref.read(collaborationProvider).valueOrNull?.organizationsSupported !=
              true) {
        throw const CollaborationException('client_upgrade_required');
      }
      setState(() => _submitted = true);
      await widget.store.save({
        'id': _id,
        'requestId': _requestId,
        'partition': state.session!.partition,
        'name': _name.text.trim(),
        'address': _address.text.trim(),
        'kind': _kind.name,
      });
      if (!mounted || !_guard!.isCurrent) {
        throw const CollaborationException('session_changed');
      }
      final id = await _guard!.controller.createScope(
        _name.text.trim(),
        kind: _kind == LocalSpaceKind.organization
            ? SharedScopeKind.organization
            : SharedScopeKind.household,
        address: _address.text.trim(),
        id: _id,
        requestId: _requestId,
      );
      await widget.store.complete(_requestId);
      if (mounted && _guard!.isCurrent) {
        Navigator.pop(context, CreatedOrganizerSpace(id, connected: true));
      }
    } catch (error) {
      if (mounted) setState(() => _error = sharingErrorMessage(context, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final session = ref.watch(collaborationProvider).valueOrNull?.session;
    final locked = _busy || _submitted;
    final needsLogin =
        session == null ||
        !session.expiresAt.isAfter(DateTime.now()) ||
        ref.watch(collaborationProvider).valueOrNull?.sessionInvalid == true;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        insetPadding: const EdgeInsets.all(12),
        scrollable: true,
        title: Text(l.spacePickerNewSpace),
        content: SizedBox(
          width: 440,
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  key: const ValueKey('sharing-name'),
                  controller: _name,
                  enabled: !locked,
                  maxLength: 200,
                  decoration: InputDecoration(labelText: l.sharingSpaceName),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? l.sharingRequired
                      : _cloudTextError(value, 200),
                ),
                DropdownButtonFormField<LocalSpaceKind>(
                  key: const ValueKey('sharing-kind'),
                  initialValue: _kind,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: l.sharingScopeType),
                  items: [
                    DropdownMenuItem(
                      value: LocalSpaceKind.household,
                      child: Text(l.sharingHousehold),
                    ),
                    DropdownMenuItem(
                      value: LocalSpaceKind.organization,
                      child: Text(l.organizationTitle),
                    ),
                  ],
                  onChanged: locked
                      ? null
                      : (value) => setState(() => _kind = value!),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('sharing-address'),
                  controller: _address,
                  enabled: !locked,
                  maxLength: 1000,
                  decoration: InputDecoration(labelText: l.localSpaceAddress),
                  validator: (value) =>
                      _cloudTextError(value, 1000, empty: true),
                ),
                CheckboxListTile(
                  key: const ValueKey('space-flow-cloud'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(l.spaceFlowCloud),
                  subtitle: Text(l.spaceFlowCloudDescription),
                  value: _cloud,
                  onChanged: locked || !widget.allowCloud
                      ? null
                      : (value) => setState(() => _cloud = value!),
                ),
                if (!widget.allowCloud) Text(l.spaceFlowLocalOnlyPending),
                if (_cloud && session != null)
                  Text(
                    '${session.username} · ${Uri.tryParse(session.serverUrl)?.host ?? session.serverUrl}',
                  ),
                if (_cloud && needsLogin) Text(l.spaceFlowSignInCreate),
                if (_submitted && !_busy)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(l.spaceFlowCreateUnknown),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (_busy) const LinearProgressIndicator(),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: Text(l.cancel),
          ),
          FilledButton(
            key: const ValueKey('sharing-submit'),
            onPressed: _busy ? null : _create,
            child: Text(
              _submitted && !_busy
                  ? l.organizerRetry
                  : _cloud && needsLogin
                  ? l.spaceFlowSignInCreate
                  : l.localSpaceCreate,
            ),
          ),
        ],
      ),
    );
  }
}
