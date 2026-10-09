import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/all_spaces_projection.dart';
import 'collaboration_provider.dart';
import 'organizer_provider.dart';
import 'local_spaces_provider.dart';

export '../domain/all_spaces_projection.dart';

/// Only the current account's committed projection is observed. Loading or
/// failed collaboration cannot retain another account's last visible rows.
final allSpacesProvider = Provider<AsyncValue<AllSpacesSnapshot>>((ref) {
  final personal = ref.watch(organizerProvider);
  final shared = ref.watch(collaborationProvider);
  // A refresh can carry the prior workspace as AsyncLoading.previous. Do not
  // turn that retained value into rows during an identity/workspace transition.
  if (personal.isLoading) return const AsyncLoading();
  if (personal.hasError) {
    return AsyncError(personal.error!, personal.stackTrace!);
  }
  final snapshot = personal.asData?.value;
  if (snapshot == null) {
    return const AsyncLoading();
  }
  return AsyncData(
    projectAllSpaces(
      personal: snapshot,
      localSpaces: ref.watch(localSpacesProvider).valueOrNull,
      shared: shared.isLoading || shared.hasError
          ? CollaborationState()
          : shared.valueOrNull ?? CollaborationState(),
    ),
  );
});
