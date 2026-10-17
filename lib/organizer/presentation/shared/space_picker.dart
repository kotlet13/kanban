import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../l10n/l10n.dart';
import '../../state/collaboration_provider.dart';
import 'create_space_dialog.dart';
import '../../state/local_spaces_provider.dart';
import '../../state/organizer_provider.dart';
import '../../domain/organizer_models.dart';

class OrganizerSpacePicker extends ConsumerWidget {
  const OrganizerSpacePicker({
    super.key,
    required this.onSelected,
    required this.onConnect,
    this.compact = false,
    this.onAllSelected,
    this.onLocalSelected,
    this.onAuthenticate,
    this.onLocalProjectSelected,
    this.onSharedProjectSelected,
  });
  final ValueChanged<String?> onSelected;
  final VoidCallback onConnect;
  final Future<bool> Function()? onAuthenticate;
  final bool compact;
  final VoidCallback? onAllSelected;
  final ValueChanged<String>? onLocalSelected;
  final void Function(String spaceId, String projectId)? onLocalProjectSelected;
  final void Function(String scopeId, String projectId)?
  onSharedProjectSelected;
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
      initialProjects:
          chosen?.kind == SharedScopeKind.project && chosen?.isOwner == false,
      initialScopeId: chosen?.id,
    );
    final result = Theme.of(context).platform == TargetPlatform.iOS
        ? await Navigator.of(context).push<_SpaceChoice>(
            MaterialPageRoute(
              fullscreenDialog: true,
              builder: (_) => Scaffold(body: SafeArea(child: panel)),
            ),
          )
        : await showDialog<_SpaceChoice>(
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
    final value = result.value;
    if ((
          ref.read(collaborationProvider).valueOrNull?.session?.partition,
          ref.read(collaborationProvider).valueOrNull?.session?.deviceId,
        ) !=
        identity) {
      return;
    }
    if (value == allAction) {
      if (onAllSelected != null) {
        onAllSelected!();
      } else {
        ref.read(collaborationProvider.notifier).selectAllSpaces();
      }
    } else if (value == createAction) {
      await _create(context, ref);
    } else if (value.startsWith('local:')) {
      final id = value.substring(6);
      final local = ref.read(localSpacesProvider).valueOrNull;
      if (local?.spaces.any((s) => s.id == id && s.binding == null) == true ||
          id == 'local' && local == null) {
        if (result.projectId case final projectId?) {
          final current = ref.read(collaborationProvider).valueOrNull;
          final personal = ref.exists(organizerProvider)
              ? ref.read(organizerProvider).valueOrNull
              : null;
          final snapshot = spacePickerLocalSnapshot(
            id,
            local,
            personal,
            current,
          );
          if (snapshot?.workspaceKey != result.workspaceKey ||
              snapshot?.projects.any((p) => p.id == projectId) != true) {
            return;
          }
          onLocalProjectSelected?.call(id, projectId);
        } else {
          _selectLocal(ref, id);
        }
      }
    } else {
      final current = ref.read(collaborationProvider).valueOrNull;
      if (current?.localAccessAllowed != true ||
          current?.sessionInvalid == true ||
          current?.deletionPending == true ||
          (current?.session?.partition, current?.session?.deviceId) !=
              identity ||
          current?.scopes.any(
                (s) => s.id == value && !s.revoked && !s.deleted && s.canRead,
              ) !=
              true) {
        return;
      }
      if (result.projectId case final projectId?) {
        if (current!
            .dataForScope(value)
            .projects
            .any((p) => p.id == projectId)) {
          onSharedProjectSelected?.call(value, projectId);
        }
      } else {
        onSelected(value);
      }
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

/// Closed selection remains visible when its branch is collapsed or its former
/// access has been revoked.
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

class _SpaceChoice {
  const _SpaceChoice(this.value, {this.projectId, this.workspaceKey});
  final String value;
  final String? projectId, workspaceKey;
}

/// Resolves an exact local source without changing selection or opening storage.
/// The current editor wins over the catalog only for its selected workspace;
/// private snapshots additionally require the active, readable account identity.
OrganizerSnapshot? spacePickerLocalSnapshot(
  String id,
  LocalSpacesState? local,
  OrganizerSnapshot? current,
  CollaborationState? shared,
) {
  // The open editor may already contain a newer personal snapshot than the
  // catalog. Match the workspace and identity before using it for another row.
  if (local?.selectedSpaceId == id &&
      current != null &&
      (current.workspaceKey == id ||
          id == 'local' &&
              shared?.session != null &&
              shared?.localAccessAllowed == true &&
              shared?.sessionInvalid != true &&
              shared?.deletionPending != true &&
              current.workspaceKey ==
                  'private:${shared!.session!.partition}')) {
    return current;
  }
  final snapshot = local?.snapshots[id];
  if (snapshot?.workspaceKey.startsWith('private:') == true &&
      (id != 'local' ||
          shared?.localAccessAllowed != true ||
          shared?.sessionInvalid == true ||
          shared?.deletionPending == true ||
          shared?.session == null ||
          snapshot!.workspaceKey != 'private:${shared!.session!.partition}')) {
    return null;
  }
  if (snapshot != null &&
      !snapshot.workspaceKey.startsWith('private:') &&
      snapshot.workspaceKey != id) {
    return null;
  }
  return snapshot;
}

class _SpaceSelectionPanel extends ConsumerStatefulWidget {
  const _SpaceSelectionPanel({
    required this.initialProjects,
    this.initialScopeId,
  });
  final bool initialProjects;
  final String? initialScopeId;
  @override
  ConsumerState<_SpaceSelectionPanel> createState() =>
      _SpaceSelectionPanelState();
}

class _SpaceSelectionPanelState extends ConsumerState<_SpaceSelectionPanel> {
  late bool _projects = widget.initialProjects;
  final Set<String> _expanded = {};
  bool _initializedExpansion = false;
  String _query = '';
  bool get _searching => _query.trim().isNotEmpty;
  bool _match(String title) =>
      title.toLowerCase().contains(_query.trim().toLowerCase());

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final state = ref.watch(collaborationProvider).valueOrNull;
    final local = ref.watch(localSpacesProvider).valueOrNull;
    final personal = ref.exists(organizerProvider)
        ? ref.watch(organizerProvider).valueOrNull
        : null;
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
    final parents = {
      for (final scope in scopes)
        if (scope.kind != SharedScopeKind.project) scope.id: scope,
    };
    final projects = scopes
        .where((scope) => scope.kind == SharedScopeKind.project)
        .toList();
    if (!_initializedExpansion) {
      final initial = projects
          .where((p) => p.id == widget.initialScopeId)
          .firstOrNull;
      if (initial != null && parents.containsKey(initial.parentSpaceId)) {
        _expanded.add(initial.parentSpaceId!);
      }
      _initializedExpansion = true;
    }
    final selected = state?.allSpacesSelected == true
        ? OrganizerSpacePicker.allAction
        : state?.selectedSpaceId ??
              'local:${local?.selectedSpaceId ?? 'local'}';

    String scopeSubtitle(SharedScope scope) {
      if (scope.kind == SharedScopeKind.project) {
        // A project-only grant confers no parent read/list permission.
        return parents[scope.parentSpaceId]?.name ??
            (scope.isOwner ? l.project : l.spacePickerDirectProject);
      }
      return scope.kind == SharedScopeKind.organization
          ? l.organizationTitle
          : l.sharingHousehold;
    }

    Widget row(
      String value,
      String title,
      IconData icon, {
      String? subtitle,
      String? rowKey,
      String? projectId,
      String? workspaceKey,
      bool? expanded,
    }) => ListTile(
      key: ValueKey('space-choice-${rowKey ?? value}'),
      minVerticalPadding: 12,
      leading: Icon(icon),
      title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: subtitle == null
          ? null
          : Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      selected: projectId == null && value == selected,
      trailing: expanded == null
          ? projectId == null && value == selected
                ? const Icon(Icons.check)
                : null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (value == selected) const Icon(Icons.check),
                IconButton(
                  key: ValueKey('space-picker-expand-$value'),
                  tooltip: expanded
                      ? l.spacePickerCollapseProjects
                      : l.spacePickerExpandProjects,
                  onPressed: _searching
                      ? null
                      : () => setState(() {
                          if (!_expanded.add(value)) _expanded.remove(value);
                        }),
                  icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
                ),
              ],
            ),
      onTap: () => Navigator.pop(
        context,
        _SpaceChoice(value, projectId: projectId, workspaceKey: workspaceKey),
      ),
    );

    Widget archivedGroup(String key, List<Widget> children) => ExpansionTile(
      // Search always exposes archived matches, while clearing it restores the
      // ordinary collapsed archive rather than hiding a matching child.
      key: ValueKey('space-picker-archived-$key${_searching ? '-search' : ''}'),
      initiallyExpanded: _searching,
      title: Text(l.scopeArchivedSection),
      children: children,
    );

    Widget branch(
      String value,
      String title,
      IconData icon,
      String subtitle,
      List<({Widget row, bool archived})> children,
    ) {
      final expanded = _searching || _expanded.contains(value);
      final activeChildren = [
        for (final child in children)
          if (!child.archived) child.row,
      ];
      final archivedChildren = [
        for (final child in children)
          if (child.archived) child.row,
      ];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          row(
            value,
            title,
            icon,
            subtitle: subtitle,
            expanded: children.isEmpty ? null : expanded,
          ),
          if (expanded && children.isNotEmpty)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ...activeChildren,
                  if (archivedChildren.isNotEmpty)
                    archivedGroup(value, archivedChildren),
                ],
              ),
            ),
        ],
      );
    }

    final active = <Widget>[], archived = <Widget>[];
    void add(Widget child, bool isArchived) =>
        (isArchived ? archived : active).add(child);
    if (!_projects || _searching) {
      if (_match(l.allSpacesTitle)) {
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
        final snapshot = spacePickerLocalSnapshot(
          space.id,
          local,
          personal,
          state,
        );
        final children = [
          for (final project in snapshot?.projects ?? <LocalProject>[])
            if (!_searching || _match('$title ${project.title}'))
              (
                row: row(
                  'local:${space.id}',
                  project.title,
                  project.archived
                      ? Icons.inventory_2_outlined
                      : Icons.folder_outlined,
                  rowKey: 'local-project:${space.id}:${project.id}',
                  projectId: project.id,
                  workspaceKey: snapshot!.workspaceKey,
                ),
                archived: project.archived,
              ),
        ];
        if (!_match(title) && children.isEmpty) continue;
        add(
          branch(
            'local:${space.id}',
            title,
            _localIcon(space.kind),
            l.localSpaceState,
            children,
          ),
          space.archived,
        );
      }
      for (final scope in parents.values) {
        final subtitle = scopeSubtitle(scope);
        final childScopes = projects
            .where((p) => p.parentSpaceId == scope.id)
            .toList();
        final representedIds = {
          for (final project in childScopes)
            project.projectRootId ?? project.id,
        };
        final children = [
          for (final project in childScopes)
            if (!_searching || _match('${scope.name} ${project.name}'))
              (
                row: row(
                  project.id,
                  project.name,
                  _scopeIcon(project),
                  subtitle: scopeSubtitle(project),
                ),
                archived: project.archived,
              ),
          for (final project in state!.dataForScope(scope.id).projects)
            if (!representedIds.contains(project.id) &&
                (!_searching || _match('${scope.name} ${project.title}')))
              (
                row: row(
                  scope.id,
                  project.title,
                  project.archived
                      ? Icons.inventory_2_outlined
                      : Icons.folder_outlined,
                  rowKey: 'shared-project:${scope.id}:${project.id}',
                  projectId: project.id,
                ),
                archived: project.archived,
              ),
        ];
        if (!_match('${scope.name} $subtitle') && children.isEmpty) continue;
        add(
          branch(scope.id, scope.name, _scopeIcon(scope), subtitle, children),
          scope.archived,
        );
      }
      for (final project in projects.where(
        (p) => p.isOwner && !parents.containsKey(p.parentSpaceId),
      )) {
        final subtitle = scopeSubtitle(project);
        if (!_match('${project.name} $subtitle')) continue;
        add(
          row(
            project.id,
            project.name,
            _scopeIcon(project),
            subtitle: subtitle,
          ),
          project.archived,
        );
      }
    }
    if (_projects || _searching) {
      final sharedActive = <Widget>[], sharedArchived = <Widget>[];
      for (final project in projects.where(
        (p) =>
            !p.isOwner &&
            (!_searching || !parents.containsKey(p.parentSpaceId)),
      )) {
        final subtitle = scopeSubtitle(project);
        if (!_match('${project.name} $subtitle')) continue;
        (project.archived ? sharedArchived : sharedActive).add(
          row(
            project.id,
            project.name,
            _scopeIcon(project),
            subtitle: subtitle,
          ),
        );
      }
      if (_searching &&
          (sharedActive.isNotEmpty || sharedArchived.isNotEmpty)) {
        active.add(
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 4),
            child: Text(
              l.spacePickerSharedWithMe,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
        );
      }
      active.addAll(sharedActive);
      archived.addAll(sharedArchived);
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
              if (archived.isNotEmpty) archivedGroup('$_projects', archived),
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
          onPressed: () => Navigator.pop(
            context,
            const _SpaceChoice(OrganizerSpacePicker.createAction),
          ),
          icon: const Icon(Icons.add),
          label: Text(l.spacePickerCreateAction),
        ),
      ],
    );
  }
}
