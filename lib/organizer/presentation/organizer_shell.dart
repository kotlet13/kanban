import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../widgets/jivie_brand_mark.dart';
import '../domain/organizer_models.dart';
import '../state/organizer_provider.dart';
import 'calendar_page.dart';
import 'finance_page.dart';
import 'garden/garden_page.dart';
import 'organizer_actions.dart';
import 'organizer_widgets.dart';
import 'projects_page.dart';
import 'settings_page.dart';
import 'shopping_page.dart';
import 'today_page.dart';
import 'shared/sharing_account_page.dart';
import 'shared/sharing_workspace.dart';
import 'shared/space_picker.dart';
import 'people/people_page.dart';
import 'shared/sharing_copy.dart';
import '../state/collaboration_provider.dart';
import '../platform/notification_providers.dart';
import '../platform/remote_push/remote_push_providers.dart';
import 'inbox/inbox_page.dart';
import 'inbox/inbox_preferences.dart';
import 'inbox/notification_target_view.dart';
import 'onboarding/getting_started.dart';
import '../platform/invitation_links/invitation_link.dart';
import '../platform/invitation_links/invitation_link_providers.dart';
import 'shared/sharing_accept.dart';

enum _Area {
  today,
  plans,
  calendar,
  projects,
  shopping,
  finances,
  home,
  garden,
  more,
  settings,
  sharing,
  inbox,
  people,
}

class OrganizerShell extends ConsumerStatefulWidget {
  const OrganizerShell({super.key});
  @override
  ConsumerState<OrganizerShell> createState() => _OrganizerShellState();
}

class _OrganizerShellState extends ConsumerState<OrganizerShell> {
  _Area _area = _Area.today;
  _Area _planArea = _Area.plans;
  String? _shoppingId;
  String? _projectId;
  String? _homeProjectId;
  bool _sharedShopping = false;
  bool _sharedFinance = false;
  String? _sharedScopeId;
  String? _sharedListId;
  String? _sharedProjectId;
  SharingView _sharingView = SharingView.shopping;
  bool _sharingMembers = false;
  bool get _isSharedArea =>
      _area == _Area.sharing ||
      (_area == _Area.shopping && _sharedShopping) ||
      (_area == _Area.finances && _sharedFinance);
  SetupIntent? _setupIntent;
  InvitationLink? _incomingInvitation;
  bool _openingInvite = false;
  Future<void> _startSetup() async {
    final intent = await showGettingStarted(context);
    if (intent == null || !mounted) return;
    try {
      await ref.read(gettingStartedSeenProvider.notifier).acknowledge();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.organizerSaveError)),
        );
      }
    }
    if (!mounted) return;
    setState(() {
      _setupIntent = intent;
      _area = intent == SetupIntent.deviceOnly ? _Area.today : _Area.sharing;
    });
  }

  Future<void> _processInvitation() async {
    if (!mounted || _openingInvite || _openingNotification) return;
    final link = ref.read(pendingInvitationLinkProvider);
    if (link == null) return;
    _openingInvite = true;
    final captured = ref.read(collaborationProvider).valueOrNull?.session;
    final identity = '${captured?.partition}:${captured?.deviceId}';
    try {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.l10n.inviteOpenTitle),
          content: Text(
            '${context.l10n.inviteOpenWarning}\n\n${link.serverUrl}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.l10n.inviteOpenContinue),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (identical(ref.read(pendingInvitationLinkProvider), link)) {
        ref.read(pendingInvitationLinkProvider.notifier).state = null;
      }
      if (proceed != true) return;
      final now = ref.read(collaborationProvider).valueOrNull?.session;
      if ('${now?.partition}:${now?.deviceId}' != identity) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.sharingSessionExpired)),
        );
        return;
      }
      final session = ref.read(collaborationProvider).valueOrNull?.session;
      if (session != null &&
          Uri.parse(
                session.serverUrl,
              ).normalizePath().toString().replaceAll(RegExp(r'/+$'), '') ==
              Uri.parse(
                link.serverUrl,
              ).normalizePath().toString().replaceAll(RegExp(r'/+$'), '')) {
        await showAcceptSharingInvite(
          context,
          ref,
          initialToken: link.token,
          onAccepted: (id) => setState(() {
            _sharedScopeId = id;
            _area = _Area.sharing;
          }),
        );
      } else {
        setState(() {
          _incomingInvitation = link;
          _area = _Area.sharing;
        });
      }
    } finally {
      _openingInvite = false;
    }
  }

  bool _openingNotification = false;
  String? _notificationAttempt;
  String? _remoteAttempt;
  Future<void> _processRemoteReference() async {
    final reference = ref.read(remotePushLaunchReferenceProvider);
    if (!mounted || _openingNotification || reference == null) return;
    final shared = ref.read(collaborationProvider);
    if (shared.isLoading) return;
    final session = shared.valueOrNull?.session;
    final identity = '${session?.partition}:${session?.deviceId}';
    final attempt =
        '$identity:${reference.serverId}:${reference.accountId}:${reference.notificationId}';
    if (_remoteAttempt == attempt) return;
    _remoteAttempt = attempt;
    _openingNotification = true;
    try {
      final result = await ref
          .read(collaborationProvider.notifier)
          .openRemotePushReference(reference);
      if (!mounted) return;
      final current = ref.read(collaborationProvider).valueOrNull?.session;
      if ('${current?.partition}:${current?.deviceId}' != identity) return;
      if (result.target != null &&
          {
            RemotePushOpenStatus.available,
            RemotePushOpenStatus.offline,
          }.contains(result.status)) {
        if (identical(ref.read(remotePushLaunchReferenceProvider), reference)) {
          ref.read(remotePushLaunchReferenceProvider.notifier).state = null;
          ref.read(notificationLaunchTargetProvider.notifier).state =
              result.target;
        }
      } else {
        final l = context.l10n;
        final message = switch (result.status) {
          RemotePushOpenStatus.requiresLogin => l.remotePushLoginForOpen,
          RemotePushOpenStatus.wrongAccount => l.inboxWrongAccount,
          RemotePushOpenStatus.permissionDenied => l.sharingAccessRevoked,
          RemotePushOpenStatus.deleted => l.inboxDeleted,
          _ => l.inboxNeedsConnection,
        };
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l.inboxTitle),
            content: Text(message),
            actions: [
              if ({
                RemotePushOpenStatus.requiresLogin,
                RemotePushOpenStatus.wrongAccount,
              }.contains(result.status))
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _navigate(_Area.sharing);
                  },
                  child: Text(l.sharingGoToAccount),
                ),
              if (result.status == RemotePushOpenStatus.requiresConnection)
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _remoteAttempt = null;
                  },
                  child: Text(l.remotePushRetry),
                ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l.close),
              ),
            ],
          ),
        );
        if (mounted &&
            {
              RemotePushOpenStatus.deleted,
              RemotePushOpenStatus.permissionDenied,
            }.contains(result.status) &&
            identical(ref.read(remotePushLaunchReferenceProvider), reference)) {
          ref.read(remotePushLaunchReferenceProvider.notifier).state = null;
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.inboxNeedsConnection)),
        );
      }
    } finally {
      _openingNotification = false;
      if (mounted) _queueNotificationTarget();
    }
  }

  Future<void> _processNotificationTarget() async {
    if (!mounted || _openingNotification || _openingInvite) return;
    if (ref.read(remotePushLaunchReferenceProvider) != null) {
      await _processRemoteReference();
    }
    if (!mounted || _openingNotification || _openingInvite) return;
    final target = ref.read(notificationLaunchTargetProvider);
    if (target == null) {
      _notificationAttempt = null;
      return;
    }
    if (!ref.read(organizerProvider).hasValue) return;
    final shared = ref.read(collaborationProvider);
    if (!target.isPersonal && shared.isLoading) return;
    final identity = target.isPersonal
        ? 'personal'
        : '${shared.valueOrNull?.session?.partition}:${shared.valueOrNull?.session?.deviceId}';
    final attempt = '$identity:${jsonEncode(target.toJson())}';
    if (_notificationAttempt == attempt) return;
    _notificationAttempt = attempt;
    _openingNotification = true;
    try {
      final opened = await showNotificationTarget(
        context,
        ref,
        target,
        onAccount: () => _navigate(_Area.sharing),
        onMembers: (id) => setState(() {
          _sharedScopeId = id;
          _sharingMembers = true;
          _area = _Area.sharing;
        }),
      );
      if (mounted &&
          opened &&
          identical(ref.read(notificationLaunchTargetProvider), target)) {
        ref.read(notificationLaunchTargetProvider.notifier).state = null;
      }
    } finally {
      _openingNotification = false;
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _processNotificationTarget(),
        );
      }
    }
  }

  void _queueNotificationTarget() => WidgetsBinding.instance
      .addPostFrameCallback((_) => _processNotificationTarget());

  void _selectScope(String? id) => setState(() {
    if (_sharedScopeId != id) {
      _sharedListId = null;
      _sharedProjectId = null;
    }
    _sharedScopeId = id;
  });

  Future<void> _copyList(OrganizerSnapshot snapshot, LocalShoppingList list) =>
      showPublishPersonalCopy(
        context,
        ref,
        personal: snapshot,
        list: list,
        onConnect: () => _navigate(_Area.sharing),
        onPublished: (scopeId, id) => setState(() {
          _sharedScopeId = scopeId;
          _sharedListId = id;
          _sharedShopping = true;
          _area = _Area.shopping;
        }),
      );

  Future<void> _copyProject(OrganizerSnapshot snapshot, LocalProject project) =>
      showPublishPersonalCopy(
        context,
        ref,
        personal: snapshot,
        project: project,
        onConnect: () => _navigate(_Area.sharing),
        onPublished: (scopeId, id) => setState(() {
          _sharedScopeId = scopeId;
          _sharedProjectId = id;
          _sharingView = SharingView.projects;
          _sharingMembers = false;
          _area = _Area.sharing;
        }),
      );
  Future<void> _selectSpace(String? id) async {
    try {
      if (ref.read(collaborationProvider).valueOrNull?.session != null) {
        await ref.read(collaborationProvider.notifier).selectSpace(id);
      }
      if (!mounted) return;
      setState(() {
        _sharedScopeId = id;
        _sharedListId = null;
        _sharedProjectId = null;
        _sharingMembers = false;
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.sharingAccessRevoked)),
        );
      }
    }
  }

  void _navigate(_Area area) => setState(() => _area = area);

  String _label(BuildContext context, _Area area) {
    final l = context.l10n;
    return switch (area) {
      _Area.today => l.organizerToday,
      _Area.plans => l.organizerPlans,
      _Area.calendar => l.organizerCalendar,
      _Area.projects => l.organizerProjects,
      _Area.shopping => l.organizerShopping,
      _Area.finances => l.organizerFinances,
      _Area.home => l.organizerHome,
      _Area.garden => l.gardenTitle,
      _Area.more => l.organizerMore,
      _Area.settings => l.organizerSettings,
      _Area.sharing => l.sharingAccount,
      _Area.inbox => l.inboxTitle,
      _Area.people => l.peopleTitle,
    };
  }

  IconData _icon(_Area area) => switch (area) {
    _Area.today => Icons.wb_sunny_outlined,
    _Area.plans => Icons.event_note_outlined,
    _Area.calendar => Icons.calendar_month_outlined,
    _Area.projects => Icons.folder_outlined,
    _Area.shopping => Icons.shopping_bag_outlined,
    _Area.finances => Icons.account_balance_wallet_outlined,
    _Area.home => Icons.home_outlined,
    _Area.garden => Icons.yard_outlined,
    _Area.more => Icons.grid_view_outlined,
    _Area.settings => Icons.tune_outlined,
    _Area.sharing => Icons.people_outline,
    _Area.inbox => Icons.notifications_none_outlined,
    _Area.people => Icons.person_outline,
  };

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(organizerProvider);
    final l = context.l10n;
    final shared = ref.watch(collaborationProvider).valueOrNull;
    final hasUnread =
        (data.valueOrNull?.reminders.any((r) => !r.isRead) ?? false) ||
        (shared?.inbox.any((item) => !item.isRead) ?? false);
    ref.listen(
      notificationLaunchTargetProvider,
      (_, _) => _queueNotificationTarget(),
    );
    ref.listen(remotePushLaunchReferenceProvider, (_, _) {
      _remoteAttempt = null;
      _queueNotificationTarget();
    });
    ref.listen(collaborationProvider, (_, _) => _queueNotificationTarget());
    ref.listen(organizerProvider, (_, _) => _queueNotificationTarget());
    ref.listen(
      pendingInvitationLinkProvider,
      (_, _) => WidgetsBinding.instance.addPostFrameCallback(
        (_) => _processInvitation(),
      ),
    );
    ref.listen(invitationLinkErrorProvider, (_, invalid) {
      if (invalid) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ref.read(invitationLinkErrorProvider.notifier).state = false;
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(l.inviteLinkInvalid)));
          }
        });
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _processInvitation());
    // Initialization may publish a cold-launch target before this widget mounts.
    _queueNotificationTarget();
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 900;
        final scheme = Theme.of(context).colorScheme;
        final body = data.when(
          data: (snapshot) {
            final actions = OrganizerActions(context, ref, snapshot);
            return SingleChildScrollView(
              key: ValueKey('content-$_area'),
              padding: EdgeInsets.fromLTRB(
                desktop ? 36 : 20,
                desktop ? 32 : 20,
                desktop ? 36 : 20,
                32,
              ),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1160),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      OrganizerSpacePicker(
                        onSelected: _selectSpace,
                        onConnect: () => _navigate(_Area.sharing),
                      ),
                      const SizedBox(height: 16),
                      _content(context, snapshot, actions, desktop),
                    ],
                  ),
                ),
              ),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l.organizerLoadError),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () =>
                        ref.invalidate(organizerRepositoryProvider),
                    child: Text(l.organizerRetry),
                  ),
                ],
              ),
            ),
          ),
        );
        return Scaffold(
          appBar: desktop
              ? null
              : AppBar(
                  title: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const JivieBrandMark(size: 28),
                      const SizedBox(width: 9),
                      Text(l.organizerAppName),
                    ],
                  ),
                  actions: [
                    IconButton(
                      tooltip: l.inboxTitle,
                      onPressed: () => _navigate(_Area.inbox),
                      icon: Badge(
                        isLabelVisible: hasUnread,
                        smallSize: 6,
                        child: const Icon(Icons.notifications_none_outlined),
                      ),
                    ),
                  ],
                ),
          body: SafeArea(
            child: desktop
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _sidebar(context),
                      Expanded(
                        child: Column(
                          children: [
                            Container(
                              height: 72,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 36,
                              ),
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(
                                    color: scheme.outlineVariant,
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.person_outline,
                                    size: 18,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    _isSharedArea
                                        ? l.sharingShared
                                        : l.organizerLocalSpace,
                                  ),
                                  const Spacer(),
                                  Text(
                                    _isSharedArea
                                        ? l.sharingAccount
                                        : l.organizerLocalOnly,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                  const SizedBox(width: 14),
                                  IconButton(
                                    tooltip: l.inboxTitle,
                                    onPressed: () => _navigate(_Area.inbox),
                                    icon: Badge(
                                      isLabelVisible: hasUnread,
                                      smallSize: 6,
                                      child: const Icon(
                                        Icons.notifications_none_outlined,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(child: body),
                          ],
                        ),
                      ),
                    ],
                  )
                : body,
          ),
          bottomNavigationBar: desktop
              ? null
              : NavigationBar(
                  height: 76,
                  backgroundColor: scheme.surface,
                  indicatorColor: scheme.primaryContainer,
                  selectedIndex: switch (_area) {
                    _Area.today => 0,
                    _Area.plans || _Area.projects || _Area.calendar => 1,
                    _Area.shopping => 2,
                    _ => 3,
                  },
                  onDestinationSelected: (i) => _navigate(
                    [_Area.today, _Area.plans, _Area.shopping, _Area.more][i],
                  ),
                  destinations: [
                    for (final area in [
                      _Area.today,
                      _Area.plans,
                      _Area.shopping,
                      _Area.more,
                    ])
                      NavigationDestination(
                        icon: Icon(_icon(area), size: 23),
                        label: _label(context, area),
                      ),
                  ],
                ),
        );
      },
    );
  }

  Widget _sidebar(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final shared = _isSharedArea;
    return Container(
      width: 218,
      padding: const EdgeInsets.fromLTRB(14, 28, 14, 20),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(right: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 32),
              child: Row(
                children: [
                  const JivieBrandMark(),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      l.organizerAppName,
                      style: Theme.of(
                        context,
                      ).textTheme.titleLarge?.copyWith(fontSize: 23),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  for (final area in [
                    _Area.today,
                    _Area.inbox,
                    _Area.plans,
                    _Area.calendar,
                    _Area.projects,
                    _Area.shopping,
                    _Area.finances,
                    _Area.home,
                    _Area.garden,
                    _Area.people,
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: ListTile(
                        dense: true,
                        minTileHeight: 47,
                        selected:
                            _area == area ||
                            (_area == _Area.plans && area == _planArea),
                        selectedTileColor: scheme.surface,
                        selectedColor: scheme.primary,
                        leading: Icon(_icon(area), size: 21),
                        title: Text(_label(context, area)),
                        onTap: () => _navigate(area),
                      ),
                    ),
                ],
              ),
            ),
            ListTile(
              dense: true,
              selected: _area == _Area.sharing,
              leading: const Icon(Icons.people_outline, size: 21),
              title: Text(l.sharingAccount),
              onTap: () => _navigate(_Area.sharing),
            ),
            ListTile(
              dense: true,
              selected: _area == _Area.settings,
              leading: const Icon(Icons.tune_outlined, size: 21),
              title: Text(l.organizerSettings),
              onTap: () => _navigate(_Area.settings),
            ),
            const SizedBox(height: 18),
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 18, 10, 0),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 17,
                    backgroundColor: scheme.primaryContainer,
                    child: Icon(
                      Icons.person_outline,
                      color: scheme.primary,
                      size: 19,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          shared ? l.sharingAccount : l.organizerLocalSpace,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          shared ? l.sharingShared : l.organizerPersonal,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content(
    BuildContext context,
    OrganizerSnapshot snapshot,
    OrganizerActions actions,
    bool desktop,
  ) {
    final l = context.l10n;
    final active = ref
        .watch(collaborationProvider)
        .valueOrNull
        ?.selectedSpaceId;
    if (active != null &&
        const {
          _Area.today,
          _Area.plans,
          _Area.calendar,
          _Area.projects,
          _Area.shopping,
          _Area.finances,
          _Area.home,
          _Area.people,
        }.contains(_area)) {
      final view = switch (_area) {
        _Area.today => SharingView.agenda,
        _Area.calendar => SharingView.timeline,
        _Area.projects || _Area.home => SharingView.projects,
        _Area.shopping => SharingView.shopping,
        _Area.finances => SharingView.finances,
        _Area.people => SharingView.people,
        _ =>
          _planArea == _Area.projects
              ? SharingView.projects
              : (_planArea == _Area.calendar
                    ? SharingView.timeline
                    : SharingView.tasks),
      };
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_area == _Area.plans)
            SegmentedButton<_Area>(
              segments: [
                ButtonSegment(
                  value: _Area.plans,
                  label: Text(l.organizerTasks),
                ),
                ButtonSegment(
                  value: _Area.projects,
                  label: Text(l.organizerProjects),
                ),
                ButtonSegment(
                  value: _Area.calendar,
                  label: Text(l.organizerCalendar),
                ),
              ],
              selected: {_planArea},
              onSelectionChanged: (selection) =>
                  setState(() => _planArea = selection.first),
            ),
          SharingWorkspace(
            view: view,
            selectedScopeId: active,
            showScopePicker: false,
            onScopeSelected: _selectSpace,
            onConnect: () => _navigate(_Area.sharing),
            selectedListId: _sharedListId,
            onListSelected: (id) => setState(() => _sharedListId = id),
            selectedProjectId: _sharedProjectId,
            onProjectSelected: (id) => setState(() => _sharedProjectId = id),
            onMembers: (id) => setState(() {
              _sharedScopeId = id;
              _sharingMembers = true;
              _area = _Area.sharing;
            }),
          ),
        ],
      );
    }
    return switch (_area) {
      _Area.people => OrganizerPeoplePage(
        people: snapshot.people,
        tasks: snapshot.tasks,
        onTask: (task) => actions.task(task: task),
      ),
      _Area.today => OrganizerTodayPage(
        onGettingStarted: _startSetup,
        onSharedAgenda: (scopeId) => setState(() {
          _sharedScopeId = scopeId;
          _sharingView = SharingView.agenda;
          _sharingMembers = false;
          _area = _Area.sharing;
        }),
        snapshot: snapshot,
        actions: actions,
        onShopping: () => _navigate(_Area.shopping),
        onPlans: () => setState(() {
          _planArea = _Area.plans;
          _area = _Area.plans;
        }),
      ),
      _Area.plans => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<_Area>(
            style: ButtonStyle(
              padding: WidgetStateProperty.all(
                const EdgeInsets.symmetric(horizontal: 8),
              ),
              textStyle: WidgetStateProperty.all(const TextStyle(fontSize: 13)),
            ),
            segments: [
              ButtonSegment(value: _Area.plans, label: Text(l.organizerTasks)),
              ButtonSegment(
                value: _Area.projects,
                label: Text(l.organizerProjects),
              ),
              ButtonSegment(
                value: _Area.calendar,
                label: Text(l.organizerCalendar),
              ),
            ],
            selected: {_planArea},
            showSelectedIcon: false,
            onSelectionChanged: (v) => setState(() => _planArea = v.single),
          ),
          const SizedBox(height: 24),
          switch (_planArea) {
            _Area.calendar => OrganizerCalendarPage(
              snapshot: snapshot,
              actions: actions,
            ),
            _Area.projects => OrganizerProjectsPage(
              snapshot: snapshot,
              actions: actions,
              selectedId: _projectId,
              onSelection: (id) => setState(() => _projectId = id),
              onShare: (project) => _copyProject(snapshot, project),
            ),
            _ => OrganizerTasksPage(snapshot: snapshot, actions: actions),
          },
        ],
      ),
      _Area.calendar => OrganizerCalendarPage(
        snapshot: snapshot,
        actions: actions,
      ),
      _Area.projects => OrganizerProjectsPage(
        snapshot: snapshot,
        actions: actions,
        selectedId: _projectId,
        onSelection: (id) => setState(() => _projectId = id),
        onShare: (project) => _copyProject(snapshot, project),
      ),
      _Area.shopping => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                selected: !_sharedShopping,
                label: Text(l.sharingPersonal),
                onSelected: (_) => setState(() => _sharedShopping = false),
              ),
              ChoiceChip(
                selected: _sharedShopping,
                label: Text(l.sharingShared),
                onSelected: (_) => setState(() => _sharedShopping = true),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (_sharedShopping)
            SharingWorkspace(
              view: SharingView.shopping,
              selectedScopeId: _sharedScopeId,
              onScopeSelected: _selectScope,
              selectedListId: _sharedListId,
              onListSelected: (id) => setState(() => _sharedListId = id),
              onConnect: () => _navigate(_Area.sharing),
              onMembers: (id) => setState(() {
                _sharedScopeId = id;
                _sharingMembers = true;
                _area = _Area.sharing;
              }),
            )
          else
            OrganizerShoppingPage(
              snapshot: snapshot,
              actions: actions,
              selectedId: _shoppingId,
              onSelection: (id) => setState(() => _shoppingId = id),
              onShare: (list) => _copyList(snapshot, list),
            ),
        ],
      ),
      _Area.finances => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                selected: !_sharedFinance,
                label: Text(l.sharingPersonal),
                onSelected: (_) => setState(() => _sharedFinance = false),
              ),
              ChoiceChip(
                selected: _sharedFinance,
                label: Text(l.sharingShared),
                onSelected: (_) => setState(() => _sharedFinance = true),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (_sharedFinance)
            SharingWorkspace(
              view: SharingView.finances,
              selectedScopeId: _sharedScopeId,
              onScopeSelected: _selectScope,
              onConnect: () => _navigate(_Area.sharing),
            )
          else
            OrganizerFinancePage(snapshot: snapshot, actions: actions),
        ],
      ),
      _Area.home => OrganizerProjectsPage(
        key: const ValueKey('home'),
        snapshot: snapshot,
        actions: actions,
        home: true,
        selectedId: _homeProjectId,
        onSelection: (id) => setState(() => _homeProjectId = id),
        onShare: (project) => _copyProject(snapshot, project),
      ),
      _Area.settings => OrganizerSettingsPage(actions: actions),
      _Area.garden => const GardenPage(),
      _Area.inbox => OrganizerInboxPage(
        onSettings: () => showInboxPreferences(context, ref),
        onAccount: () => _navigate(_Area.sharing),
      ),
      _Area.sharing => SharingAccountPage(
        setupIntent: _setupIntent,
        initialInvitation: _incomingInvitation,
        onInvitationHandled: () => setState(() => _incomingInvitation = null),
        selectedScopeId: _sharedScopeId,
        onScopeSelected: _selectScope,
        initialView: _sharingView,
        showMembers: _sharingMembers,
        selectedListId: _sharedListId,
        selectedProjectId: _sharedProjectId,
        onListSelected: (id) => setState(() => _sharedListId = id),
        onProjectSelected: (id) => setState(() => _sharedProjectId = id),
      ),
      _Area.more => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OrganizerHeading(title: l.organizerMore),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            leading: const Icon(Icons.waving_hand_outlined),
            title: Text(l.setupOpen),
            onTap: _startSetup,
          ),
          for (final area in [
            _Area.sharing,
            _Area.finances,
            _Area.home,
            _Area.garden,
            _Area.people,
            _Area.settings,
          ])
            ListTile(
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              leading: Icon(
                _icon(area),
                color: Theme.of(context).colorScheme.primary,
              ),
              title: Text(_label(context, area)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _navigate(area),
            ),
          const SizedBox(height: 24),
          Text(
            l.organizerLocalDescription,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    };
  }
}
