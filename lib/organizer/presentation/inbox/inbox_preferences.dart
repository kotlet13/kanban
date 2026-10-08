import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../l10n/l10n.dart';
import '../../state/collaboration_provider.dart';
import '../../platform/remote_push/remote_push_providers.dart';
import '../planning/device_reminder_settings.dart';
import '../planning/remote_push_device_settings.dart';
import '../shared/sharing_errors.dart';
import '../shared/sharing_session_boundary.dart';

Future<void> showInboxPreferences(
  BuildContext context,
  WidgetRef ref, {
  String? initialScopeId,
}) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(context.l10n.inboxSettings),
    content: SizedBox(
      width: 640,
      child: SingleChildScrollView(
        child: InboxPreferences(initialScopeId: initialScopeId),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.l10n.close),
      ),
    ],
  ),
);

class InboxPreferences extends ConsumerStatefulWidget {
  const InboxPreferences({super.key, this.initialScopeId});
  final String? initialScopeId;
  @override
  ConsumerState<InboxPreferences> createState() => _InboxPreferencesState();
}

class _InboxPreferencesState extends ConsumerState<InboxPreferences> {
  String? _scopeId;
  String? _selectionBinding;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _scopeId = widget.initialScopeId;
    final session = ref.read(collaborationProvider).valueOrNull?.session;
    _selectionBinding = session == null ? null : pushDeviceKey(session);
  }

  Future<void> _save(
    String scopeId,
    String category,
    SharedNotificationSettings settings,
  ) async {
    final guard = SharingSessionGuard(context, ref);
    setState(() => _busy = true);
    try {
      await guard.controller.setNotificationPreferences(
        scopeId: scopeId,
        category: category,
        settings: settings,
      );
    } catch (e) {
      if (mounted && guard.isCurrent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(sharingErrorMessage(context, e))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n,
        state = ref.watch(collaborationProvider).valueOrNull;
    final scopes =
        state?.scopes.where((s) => !s.revoked).toList() ?? <SharedScope>[];
    final session = state?.session;
    final binding = session == null ? null : pushDeviceKey(session);
    _selectionBinding ??= binding;
    final selectedScopeId = _selectionBinding == binding
        ? _scopeId ?? state?.selectedSpaceId
        : state?.selectedSpaceId;
    final scope =
        scopes.where((s) => s.id == selectedScopeId).firstOrNull ??
        scopes.firstOrNull;
    final categories = {
      'reminders': l.inboxCategoryReminders,
      'tasks': l.inboxCategoryTasks,
      'events': l.inboxCategoryEvents,
      'shopping': l.inboxCategoryShopping,
      'membership': l.inboxCategoryMembers,
      if (scope != null && state!.financePolicyForScope(scope.id).canRead)
        'finance': l.inboxCategoryFinance,
    };
    final pushCategories = scope == null
        ? <String>[]
        : [
            for (final category in categories.entries)
              if (state!.notificationPreferences[scope.id]
                      ?.forCategory(category.key)
                      .push ==
                  true)
                category.value,
          ];
    final deviceReady = ref.watch(remotePushDeviceReadyProvider);
    final accountUsable = remotePushAccountUsable(state);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const DeviceReminderSettings(),
        const SizedBox(height: 24),
        const RemotePushDeviceSettings(),
        const SizedBox(height: 24),
        if (state?.session != null && scope != null) ...[
          Text(l.inboxPreferencesDescription),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            key: ValueKey(
              'preferences-${state!.session!.partition}-${scope.id}',
            ),
            initialValue: scope.id,
            isExpanded: true,
            decoration: InputDecoration(labelText: l.inboxScope),
            items: [
              for (final s in scopes)
                DropdownMenuItem(
                  value: s.id,
                  child: Text(
                    s.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: _busy
                ? null
                : (value) => setState(() {
                    _selectionBinding = binding;
                    _scopeId = value;
                  }),
          ),
          if (!state.inboxSupported)
            Text(l.inboxPreferencesUnsupported)
          else ...[
            const SizedBox(height: 16),
            Text(
              pushCategories.isEmpty
                  ? l.inboxPushCategoriesNone(scope.name)
                  : l.inboxPushCategoriesSelected(
                      scope.name,
                      pushCategories.length,
                    ),
              key: const ValueKey('inbox-push-category-summary'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if (pushCategories.isNotEmpty) Text(pushCategories.join(', ')),
            const SizedBox(height: 8),
            Text(l.inboxPushCategoriesDescription),
            const SizedBox(height: 8),
            for (final category in categories.entries)
              Builder(
                builder: (context) {
                  final settings =
                      state.notificationPreferences[scope.id]?.forCategory(
                        category.key,
                      ) ??
                      const SharedNotificationSettings();
                  Widget toggle(
                    String label,
                    bool value,
                    void Function(bool) change, {
                    bool available = true,
                    String? unavailableMessage,
                  }) => SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(label),
                    subtitle: available
                        ? null
                        : Text(unavailableMessage ?? l.inboxChannelUnavailable),
                    value: value,
                    onChanged: _busy || !accountUsable || !available
                        ? null
                        : change,
                  );
                  return ExpansionTile(
                    key: ValueKey(
                      'preference-$binding-${scope.id}-${category.key}',
                    ),
                    initiallyExpanded: category.key == 'reminders',
                    tilePadding: EdgeInsets.zero,
                    title: Text(category.value),
                    children: [
                      toggle(
                        l.inboxChannelInApp,
                        settings.inApp,
                        (value) => _save(
                          scope.id,
                          category.key,
                          SharedNotificationSettings(
                            inApp: value,
                            sound: settings.sound,
                            push: settings.push,
                            email: settings.email,
                          ),
                        ),
                      ),
                      if (category.key == 'reminders')
                        toggle(
                          l.inboxChannelSound,
                          settings.sound,
                          (value) => _save(
                            scope.id,
                            category.key,
                            SharedNotificationSettings(
                              inApp: settings.inApp,
                              sound: value,
                              push: settings.push,
                              email: settings.email,
                            ),
                          ),
                        ),
                      toggle(
                        l.inboxChannelPush,
                        settings.push,
                        (value) => _save(
                          scope.id,
                          category.key,
                          SharedNotificationSettings(
                            inApp: settings.inApp,
                            sound: settings.sound,
                            push: value,
                            email: settings.email,
                          ),
                        ),
                        available: state.externalPushSupported && deviceReady,
                        unavailableMessage: state.externalPushSupported
                            ? l.remotePushDeviceUnavailable
                            : l.inboxChannelUnavailable,
                      ),
                      toggle(
                        l.inboxChannelEmail,
                        settings.email,
                        (value) => _save(
                          scope.id,
                          category.key,
                          SharedNotificationSettings(
                            inApp: settings.inApp,
                            sound: settings.sound,
                            push: settings.push,
                            email: value,
                          ),
                        ),
                        available: state.smtpSupported,
                      ),
                    ],
                  );
                },
              ),
          ],
        ],
      ],
    );
  }
}
