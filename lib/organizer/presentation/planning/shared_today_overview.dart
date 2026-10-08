import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../domain/organizer_projections.dart';
import '../../state/collaboration_provider.dart';
import '../inbox/notification_target_view.dart';
import '../organizer_widgets.dart';

class SharedTodayOverview extends ConsumerWidget {
  const SharedTodayOverview({super.key, required this.onAgenda});
  final ValueChanged<String> onAgenda;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(collaborationProvider).valueOrNull;
    if (state?.session == null) return const SizedBox.shrink();
    final scopes = state!.scopes
        .where(
          (scope) =>
              !scope.revoked &&
              !scope.archived &&
              scope.kind != SharedScopeKind.personal,
        )
        .toList();
    if (scopes.isEmpty) return const SizedBox.shrink();
    final l = context.l10n;
    String assignees(AgendaItem item) {
      final data = state.dataForScope(item.scopeId!);
      final task = data.tasks.where((t) => t.id == item.id).firstOrNull;
      final names = [
        for (final id in item.assigneeAccountIds)
          state
                  .membersForScope(item.scopeId!)
                  .where((m) => m.accountId == id)
                  .firstOrNull
                  ?.displayName ??
              l.planningFormerMember,
      ];
      if (task?.assigneePersonId != null) {
        names.add(
          data.people
                  .where((p) => p.id == task!.assigneePersonId)
                  .firstOrNull
                  ?.name ??
              l.planningFormerMember,
        );
      }
      return names.isEmpty ? l.planningUnassigned : names.join(', ');
    }

    final items =
        [
          for (final scope in scopes)
            ...dailyAgenda(
              state.dataForScope(scope.id),
              scopeId: scope.id,
              day: DateTime.now(),
            ),
        ]..sort(
          (a, b) => (a.sortAt ?? DateTime(2200)).compareTo(
            b.sortAt ?? DateTime(2200),
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: OrganizerSection(
        title: l.planningSharedToday,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (items.isEmpty) Text(l.planningNoAgenda),
            for (final item in items.take(3))
              Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  leading: Icon(
                    item.type == 'event'
                        ? Icons.event_outlined
                        : Icons.check_circle_outline,
                    size: 20,
                  ),
                  title: Text(item.title),
                  subtitle: Text(
                    '${scopes.where((scope) => scope.id == item.scopeId).first.name} · ${assignees(item)}${item.sortAt == null ? '' : '\n${organizerDateTime(context, item.sortAt!)}'}',
                  ),
                  onTap: () => onAgenda(item.scopeId!),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () =>
                    onAgenda(items.firstOrNull?.scopeId ?? scopes.first.id),
                child: Text(l.planningFullDay),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
