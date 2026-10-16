import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../l10n/l10n.dart';
import '../../state/collaboration_provider.dart';
import 'create_space_dialog.dart';
import '../../state/local_spaces_provider.dart';

class OrganizerSpacePicker extends ConsumerWidget {
  const OrganizerSpacePicker({
    super.key,
    required this.onSelected,
    required this.onConnect,
    this.compact = false,
    this.onAllSelected,
    this.onLocalSelected,
    this.onAuthenticate,
  });
  final ValueChanged<String?> onSelected;
  final VoidCallback onConnect;
  final Future<bool> Function()? onAuthenticate;
  final bool compact;
  final VoidCallback? onAllSelected;
  final ValueChanged<String>? onLocalSelected;
  static const allAction = 'all-spaces';
  static const createAction = 'create-space';
  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final result = await showCreateOrganizerSpace(
      context,
      onAuthenticate: onAuthenticate,
    );
    if (!context.mounted || result == null) return;
    if (result.connected) {
      onSelected(result.id);
    } else {
      _selectLocal(ref, result.id);
    }
  }

  void _selectLocal(WidgetRef ref, String id) {
    if (onLocalSelected != null) {
      onLocalSelected!(id);
    } else {
      ref.read(collaborationProvider.notifier).selectSpace(null);
      ref.read(localSpacesProvider.notifier).selectSpace(id);
      onSelected(null);
    }
  }

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final before = ref.read(collaborationProvider).valueOrNull;
    final identity = (before?.session?.partition, before?.session?.deviceId);
    final chosen = before?.scopes
        .where((s) => s.id == before.selectedSpaceId)
        .firstOrNull;
    final panel = _SpaceSelectionPanel(
      initialProjects: chosen?.kind == SharedScopeKind.project,
    );
    final result = Theme.of(context).platform == TargetPlatform.iOS
        ? await Navigator.of(context).push<String>(
            MaterialPageRoute(
              fullscreenDialog: true,
              builder: (_) => Scaffold(body: SafeArea(child: panel)),
            ),
          )
        : await showDialog<String>(
            context: context,
            builder: (context) => Dialog(
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                width: 560,
                height: (MediaQuery.sizeOf(context).height - 64).clamp(
                  240,
                  680,
                ),
                child: panel,
              ),
            ),
          );
    if (result == null || !context.mounted) return;
    if (result == allAction) {
      if (onAllSelected != null) {
        onAllSelected!();
      } else {
        ref.read(collaborationProvider.notifier).selectAllSpaces();
      }
    } else if (result == createAction) {
      await _create(context, ref);
    } else if (result.startsWith('local:')) {
      final id = result.substring(6);
      final local = ref.read(localSpacesProvider).valueOrNull;
      if (local?.spaces.any((s) => s.id == id && s.binding == null) == true ||
          id == 'local' && local == null) {
        _selectLocal(ref, id);
      }
    } else {
      final current = ref.read(collaborationProvider).valueOrNull;
      if (current?.localAccessAllowed != true ||
          current?.sessionInvalid == true ||
          current?.deletionPending == true ||
          (current?.session?.partition, current?.session?.deviceId) !=
              identity ||
          current?.scopes.any(
                (s) => s.id == result && !s.revoked && !s.deleted && s.canRead,
              ) !=
              true) {
        return;
      }
      onSelected(result);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(collaborationProvider).valueOrNull;
    final local = ref.watch(localSpacesProvider).valueOrNull;
    final l = context.l10n;
    final chosen = state?.selectedSpaceId;
    final scope = state?.scopes.where((s) => s.id == chosen).firstOrNull;
    final all = state?.allSpacesSelected == true;
    final space = local?.selectedSpace;
    final label = all
        ? l.allSpacesTitle
        : chosen == null
        ? space == null || space.name.isEmpty
              ? l.organizerPersonal
              : space.name
        : scope == null || scope.revoked || scope.deleted
        ? l.sharingAccessRevoked
        : scope.name;
    final icon = all
        ? Icons.dashboard_outlined
        : chosen == null
        ? _localIcon(space?.kind ?? LocalSpaceKind.personal)
        : scope == null || scope.revoked || scope.deleted
        ? Icons.lock_outline
        : _scopeIcon(scope);
    final value = all
        ? allAction
        : chosen ?? 'local:${local?.selectedSpaceId ?? 'local'}';
    final button = OrganizerSpacePickerButton(
      key: ValueKey('active-space-${state?.session?.partition}-$chosen'),
      value: value,
      label: label,
      icon: icon,
      compact: compact,
      onPressed: () => _open(context, ref),
    );
    return compact
        ? Material(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: button,
          )
        : InputDecorator(
            decoration: InputDecoration(labelText: l.spacePickerTitle),
            child: button,
          );
  }
}

/// Closed selection remains visible even when its project is in the separate
/// project list, or when its former access has been revoked.
class OrganizerSpacePickerButton extends StatelessWidget {
  const OrganizerSpacePickerButton({
    super.key,
    required this.value,
    required this.label,
    required this.icon,
    required this.onPressed,
    required this.compact,
  });
  final String value, label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool compact;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: '${context.l10n.spacePickerTitle}: $label',
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onPressed,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 0,
            vertical: 10,
          ),
          child: Row(
            children: [
              if (compact) ...[
                Icon(
                  icon,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: compact
                      ? Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        )
                      : Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.expand_more,
                size: compact ? 20 : 24,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

IconData _localIcon(LocalSpaceKind kind) => switch (kind) {
  LocalSpaceKind.personal => Icons.person_outline,
  LocalSpaceKind.household => Icons.home_outlined,
  LocalSpaceKind.organization => Icons.business_outlined,
};
IconData _scopeIcon(SharedScope scope) => scope.archived
    ? Icons.inventory_2_outlined
    : switch (scope.kind) {
        SharedScopeKind.personal => Icons.person_outline,
        SharedScopeKind.household => Icons.home_outlined,
        SharedScopeKind.organization => Icons.business_outlined,
        SharedScopeKind.project => Icons.folder_outlined,
      };

class _SpaceSelectionPanel extends ConsumerStatefulWidget {
  const _SpaceSelectionPanel({required this.initialProjects});
  final bool initialProjects;
  @override
  ConsumerState<_SpaceSelectionPanel> createState() =>
      _SpaceSelectionPanelState();
}

class _SpaceSelectionPanelState extends ConsumerState<_SpaceSelectionPanel> {
  late bool _projects = widget.initialProjects;
  String _query = '';
  bool _match(String title) =>
      title.toLowerCase().contains(_query.toLowerCase());
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final state = ref.watch(collaborationProvider).valueOrNull;
    final local = ref.watch(localSpacesProvider).valueOrNull;
    final scopes =
        (state?.localAccessAllowed == true &&
                    state?.sessionInvalid != true &&
                    state?.deletionPending != true
                ? state?.scopes
                : null)
            ?.where(
              (s) =>
                  s.kind != SharedScopeKind.personal &&
                  !s.revoked &&
                  !s.deleted &&
                  s.canRead,
            )
            .toList() ??
        <SharedScope>[];
    final spaces =
        local?.spaces.where((s) => s.binding == null).toList() ??
        <LocalSpace>[];
    final selected = state?.allSpacesSelected == true
        ? OrganizerSpacePicker.allAction
        : state?.selectedSpaceId ??
              'local:${local?.selectedSpaceId ?? 'local'}';
    String scopeSubtitle(SharedScope scope) {
      if (scope.kind == SharedScopeKind.project) {
        // A project-only grant confers no parent read/list permission.
        final parent = scopes
            .where(
              (s) =>
                  s.id == scope.parentSpaceId &&
                  s.kind != SharedScopeKind.project,
            )
            .firstOrNull;
        return parent?.name ?? l.spacePickerDirectProject;
      }
      return scope.kind == SharedScopeKind.organization
          ? l.organizationTitle
          : l.sharingHousehold;
    }

    Widget row(String value, String title, IconData icon, {String? subtitle}) =>
        ListTile(
          key: ValueKey('space-choice-$value'),
          minVerticalPadding: 12,
          leading: Icon(icon),
          title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: subtitle == null
              ? null
              : Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
          selected: value == selected,
          trailing: value == selected ? const Icon(Icons.check) : null,
          onTap: () => Navigator.pop(context, value),
        );
    final active = <Widget>[], archived = <Widget>[];
    if (!_projects) {
      if (_query.isEmpty || _match(l.allSpacesTitle)) {
        active.add(
          row(
            OrganizerSpacePicker.allAction,
            l.allSpacesTitle,
            Icons.dashboard_outlined,
          ),
        );
      }
      if (spaces.isEmpty && _match(l.organizerPersonal)) {
        active.add(
          row('local:local', l.organizerPersonal, Icons.person_outline),
        );
      }
      for (final space in spaces) {
        final title = space.name.isEmpty ? l.organizerPersonal : space.name;
        if (!_match(title)) continue;
        (space.archived ? archived : active).add(
          row(
            'local:${space.id}',
            title,
            _localIcon(space.kind),
            subtitle: l.localSpaceState,
          ),
        );
      }
    }
    for (final scope in scopes.where(
      (s) => _projects
          ? s.kind == SharedScopeKind.project
          : s.kind != SharedScopeKind.project,
    )) {
      final subtitle = scopeSubtitle(scope);
      if (!_match('${scope.name} $subtitle')) continue;
      (scope.archived ? archived : active).add(
        row(scope.id, scope.name, _scopeIcon(scope), subtitle: subtitle),
      );
    }
    Widget tab(bool projects, String label, IconData icon) => Semantics(
      selected: _projects == projects,
      child: TextButton(
        key: ValueKey(
          projects ? 'space-picker-projects' : 'space-picker-spaces',
        ),
        style: TextButton.styleFrom(
          backgroundColor: _projects == projects
              ? Theme.of(context).colorScheme.primaryContainer
              : null,
          minimumSize: const Size(48, 48),
        ),
        onPressed: () => setState(() => _projects = projects),
        child: Row(
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 20, top: 8, end: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l.spacePickerTitle,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: l.close,
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final stacked =
                  MediaQuery.textScalerOf(context).scale(14) > 20 &&
                  constraints.maxWidth < 400;
              final spaces = tab(
                false,
                l.spacePickerSpaces,
                Icons.home_outlined,
              );
              final projects = tab(
                true,
                l.spacePickerSharedWithMe,
                Icons.folder_shared_outlined,
              );
              return stacked
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [spaces, const SizedBox(height: 4), projects],
                    )
                  : Row(
                      children: [
                        Expanded(child: spaces),
                        const SizedBox(width: 8),
                        Expanded(child: projects),
                      ],
                    );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            key: const ValueKey('space-picker-search'),
            decoration: InputDecoration(
              labelText: l.spacePickerSearch,
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
        ),
        Expanded(
          child: ListView(
            key: ValueKey(
              _projects
                  ? 'space-picker-project-list'
                  : 'space-picker-space-list',
            ),
            children: [
              ...active,
              if (archived.isNotEmpty)
                ExpansionTile(
                  key: ValueKey('space-picker-archived-$_projects'),
                  title: Text(l.scopeArchivedSection),
                  children: archived,
                ),
              if (active.isEmpty && archived.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(l.spacePickerNoResults),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        TextButton.icon(
          onPressed: () =>
              Navigator.pop(context, OrganizerSpacePicker.createAction),
          icon: const Icon(Icons.add),
          label: Text(l.spacePickerCreateAction),
        ),
      ],
    );
  }
}
