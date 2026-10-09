import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/l10n.dart';
import '../state/organizer_provider.dart';
import '../state/collaboration_provider.dart';

/// A personal form belongs to the workspace it opened in. An anonymous form
/// may survive an unrelated login while that same local workspace stays active.
class PersonalWorkspaceGuard {
  PersonalWorkspaceGuard(BuildContext context, WidgetRef ref, this.workspaceKey)
    : _context = context,
      _container = ProviderScope.containerOf(context, listen: false),
      _partition = !workspaceKey.startsWith('private:')
          ? null
          : ref.read(collaborationProvider).valueOrNull?.session?.partition,
      _deviceId = !workspaceKey.startsWith('private:')
          ? null
          : ref.read(collaborationProvider).valueOrNull?.session?.deviceId;
  final BuildContext _context;
  final ProviderContainer _container;
  final String workspaceKey;
  final String? _partition, _deviceId;
  bool get isCurrent {
    if (!_context.mounted) return false;
    final personal = _container.read(organizerProvider).valueOrNull;
    if (personal?.workspaceKey != workspaceKey) return false;
    if (!workspaceKey.startsWith('private:')) return true;
    final shared = _container.read(collaborationProvider).valueOrNull;
    return shared?.localAccessAllowed == true &&
        shared?.session?.partition == _partition &&
        shared?.session?.deviceId == _deviceId &&
        shared?.scopes.any(
              (scope) =>
                  scope.id == shared.privateSync.scopeId &&
                  !scope.revoked &&
                  !scope.blocked,
            ) ==
            true;
  }

  Widget wrap(Widget child) =>
      PersonalWorkspaceBoundary(guard: this, child: child);
}

class PersonalWorkspaceBoundary extends ConsumerStatefulWidget {
  const PersonalWorkspaceBoundary({
    super.key,
    required this.guard,
    required this.child,
  });
  final PersonalWorkspaceGuard guard;
  final Widget child;
  @override
  ConsumerState<PersonalWorkspaceBoundary> createState() =>
      _PersonalWorkspaceBoundaryState();
}

class _PersonalWorkspaceBoundaryState
    extends ConsumerState<PersonalWorkspaceBoundary> {
  bool _closing = false;
  @override
  Widget build(BuildContext context) {
    ref.watch(organizerProvider);
    ref.watch(collaborationProvider);
    if (widget.guard.isCurrent) return widget.child;
    if (!_closing && ModalRoute.of(context)?.isCurrent == true) {
      _closing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && ModalRoute.of(context)?.isCurrent == true) {
          Navigator.pop(context);
        } else {
          _closing = false;
        }
      });
    }
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Text(context.l10n.sharingSessionExpired),
    );
  }
}
