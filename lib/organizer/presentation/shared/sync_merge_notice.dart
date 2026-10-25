import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/application_sync_activity.dart';
import '../../state/collaboration_provider.dart';

/// A short local acknowledgement; it neither starts sync nor grants access.
class SyncMergeNotice extends ConsumerStatefulWidget {
  const SyncMergeNotice({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<SyncMergeNotice> createState() => _SyncMergeNoticeState();
}

class _SyncMergeNoticeState extends ConsumerState<SyncMergeNotice>
    with WidgetsBindingObserver {
  Timer? _timer;
  String? _shown;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _timer?.cancel();
    _shown = null;
    if (mounted) setState(() {});
  }

  Future<void> _ack(
    CollaborationAutoMergeNotice notice,
    String partition,
  ) async {
    if (_closing ||
        ref.read(collaborationProvider).valueOrNull?.session?.partition !=
            partition) {
      return;
    }
    _closing = true;
    try {
      await ref
          .read(collaborationProvider.notifier)
          .acknowledgeAutoMergeNotice(notice.key, notice.at);
    } catch (_) {
      // A failed local acknowledgement retains the durable notice for later.
    } finally {
      _closing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(collaborationProvider).valueOrNull;
    final partition = state?.session?.partition;
    final notice =
        state?.localAccessAllowed == true &&
            partition != null &&
            collaborationAppActive(WidgetsBinding.instance.lifecycleState)
        ? state?.autoMergeNotices
              .where(
                (notice) => state.scopes.any(
                  (scope) =>
                      scope.id == notice.scopeId &&
                      scope.canRead &&
                      !scope.deleted,
                ),
              )
              .firstOrNull
        : null;
    final identity = notice == null
        ? null
        : '$partition:${notice.key}:${notice.at}';
    if (_shown != identity) {
      _timer?.cancel();
      _shown = identity;
      if (notice != null) {
        _timer = Timer(const Duration(seconds: 6), () {
          if (mounted &&
              collaborationAppActive(WidgetsBinding.instance.lifecycleState)) {
            unawaited(_ack(notice, partition!));
          }
        });
      }
    }
    if (notice == null) return widget.child;
    final sl = Localizations.localeOf(context).languageCode == 'sl';
    return Stack(
      children: [
        widget.child,
        Positioned(
          left: 16,
          right: 16,
          bottom: MediaQuery.paddingOf(context).bottom + 16,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Material(
                key: const ValueKey('sync-auto-merge-notice'),
                elevation: 6,
                borderRadius: BorderRadius.circular(12),
                color: Theme.of(context).colorScheme.inverseSurface,
                child: Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            sl
                                ? 'Neodvisne spremembe zapisa so združene.'
                                : 'Independent changes to the record have been merged.',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onInverseSurface,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: sl ? 'Zapri' : 'Dismiss',
                        onPressed: () => _ack(notice, partition!),
                        icon: Icon(
                          Icons.close,
                          color: Theme.of(context).colorScheme.onInverseSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
