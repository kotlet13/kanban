import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/e2ee/account_crypto_repository.dart';
import 'collaboration_provider.dart';

final accountCryptoPreviewProvider = FutureProvider<AccountCryptoWorkflow?>((
  ref,
) async {
  final identity = ref.watch(
    collaborationProvider.select(
      (state) => (
        state.valueOrNull?.session?.partition,
        state.valueOrNull?.session?.deviceId,
      ),
    ),
  );
  if (identity.$1 == null) return null;
  return ref.read(collaborationProvider.notifier).accountCryptoPreview();
});
