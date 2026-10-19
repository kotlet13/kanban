import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../data/collaboration_transport.dart';
import '../../domain/hosting_information.dart';
import '../../state/collaboration_provider.dart';

export '../../domain/hosting_information.dart';

typedef HostingTarget = ({String serverUrl, bool allowLocalHttp});

/// Public request only: no account bearer, password, invitation, or device keys.
/// The target is part of the provider key, so late replies cannot replace a
/// different server's disclosure. Disposal closes the dedicated transport.
final hostingInformationProvider = FutureProvider.autoDispose
    .family<HostingInformation, HostingTarget>((ref, target) async {
      // A typed URL may be valid at every keystroke. Wait for a quiet interval
      // before opening a transport, and cancel promptly if its target changes.
      final ready = Completer<bool>();
      Timer? timer;
      void schedule() {
        timer = Timer(const Duration(milliseconds: 300), () {
          if (!ready.isCompleted) ready.complete(true);
        });
      }

      schedule();
      ref.onCancel(() => timer?.cancel());
      ref.onResume(() {
        if (!ready.isCompleted) schedule();
      });
      ref.onDispose(() {
        timer?.cancel();
        if (!ready.isCompleted) ready.complete(false);
      });
      if (!await ready.future) return const HostingInformation();
      final transport = ref.read(collaborationTransportFactoryProvider)();
      ref.onDispose(transport.close);
      final caps = await transport.call(
        serverUrl: target.serverUrl,
        operation: 'capabilities',
        allowLocalHttp: target.allowLocalHttp,
      );
      if (caps['api'] != 'familyhub_native' || caps['version'] != 1) {
        return const HostingInformation();
      }
      return HostingInformation.fromCapabilities(caps);
    });

class HostingDisclosureForServer extends ConsumerWidget {
  const HostingDisclosureForServer({
    super.key,
    required this.serverUrl,
    this.allowLocalHttp = false,
    this.compact = false,
  });

  final String serverUrl;
  final bool allowLocalHttp, compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    String endpoint;
    try {
      endpoint = normalizeCollaborationServer(
        serverUrl,
        allowLocalHttp: allowLocalHttp,
      );
    } on CollaborationException {
      return const SizedBox.shrink();
    }
    final info = ref.watch(
      hostingInformationProvider((
        serverUrl: endpoint,
        allowLocalHttp: allowLocalHttp,
      )),
    );
    return HostingDisclosure(
      serverUrl: endpoint,
      information: info.valueOrNull,
      compact: compact,
    );
  }
}

class HostingDisclosure extends StatelessWidget {
  const HostingDisclosure({
    super.key,
    required this.serverUrl,
    this.information,
    this.compact = false,
  });
  final String serverUrl;
  final HostingInformation? information;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 8 : 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.hostingDisclosureTitle,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Text(serverUrl),
          Text(
            information == null
                ? l.hostingOperatorUnavailable
                : information!.operatorName == null
                ? l.hostingOperatorNotProvided
                : l.hostingOperatorSupplied(information!.operatorName!),
          ),
          if (information?.operatorContact != null)
            Text(l.hostingContactSupplied(information!.operatorContact!)),
          const SizedBox(height: 6),
          Text(l.hostingTrustExplanation),
        ],
      ),
    );
  }
}
