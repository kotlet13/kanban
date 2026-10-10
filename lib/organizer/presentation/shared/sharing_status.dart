import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../state/collaboration_provider.dart';
import 'sharing_errors.dart';
import 'sharing_status_projection.dart';
import 'sharing_status_dialog.dart';
export 'sharing_status_dialog.dart' show SharingStatusDetailsBuilder;
export 'sharing_status_projection.dart' show SharingStatusSupplement;

class SharingStatus extends ConsumerWidget {
  const SharingStatus({
    super.key,
    required this.state,
    required this.onSync,
    required this.onConflicts,
    this.onExport,
    this.onConnect,
    this.scopeId,
    this.privateSync = false,
    this.allowLocalActions = false,
    this.busyListenable,
    this.detailsBuilder,
    this.supplementListenable,
  });
  static const width = 88.0;
  static const height = 48.0;
  final CollaborationState state;
  final VoidCallback onSync, onConflicts;
  final VoidCallback? onExport, onConnect;
  final String? scopeId;
  final bool privateSync, allowLocalActions;
  final ValueListenable<bool>? busyListenable;
  final SharingStatusDetailsBuilder? detailsBuilder;
  final ValueListenable<SharingStatusSupplement>? supplementListenable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backgroundError = ref.watch(collaborationBackgroundErrorProvider);
    Widget indicator(bool busy) => supplementListenable == null
        ? _indicator(
            context,
            busy,
            const SharingStatusSupplement(),
            backgroundError,
          )
        : ValueListenableBuilder<SharingStatusSupplement>(
            valueListenable: supplementListenable!,
            builder: (context, supplement, _) =>
                _indicator(context, busy, supplement, backgroundError),
          );
    return busyListenable == null
        ? indicator(false)
        : ValueListenableBuilder<bool>(
            valueListenable: busyListenable!,
            builder: (context, busy, _) => indicator(busy),
          );
  }

  Widget _indicator(
    BuildContext context,
    bool busy,
    SharingStatusSupplement supplement,
    Object? backgroundError,
  ) {
    final projection = SharingStatusProjection.fromState(
      state,
      now: DateTime.now(),
      privateSync: privateSync,
      busy: busy,
      scopeId: scopeId,
      supplement: supplement,
      backgroundError: backgroundError,
    );
    final scheme = Theme.of(context).colorScheme;
    final icon = switch (projection.status) {
      SharingSyncStatus.synced => Icons.cloud_done_outlined,
      SharingSyncStatus.offline ||
      SharingSyncStatus.local => Icons.cloud_off_outlined,
      _ => Icons.cloud_outlined,
    };
    final color = switch (projection.status) {
      SharingSyncStatus.synced =>
        Theme.of(context).brightness == Brightness.dark
            ? Colors.green.shade300
            : Colors.green.shade700,
      SharingSyncStatus.problem => scheme.error,
      _ => scheme.onSurfaceVariant,
    };
    final label = sharingStatusLabel(context, projection.status);
    return SizedBox(
      key: const ValueKey('sharing-sync-status-slot'),
      width: width,
      height: height,
      child: Row(
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: IconButton(
              key: const ValueKey('sharing-sync-status-cloud'),
              tooltip: '${context.l10n.syncStatusDetails}: $label',
              onPressed: () => showSharingStatusDetails(
                context,
                state: state,
                onSync: onSync,
                onConflicts: onConflicts,
                onExport: onExport,
                onConnect: onConnect,
                scopeId: scopeId,
                privateSync: privateSync,
                allowLocalActions: allowLocalActions,
                busyListenable: busyListenable,
                detailsBuilder: detailsBuilder,
                supplementListenable: supplementListenable,
              ),
              icon: projection.status == SharingSyncStatus.problem
                  ? SizedBox(
                      width: 24,
                      height: 24,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Icon(icon, color: color, size: 24),
                          Positioned(
                            right: -3,
                            bottom: -2,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: scheme.surface,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.error, color: color, size: 12),
                            ),
                          ),
                        ],
                      ),
                    )
                  : Icon(icon, color: color, size: 24),
            ),
          ),
          SizedBox(
            width: 40,
            height: 48,
            child: Center(
              child: ExcludeSemantics(
                child: _SyncRefresh(active: state.isSyncing || busy),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SyncRefresh extends StatefulWidget {
  const _SyncRefresh({required this.active});
  final bool active;
  @override
  State<_SyncRefresh> createState() => _SyncRefreshState();
}

class _SyncRefreshState extends State<_SyncRefresh>
    with SingleTickerProviderStateMixin {
  late final _rotation = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _update();
  }

  @override
  void didUpdateWidget(covariant _SyncRefresh oldWidget) {
    super.didUpdateWidget(oldWidget);
    _update();
  }

  void _update() {
    if (widget.active &&
        !MediaQuery.disableAnimationsOf(context) &&
        !MediaQuery.accessibleNavigationOf(context) &&
        TickerMode.valuesOf(context).enabled) {
      if (!_rotation.isAnimating) _rotation.repeat();
    } else {
      _rotation.stop();
      _rotation.value = 0;
    }
  }

  @override
  void dispose() {
    _rotation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    const icon = Icon(Icons.refresh, size: 20);
    return SizedBox(
      width: 20,
      height: 20,
      child: !widget.active
          ? const SizedBox.shrink()
          : reduceMotion
          ? icon
          : RotationTransition(
              key: const ValueKey('sharing-sync-refresh-rotation'),
              turns: _rotation,
              child: icon,
            ),
    );
  }
}

class SharingScopePicker extends StatelessWidget {
  const SharingScopePicker({
    super.key,
    required this.scopes,
    required this.selectedId,
    required this.onChanged,
  });
  final List<SharedScope> scopes;
  final String? selectedId;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    key: ValueKey('sharing-scope-$selectedId'),
    initialValue: scopes.any((scope) => scope.id == selectedId)
        ? selectedId
        : null,
    isExpanded: true,
    decoration: InputDecoration(labelText: context.l10n.sharingChooseSpace),
    items: [
      for (final scope in scopes)
        DropdownMenuItem(
          value: scope.id,
          child: Text(
            '${scope.name} · ${sharingRoleLabel(context, scope.role)}',
            overflow: TextOverflow.ellipsis,
          ),
        ),
    ],
    onChanged: (value) {
      if (value != null) onChanged(value);
    },
  );
}
