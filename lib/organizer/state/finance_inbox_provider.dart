import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/finance_inbox_store.dart';
import 'local_database_provider.dart';
import 'organizer_provider.dart';

final financeInboxStoreProvider = FutureProvider<FinanceInboxStore>(
  (ref) async => FinanceInboxStore(
    await ref.watch(localDatabaseProvider.future),
    clock: ref.watch(organizerClockProvider),
  ),
);

final financeInboxClockProvider = StreamProvider.autoDispose<DateTime>((ref) {
  final clock = ref.watch(organizerClockProvider);
  final stream = StreamController<DateTime>();
  final cancel = ref.watch(organizerReminderSchedulerProvider)(
    () => stream.add(clock()),
  );
  ref.onDispose(() {
    cancel();
    stream.close();
  });
  stream.add(clock());
  return stream.stream;
});
