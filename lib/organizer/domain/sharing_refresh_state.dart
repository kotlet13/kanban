/// Session-local display invalidation only. These counters never grant access.
class SharingRefreshState {
  const SharingRefreshState({
    this.coordinated = false,
    this.allMembers = 0,
    this.invitations = 0,
    this.scopes = const {},
  });
  final bool coordinated;
  final int allMembers, invitations;
  final Map<String, int> scopes;
  (int, int, int) forScope(String id) =>
      (allMembers, invitations, scopes[id] ?? 0);

  SharingRefreshState next({
    required bool all,
    required bool invitationChange,
    required Set<String> affectedScopes,
  }) => SharingRefreshState(
    coordinated: true,
    allMembers: allMembers + (all ? 1 : 0),
    invitations: invitations + (invitationChange || all ? 1 : 0),
    scopes: Map.unmodifiable({
      ...scopes,
      for (final id in affectedScopes) id: (scopes[id] ?? 0) + 1,
    }),
  );
}
