import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../l10n/l10n.dart';
import '../../state/collaboration_provider.dart';
import '../../domain/organizer_models.dart';
import '../../state/local_spaces_provider.dart';
import '../../state/notification_local_spaces_provider.dart';
import '../../state/local_notification_preferences_provider.dart';
import '../../state/notification_settings_actions.dart';
import '../../platform/notification_providers.dart';
import '../../platform/local_notification_scheduler.dart';
import '../../platform/remote_push/remote_push_providers.dart';
import '../planning/remote_push_device_settings.dart';
import '../shared/sharing_errors.dart';

/// All entry points open the same full screen, including the reminder editor.
Future<void> showInboxPreferences(
  BuildContext context,
  WidgetRef ref, {
  String? initialScopeId,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (context) => Scaffold(
      appBar: AppBar(title: Text(context.l10n.reminderSettingsTitle)),
      body: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 840),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: InboxPreferences(
                initialScopeId: initialScopeId,
                showHeading: false,
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);

class InboxPreferences extends ConsumerStatefulWidget {
  const InboxPreferences({
    super.key,
    this.initialScopeId,
    this.showHeading = true,
  });
  final String? initialScopeId;
  final bool showHeading;
  @override
  ConsumerState<InboxPreferences> createState() => _InboxPreferencesState();
}

class _InboxPreferencesState extends ConsumerState<InboxPreferences> {
  bool _busy = false, _initialCaptured = false;
  String? _initialIdentity;
  String? get _identity =>
      ref.read(notificationSettingsActionsProvider).identity;

  Future<void> _change(
    String channel,
    bool enabled, {
    Iterable<String> scopes = const [],
    String? category,
    bool local = false,
    String? workspace,
    String? project,
    bool all = false,
  }) async {
    if (_busy) return;
    final identity = _identity;
    setState(() => _busy = true);
    try {
      await ref
          .read(notificationSettingsActionsProvider)
          .change(
            channel: channel,
            enabled: enabled,
            expectedIdentity: identity,
            scopeIds: scopes,
            category: category,
            includeLocal: local,
            workspace: workspace,
            project: project,
            all: all,
          );
    } catch (error) {
      if (mounted && identity == _identity) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is CollaborationException
                  ? sharingErrorMessage(context, error)
                  : context.l10n.inboxDeviceError,
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<String> _categories(CollaborationState state, SharedScope scope) => [
    for (final category in sharedNotificationCategories)
      if (category != 'ideas' || state.recordContractVersion >= 5)
        if (category != 'finance' ||
            state.financePolicyForScope(scope.id).canRead)
          category,
  ];
  String _category(String category) {
    final l = context.l10n;
    return switch (category) {
      'reminders' => l.inboxCategoryReminders,
      'tasks' => l.inboxCategoryTasks,
      'events' => l.inboxCategoryEvents,
      'shopping' => l.inboxCategoryShopping,
      'membership' => l.inboxCategoryMembers,
      'finance' => l.inboxCategoryFinance,
      _ => l.ideasTitle,
    };
  }

  String _channel(String channel) {
    final l = context.l10n;
    return switch (channel) {
      'inApp' => l.inboxChannelInApp,
      'sound' => l.notificationSound,
      'push' => l.notificationPush,
      _ => l.inboxChannelEmail,
    };
  }

  bool? _aggregate(Iterable<bool> values) {
    final list = values.toList();
    if (list.isEmpty) return false;
    if (list.every((v) => v)) return true;
    if (list.every((v) => !v)) return false;
    return null;
  }

  Widget _toggle(
    String id,
    String channel,
    Iterable<bool> values,
    void Function(bool)? change, {
    String? unavailable,
    String? label,
  }) {
    final value = _aggregate(values);
    return CheckboxListTile(
      key: ValueKey('notification-setting-$id-$channel'),
      contentPadding: EdgeInsets.zero,
      title: Text(label ?? _channel(channel)),
      subtitle: unavailable != null
          ? Text(unavailable)
          : value == null
          ? Text(context.l10n.notificationMixed)
          : null,
      tristate: true,
      value: value,
      onChanged: _busy || change == null ? null : (_) => change(value != true),
      controlAffinity: ListTileControlAffinity.trailing,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final sharedAsync = ref.watch(collaborationProvider);
    final shared = sharedAsync.valueOrNull ?? CollaborationState();
    final identity = _identity;
    if (!_initialCaptured && !sharedAsync.isLoading) {
      _initialCaptured = true;
      _initialIdentity = identity;
    }
    final scopes =
        shared.scopes.where((s) => !s.revoked && !s.archived).toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    final localAsync = ref.watch(notificationLocalSnapshotsProvider);
    final snapshots = localAsync.valueOrNull ?? const <OrganizerSnapshot>[];
    final policyAsync = ref.watch(localNotificationPreferencesProvider);
    final policy = policyAsync.valueOrNull;
    final catalog = ref.watch(localSpacesProvider).valueOrNull;
    final usable =
        !sharedAsync.isLoading &&
        !sharedAsync.hasError &&
        remotePushAccountUsable(shared) &&
        shared.inboxSupported;
    final ready =
        policy != null &&
        !policyAsync.isLoading &&
        !policyAsync.hasError &&
        !localAsync.isLoading &&
        !localAsync.hasError &&
        !sharedAsync.isLoading &&
        !sharedAsync.hasError;
    final localValues = [
      if (policy != null)
        for (final snapshot in snapshots) ...[
          policy.resolve(snapshot.workspaceKey),
          for (final project in snapshot.projects)
            policy.resolve(snapshot.workspaceKey, project.id),
        ],
    ];
    final remoteValues = [
      for (final scope in scopes)
        for (final category in _categories(shared, scope))
          shared.notificationPreferences[scope.id]?.forCategory(category) ??
              const SharedNotificationSettings(),
    ];
    bool remoteChannelAvailable(String channel) =>
        usable &&
        (channel != 'push' || shared.externalPushSupported) &&
        (channel != 'email' || shared.smtpSupported);
    String? unavailable(String channel) => !remotePushAccountUsable(shared)
        ? l.sharingLoginAction
        : !usable
        ? l.inboxChannelUnavailable
        : channel == 'email' && !shared.smtpSupported ||
              channel == 'push' && !shared.externalPushSupported
        ? l.inboxChannelUnavailable
        : null;
    Widget card(List<Widget> children) => Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
    Widget localControls(String workspace, String? project) {
      final settings = policy!.resolve(workspace, project);
      final id =
          'local-${LocalNotificationPreferences.key(workspace, project)}';
      return Column(
        children: [
          for (final channel in ['inApp', 'sound', 'push'])
            _toggle(
              id,
              channel,
              [settings.channel(channel)],
              !ready
                  ? null
                  : (value) => _change(
                      channel,
                      value,
                      local: true,
                      workspace: workspace,
                      project: project,
                    ),
              label: channel == 'push' ? l.notificationDeviceDelivery : null,
            ),
        ],
      );
    }

    String localName(OrganizerSnapshot snapshot) =>
        snapshot.workspaceKey.startsWith('private:') ||
            snapshot.workspaceKey == 'local'
        ? l.organizerPersonal
        : catalog?.spaces
                  .where((s) => s.id == snapshot.workspaceKey)
                  .firstOrNull
                  ?.name ??
              l.organizerLocalOnly;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showHeading) ...[
          Text(
            l.reminderSettingsTitle,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
        ],
        card([
          Text(
            l.notificationAllSpaces,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(l.notificationAllSpacesDescription),
          if (_busy) const LinearProgressIndicator(),
          if (policyAsync.isLoading ||
              localAsync.isLoading ||
              sharedAsync.isLoading)
            const Padding(
              padding: EdgeInsets.all(8),
              child: LinearProgressIndicator(),
            ),
          for (final channel in ['inApp', 'sound', 'push', 'email'])
            _toggle(
              'all',
              channel,
              [
                if (channel != 'email')
                  for (final settings in localValues) settings.channel(channel),
                for (final settings in remoteValues) settings.channel(channel),
              ],
              !ready ||
                      scopes.isNotEmpty && !remoteChannelAvailable(channel) ||
                      channel == 'email' && scopes.isEmpty
                  ? null
                  : (value) => _change(
                      channel,
                      value,
                      scopes: scopes.map((s) => s.id),
                      local: true,
                      all: true,
                    ),
              unavailable: scopes.isEmpty && channel == 'email'
                  ? l.notificationServerRequired
                  : scopes.isNotEmpty && !remoteChannelAvailable(channel)
                  ? unavailable(channel)
                  : null,
            ),
        ]),
        if (localAsync.hasError || policyAsync.hasError)
          card([
            Text(l.inboxDeviceError),
            TextButton(
              onPressed: () {
                ref.invalidate(notificationLocalSnapshotsProvider);
                ref.invalidate(localNotificationPreferencesProvider);
              },
              child: Text(l.organizerRetry),
            ),
          ]),
        const SizedBox(height: 16),
        Text(
          l.notificationSpacesAndProjects,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(l.notificationIndividualDescription),
        if (policy != null)
          for (final snapshot in snapshots)
            card([
              ExpansionTile(
                key: ValueKey(
                  'notification-local-space-${snapshot.workspaceKey}',
                ),
                tilePadding: EdgeInsets.zero,
                title: Text(localName(snapshot)),
                subtitle: Text(l.notificationLocalSpace),
                children: [
                  localControls(snapshot.workspaceKey, null),
                  for (final project in snapshot.projects)
                    ExpansionTile(
                      key: ValueKey(
                        'notification-local-project-${snapshot.workspaceKey}-${project.id}',
                      ),
                      title: Text(project.title),
                      subtitle: Text(l.organizerProjects),
                      children: [
                        localControls(snapshot.workspaceKey, project.id),
                      ],
                    ),
                ],
              ),
            ]),
        for (final scope in scopes)
          card([
            ExpansionTile(
              key: ValueKey('notification-shared-space-${scope.id}'),
              initiallyExpanded:
                  _initialIdentity == identity &&
                  widget.initialScopeId == scope.id,
              tilePadding: EdgeInsets.zero,
              title: Text(scope.name),
              subtitle: Text(
                scope.kind == SharedScopeKind.project
                    ? l.organizerProjects
                    : l.notificationSharedSpace,
              ),
              children: [
                for (final channel in ['inApp', 'sound', 'push', 'email'])
                  _toggle(
                    scope.id,
                    channel,
                    [
                      for (final category in _categories(shared, scope))
                        (shared.notificationPreferences[scope.id]?.forCategory(
                                  category,
                                ) ??
                                const SharedNotificationSettings())
                            .channel(channel),
                    ],
                    remoteChannelAvailable(channel)
                        ? (value) => _change(channel, value, scopes: [scope.id])
                        : null,
                    unavailable: remoteChannelAvailable(channel)
                        ? null
                        : unavailable(channel),
                  ),
                ExpansionTile(
                  title: Text(l.notificationTypes),
                  tilePadding: EdgeInsets.zero,
                  children: [
                    for (final category in _categories(shared, scope))
                      ExpansionTile(
                        key: ValueKey(
                          'notification-category-${scope.id}-$category',
                        ),
                        title: Text(_category(category)),
                        children: [
                          for (final channel in [
                            'inApp',
                            'sound',
                            'push',
                            'email',
                          ])
                            _toggle(
                              '${scope.id}-$category',
                              channel,
                              [
                                (shared.notificationPreferences[scope.id]
                                            ?.forCategory(category) ??
                                        const SharedNotificationSettings())
                                    .channel(channel),
                              ],
                              remoteChannelAvailable(channel)
                                  ? (value) => _change(
                                      channel,
                                      value,
                                      scopes: [scope.id],
                                      category: category,
                                    )
                                  : null,
                              unavailable: remoteChannelAvailable(channel)
                                  ? null
                                  : unavailable(channel),
                            ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ]),
        if (snapshots.isEmpty && scopes.isEmpty && ready)
          Text(l.notificationNoSpaces),
        const SizedBox(height: 16),
        card([
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(l.notificationThisDevice),
            children: [
              Text(l.notificationDeviceDescription),
              ref
                  .watch(localNotificationDeviceStatusProvider)
                  .when(
                    data: (status) => Text(switch (status.permission) {
                      LocalNotificationPermission.granted =>
                        l.inboxDeviceGranted,
                      LocalNotificationPermission.denied => l.inboxDeviceDenied,
                      LocalNotificationPermission.unsupported =>
                        l.inboxDeviceUnsupported,
                      LocalNotificationPermission.unknown =>
                        l.inboxDeviceUnknown,
                    }),
                    loading: () => const LinearProgressIndicator(),
                    error: (_, _) => Text(l.inboxDeviceError),
                  ),
              const SizedBox(height: 16),
              const RemotePushDeviceSettings(),
            ],
          ),
        ]),
      ],
    );
  }
}
