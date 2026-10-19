import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'collaboration_provider.dart';

/// Completion refreshes existing summary widgets once, without polling or
/// repeating account protection. Newly mounted summaries already fetch afresh.
final accountSummaryRefreshProvider = StateProvider.autoDispose
    .family<int, (String, String)>((ref, identity) => 0);

bool refreshAccountSummaries(
  ProviderContainer container, {
  required String partition,
  required String deviceId,
}) {
  final session = container.read(collaborationProvider).valueOrNull?.session;
  if (session?.partition != partition || session?.deviceId != deviceId) {
    return false;
  }
  container
      .read(accountSummaryRefreshProvider((partition, deviceId)).notifier)
      .state++;
  return true;
}
