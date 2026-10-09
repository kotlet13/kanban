import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/linked_payments_repository.dart';
import '../domain/linked_payment_models.dart';
import 'collaboration_provider.dart';
import 'local_database_provider.dart';

export '../domain/linked_payment_models.dart';

typedef PaymentSpaceKey = ({String id, String? partition});
PaymentSpaceKey paymentSpaceKey(PaymentSpaceRef space) =>
    (id: space.id, partition: space.partition);
final linkedPaymentsRepositoryProvider =
    FutureProvider<LinkedPaymentsRepository>((ref) async {
      final database = await ref.watch(localDatabaseProvider.future);
      try {
        return LinkedPaymentsRepository(
          database,
          collaboration: await ref.watch(
            collaborationRepositoryProvider.future,
          ),
        );
      } catch (_) {
        // Anonymous device-owned spaces need no credential store or server.
        return LinkedPaymentsRepository(database);
      }
    });
final linkedPaymentChangesProvider = StreamProvider.autoDispose<int>((
  ref,
) async* {
  final repository = await ref.watch(linkedPaymentsRepositoryProvider.future);
  var revision = 0;
  yield revision;
  await for (final _ in repository.changes) {
    yield ++revision;
  }
});
final linkedPaymentsProvider = FutureProvider.autoDispose
    .family<PaymentSnapshot, PaymentSpaceKey>((ref, key) async {
      ref.watch(collaborationProvider);
      ref.watch(linkedPaymentChangesProvider);
      final repository = await ref.watch(
        linkedPaymentsRepositoryProvider.future,
      );
      return repository.read(PaymentSpaceRef(key.id, partition: key.partition));
    });
