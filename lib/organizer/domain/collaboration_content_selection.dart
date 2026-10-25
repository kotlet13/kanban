import 'dart:convert';

import 'collaboration_models.dart';

const collaborationContentDomains = {
  'organizer',
  'ideas',
  'garden',
  'payments',
  'spaces',
};

// SharedScopeData is immutable. Cache signatures by projection identity, so
// sync-status publications never reserialize unchanged record collections.
final _projectionSignatures = Expando<Map<String, String>>();

String _projectionSignature(SharedScopeData data, String domain) {
  final signatures = _projectionSignatures[data] ??= {};
  return signatures.putIfAbsent(
    domain,
    () => jsonEncode([
      switch (domain) {
        'ideas' => data.ideas,
        'garden' => data.gardens,
        'payments' => [
          data.financeAccounts,
          data.financeEntries,
          data.personalFinanceEntries,
          data.financeTransfers,
        ],
        'organizer' => [
          data.projects,
          data.tasks,
          data.shoppingLists,
          data.shoppingItems,
          data.events,
          data.people,
          data.financeAccounts,
          data.financeEntries,
          data.personalFinanceEntries,
          data.financeTransfers,
          data.financeRecurrenceRules,
        ],
        _ => const [],
      },
      _creatorBindings(data, domain),
    ]),
  );
}

Map<String, String?> _creatorBindings(SharedScopeData data, String domain) {
  final keys = <String>{
    if (domain == 'ideas')
      for (final row in data.ideas) 'content:${row.id}',
    if (domain == 'garden')
      for (final row in data.gardens) 'content:${row.id}',
    if (domain == 'organizer') ...[
      for (final row in data.projects) 'content:${row.id}',
      for (final row in data.tasks) 'content:${row.id}',
      for (final row in data.shoppingLists) 'content:${row.id}',
      for (final row in data.shoppingItems) 'content:${row.id}',
      for (final row in data.events) 'content:${row.id}',
      for (final row in data.people) 'content:${row.id}',
      for (final row in data.financeRecurrenceRules) 'finance:${row.id}',
    ],
    if (domain == 'organizer' || domain == 'payments') ...[
      for (final row in data.financeAccounts) 'finance:${row.id}',
      for (final row in data.financeEntries) 'finance:${row.id}',
      for (final row in data.personalFinanceEntries) 'finance:${row.id}',
      for (final row in data.financeTransfers) 'finance:${row.id}',
    ],
  }.toList()..sort();
  return {for (final key in keys) key: data.recordCreators[key]};
}

/// Content/access only: status, last-attempt timestamps and queues are not
/// reasons to reload repositories. A scope filter also isolates shared editors.
String collaborationContentSignature(
  CollaborationState? state,
  String domain, {
  String? scopeId,
}) {
  if (state == null) return 'null';
  final scopes = state.scopes.where((s) => scopeId == null || s.id == scopeId);
  final ids = (scopeId == null ? state.data.keys.toList() : [scopeId])..sort();
  final financial = domain == 'organizer' || domain == 'payments';
  return jsonEncode([
    state.session?.partition,
    state.session?.deviceId,
    state.localAccessAllowed,
    state.deletionPending,
    if (scopeId == null)
      [
        state.selectedSpaceId,
        state.allSpacesSelected,
        state.privateSync.enabled,
        state.privateSync.paused,
        state.privateSync.scopeId,
        state.privateRecordIds,
      ],
    [for (final scope in scopes) scope.toJson()..remove('sequence')],
    if (domain != 'spaces')
      [
        for (final id in ids)
          [
            id,
            if (state.data[id] case final data?)
              _projectionSignature(data, domain),
            if (financial)
              [
                state.financePolicyForScope(id).toJson(),
                state.financeSnapshotComplete[id],
              ],
          ],
      ],
  ]);
}

Set<String> changedCollaborationContentDomains(
  CollaborationState? before,
  CollaborationState after,
) => {
  for (final domain in collaborationContentDomains)
    if (collaborationContentSignature(before, domain) !=
        collaborationContentSignature(after, domain))
      domain,
};
