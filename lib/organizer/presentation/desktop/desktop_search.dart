import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../state/all_spaces_provider.dart';
import '../../state/collaboration_provider.dart';
import '../../state/idea_provider.dart';
import '../all_spaces/all_spaces_area.dart';
import '../all_spaces/all_spaces_rows.dart';

class OrganizerDesktopSearchResult {
  const OrganizerDesktopSearchResult.record(this.row) : idea = null;
  const OrganizerDesktopSearchResult.idea(this.idea) : row = null;
  final AllSpacesRow? row;
  final IdeaSpaceEntry? idea;
}

/// Search observes the same permission-aware projections as All. Results keep
/// their source; they never become a synthetic destination for writes.
class OrganizerDesktopSearch extends ConsumerStatefulWidget {
  const OrganizerDesktopSearch({super.key});
  @override
  ConsumerState<OrganizerDesktopSearch> createState() =>
      _OrganizerDesktopSearchState();
}

class _OrganizerDesktopSearchState
    extends ConsumerState<OrganizerDesktopSearch> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final projection = ref.watch(allSpacesProvider);
    final sharing = ref.watch(collaborationProvider);
    final ideas = ref.watch(ideaAllSpacesProvider);
    final text = _query.trim().toLowerCase();
    final rows = <String, AllSpacesRow>{};
    final snapshot = projection.asData?.value;
    if (!projection.isLoading && snapshot != null && text.isNotEmpty) {
      void add(AllSpacesRow row) {
        if ('${row.title} ${row.notes} ${row.source.name ?? ''}'
            .toLowerCase()
            .contains(text)) {
          rows['${row.source.key}:${row.type}:${row.id}'] = row;
        }
        for (final child in row.children) {
          add(child);
        }
      }

      for (final area in [
        AllSpacesArea.tasks,
        AllSpacesArea.calendar,
        AllSpacesArea.projects,
        AllSpacesArea.shopping,
        AllSpacesArea.finances,
        AllSpacesArea.people,
      ]) {
        for (final row in allSpacesRows(
          snapshot,
          area,
          now: DateTime.now(),
          showCompleted: true,
        )) {
          add(row);
        }
      }
    }
    final records = rows.values.toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    final state = sharing.asData?.value;
    final ideaResults = text.isEmpty || ideas.isLoading
        ? <IdeaSpaceEntry>[]
        : (ideas.asData?.value ?? const <IdeaSpaceEntry>[]).where((entry) {
            if (entry.sharedScopeId != null &&
                (sharing.isLoading ||
                    state?.localAccessAllowed != true ||
                    entry.workspaceKey !=
                        'shared:${state?.session?.partition}:${entry.sharedScopeId}' ||
                    !state!.scopes.any(
                      (s) =>
                          s.id == entry.sharedScopeId &&
                          !s.revoked &&
                          !s.blocked &&
                          !s.archived,
                    ))) {
              return false;
            }
            return '${entry.board.title} ${entry.sourceName} '
                    '${entry.board.elements.map((e) => e.text).join(' ')}'
                .toLowerCase()
                .contains(text);
          }).toList();
    return Dialog(
      child: SizedBox(
        width: 680,
        height: MediaQuery.sizeOf(context).height * .72,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l.desktopSearch,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).closeButtonTooltip,
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('desktop-search-input'),
                autofocus: true,
                decoration: InputDecoration(
                  labelText: l.desktopSearchHint,
                  prefixIcon: const Icon(Icons.search),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: text.isEmpty
                    ? Center(child: Text(l.desktopSearchPrompt))
                    : projection.isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : projection.hasError
                    ? Center(child: Text(l.organizerLoadError))
                    : records.isEmpty && ideaResults.isEmpty
                    ? Center(child: Text(l.desktopSearchEmpty))
                    : ListView(
                        children: [
                          for (final row in records.take(100))
                            ListTile(
                              key: ValueKey(
                                'desktop-search-${row.source.key}:${row.type}:${row.id}',
                              ),
                              leading: Icon(row.icon),
                              title: Text(row.title),
                              subtitle: Text(
                                allSpacesSourceLabel(context, row.source),
                              ),
                              onTap: () {
                                if (allSpacesSourceIsCurrent(
                                  ref,
                                  row.source,
                                  financial: row.amountMinor != null,
                                )) {
                                  Navigator.pop(
                                    context,
                                    OrganizerDesktopSearchResult.record(row),
                                  );
                                }
                              },
                            ),
                          for (final entry in ideaResults.take(100))
                            ListTile(
                              leading: const Icon(Icons.lightbulb_outline),
                              title: Text(entry.board.title),
                              subtitle: Text(entry.sourceName),
                              onTap: () => Navigator.pop(
                                context,
                                OrganizerDesktopSearchResult.idea(entry),
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
