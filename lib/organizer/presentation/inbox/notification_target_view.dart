import '../shopping_page.dart';
import '../ideas/ideas_page.dart';
import '../ideas/idea_editor.dart';
import '../../state/idea_provider.dart';
import '../shared/content_actions_menu.dart';
import '../shared/shared_documents.dart';
import '../../domain/attachment_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../state/collaboration_provider.dart';
import '../../state/organizer_provider.dart';
import '../../state/local_spaces_provider.dart';
import '../../domain/organizer_models.dart';
import '../organizer_actions.dart';
import '../finance/shared_finance_actions.dart';
import '../finance/finance_money.dart';
import '../finance/finance_plan_forms.dart';
import '../finance/finance_entry_editing.dart';
import '../finance/finance_access_guard.dart';
import '../personal_workspace_boundary.dart';
import '../collection_actions.dart';
import '../organizer_widgets.dart';
import '../shared/collaboration_actions.dart';
import '../shared/sharing_errors.dart';
import '../shared/sharing_session_boundary.dart';
import '../recovery/crypto_invitation_page.dart';
import 'reminder_snooze.dart';
import 'local_task_reminder_editor.dart';
import 'local_notification_target.dart';
import 'remote_reminder_editor.dart';

Future<bool> showNotificationTarget(
  BuildContext context,
  WidgetRef ref,
  NotificationTarget target, {
  VoidCallback? onAccount,
  ValueChanged<String>? onMembers,
  Widget Function(Widget)? wrap,
  bool Function()? isCurrent,
  NotificationOpenResult? validatedResult,
}) async {
  if (isCurrent?.call() == false) return false;
  if (!await activateLocalNotificationTarget(context, ref, target) ||
      !context.mounted ||
      isCurrent?.call() == false) {
    return false;
  }
  final capturedSession = ref.read(collaborationProvider).valueOrNull?.session;
  try {
    final result =
        validatedResult ??
        await ref
            .read(collaborationProvider.notifier)
            .openNotificationTarget(target);
    if (!context.mounted || isCurrent?.call() == false) return false;
    final current = ref.read(collaborationProvider).valueOrNull;
    if (!target.isPersonal &&
        (capturedSession?.partition != current?.session?.partition ||
            capturedSession?.deviceId != current?.session?.deviceId)) {
      return false;
    }
    final l = context.l10n;
    if (result.status != NotificationOpenStatus.available &&
        result.status != NotificationOpenStatus.offline) {
      final message = switch (result.status) {
        NotificationOpenStatus.deleted => l.inboxDeleted,
        NotificationOpenStatus.permissionDenied => l.sharingAccessRevoked,
        NotificationOpenStatus.wrongAccount => l.inboxWrongAccount,
        _ => l.inboxNeedsConnection,
      };
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l.inboxTitle),
          content: Text(message),
          actions: [
            if (result.status == NotificationOpenStatus.wrongAccount &&
                onAccount != null)
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  onAccount();
                },
                child: Text(l.sharingGoToAccount),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l.close),
            ),
          ],
        ),
      );
      return false;
    }
    if (!target.isPersonal &&
        (current?.session == null || !target.matches(current!.session!))) {
      return false;
    }
    final acceptance = result.target.invitationAcceptance;
    if (acceptance != null) {
      final scope = current?.scopes
          .where((s) => s.id == acceptance.scopeId)
          .firstOrNull;
      if (result.status != NotificationOpenStatus.available ||
          scope == null ||
          !scope.canManage ||
          scope.blocked ||
          scope.archived ||
          scope.revoked) {
        return false;
      }
      final repository = await ref.read(collaborationRepositoryProvider.future);
      if (!context.mounted || isCurrent?.call() == false) return false;
      final account = await repository.connectedCryptoAccount();
      if (!context.mounted ||
          isCurrent?.call() == false ||
          !account.directory.isCurrent()) {
        return false;
      }
      final now = ref.read(collaborationProvider).valueOrNull;
      if (now?.session?.partition != capturedSession?.partition ||
          now?.session?.deviceId != capturedSession?.deviceId ||
          !now!.scopes.any(
            (s) =>
                s.id == scope.id &&
                s.canManage &&
                !s.revoked &&
                !s.blocked &&
                !s.archived,
          )) {
        return false;
      }
      await Navigator.of(context, rootNavigator: true).push<void>(
        MaterialPageRoute(
          builder: (_) => CryptoInvitationPage(
            account: account,
            scopeId: scope.id,
            invitationId: acceptance.invitationId,
            label: scope.name,
            kind: scope.kind,
            expectedAcceptance: acceptance,
          ),
        ),
      );
      return true;
    }
    if (target.records.isNotEmpty &&
        target.records.every(
          (record) =>
              record.type == 'shoppingList' || record.type == 'shoppingItem',
        )) {
      await Navigator.of(context, rootNavigator: true).push<void>(
        MaterialPageRoute(
          builder: (_) => ShoppingNotificationPage(
            target: result.target,
            offline: result.status == NotificationOpenStatus.offline,
          ),
        ),
      );
      return true;
    }
    if (target.records.length == 1 && target.records.single.type == 'idea') {
      return await openIdeaNotificationBoard(
        context,
        ref,
        target,
        target.records.single.recordId,
      );
    }
    if (await _openFinanceConfirmation(context, ref, target)) return true;
    if (!context.mounted) return false;
    final guard = target.isPersonal ? null : SharingSessionGuard(context, ref);
    await showDialog<void>(
      context: context,
      builder: (context) {
        final dialog = AlertDialog(
          title: Text(
            target.isPersonal
                ? l.inboxForMe
                : current!.scopes
                          .where((s) => s.id == target.scopeId)
                          .firstOrNull
                          ?.name ??
                      l.sharingShared,
          ),
          content: SizedBox(
            width: 760,
            child: SingleChildScrollView(
              child: NotificationTargetContent(
                target: target,
                offline: result.status == NotificationOpenStatus.offline,
                onMembers: onMembers,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l.close),
            ),
          ],
        );
        final protectedDialog = guard == null
            ? dialog
            : SharingSessionBoundary(
                guard: guard,
                visibleWhen: (state) =>
                    state.scopes.any(
                      (scope) => scope.id == target.scopeId && !scope.revoked,
                    ) &&
                    (!target.records.any(
                          (r) => SharedFinanceRecordType.values.any(
                            (type) => type.name == r.type,
                          ),
                        ) ||
                        state.financePolicyForScope(target.scopeId!).canRead),
                child: dialog,
              );
        return wrap?.call(protectedDialog) ?? protectedDialog;
      },
    );
    return true;
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(sharingErrorMessage(context, error))),
      );
    }
    return false;
  }
}

class ShoppingNotificationPage extends ConsumerStatefulWidget {
  const ShoppingNotificationPage({
    super.key,
    required this.target,
    this.offline = false,
  });
  final NotificationTarget target;
  final bool offline;
  @override
  ConsumerState<ShoppingNotificationPage> createState() =>
      _ShoppingNotificationPageState();
}

class _ShoppingNotificationPageState
    extends ConsumerState<ShoppingNotificationPage> {
  String? _selected;
  @override
  Widget build(BuildContext context) {
    final target = widget.target, l = context.l10n;
    final personal = ref.watch(organizerProvider).valueOrNull;
    final state = ref.watch(collaborationProvider).valueOrNull;
    final scope = state?.scopes
        .where((scope) => scope.id == target.scopeId)
        .firstOrNull;
    final permitted = target.isPersonal
        ? personal != null &&
              (personal.workspaceKey == target.localWorkspaceId ||
                  target.localWorkspaceId == 'local' &&
                      personal.workspaceKey ==
                          'private:${state?.session?.partition}' &&
                      state?.localAccessAllowed == true)
        : state?.session != null &&
              target.matches(state!.session!) &&
              scope != null &&
              !scope.revoked &&
              !scope.blocked &&
              state.localAccessAllowed;
    if (!permitted) {
      return Scaffold(
        appBar: AppBar(title: Text(l.organizerShopping)),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(l.sharingAccessRevoked),
        ),
      );
    }
    final personalPresentation =
        target.isPersonal || scope?.kind == SharedScopeKind.personal;
    if (personalPresentation && personal == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l.organizerShopping)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final snapshot = personalPresentation
        ? personal!
        : sharedPresentationSnapshot(state!.dataForScope(scope!.id));
    String recordId(NotificationRecordTarget record) =>
        scope?.kind == SharedScopeKind.personal
        ? state!.personalRecordId(record.recordId)
        : record.recordId;
    final changedItems = {
      for (final record in target.records)
        if (record.type == 'shoppingItem') recordId(record),
    };
    final lists = {
      for (final record in target.records)
        if (record.type == 'shoppingList') recordId(record),
      for (final item in snapshot.shoppingItems)
        if (changedItems.contains(item.id)) item.listId,
    };
    final visibleLists = snapshot.shoppingLists
        .where((list) => lists.contains(list.id))
        .toList();
    final active =
        _selected ?? (visibleLists.length == 1 ? visibleLists.single.id : null);
    final actions = personalPresentation
        ? OrganizerActions(context, ref, personal!)
        : CollaborationActions(
            context,
            ref,
            scope!,
            state!.dataForScope(scope.id),
          );
    final removed = changedItems.any(
      (id) => !snapshot.shoppingItems.any((item) => item.id == id),
    );
    return Scaffold(
      appBar: AppBar(title: Text(l.organizerShopping)),
      body: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.offline)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(l.inboxOfflineView),
                    ),
                  if (removed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(l.notificationShoppingRemoved),
                    ),
                  if (visibleLists.isEmpty)
                    Text(l.inboxDeleted)
                  else
                    OrganizerShoppingPage(
                      snapshot: snapshot.copyWith(shoppingLists: visibleLists),
                      actions: actions,
                      selectedId: active,
                      onSelection: (id) => setState(() => _selected = id),
                      readOnly:
                          !personalPresentation &&
                          (!scope!.canEdit ||
                              scope.archived ||
                              state!.deletionPending),
                      reportScopeId: personalPresentation ? null : scope!.id,
                      scopeLabel: scope?.name,
                      highlightedItemIds: changedItems,
                      highlightList: target.records.any(
                        (record) => record.type == 'shoppingList',
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class NotificationTargetContent extends ConsumerWidget {
  const NotificationTargetContent({
    super.key,
    required this.target,
    this.offline = false,
    this.onMembers,
  });
  final NotificationTarget target;
  final bool offline;
  final ValueChanged<String>? onMembers;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final personal = ref.watch(organizerProvider).valueOrNull;
    final state = ref.watch(collaborationProvider).valueOrNull;
    final scope = state?.scopes
        .where((s) => s.id == target.scopeId)
        .firstOrNull;
    if (!target.isPersonal &&
        (state?.session == null ||
            !target.matches(state!.session!) ||
            scope == null ||
            scope.revoked ||
            scope.deleted ||
            !state.localAccessAllowed)) {
      return Text(l.sharingAccessRevoked);
    }
    if (personal == null) return const CircularProgressIndicator();
    if (target.isPersonal &&
        personal.workspaceKey != target.localWorkspaceId &&
        !(target.localWorkspaceId == 'local' &&
            personal.workspaceKey.startsWith('private:') &&
            state?.localAccessAllowed == true &&
            personal.workspaceKey == 'private:${state?.session?.partition}')) {
      return Text(l.inboxDeleted);
    }
    final personalPresentation =
        target.isPersonal || scope?.kind == SharedScopeKind.personal;
    final data = state?.dataForScope(target.scopeId ?? '');
    String localId(NotificationRecordTarget record) =>
        scope?.kind == SharedScopeKind.personal
        ? state!.personalRecordId(record.recordId)
        : record.recordId;
    final snapshot = personalPresentation
        ? personal
        : sharedPresentationSnapshot(data!);
    final sharedActions = personalPresentation
        ? null
        : CollaborationActions(context, ref, scope!, data!);
    final personalActions = OrganizerActions(context, ref, personal);
    final OrganizerCollectionActions actions = sharedActions ?? personalActions;
    final localArchived =
        target.isPersonal &&
        ref
                .watch(localSpacesProvider)
                .valueOrNull
                ?.spaces
                .any(
                  (space) =>
                      space.id == personal.workspaceKey && space.archived,
                ) ==
            true;
    final canEdit = personalPresentation
        ? !localArchived &&
              (target.isPersonal ||
                  (scope!.canEdit &&
                      !scope.deleted &&
                      state?.deletionPending != true))
        : scope!.canEdit && !scope.deleted && state?.deletionPending != true;
    bool taskEditable(LocalTask task) =>
        canEdit &&
        !snapshot.projects.any((p) => p.id == task.projectId && p.archived);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (offline)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(l.inboxOfflineView),
          ),
        for (final record in target.records) ...[
          if (!personalPresentation && record.type != 'membership')
            Align(
              alignment: Alignment.centerRight,
              child: SharedContentActionsMenu(
                scopeId: scope!.id,
                targetId: localId(record),
                actions: [
                  if (record.type == 'task')
                    ContentMenuAction(
                      label: l.documentsAttachments,
                      icon: Icons.attach_file,
                      onSelected: () => openSharedDocuments(
                        context,
                        scope,
                        target: AttachmentTarget(
                          scopeId: scope.id,
                          targetType: 'task',
                          targetId: localId(record),
                        ),
                      ),
                    ),
                ],
                targetType: record.type.startsWith('finance')
                    ? 'finance'
                    : 'record',
              ),
            ),
          if (record.type == 'membership') ...[
            Text(l.inboxJoinedScope),
            for (final member
                in state!.membersForScope(scope!.id).where((m) => m.active))
              ListTile(
                title: Text(
                  member.displayName.isEmpty
                      ? member.username
                      : member.displayName,
                ),
                subtitle: Text(sharingRoleLabel(context, member.role)),
              ),
            if (onMembers != null)
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  onMembers!(scope.id);
                },
                child: Text(l.sharingMembers),
              ),
          ] else if (record.type == 'idea') ...[
            for (final board in (data?.ideas ?? <IdeaBoard>[]).where(
              (b) => b.id == record.recordId,
            ))
              IdeaCard(
                board: board,
                workspaceKey:
                    'shared:${state!.session!.partition}:${scope!.id}',
                onOpen: () =>
                    openIdeaNotificationBoard(context, ref, target, board.id),
              ),
          ] else if (record.type == 'task') ...[
            for (final task in snapshot.tasks.where(
              (t) => t.id == localId(record),
            ))
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (task.notes.isNotEmpty) Text(task.notes),
                      if (!personalPresentation)
                        Text(
                          task.assigneeAccountIds.isEmpty
                              ? l.planningUnassigned
                              : task.assigneeAccountIds
                                    .map(
                                      (id) =>
                                          state!
                                              .membersForScope(scope!.id)
                                              .where((m) => m.accountId == id)
                                              .firstOrNull
                                              ?.displayName ??
                                          l.planningFormerMember,
                                    )
                                    .join(', '),
                        ),
                      if (task.startAt != null)
                        Text(
                          '${l.planningStart}: ${organizerDateTime(context, task.startAt!)}',
                        ),
                      if (task.endAt != null)
                        Text(
                          '${l.planningEnd}: ${organizerDateTime(context, task.endAt!)}',
                        ),
                      if (task.dueAt != null)
                        Text(
                          '${l.planningDue}: ${organizerDateTime(context, task.dueAt!)}',
                        ),
                      _TaskCompletionControl(
                        task: task,
                        enabled: taskEditable(task),
                        onChanged: (value) =>
                            actions.setTaskCompleted(task.id, value),
                      ),
                      if (personalPresentation && !task.isCompleted)
                        LocalTaskReminderButton(
                          task: task,
                          workspaceKey: personal.workspaceKey,
                        ),
                      if (!personalPresentation && !task.isCompleted)
                        RemoteReminderButton(
                          scopeId: scope!.id,
                          targetType: 'task',
                          targetId: task.id,
                        ),
                      if (!task.isCompleted)
                        ReminderSnoozeButton(
                          target: NotificationTarget(
                            serverUrl: target.serverUrl,
                            serverId: target.serverId,
                            accountId: target.accountId,
                            scopeId: target.scopeId,
                            records: [record],
                          ),
                        ),
                      if (!personalPresentation &&
                          task.createdByAccountId != null)
                        Text(
                          '${l.planningCreatedBy}: ${state?.membersForScope(scope!.id).where((m) => m.accountId == task.createdByAccountId).firstOrNull?.displayName ?? l.planningFormerMember}',
                        ),
                      if (taskEditable(task))
                        TextButton(
                          onPressed: () => (sharedActions ?? personalActions)
                              .task(task: task),
                          child: Text(l.organizerEditTask),
                        ),
                    ],
                  ),
                ),
              ),
          ] else if (record.type == 'event') ...[
            if (personalPresentation)
              for (final event in personal.events.where(
                (e) => e.id == localId(record),
              ))
                OrganizerEventCard(
                  event: event,
                  onTap: () => personalActions.event(event),
                )
            else
              for (final event in data!.events.where(
                (e) => e.id == localId(record),
              ))
                Card(
                  child: ListTile(
                    title: Text(event.title),
                    subtitle: Text(
                      '${organizerDateTime(context, event.startAt)}\n${event.notes}',
                    ),
                    trailing: RemoteReminderButton(
                      scopeId: scope!.id,
                      targetType: 'event',
                      targetId: event.id,
                    ),
                    onTap: canEdit ? () => sharedActions!.event(event) : null,
                  ),
                ),
          ] else if (record.type == 'project') ...[
            for (final project in snapshot.projects.where(
              (p) => p.id == localId(record),
            ))
              Card(
                child: ListTile(
                  title: Text(project.title),
                  subtitle: Text(project.description),
                  onTap: canEdit ? () => actions.project(project) : null,
                ),
              ),
          ] else if (record.type == 'shoppingList') ...[
            for (final list in snapshot.shoppingLists.where(
              (v) => v.id == localId(record),
            ))
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        list.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      for (final item in snapshot.shoppingItems.where(
                        (i) => i.listId == list.id,
                      ))
                        Text(
                          '${item.isChecked ? '✓' : '○'} ${item.title} · ${item.quantity}',
                        ),
                    ],
                  ),
                ),
              ),
          ] else if (record.type == 'shoppingItem') ...[
            for (final item in snapshot.shoppingItems.where(
              (v) => v.id == localId(record),
            ))
              Card(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: ListTile(
                  title: Text(item.title),
                  subtitle: Text(
                    '${item.quantity} · ${snapshot.shoppingLists.where((v) => v.id == item.listId).firstOrNull?.title ?? l.organizerShopping}',
                  ),
                  onTap: canEdit
                      ? () => actions.shoppingItem(item.listId, item)
                      : null,
                ),
              ),
          ] else if (record.type == 'personalFinanceEntry' ||
              (record.type == 'financeEntry' && personalPresentation)) ...[
            if (target.isPersonal ||
                (state!.financePolicyForScope(scope!.id).canRead &&
                    state.financeSnapshotComplete[scope.id] == true))
              for (final entry in personal.financeEntries.where(
                (entry) => entry.id == localId(record),
              ))
                Card(
                  child: ListTile(
                    title: Text(entry.title),
                    subtitle: Text(
                      '${sharedMoneyLabel(context, BigInt.from(entry.amountMinor), entry.currency)} · ${organizerDateTime(context, entry.occurredAt)}\n${entry.notes}',
                    ),
                    onTap: canEdit
                        ? () async {
                            if (entry.status != FinanceEntryStatus.planned) {
                              if (entry.recurrenceRuleId != null) {
                                await editRecordedPersonalOccurrence(
                                  context,
                                  ref,
                                  personal,
                                  entry,
                                );
                              } else {
                                await personalActions.finance(entry);
                              }
                              return;
                            }
                            final guard = PersonalWorkspaceGuard(
                              context,
                              ref,
                              personal.workspaceKey,
                            );
                            final financial = target.isPersonal
                                ? null
                                : FinanceAccessGuard(
                                    context,
                                    ref,
                                    scope!.id,
                                    write: true,
                                  );
                            await showFinanceOccurrenceConfirmation(
                              context,
                              entry: entry,
                              sourceWorkspaceKey: personal.workspaceKey,
                              initialPaidAt: ref.read(organizerClockProvider)(),
                              wrap: (child) =>
                                  guard.wrap(financial?.wrap(child) ?? child),
                              onConfirm: (amount, date) async {
                                if (!guard.isCurrent ||
                                    financial?.isCurrent == false) {
                                  throw const CollaborationException(
                                    'finance_forbidden',
                                  );
                                }
                                await ref
                                    .read(organizerProvider.notifier)
                                    .confirmFinanceOccurrence(
                                      entry: entry,
                                      amountMinor: amount,
                                      paidAt: date,
                                      expectedWorkspaceKey:
                                          personal.workspaceKey,
                                    );
                              },
                            );
                          }
                        : null,
                  ),
                )
            else
              Text(l.sharingAccessRevoked),
          ] else if (record.type.startsWith('finance')) ...[
            if (state!.financePolicyForScope(scope!.id).canRead &&
                state.financeSnapshotComplete[scope.id] == true) ...[
              for (final account in data!.financeAccounts.where(
                (v) =>
                    record.type == 'financeAccount' && v.id == localId(record),
              ))
                Card(
                  child: ListTile(
                    title: Text(account.name),
                    subtitle: Text(
                      sharedMoneyLabel(
                        context,
                        BigInt.from(account.openingBalanceMinor ?? 0),
                        account.currency,
                      ),
                    ),
                    onTap: state.financePolicyForScope(scope.id).canWrite
                        ? () => SharedFinanceActions(
                            context,
                            ref,
                            scope,
                            state,
                          ).account(account)
                        : null,
                  ),
                ),
              for (final entry in data.financeEntries.where(
                (v) => record.type == 'financeEntry' && v.id == localId(record),
              ))
                Card(
                  child: ListTile(
                    title: Text(entry.title),
                    subtitle: Text(
                      '${sharedMoneyLabel(context, BigInt.from(entry.amountMinor), entry.currency)} · ${organizerDateTime(context, entry.occurredAt)}\n${entry.notes}',
                    ),
                    trailing: entry.status == SharedFinanceStatus.planned
                        ? RemoteReminderButton(
                            scopeId: scope.id,
                            targetType: 'financeEntry',
                            targetId: entry.id,
                          )
                        : null,
                    onTap: state.financePolicyForScope(scope.id).canWrite
                        ? () async {
                            if (entry.status != SharedFinanceStatus.planned) {
                              await SharedFinanceActions(
                                context,
                                ref,
                                scope,
                                state,
                              ).entry(entry);
                              return;
                            }
                            final guard = FinanceAccessGuard(
                              context,
                              ref,
                              scope.id,
                              write: true,
                            );
                            final local = FinanceEntry(
                              id: entry.id,
                              title: entry.title,
                              amountMinor: entry.amountMinor,
                              currency: entry.currency,
                              kind: entry.kind,
                              occurredAt: entry.occurredAt,
                              projectId: null,
                              taskId: entry.taskId,
                              notes: entry.notes,
                              createdAt: entry.createdAt,
                              updatedAt: entry.updatedAt,
                            );
                            await showFinanceOccurrenceConfirmation(
                              context,
                              entry: local,
                              sourceScopeId: scope.id,
                              sourcePartition: state.session!.partition,
                              wrap: guard.wrap,
                              onConfirm: (amount, date) => guard.controller
                                  .confirmFinanceOccurrenceForScope(
                                    scope.id,
                                    entry,
                                    amountMinor: amount,
                                    paidAt: date,
                                  ),
                            );
                          }
                        : null,
                  ),
                ),
              for (final transfer in data.financeTransfers.where(
                (v) =>
                    record.type == 'financeTransfer' && v.id == localId(record),
              ))
                Card(
                  child: ListTile(
                    title: Text(transfer.title),
                    subtitle: Text(
                      '${sharedMoneyLabel(context, BigInt.from(transfer.amountMinor), transfer.currency)} · ${organizerDateTime(context, transfer.occurredAt)}',
                    ),
                    onTap: state.financePolicyForScope(scope.id).canWrite
                        ? () => SharedFinanceActions(
                            context,
                            ref,
                            scope,
                            state,
                          ).transfer(transfer)
                        : null,
                  ),
                ),
              TextButton(
                onPressed: () => SharedFinanceActions(
                  context,
                  ref,
                  scope,
                  state,
                ).audit(localId(record)),
                child: Text(l.financeAudit),
              ),
            ] else if (state.financePolicyForScope(scope.id).canRead)
              Text(l.financeLoadingSnapshot)
            else
              Text(l.sharingAccessRevoked),
          ],
        ],
      ],
    );
  }
}

String organizerDateTime(BuildContext context, DateTime value) {
  final local = value.toLocal();
  return '${organizerDate(context, local)} · ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
}

Future<bool> _openFinanceConfirmation(
  BuildContext context,
  WidgetRef ref,
  NotificationTarget target,
) async {
  if (target.records.length != 1) return false;
  final record = target.records.single;
  if (!['financeEntry', 'personalFinanceEntry'].contains(record.type)) {
    return false;
  }
  final state = ref.read(collaborationProvider).valueOrNull;
  final personal = ref.read(organizerProvider).valueOrNull;
  final scope = state?.scopes.where((s) => s.id == target.scopeId).firstOrNull;
  if (target.isPersonal || scope?.kind == SharedScopeKind.personal) {
    final id = scope?.kind == SharedScopeKind.personal
        ? state!.personalRecordId(record.recordId)
        : record.recordId;
    final entry = personal?.financeEntries.where((e) => e.id == id).firstOrNull;
    if (entry == null || entry.status != FinanceEntryStatus.planned) {
      return false;
    }
    final guard = PersonalWorkspaceGuard(context, ref, personal!.workspaceKey);
    final financeScope =
        target.scopeId ??
        (personal.workspaceKey == 'local' ? null : state?.privateSync.scopeId);
    final financial = financeScope == null
        ? null
        : FinanceAccessGuard(context, ref, financeScope, write: true);
    if (!guard.isCurrent || financial?.isCurrent == false) return false;
    await showFinanceOccurrenceConfirmation(
      context,
      entry: entry,
      sourceWorkspaceKey: personal.workspaceKey,
      initialPaidAt: ref.read(organizerClockProvider)(),
      wrap: (child) => guard.wrap(financial?.wrap(child) ?? child),
      isCurrent: () => guard.isCurrent && (financial?.isCurrent ?? true),
      onConfirm: (amount, date) async {
        if (!guard.isCurrent || financial?.isCurrent == false) {
          throw const CollaborationException('finance_forbidden');
        }
        await ref
            .read(organizerProvider.notifier)
            .confirmFinanceOccurrence(
              entry: entry,
              amountMinor: amount,
              paidAt: date,
              expectedWorkspaceKey: personal.workspaceKey,
            );
      },
    );
    return true;
  }
  if (state == null || scope == null) return false;
  final entry = state
      .dataForScope(scope.id)
      .financeEntries
      .where((e) => e.id == record.recordId)
      .firstOrNull;
  if (entry == null || entry.status != SharedFinanceStatus.planned) {
    return false;
  }
  final guard = FinanceAccessGuard(context, ref, scope.id, write: true);
  if (!guard.isCurrent) return false;
  final local = FinanceEntry(
    id: entry.id,
    title: entry.title,
    amountMinor: entry.amountMinor,
    currency: entry.currency,
    kind: entry.kind,
    occurredAt: entry.occurredAt,
    projectId: null,
    taskId: entry.taskId,
    notes: entry.notes,
    createdAt: entry.createdAt,
    updatedAt: entry.updatedAt,
  );
  await showFinanceOccurrenceConfirmation(
    context,
    entry: local,
    sourceScopeId: scope.id,
    sourcePartition: state.session!.partition,
    initialPaidAt: ref.read(organizerClockProvider)(),
    wrap: guard.wrap,
    isCurrent: () => guard.isCurrent,
    onConfirm: (amount, date) =>
        guard.controller.confirmFinanceOccurrenceForScope(
          scope.id,
          entry,
          amountMinor: amount,
          paidAt: date,
        ),
  );
  return true;
}

class _TaskCompletionControl extends StatefulWidget {
  const _TaskCompletionControl({
    required this.task,
    required this.enabled,
    required this.onChanged,
  });
  final LocalTask task;
  final bool enabled;
  final Future<void> Function(bool) onChanged;
  @override
  State<_TaskCompletionControl> createState() => _TaskCompletionControlState();
}

class _TaskCompletionControlState extends State<_TaskCompletionControl> {
  bool _busy = false;
  Future<void> _change(bool? value) async {
    if (_busy || !widget.enabled || value == null) return;
    setState(() => _busy = true);
    try {
      await widget.onChanged(value);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => CheckboxListTile(
    key: ValueKey('task-detail-completed-${widget.task.id}'),
    contentPadding: EdgeInsets.zero,
    title: Text(context.l10n.organizerCompleted),
    value: widget.task.isCompleted,
    onChanged: widget.enabled && !_busy ? _change : null,
    controlAffinity: ListTileControlAffinity.leading,
  );
}
