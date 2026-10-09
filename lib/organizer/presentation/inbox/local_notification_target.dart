import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../state/collaboration_provider.dart';
import '../../state/local_spaces_provider.dart';
import '../../state/organizer_provider.dart';

final _activatingLocalTarget = Expando<bool>();

/// Old device payloads always refer to default Personal. Named local targets
/// carry their exact catalog ID and cannot reopen a parked published copy.
Future<bool> activateLocalNotificationTarget(
  BuildContext context,
  WidgetRef ref,
  NotificationTarget target,
) async {
  if (!target.isPersonal) return true;
  final current = ref.read(organizerProvider).valueOrNull;
  final shared = ref.read(collaborationProvider).valueOrNull;
  final localId = target.localWorkspaceId;
  final private = current?.workspaceKey.startsWith('private:') == true;
  final matching =
      current?.workspaceKey == localId ||
      localId == 'local' &&
          private &&
          shared?.localAccessAllowed == true &&
          shared?.session != null &&
          current?.workspaceKey == 'private:${shared!.session!.partition}';
  if (matching) return true;
  final navigator = Navigator.of(context, rootNavigator: true);
  if (_activatingLocalTarget[navigator] == true) return false;
  _activatingLocalTarget[navigator] = true;
  final identity = '${shared?.session?.partition}:${shared?.session?.deviceId}';
  try {
    final catalog = await ref.read(localSpacesProvider.future);
    if (!context.mounted) return false;
    final space = catalog.spaces
        .where((space) => space.id == localId)
        .firstOrNull;
    if (space == null || space.binding != null) return false;
    final controller = ref.read(collaborationProvider.notifier);
    await controller.selectSpace(null);
    if (!context.mounted) return false;
    final account = ref.read(collaborationProvider).valueOrNull?.session;
    if ('${account?.partition}:${account?.deviceId}' != identity) return false;
    await ref.read(localSpacesProvider.notifier).selectSpace(localId);
    if (!context.mounted) return false;
    await (await ref.read(organizerRepositoryProvider.future)).reload();
    final snapshot = await ref.read(organizerProvider.future);
    final after = ref.read(collaborationProvider).valueOrNull;
    return context.mounted &&
        '${after?.session?.partition}:${after?.session?.deviceId}' ==
            identity &&
        (snapshot.workspaceKey == localId ||
            localId == 'local' &&
                after?.localAccessAllowed == true &&
                snapshot.workspaceKey ==
                    'private:${after?.session?.partition}');
  } catch (_) {
    return false;
  } finally {
    _activatingLocalTarget[navigator] = false;
  }
}
