import 'dart:async';
import '../state/idea_provider.dart';
import 'ideas/idea_editor.dart';
import 'ideas/ideas_page.dart';
import 'ideas/ideas_all_spaces_page.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../widgets/jivie_brand_mark.dart';
import '../domain/organizer_models.dart';
import '../state/organizer_provider.dart';
import '../state/local_spaces_provider.dart';
import '../state/garden_provider.dart';
import '../state/inbox_projection_provider.dart';
import 'all_spaces/all_spaces_page.dart';
import 'all_spaces/all_spaces_rows.dart';
import '../state/all_spaces_provider.dart';
import 'desktop/desktop_layout.dart';
import 'desktop/desktop_frame.dart';
import 'desktop/desktop_inspector.dart';
import 'desktop/desktop_commands.dart';
import 'desktop/desktop_search.dart';
import 'shared/collaboration_actions.dart';
import 'finance/shared_finance_actions.dart';
import 'calendar_page.dart';
import 'finance_page.dart';
import 'garden/garden_page.dart';
import 'garden/garden_space_chooser.dart';
import 'organizer_actions.dart';
import 'organizer_widgets.dart';
import 'projects_page.dart';
import 'settings_page.dart';
import 'shopping_page.dart';
import 'today_page.dart';
import 'shared/sharing_account_page.dart';
import 'shared/sharing_auth.dart';
import 'shared/invitation_wizard.dart';
import 'shared/received_invitation_notice.dart';
import 'shared/connect_space_flow.dart';
import 'shared/scope_invitation_form.dart';
import 'shared/sharing_errors.dart';
import 'shared/space_settings_page.dart';
import 'shared/sharing_workspace.dart';
import 'shared/space_picker.dart';
import 'shared/household_transfer.dart';
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
import 'navigation/organizer_destination_widgets.dart';
import 'backup/backup_wizard.dart';
import 'backup/backup_recovery.dart';
import 'onboarding/first_time_guide.dart';
import 'jivie_public_links.dart';
import 'navigation/organizer_navigation.dart';
import 'navigation/organizer_back_boundary.dart';

typedef _Area = OrganizerArea;

class OrganizerShell extends ConsumerStatefulWidget {
  const OrganizerShell({super.key});
  @override
  ConsumerState<OrganizerShell> createState() => _OrganizerShellState();
}

class _OrganizerShellState extends ConsumerState<OrganizerShell> {
  final _navigationState = OrganizerNavigationState();
  final _history = OrganizerNavigationHistory();
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _desktopInspector = OrganizerDesktopInspectorController();
  final _desktopInspectorKey = GlobalKey();
  bool _desktopPlannerExpanded = true, _desktopSpaceExpanded = true;
  int _navigationRevision = 0;
  int _spaceRestorations = 0;
  int _navigationOperation = 0;
  bool get _restoringSpace => _spaceRestorations > 0;

  String get _accountIdentity {
    final session = ref.read(collaborationProvider).valueOrNull?.session;
    return '${session?.partition}:${session?.deviceId}';
  }

  OrganizerLocation get _location {
    final selection = ref.read(collaborationProvider).valueOrNull;
    return _navigationState.location(
      spaceId: selection?.selectedSpaceId,
      allSpaces: selection?.allSpacesSelected == true,
      localSpaceId:
          ref.read(localSpacesProvider).valueOrNull?.selectedSpaceId ?? 'local',
    );
  }

  void _changeNavigation(VoidCallback change) {
    final before = _location;
    setState(() {
      change();
      final after = _location;
      _history.record(before, after);
      if (before != after) {
        _navigationRevision++;
        _navigationOperation++;
      }
    });
  }

  void _clearNavigationHistory({bool accountChanged = false}) {
    _history.clear();
    _navigationOperation++;
    _navigationState.clearSelections(accountChanged: accountChanged);
    if (accountChanged) {
      _incomingInvitation = null;
      _setupIntent = null;
    }
    _navigationRevision++;
  }

  Future<void> _goBack() async {
    final previous = _history.takePrevious();
    if (previous == null) {
      setState(() {
        _clearNavigationHistory();
        _navigationState.area = _Area.today;
      });
      return;
    }
    final identity = _accountIdentity;
    final operation = ++_navigationOperation;
    final revision = _navigationRevision;
    final current = _location;
    if (previous.spaceId != current.spaceId ||
        previous.allSpaces != current.allSpaces ||
        previous.localSpaceId != current.localSpaceId) {
      _spaceRestorations++;
      try {
        final controller = ref.read(collaborationProvider.notifier);
        if (previous.allSpaces) {
          await controller.selectAllSpaces();
        } else {
          await controller.selectSpace(previous.spaceId);
          if (previous.spaceId == null) {
            await ref
                .read(localSpacesProvider.notifier)
                .selectSpace(previous.localSpaceId);
          }
        }
      } catch (_) {
        if (mounted &&
            identity == _accountIdentity &&
            operation == _navigationOperation) {
          setState(() => _navigationRevision++);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.sharingAccessRevoked)),
          );
        }
        return;
      } finally {
        _spaceRestorations--;
      }
    }
    if (!mounted ||
        identity != _accountIdentity ||
        operation != _navigationOperation ||
        revision != _navigationRevision) {
      return;
    }
    setState(() {
      _navigationState.restore(previous);
      _navigationRevision++;
    });
  }

  bool get _isSharedArea =>
      ref.read(collaborationProvider).valueOrNull?.selectedSpaceId != null;
  String _spaceKindLabel(BuildContext context) {
    final shared = ref.read(collaborationProvider).valueOrNull;
    final scope = shared?.scopes
        .where((s) => s.id == shared.selectedSpaceId)
        .firstOrNull;
    final local = ref.read(localSpacesProvider).valueOrNull?.selectedSpace;
    if (scope?.kind == SharedScopeKind.organization ||
        scope == null && local?.kind == LocalSpaceKind.organization) {
      return context.l10n.organizationTitle;
    }
    if (scope?.kind == SharedScopeKind.household ||
        scope == null && local?.kind == LocalSpaceKind.household) {
      return context.l10n.sharingHousehold;
    }
    if (scope?.kind == SharedScopeKind.project) {
      return context.l10n.organizerProjects;
    }
    return context.l10n.organizerPersonal;
  }

  bool get _spaceConnected =>
      _isSharedArea ||
      ref
              .read(organizerProvider)
              .valueOrNull
              ?.workspaceKey
              .startsWith('private:') ==
          true;
  IconData get _spaceKindIcon {
    final shared = ref.read(collaborationProvider).valueOrNull;
    if (shared?.allSpacesSelected == true) return Icons.dashboard_outlined;
    final scope = shared?.scopes
        .where((s) => s.id == shared.selectedSpaceId)
        .firstOrNull;
    final local = ref.read(localSpacesProvider).valueOrNull?.selectedSpace;
    if (scope?.kind == SharedScopeKind.organization ||
        scope == null && local?.kind == LocalSpaceKind.organization) {
      return Icons.business_outlined;
    }
    if (scope?.kind == SharedScopeKind.household ||
        scope == null && local?.kind == LocalSpaceKind.household) {
      return Icons.home_outlined;
    }
    if (scope?.kind == SharedScopeKind.project) return Icons.folder_outlined;
    return Icons.person_outline;
  }

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
    if (intent == SetupIntent.invitation) {
      await showInvitationWizard(context, ref, onAccepted: _invitationAccepted);
      return;
    }
    _changeNavigation(() {
      _setupIntent = intent;
      _navigationState.area = intent == SetupIntent.deviceOnly
          ? _Area.today
          : _Area.sharing;
    });
  }

  void _invitationAccepted(String id) {
    if (!mounted) return;
    final state = ref.read(collaborationProvider).valueOrNull;
    if (state?.selectedSpaceId != id || state?.sessionInvalid != false) return;
    _changeNavigation(() {
      _incomingInvitation = null;
      _navigationState.sharedScopeId = id;
      _navigationState.area = _Area.today;
      _navigationState.sharedListId = null;
      _navigationState.sharedProjectId = null;
    });
  }

  Future<void> _processInvitation() async {
    if (!mounted ||
        _openingInvite ||
        _openingNotification ||
        _spaceFlowBusy ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    final link = ref.read(pendingInvitationLinkProvider);
    if (link == null) return;
    _openingInvite = true;
    try {
      // Only consume the routing signal. The wizard owns the securely saved
      // invitation, including origin confirmation and resuming after login.
      if (identical(ref.read(pendingInvitationLinkProvider), link)) {
        ref.read(pendingInvitationLinkProvider.notifier).state = null;
      }
      await showInvitationWizard(
        context,
        ref,
        initialLink: link,
        onAccepted: _invitationAccepted,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(sharingErrorMessage(context, error))),
        );
      }
    } finally {
      _openingInvite = false;
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _processInvitation(),
        );
      }
    }
  }

  bool _spaceFlowBusy = false;

  bool get _canShareCurrentSpace {
    final state = ref.read(collaborationProvider).valueOrNull;
    if (state?.allSpacesSelected == true || state?.deletionPending == true) {
      return false;
    }
    final scope = state?.scopes
        .where((s) => s.id == state.selectedSpaceId)
        .firstOrNull;
    if (state?.selectedSpaceId != null) {
      return scope != null &&
          scope.kind != SharedScopeKind.personal &&
          scope.canManage &&
          !scope.blocked &&
          !scope.archived;
    }
    final local = ref.read(localSpacesProvider).valueOrNull?.selectedSpace;
    return local != null &&
        local.kind != LocalSpaceKind.personal &&
        !local.archived;
  }

  Future<bool> _authenticateForSpace() => showSharingSignIn(
    context,
    initialServer:
        ref.read(collaborationProvider).valueOrNull?.session?.serverUrl ?? '',
  );

  Future<void> _connectCurrentSpace({bool invite = false}) async {
    if (_spaceFlowBusy || _desktopInspector.isOpen) return;
    final initial = ref.read(collaborationProvider).valueOrNull;
    if (initial?.allSpacesSelected == true) return;
    final originalScope = initial?.selectedSpaceId;
    final originalPartition = initial?.session?.partition;
    final local = ref.read(localSpacesProvider).valueOrNull?.selectedSpace;
    if (originalScope == null &&
        (local == null || local.kind == LocalSpaceKind.personal)) {
      _navigate(_Area.sharing);
      return;
    }
    setState(() => _spaceFlowBusy = true);
    try {
      var state = initial;
      var authenticated = false;
      if (state?.session == null ||
          state!.sessionInvalid ||
          !state.session!.expiresAt.isAfter(DateTime.now())) {
        if (!await _authenticateForSpace() || !mounted) return;
        state = ref.read(collaborationProvider).valueOrNull;
        authenticated = true;
      }
      if (state?.session == null ||
          state!.sessionInvalid ||
          state.deletionPending) {
        return;
      }
      // A shared-space action cannot be continued under another account.
      if (originalScope != null &&
          state.session!.partition != originalPartition) {
        return;
      }
      final identity = _accountIdentity;
      var target = originalScope;
      if (target == null) {
        target = await showLocalSpaceConnection(
          context,
          ref,
          localSpaceId: local!.id,
        );
        if (!mounted || target == null || identity != _accountIdentity) return;
        await _selectSpace(target);
      } else if (authenticated && state.selectedSpaceId != target) {
        await _selectSpace(target);
      }
      if (!mounted || identity != _accountIdentity) return;
      state = ref.read(collaborationProvider).valueOrNull;
      if (state?.selectedSpaceId != target || state?.sessionInvalid != false) {
        return;
      }
      final scope = state!.scopes.where((s) => s.id == target).firstOrNull;
      if (scope == null) return;
      if (invite) {
        final sent = await showScopeInvitation(
          context,
          ref,
          scope: scope,
          session: state.session!,
        );
        if (sent &&
            mounted &&
            identity == _accountIdentity &&
            ref.read(collaborationProvider).valueOrNull?.selectedSpaceId ==
                target) {
          _openSpaceSettings(target);
        }
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(sharingErrorMessage(context, error))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _spaceFlowBusy = false);
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _processInvitation(),
        );
      }
    }
  }

  Widget _shareSpaceButton() => IconButton(
    key: const ValueKey('organizer-share-space'),
    tooltip: context.l10n.spaceFlowShare,
    onPressed: _spaceFlowBusy || _desktopInspector.isOpen
        ? null
        : () => _connectCurrentSpace(invite: true),
    icon: const Icon(Icons.person_add_alt_outlined),
  );

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
      if (ref.read(remotePushSummaryLaunchProvider) &&
          session != null &&
          reference.matches(session)) {
        ref.read(remotePushSummaryLaunchProvider.notifier).state = false;
        ref.read(remotePushLaunchReferenceProvider.notifier).state = null;
        _navigate(_Area.inbox);
        unawaited(
          ref
              .read(collaborationProvider.notifier)
              .syncNow()
              .catchError((Object _) {}),
        );
        return;
      }
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
          await showNotificationTarget(
            context,
            ref,
            result.target!,
            validatedResult: NotificationOpenResult(
              status: NotificationOpenStatus.values.byName(result.status.name),
              target: result.target!,
            ),
            onAccount: () => _navigate(_Area.sharing),
            onMembers: _openSpaceSettings,
            isCurrent: () => mounted && _accountIdentity == identity,
          );
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
        onMembers: _openSpaceSettings,
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

  void _selectScope(String? id) => _changeNavigation(() {
    if (_navigationState.sharedScopeId != id) {
      _navigationState.sharedListId = null;
      _navigationState.sharedProjectId = null;
    }
    _navigationState.sharedScopeId = id;
  });

  Future<void> _copyList(OrganizerSnapshot snapshot, LocalShoppingList list) =>
      showPublishPersonalCopy(
        context,
        ref,
        personal: snapshot,
        list: list,
        onConnect: () => _navigate(_Area.sharing),
        onPublished: (scopeId, id) async {
          final identity = _accountIdentity;
          await _selectSpace(scopeId);
          if (!mounted ||
              identity != _accountIdentity ||
              ref.read(collaborationProvider).valueOrNull?.selectedSpaceId !=
                  scopeId) {
            return;
          }
          _changeNavigation(() {
            _navigationState.sharedScopeId = scopeId;
            _navigationState.sharedListId = id;
            _navigationState.sharedShopping = true;
            _navigationState.area = _Area.shopping;
          });
        },
      );

  Future<void> _copyProject(OrganizerSnapshot snapshot, LocalProject project) =>
      showPublishPersonalCopy(
        context,
        ref,
        personal: snapshot,
        project: project,
        onConnect: () => _navigate(_Area.sharing),
        onPublished: (scopeId, id) async {
          final identity = _accountIdentity;
          await _selectSpace(scopeId);
          if (!mounted ||
              identity != _accountIdentity ||
              ref.read(collaborationProvider).valueOrNull?.selectedSpaceId !=
                  scopeId) {
            return;
          }
          _changeNavigation(() {
            _navigationState.sharedScopeId = scopeId;
            _navigationState.sharedProjectId = id;
            _navigationState.sharingView = SharingView.projects;
            _navigationState.area = _Area.projects;
          });
        },
      );
  Future<void> _selectSpace(String? id) async {
    final identity = _accountIdentity;
    setState(() => _clearNavigationHistory());
    try {
      await ref.read(collaborationProvider.notifier).selectSpace(id);
      if (!mounted || identity != _accountIdentity) return;
      setState(() {
        _navigationState.sharedScopeId = id;
        _navigationState.sharedListId = null;
        _navigationState.sharedProjectId = null;
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.sharingAccessRevoked)),
        );
      }
    }
  }

  Future<void> _selectLocalSpace(String id) async {
    if (_restoringSpace) return;
    final space = ref
        .read(localSpacesProvider)
        .valueOrNull
        ?.spaces
        .where((s) => s.id == id)
        .firstOrNull;
    if (space?.binding != null) {
      final shared = ref.read(collaborationProvider).valueOrNull;
      if (space!.binding!.partition == shared?.session?.partition &&
          shared?.scopes.any(
                (s) => s.id == space.binding!.scopeId && !s.revoked,
              ) ==
              true) {
        await _selectSpace(space.binding!.scopeId);
      }
      return;
    }
    final identity = _accountIdentity;
    setState(() {
      _clearNavigationHistory();
      _navigationState.area = _Area.today;
    });
    try {
      await ref.read(collaborationProvider.notifier).selectSpace(null);
      if (!mounted || identity != _accountIdentity) return;
      await ref.read(localSpacesProvider.notifier).selectSpace(id);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.organizerSaveError)),
        );
      }
    }
  }

  Future<void> _selectAllSpaces() async {
    final identity = _accountIdentity;
    setState(() => _clearNavigationHistory());
    try {
      await ref.read(collaborationProvider.notifier).selectAllSpaces();
      if (!mounted || identity != _accountIdentity) return;
      setState(() {
        _navigationState.sharedScopeId = null;
        _navigationState.sharedListId = null;
        _navigationState.sharedProjectId = null;
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.organizerSaveError)),
        );
      }
    }
  }

  Future<void> _openAllSpacesSource(
    AllSpacesSource source,
    AllSpacesArea area,
    String? id,
  ) async {
    if (_restoringSpace || !allSpacesSourceIsCurrent(ref, source)) return;
    final previous = _location;
    final identity = _accountIdentity;
    final operation = ++_navigationOperation;
    final revision = _navigationRevision;
    _spaceRestorations++;
    try {
      await ref
          .read(collaborationProvider.notifier)
          .selectSpace(source.scopeId);
      if (source.isLocalSpace) {
        await ref
            .read(localSpacesProvider.notifier)
            .selectSpace(source.workspaceKey!);
      }
    } catch (_) {
      if (mounted &&
          identity == _accountIdentity &&
          operation == _navigationOperation) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.sharingAccessRevoked)),
        );
      }
      return;
    } finally {
      _spaceRestorations--;
    }
    if (!mounted ||
        identity != _accountIdentity ||
        operation != _navigationOperation ||
        revision != _navigationRevision ||
        !allSpacesSourceIsCurrent(ref, source)) {
      return;
    }
    final current = ref.read(collaborationProvider).asData?.value;
    if (current == null ||
        current.allSpacesSelected ||
        current.selectedSpaceId != source.scopeId) {
      return;
    }
    setState(() {
      _navigationState.clearSelections(accountChanged: false);
      _navigationState.sharedScopeId = source.scopeId;
      _navigationState.area = switch (area) {
        AllSpacesArea.today => _Area.today,
        AllSpacesArea.tasks => _Area.plans,
        AllSpacesArea.calendar => _Area.calendar,
        AllSpacesArea.projects => _Area.projects,
        AllSpacesArea.shopping => _Area.shopping,
        AllSpacesArea.finances => _Area.finances,
        AllSpacesArea.home => _Area.home,
        AllSpacesArea.people => _Area.people,
      };
      if (organizerDestinationFor(_navigationState.area) ==
          OrganizerDestination.planner) {
        _navigationState.planArea = _navigationState.area;
      }
      _navigationState.sharedShopping = false;
      _navigationState.sharedFinance = false;
      if (area == AllSpacesArea.shopping) {
        if (source.isPersonal) {
          _navigationState.shoppingId = id;
        } else {
          _navigationState.sharedListId = id;
        }
      }
      if (area == AllSpacesArea.projects || area == AllSpacesArea.home) {
        if (source.isPersonal) {
          _navigationState.projectId = id;
          _navigationState.homeProjectId = id;
        } else {
          _navigationState.sharedProjectId = id;
        }
      }
      _history.record(previous, _location);
      _navigationRevision++;
    });
  }

  void _navigate(_Area area) => _changeNavigation(() {
    _navigationState.area = area;
    if (organizerDestinationFor(area) == OrganizerDestination.planner) {
      _navigationState.planArea = area;
    }
  });

  void _selectDestination(OrganizerDestination destination) {
    setState(() {
      _history.clear();
      _navigationState.clearSelections(accountChanged: false);
      _navigationOperation++;
      _navigationRevision++;
      _navigationState.area = switch (destination) {
        OrganizerDestination.pulse => _Area.today,
        OrganizerDestination.planner => _navigationState.planArea,
        OrganizerDestination.space => _Area.space,
        OrganizerDestination.more => _Area.more,
      };
    });
  }

  void _selectPlannerView(_Area area) {
    setState(() {
      _navigationState.area = area;
      _navigationState.planArea = area;
      _navigationOperation++;
      _navigationRevision++;
    });
  }

  String _destinationLabel(
    BuildContext context,
    OrganizerDestination destination,
  ) => switch (destination) {
    OrganizerDestination.pulse => context.l10n.organizerPulse,
    OrganizerDestination.planner => context.l10n.organizerPlanner,
    OrganizerDestination.space => context.l10n.organizerSpace,
    OrganizerDestination.more => context.l10n.organizerMore,
  };

  IconData _destinationIcon(OrganizerDestination destination) =>
      switch (destination) {
        OrganizerDestination.pulse => Icons.space_dashboard_outlined,
        OrganizerDestination.planner => Icons.event_note_outlined,
        OrganizerDestination.space => Icons.folder_open_outlined,
        OrganizerDestination.more => Icons.more_horiz,
      };

  Future<void> _openSpaceSettings(String? scopeId) async {
    if (_restoringSpace) return;
    final selection = ref.read(collaborationProvider).valueOrNull;
    if (scopeId == null ||
        (selection?.selectedSpaceId == scopeId &&
            selection?.allSpacesSelected == false)) {
      _navigate(_Area.spaceSettings);
      return;
    }
    final session = selection?.session;
    if (selection == null ||
        session == null ||
        selection.sessionInvalid ||
        !session.expiresAt.isAfter(DateTime.now()) ||
        !selection.scopes.any(
          (scope) =>
              scope.id == scopeId &&
              scope.kind != SharedScopeKind.personal &&
              !scope.revoked &&
              !scope.blocked,
        )) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.sharingAccessRevoked)),
      );
      return;
    }
    final before = _location;
    final identity = _accountIdentity;
    final operation = ++_navigationOperation;
    final revision = _navigationRevision;
    _spaceRestorations++;
    try {
      await ref.read(collaborationProvider.notifier).selectSpace(scopeId);
    } catch (_) {
      if (mounted &&
          identity == _accountIdentity &&
          operation == _navigationOperation) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.sharingAccessRevoked)),
        );
      }
      return;
    } finally {
      _spaceRestorations--;
    }
    if (!mounted) return;
    final current = ref.read(collaborationProvider).valueOrNull;
    if (identity != _accountIdentity ||
        operation != _navigationOperation ||
        revision != _navigationRevision ||
        current?.selectedSpaceId != scopeId ||
        current?.allSpacesSelected != false ||
        current?.sessionInvalid != false ||
        current?.session?.expiresAt.isAfter(DateTime.now()) != true ||
        !current!.scopes.any(
          (scope) => scope.id == scopeId && !scope.revoked && !scope.blocked,
        )) {
      return;
    }
    setState(() {
      _navigationState.sharedScopeId = scopeId;
      _navigationState.sharedListId = null;
      _navigationState.sharedProjectId = null;
      _navigationState.area = _Area.spaceSettings;
      _history.record(before, _location);
      _navigationRevision++;
    });
  }

  List<_Area> _contentAreas() {
    final shared = ref.watch(collaborationProvider).valueOrNull;
    final personal = ref.watch(organizerProvider).valueOrNull;
    final local = ref.watch(localSpacesProvider).valueOrNull?.selectedSpace;
    final scope = shared?.scopes
        .where((s) => s.id == shared.selectedSpaceId)
        .firstOrNull;
    final household =
        scope?.kind == SharedScopeKind.household ||
        (scope == null && local?.kind == LocalSpaceKind.household);
    final all = shared?.allSpacesSelected == true;
    final localPersonal =
        scope == null &&
        local?.kind != LocalSpaceKind.organization &&
        !household;
    final legacyGarden =
        localPersonal &&
        ref.watch(gardenProvider).valueOrNull?.gardens.isNotEmpty == true;
    return [
      _Area.today,
      _Area.plans,
      _Area.calendar,
      _Area.projects,
      _Area.ideas,
      _Area.finances,
      if (household ||
          all ||
          (localPersonal && personal?.shoppingLists.isNotEmpty == true))
        _Area.shopping,
      if (household || all || legacyGarden) _Area.garden,
      if (household ||
          all ||
          (localPersonal && personal?.people.isNotEmpty == true))
        _Area.people,
      _Area.inbox,
    ];
  }

  String _label(BuildContext context, _Area area) {
    final l = context.l10n;
    return switch (area) {
      _Area.today => l.organizerPulse,
      _Area.plans => l.organizerTasks,
      _Area.calendar => l.organizerCalendar,
      _Area.projects => l.organizerProjects,
      _Area.shopping => l.organizerShopping,
      _Area.finances => l.organizerFinances,
      _Area.home => l.organizerHome,
      _Area.garden => l.gardenTitle,
      _Area.ideas => l.ideasTitle,
      _Area.space => l.organizerSpace,
      _Area.more => l.organizerMore,
      _Area.backups => l.organizerBackups,
      _Area.settings => l.organizerSettings,
      _Area.reminderSettings => l.reminderSettingsTitle,
      _Area.spaceSettings => l.spaceSettingsTitle,
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
    _Area.ideas => Icons.lightbulb_outline,
    _Area.space => Icons.folder_open_outlined,
    _Area.more => Icons.more_horiz,
    _Area.backups => Icons.backup_outlined,
    _Area.settings => Icons.tune_outlined,
    _Area.reminderSettings => Icons.notifications_active_outlined,
    _Area.spaceSettings => Icons.settings_outlined,
    _Area.sharing => Icons.people_outline,
    _Area.inbox => Icons.notifications_none_outlined,
    _Area.people => Icons.person_outline,
  };

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(organizerProvider);
    final l = context.l10n;
    final hasUnread = ref.watch(organizerInboxHasUnreadProvider);
    final allSpaces =
        ref.watch(collaborationProvider).valueOrNull?.allSpacesSelected == true;
    ref.listen(
      notificationLaunchTargetProvider,
      (_, _) => _queueNotificationTarget(),
    );
    ref.listen(remotePushLaunchReferenceProvider, (_, _) {
      _remoteAttempt = null;
      _queueNotificationTarget();
    });
    ref.listen(collaborationProvider, (previous, next) {
      final oldState = previous?.valueOrNull;
      final nextState = next.valueOrNull;
      if (nextState != null && oldState != null) {
        final oldSession = oldState.session;
        final newSession = nextState.session;
        final changedAccount =
            '${oldSession?.partition}:${oldSession?.deviceId}' !=
            '${newSession?.partition}:${newSession?.deviceId}';
        final changedSpace =
            oldState.selectedSpaceId != nextState.selectedSpaceId ||
            oldState.allSpacesSelected != nextState.allSpacesSelected;
        if (changedAccount || (changedSpace && !_restoringSpace)) {
          setState(
            () => _clearNavigationHistory(accountChanged: changedAccount),
          );
        }
      }
      _queueNotificationTarget();
    });
    ref.listen(localSpacesProvider, (previous, next) {
      if (previous?.valueOrNull?.selectedSpaceId !=
              next.valueOrNull?.selectedSpaceId &&
          previous?.valueOrNull != null &&
          !_restoringSpace) {
        setState(() => _clearNavigationHistory());
      }
    });
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
    return OrganizerDesktopInspectorScope(
      controller: _desktopInspector,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final desktopExperience = organizerUsesDesktopLayout(context);
          final desktop = desktopExperience || constraints.maxWidth >= 900;
          final phone = !desktopExperience && constraints.maxWidth < 600;
          final scheme = Theme.of(context).colorScheme;
          final body = _navigationState.area == _Area.reminderSettings
              ? const InboxPreferencesScrollView(
                  key: ValueKey('content-_Area.reminderSettings'),
                )
              : data.when(
                  data: (snapshot) {
                    final actions = OrganizerActions(
                      context,
                      ref,
                      snapshot,
                      onProjectShare: (project) =>
                          _copyProject(snapshot, project),
                    );
                    return SingleChildScrollView(
                      key: ValueKey(
                        'content-_Area.${_navigationState.area.name}',
                      ),
                      padding: EdgeInsets.fromLTRB(
                        desktop
                            ? 36
                            : phone && _navigationState.area == _Area.calendar
                            ? 12
                            : 20,
                        desktop ? 32 : 20,
                        desktop
                            ? 36
                            : phone && _navigationState.area == _Area.calendar
                            ? 12
                            : 20,
                        32,
                      ),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1160),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (!phone && !desktopExperience) ...[
                                OrganizerSpacePicker(
                                  onSelected: _selectSpace,
                                  onLocalSelected: _selectLocalSpace,
                                  onAllSelected: _selectAllSpaces,
                                  onAuthenticate: _authenticateForSpace,
                                  onConnect: () => _navigate(_Area.sharing),
                                ),
                                const SizedBox(height: 16),
                              ],
                              if (!desktopExperience &&
                                  organizerDestinationFor(
                                        _navigationState.area,
                                      ) ==
                                      OrganizerDestination.planner) ...[
                                OrganizerHeading(
                                  title: l.organizerPlanner,
                                  subtitle: l.organizerPlannerIntro,
                                ),
                                OrganizerPlannerViews(
                                  selected: _navigationState.area,
                                  onSelected: _selectPlannerView,
                                ),
                                const SizedBox(height: 20),
                              ],
                              if (desktop &&
                                  !desktopExperience &&
                                  _showBackControl) ...[
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton.icon(
                                    key: const ValueKey('organizer-shell-back'),
                                    onPressed: _goBack,
                                    icon: const Icon(Icons.arrow_back),
                                    label: Text(l.organizerBack),
                                  ),
                                ),
                                const SizedBox(height: 12),
                              ],
                              if (_navigationState.area == _Area.today)
                                ReceivedInvitationNotice(
                                  onAccepted: _invitationAccepted,
                                ),
                              if (organizerDestinationFor(
                                    _navigationState.area,
                                  ) ==
                                  OrganizerDestination.planner)
                                Theme(
                                  data: Theme.of(context).copyWith(
                                    textTheme: Theme.of(context).textTheme
                                        .copyWith(
                                          headlineSmall: Theme.of(context)
                                              .textTheme
                                              .headlineSmall
                                              ?.copyWith(fontSize: 22),
                                        ),
                                  ),
                                  child: _content(
                                    context,
                                    snapshot,
                                    actions,
                                    desktop,
                                  ),
                                )
                              else
                                _content(context, snapshot, actions, desktop),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
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
          if (desktopExperience) {
            final areas = [
              ..._contentAreas(),
              _Area.sharing,
              _Area.spaceSettings,
              _Area.reminderSettings,
              _Area.settings,
              _Area.backups,
            ];
            return AnimatedBuilder(
              animation: _desktopInspector,
              builder: (context, _) => OrganizerDesktopCommands(
                platform: Theme.of(context).platform,
                visibleAreas: areas,
                areaLabel: (area) => _label(context, area),
                onNavigate: (area) {
                  if (ModalRoute.of(context)?.isCurrent == true) {
                    _navigate(area);
                  }
                },
                onSearch: () => _desktopSearch(context),
                onSettings: () {
                  if (ModalRoute.of(context)?.isCurrent == true) {
                    _navigate(_Area.settings);
                  }
                },
                onNew: _desktopInspector.isOpen || !_canDesktopCreate
                    ? null
                    : () => _desktopNew(context),
                canGoBack:
                    _history.canGoBack || _navigationState.area != _Area.today,
                onBack: _goBack,
                child: OrganizerBackBoundary(
                  scaffoldKey: _scaffoldKey,
                  phone: false,
                  hasPrevious:
                      _history.canGoBack ||
                      _navigationState.area != _Area.today,
                  navigationRevision: _navigationRevision,
                  onBack: _goBack,
                  child: Scaffold(
                    key: _scaffoldKey,
                    body: SafeArea(
                      child: OrganizerDesktopFrame(
                        key: const ValueKey('organizer-desktop-frame'),
                        controller: _desktopInspector,
                        sidebar: (compact) => _desktopSidebar(context, compact),
                        toolbar: (toggle) => _desktopToolbar(
                          context,
                          toggleSidebar: toggle,
                          hasUnread: hasUnread,
                        ),
                        content: body,
                        inspector: OrganizerDesktopInspectorPanel(
                          key: _desktopInspectorKey,
                          controller: _desktopInspector,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }
          return OrganizerBackBoundary(
            scaffoldKey: _scaffoldKey,
            phone: phone,
            hasPrevious:
                _history.canGoBack || _navigationState.area != _Area.today,
            navigationRevision: _navigationRevision,
            onBack: _goBack,
            child: Scaffold(
              key: _scaffoldKey,
              appBar: desktop
                  ? null
                  : AppBar(
                      titleSpacing: phone ? (_showBackControl ? 0 : 16) : null,
                      toolbarHeight: phone
                          ? (MediaQuery.textScalerOf(context).scale(16) + 24)
                                .clamp(kToolbarHeight, double.infinity)
                          : null,
                      automaticallyImplyLeading: false,
                      leading: _showBackControl
                          ? IconButton(
                              key: const ValueKey('organizer-shell-back'),
                              tooltip: l.organizerBack,
                              icon: const Icon(Icons.arrow_back),
                              onPressed: _goBack,
                            )
                          : null,
                      title: Row(
                        mainAxisSize: phone
                            ? MainAxisSize.max
                            : MainAxisSize.min,
                        children: [
                          const JivieBrandMark(size: 28),
                          const SizedBox(width: 9),
                          if (phone)
                            Expanded(
                              child: OrganizerSpacePicker(
                                compact: true,
                                onSelected: _selectSpace,
                                onLocalSelected: _selectLocalSpace,
                                onAllSelected: _selectAllSpaces,
                                onAuthenticate: _authenticateForSpace,
                                onConnect: () => _navigate(_Area.sharing),
                              ),
                            )
                          else
                            Text(l.organizerAppName),
                        ],
                      ),
                      actions: [
                        if (_canShareCurrentSpace) _shareSpaceButton(),
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
                                        _spaceKindIcon,
                                        size: 18,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        allSpaces
                                            ? l.allSpacesTitle
                                            : _spaceKindLabel(context),
                                      ),
                                      const Spacer(),
                                      if (_canShareCurrentSpace)
                                        _shareSpaceButton(),
                                      Text(
                                        allSpaces
                                            ? l.allSpacesSources
                                            : _spaceConnected
                                            ? l.spaceConnectedShort
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
                      key: const ValueKey('organizer-primary-navigation'),
                      height: MediaQuery.textScalerOf(context).scale(12) > 18
                          ? 88
                          : 80,
                      backgroundColor: scheme.surface,
                      indicatorColor: scheme.primaryContainer,
                      selectedIndex: organizerDestinationFor(
                        _navigationState.area,
                      ).index,
                      onDestinationSelected: (index) => _selectDestination(
                        OrganizerDestination.values[index],
                      ),
                      destinations: [
                        for (final destination in OrganizerDestination.values)
                          NavigationDestination(
                            key: ValueKey(
                              'organizer-destination-${destination.name}',
                            ),
                            icon: Icon(_destinationIcon(destination), size: 23),
                            selectedIcon: Icon(switch (destination) {
                              OrganizerDestination.pulse =>
                                Icons.space_dashboard,
                              OrganizerDestination.planner => Icons.event_note,
                              OrganizerDestination.space => Icons.folder_open,
                              OrganizerDestination.more => Icons.more_horiz,
                            }, size: 23),
                            label: _destinationLabel(context, destination),
                          ),
                      ],
                    ),
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _desktopInspector.dispose();
    super.dispose();
  }

  bool get _canDesktopCreate {
    final shared = ref.read(collaborationProvider).asData?.value;
    if (shared?.allSpacesSelected == true) {
      return ref
              .read(allSpacesProvider)
              .asData
              ?.value
              .sources
              .any(
                (s) =>
                    s.isPersonal ||
                    (s.scope?.canEdit == true &&
                        !s.scope!.blocked &&
                        !s.scope!.revoked &&
                        !s.scope!.archived),
              ) ==
          true;
    }
    final scope = shared?.scopes
        .where((s) => s.id == shared.selectedSpaceId)
        .firstOrNull;
    return scope == null
        ? ref.read(organizerProvider).asData != null
        : shared?.localAccessAllowed == true &&
              scope.canEdit &&
              !scope.revoked &&
              !scope.blocked &&
              !scope.archived;
  }

  Widget _desktopToolbar(
    BuildContext context, {
    required VoidCallback toggleSidebar,
    required bool hasUnread,
  }) {
    final l = context.l10n;
    return Row(
      children: [
        IconButton(
          key: const ValueKey('desktop-toggle-sidebar'),
          tooltip: l.desktopToggleSidebar,
          onPressed: toggleSidebar,
          icon: const Icon(Icons.view_sidebar_outlined),
        ),
        if (_showBackControl)
          IconButton(
            key: const ValueKey('organizer-shell-back'),
            tooltip: l.organizerBack,
            onPressed: _goBack,
            icon: const Icon(Icons.arrow_back),
          ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _label(context, _navigationState.area),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        if (_canShareCurrentSpace) _shareSpaceButton(),
        IconButton(
          key: const ValueKey('desktop-search'),
          tooltip: l.desktopSearch,
          onPressed: () => _desktopSearch(context),
          icon: const Icon(Icons.search),
        ),
        IconButton(
          tooltip: l.inboxTitle,
          onPressed: () => _navigate(_Area.inbox),
          icon: Badge(
            isLabelVisible: hasUnread,
            smallSize: 6,
            child: const Icon(Icons.notifications_none_outlined),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          key: const ValueKey('desktop-new'),
          onPressed: _desktopInspector.isOpen || !_canDesktopCreate
              ? null
              : () => _desktopNew(context),
          icon: const Icon(Icons.add),
          label: Text(l.desktopNew),
        ),
      ],
    );
  }

  Future<void> _desktopSelectSpace(String? id, {bool local = false}) async {
    if (_desktopInspector.isOpen) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.desktopFinishEditing)),
      );
      return;
    }
    if (local && id != null) {
      await _selectLocalSpace(id);
    } else {
      await _selectSpace(id);
    }
  }

  Widget _desktopSidebar(BuildContext context, bool compact) {
    final l = context.l10n;
    final colors = Theme.of(context).colorScheme;
    Widget picker() => OrganizerSpacePicker(
      compact: true,
      onSelected: (id) => _desktopSelectSpace(id),
      onLocalSelected: (id) => _desktopSelectSpace(id, local: true),
      onAllSelected: () {
        if (_desktopInspector.isOpen) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(l.desktopFinishEditing)));
        } else {
          _selectAllSpaces();
        }
      },
      onAuthenticate: _authenticateForSpace,
      onConnect: () => _navigate(_Area.sharing),
    );
    Widget link(_Area area, {Key? key}) => Tooltip(
      message: _label(context, area),
      child: ListTile(
        key: key ?? ValueKey('organizer-leaf-${area.name}'),
        selected: _navigationState.area == area,
        selectedTileColor: colors.primaryContainer,
        selectedColor: colors.primary,
        contentPadding: EdgeInsets.symmetric(horizontal: compact ? 12 : 16),
        minTileHeight: 48,
        leading: Icon(_icon(area), size: 21),
        title: compact ? null : Text(_label(context, area)),
        onTap: () => _navigate(area),
      ),
    );
    Widget group(
      OrganizerDestination destination,
      bool expanded,
      VoidCallback toggle,
      List<_Area> areas,
    ) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Tooltip(
          message: _destinationLabel(context, destination),
          child: ListTile(
            key: ValueKey('organizer-destination-${destination.name}'),
            contentPadding: EdgeInsets.symmetric(horizontal: compact ? 12 : 16),
            minTileHeight: 48,
            leading: Icon(_destinationIcon(destination), size: 21),
            title: compact
                ? null
                : Text(
                    _destinationLabel(context, destination),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
            trailing: compact
                ? null
                : IconButton(
                    tooltip: _destinationLabel(context, destination),
                    onPressed: toggle,
                    icon: Icon(
                      expanded ? Icons.expand_less : Icons.expand_more,
                    ),
                  ),
            onTap: () => _selectDestination(destination),
          ),
        ),
        if (compact || expanded)
          for (final area in areas) link(area),
      ],
    );
    return Material(
      color: colors.surfaceContainerLow,
      child: ListView(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 4 : 10,
          vertical: 16,
        ),
        children: [
          if (!compact) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
              child: Row(
                children: [
                  const JivieBrandMark(size: 28),
                  const SizedBox(width: 10),
                  Text(
                    l.organizerAppName,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ],
              ),
            ),
            picker(),
          ] else
            IconButton(
              tooltip: l.organizerPersonal,
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => Dialog(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: SizedBox(width: 380, child: picker()),
                  ),
                ),
              ),
              icon: Icon(_spaceKindIcon),
            ),
          const SizedBox(height: 16),
          link(_Area.today, key: const ValueKey('organizer-destination-pulse')),
          link(_Area.inbox),
          const Divider(height: 24),
          group(
            OrganizerDestination.planner,
            _desktopPlannerExpanded,
            () => setState(
              () => _desktopPlannerExpanded = !_desktopPlannerExpanded,
            ),
            [_Area.plans, _Area.calendar, _Area.ideas],
          ),
          const Divider(height: 24),
          group(
            OrganizerDestination.space,
            _desktopSpaceExpanded,
            () =>
                setState(() => _desktopSpaceExpanded = !_desktopSpaceExpanded),
            _destinationAreas(OrganizerDestination.space),
          ),
          const Divider(height: 24),
          if (!compact)
            TextButton(
              key: const ValueKey('organizer-destination-more'),
              onPressed: () => _navigate(_Area.more),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(l.organizerMoreTools),
              ),
            ),
          for (final area in [
            _Area.sharing,
            _Area.spaceSettings,
            _Area.backups,
            _Area.reminderSettings,
            _Area.settings,
          ])
            link(area),
        ],
      ),
    );
  }

  Future<void> _desktopSearch(BuildContext context) async {
    if (ModalRoute.of(context)?.isCurrent != true) return;
    final identity = _accountIdentity;
    final result = await showDialog<OrganizerDesktopSearchResult>(
      context: context,
      builder: (_) => const OrganizerDesktopSearch(),
    );
    if (!mounted ||
        !context.mounted ||
        identity != _accountIdentity ||
        result == null) {
      return;
    }
    if (_desktopInspector.isOpen) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.desktopFinishEditing)),
      );
      return;
    }
    final idea = result.idea;
    if (idea != null) {
      await _openIdeaSource(
        shared: idea.sharedScopeId != null,
        spaceId: idea.sharedScopeId ?? idea.localSpaceId ?? 'local',
        boardId: idea.board.id,
      );
      return;
    }
    final row = result.row!;
    if (!allSpacesSourceIsCurrent(
      ref,
      row.source,
      financial: row.amountMinor != null,
    )) {
      return;
    }
    final area = switch (row.type) {
      'task' => AllSpacesArea.tasks,
      'event' => AllSpacesArea.calendar,
      'project' => AllSpacesArea.projects,
      'shoppingList' || 'shoppingItem' => AllSpacesArea.shopping,
      'person' => AllSpacesArea.people,
      _ => AllSpacesArea.finances,
    };
    final currentPersonal = ref.read(organizerProvider).asData?.value;
    final currentSelection = ref.read(collaborationProvider).asData?.value;
    final alreadyLocal =
        row.source.isPersonal &&
        currentPersonal?.workspaceKey == row.source.workspaceKey &&
        currentSelection?.allSpacesSelected != true &&
        currentSelection?.selectedSpaceId == null;
    if (alreadyLocal &&
        !const {'project', 'shoppingList', 'person'}.contains(row.type)) {
      _navigate(switch (area) {
        AllSpacesArea.tasks => _Area.plans,
        AllSpacesArea.calendar => _Area.calendar,
        AllSpacesArea.shopping => _Area.shopping,
        _ => _Area.finances,
      });
    } else {
      await _openAllSpacesSource(
        row.source,
        area,
        const {'project', 'shoppingList', 'person'}.contains(row.type)
            ? row.id
            : null,
      );
    }
    if (!context.mounted ||
        identity != _accountIdentity ||
        !allSpacesSourceIsCurrent(
          ref,
          row.source,
          financial: row.amountMinor != null,
        )) {
      return;
    }
    if (const {'project', 'shoppingList', 'person'}.contains(row.type)) return;
    if (row.source.isPersonal) {
      final snapshot = await ref.read(organizerProvider.future);
      if (!context.mounted ||
          identity != _accountIdentity ||
          snapshot.workspaceKey != row.source.workspaceKey) {
        return;
      }
      final actions = OrganizerActions(context, ref, snapshot);
      if (row.type == 'task') {
        final item = snapshot.tasks.where((v) => v.id == row.id).firstOrNull;
        if (item != null) await actions.task(task: item);
        return;
      }
      if (row.type == 'event') {
        final item = snapshot.events.where((v) => v.id == row.id).firstOrNull;
        if (item != null) await actions.event(item);
        return;
      }
      if (row.type == 'personalFinanceEntry') {
        final item = snapshot.financeEntries
            .where((v) => v.id == row.id)
            .firstOrNull;
        if (item != null) await actions.finance(item);
        return;
      }
    }
    await openAllSpacesRow(context, ref, row);
  }

  Future<void> _desktopNew(BuildContext context) async {
    if (ModalRoute.of(context)?.isCurrent != true ||
        _desktopInspector.isOpen ||
        !_canDesktopCreate) {
      return;
    }
    final identity = _accountIdentity;
    final l = context.l10n;
    final type = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l.desktopNew),
        children: [
          for (final (value, label, icon) in [
            ('task', l.organizerAddTask, Icons.checklist),
            ('event', l.organizerAddEvent, Icons.event_outlined),
            ('project', l.organizerAddProject, Icons.folder_outlined),
            ('idea', l.ideasAdd, Icons.lightbulb_outline),
            (
              'finance',
              l.organizerAddFinance,
              Icons.account_balance_wallet_outlined,
            ),
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, value),
              child: Row(
                children: [
                  Icon(icon),
                  const SizedBox(width: 12),
                  Flexible(child: Text(label)),
                ],
              ),
            ),
        ],
      ),
    );
    if (type == null || !context.mounted || identity != _accountIdentity) {
      return;
    }
    if (ref.read(collaborationProvider).valueOrNull?.allSpacesSelected ==
        true) {
      final snapshot = ref.read(allSpacesProvider).asData?.value;
      if (snapshot == null) return;
      final source = await showDialog<AllSpacesSource>(
        context: context,
        builder: (context) => SimpleDialog(
          title: Text(l.allSpacesChooseTarget),
          children: [
            for (final s in snapshot.sources.where(
              (s) =>
                  s.isPersonal ||
                  (s.scope?.canEdit == true &&
                      !s.scope!.blocked &&
                      !s.scope!.revoked &&
                      !s.scope!.archived),
            ))
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, s),
                child: Text(allSpacesSourceLabel(context, s)),
              ),
          ],
        ),
      );
      if (source == null ||
          !context.mounted ||
          identity != _accountIdentity ||
          !allSpacesSourceIsCurrent(ref, source)) {
        return;
      }
      await _openAllSpacesSource(source, AllSpacesArea.tasks, null);
    }
    if (!context.mounted ||
        identity != _accountIdentity ||
        !_canDesktopCreate) {
      return;
    }
    if (type == 'idea') {
      _navigate(_Area.ideas);
      await openIdeaEditor(context, ref);
      return;
    }
    final shared = ref.read(collaborationProvider).asData?.value;
    final scope = shared?.scopes
        .where((s) => s.id == shared.selectedSpaceId)
        .firstOrNull;
    if (scope != null && shared != null) {
      final actions = CollaborationActions(
        context,
        ref,
        scope,
        shared.dataForScope(scope.id),
      );
      switch (type) {
        case 'task':
          await actions.task();
        case 'event':
          await actions.event();
        case 'project':
          await actions.project();
        case 'finance':
          if (shared.financePolicyForScope(scope.id).canWrite &&
              shared.financeSnapshotComplete[scope.id] == true) {
            await SharedFinanceActions(context, ref, scope, shared).entry();
          }
      }
    } else {
      final snapshot = await ref.read(organizerProvider.future);
      if (!context.mounted || identity != _accountIdentity) return;
      final actions = OrganizerActions(context, ref, snapshot);
      switch (type) {
        case 'task':
          await actions.task();
        case 'event':
          await actions.event();
        case 'project':
          await actions.project();
        case 'finance':
          await actions.finance();
      }
    }
  }

  Widget _sidebar(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final allSpaces =
        ref.watch(collaborationProvider).valueOrNull?.allSpacesSelected == true;
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
                  for (final destination in OrganizerDestination.values) ...[
                    ListTile(
                      key: ValueKey(
                        'organizer-destination-${destination.name}',
                      ),
                      minTileHeight: 56,
                      selected:
                          organizerDestinationFor(_navigationState.area) ==
                          destination,
                      selectedTileColor: scheme.surface,
                      selectedColor: scheme.primary,
                      leading: Icon(_destinationIcon(destination), size: 21),
                      title: Text(_destinationLabel(context, destination)),
                      onTap: () => _selectDestination(destination),
                    ),
                    if (organizerDestinationFor(_navigationState.area) ==
                        destination)
                      for (final area in _destinationAreas(destination))
                        Padding(
                          padding: const EdgeInsets.only(left: 12),
                          child: ListTile(
                            key: ValueKey('organizer-leaf-${area.name}'),
                            minTileHeight: 48,
                            selected: _navigationState.area == area,
                            leading: Icon(_icon(area), size: 18),
                            title: Text(_label(context, area)),
                            onTap: () => _navigate(area),
                          ),
                        ),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
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
                      _spaceKindIcon,
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
                          allSpaces
                              ? l.allSpacesTitle
                              : _spaceKindLabel(context),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          allSpaces
                              ? l.allSpacesSources
                              : _spaceConnected
                              ? l.spaceConnectedShort
                              : l.spaceLocalShort,
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

  Future<void> _openIdeaSource({
    required bool shared,
    required String spaceId,
    String? boardId,
  }) async {
    final identity = _accountIdentity;
    if (shared) {
      await _selectSpace(spaceId);
    } else {
      await _selectLocalSpace(spaceId);
    }
    if (!mounted || identity != _accountIdentity) return;
    final snapshot = await ref.read(ideaProvider.future);
    if (!shared &&
        boardId != null &&
        snapshot.workspaceKey != spaceId &&
        mounted &&
        identity == _accountIdentity) {
      await openLocalIdeaViewer(
        context,
        ref,
        spaceId: spaceId,
        boardId: boardId,
        onReviewPrivate: () {
          if (mounted && identity == _accountIdentity) _navigate(_Area.sharing);
        },
      );
      return;
    }
    if (!mounted ||
        identity != _accountIdentity ||
        (shared
            ? snapshot.sharedScopeId != spaceId
            : snapshot.workspaceKey != spaceId)) {
      return;
    }
    final board = boardId == null
        ? null
        : snapshot.boards.where((b) => b.id == boardId).firstOrNull;
    if (boardId != null && board == null ||
        boardId == null && !snapshot.canEdit) {
      return;
    }
    await openIdeaEditor(context, ref, board: board);
  }

  void _openOverviewArea(AllSpacesArea area) => _navigate(switch (area) {
    AllSpacesArea.calendar => _Area.calendar,
    AllSpacesArea.projects => _Area.projects,
    _ => _Area.plans,
  });

  bool get _showBackControl =>
      _history.canGoBack ||
      !const {
        _Area.today,
        _Area.space,
        _Area.more,
        _Area.plans,
        _Area.calendar,
        _Area.ideas,
      }.contains(_navigationState.area);

  List<_Area> _destinationAreas(OrganizerDestination destination) =>
      switch (destination) {
        OrganizerDestination.pulse => [_Area.inbox],
        OrganizerDestination.planner => [
          _Area.plans,
          _Area.calendar,
          _Area.ideas,
        ],
        OrganizerDestination.space =>
          _contentAreas()
              .where(
                (area) =>
                    organizerDestinationFor(area) == OrganizerDestination.space,
              )
              .toList(),
        OrganizerDestination.more => [
          _Area.sharing,
          _Area.spaceSettings,
          _Area.reminderSettings,
          _Area.settings,
          _Area.backups,
        ],
      };

  Widget _spaceHub(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      OrganizerHeading(
        title: context.l10n.organizerSpace,
        subtitle: context.l10n.organizerSpaceIntro,
      ),
      for (final area in _destinationAreas(OrganizerDestination.space))
        OrganizerHubLink(
          key: ValueKey('organizer-hub-${area.name}'),
          title: _label(context, area),
          subtitle: switch (area) {
            _Area.projects => context.l10n.organizerProjectsHint,
            _Area.finances => context.l10n.organizerFinancesHint,
            _Area.shopping => context.l10n.organizerShoppingHint,
            _Area.garden => context.l10n.organizerGardenHint,
            _Area.people => context.l10n.organizerPeopleHint,
            _ => null,
          },
          icon: _icon(area),
          onTap: () => _navigate(area),
        ),
    ],
  );

  Widget _moreHub(BuildContext context) {
    final l = context.l10n;
    Widget heading(String title) => Padding(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 12),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OrganizerHeading(
          title: l.organizerMore,
          subtitle: l.organizerMoreIntro,
        ),
        heading(l.organizerMoreAccount),
        for (final area in [_Area.sharing, _Area.spaceSettings])
          OrganizerHubLink(
            title: _label(context, area),
            icon: _icon(area),
            onTap: () => _navigate(area),
          ),
        heading(l.organizerMoreTools),
        for (final area in [
          _Area.reminderSettings,
          _Area.settings,
          _Area.backups,
        ])
          OrganizerHubLink(
            title: _label(context, area),
            icon: _icon(area),
            onTap: () => _navigate(area),
          ),
        heading(l.organizerMoreHelp),
        OrganizerHubLink(
          title: l.guideOpen,
          icon: Icons.explore_outlined,
          onTap: () => showFirstTimeGuide(context, ref),
        ),
        OrganizerHubLink(
          title: l.setupOpen,
          icon: Icons.waving_hand_outlined,
          onTap: _startSetup,
        ),
        const JiviePublicLinks(),
      ],
    );
  }

  Widget _content(
    BuildContext context,
    OrganizerSnapshot snapshot,
    OrganizerActions actions,
    bool desktop,
  ) {
    final l = context.l10n;
    final selection = ref.watch(collaborationProvider).valueOrNull;
    final active = selection?.selectedSpaceId;
    if (_navigationState.area == _Area.ideas) {
      return selection?.allSpacesSelected == true
          ? IdeasAllSpacesPage(onOpenSource: _openIdeaSource)
          : const IdeasPage();
    }
    if (selection?.allSpacesSelected == true &&
        const {
          _Area.today,
          _Area.plans,
          _Area.calendar,
          _Area.projects,
          _Area.shopping,
          _Area.finances,
          _Area.home,
          _Area.people,
        }.contains(_navigationState.area)) {
      final area = switch (_navigationState.area) {
        _Area.today => AllSpacesArea.today,
        _Area.calendar => AllSpacesArea.calendar,
        _Area.projects => AllSpacesArea.projects,
        _Area.shopping => AllSpacesArea.shopping,
        _Area.finances => AllSpacesArea.finances,
        _Area.home => AllSpacesArea.home,
        _Area.people => AllSpacesArea.people,
        _ => AllSpacesArea.tasks,
      };
      return AllSpacesPage(
        key: ValueKey('all-spaces-${area.name}'),
        area: area,
        onSource: _openAllSpacesSource,
        onOverviewArea: _openOverviewArea,
      );
    }
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
        }.contains(_navigationState.area)) {
      final view = switch (_navigationState.area) {
        _Area.today => SharingView.agenda,
        _Area.calendar => SharingView.timeline,
        _Area.projects || _Area.home => SharingView.projects,
        _Area.shopping => SharingView.shopping,
        _Area.finances => SharingView.finances,
        _Area.people => SharingView.people,
        _ => SharingView.tasks,
      };
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SharingWorkspace(
            view: view,
            selectedScopeId: active,
            onSource: _openAllSpacesSource,
            onOverviewArea: _openOverviewArea,
            showScopePicker: false,
            onScopeSelected: _selectSpace,
            onConnect: () => _navigate(_Area.sharing),
            selectedListId: _navigationState.sharedListId,
            onListSelected: (id) =>
                _changeNavigation(() => _navigationState.sharedListId = id),
            selectedProjectId: _navigationState.sharedProjectId,
            onProjectSelected: (id) =>
                _changeNavigation(() => _navigationState.sharedProjectId = id),
            onMembers: _openSpaceSettings,
          ),
        ],
      );
    }
    return switch (_navigationState.area) {
      _Area.people => OrganizerPeoplePage(
        people: snapshot.people,
        tasks: snapshot.tasks,
        onTask: (task) => actions.task(task: task),
      ),
      _Area.today => OrganizerTodayPage(
        onInvitation: () =>
            showInvitationWizard(context, ref, onAccepted: _invitationAccepted),
        onGettingStarted:
            ref.watch(localSpacesProvider).valueOrNull?.selectedSpace?.kind ==
                LocalSpaceKind.personal
            ? _startSetup
            : null,
        onSharedAgenda: (scopeId) => _changeNavigation(() {
          _navigationState.sharedScopeId = scopeId;
          _navigationState.sharingView = SharingView.agenda;
          _navigationState.area = _Area.sharing;
        }),
        snapshot: snapshot,
        actions: actions,
        onShopping: () => _navigate(_Area.shopping),
        showShopping: _contentAreas().contains(_Area.shopping),
        onCalendar: () => _navigate(_Area.calendar),
        onProjects: () => _navigate(_Area.projects),
        onProjectSelected: (id) => _changeNavigation(() {
          _navigationState.area = _Area.projects;
          _navigationState.projectId = id;
        }),
        onPlans: () => _changeNavigation(() {
          _navigationState.planArea = _Area.plans;
          _navigationState.area = _Area.plans;
        }),
      ),
      _Area.plans => OrganizerTasksPage(snapshot: snapshot, actions: actions),
      _Area.calendar => OrganizerCalendarPage(
        snapshot: snapshot,
        actions: actions,
      ),
      _Area.projects => OrganizerProjectsPage(
        snapshot: snapshot,
        actions: actions,
        selectedId: _navigationState.projectId,
        onSelection: (id) =>
            _changeNavigation(() => _navigationState.projectId = id),
        onShare: (project) => _copyProject(snapshot, project),
        scopeLabel:
            ref.watch(localSpacesProvider).valueOrNull?.selectedSpace?.kind ==
                LocalSpaceKind.personal
            ? null
            : ref.watch(localSpacesProvider).valueOrNull?.selectedSpace?.name,
      ),
      _Area.shopping => OrganizerShoppingPage(
        snapshot: snapshot,
        actions: actions,
        selectedId: _navigationState.shoppingId,
        onSelection: (id) =>
            _changeNavigation(() => _navigationState.shoppingId = id),
        onShare: snapshot.workspaceKey == 'local'
            ? (list) => _copyList(snapshot, list)
            : null,
        onMoveToHousehold:
            ref.watch(localSpacesProvider).valueOrNull?.selectedSpace?.kind ==
                LocalSpaceKind.household
            ? null
            : (list) => transferToLocalHousehold(
                context,
                ref,
                name: list.title,
                transfer: (id) => ref
                    .read(localSpacesProvider.notifier)
                    .moveShoppingListToHousehold(
                      list.id,
                      id,
                      expectedRevision: list.revision,
                    ),
              ),
      ),
      _Area.finances => OrganizerFinancePage(
        snapshot: snapshot,
        actions: actions,
      ),
      _Area.home => OrganizerProjectsPage(
        key: const ValueKey('home'),
        snapshot: snapshot,
        actions: actions,
        home: true,
        selectedId: _navigationState.homeProjectId,
        onSelection: (id) =>
            _changeNavigation(() => _navigationState.homeProjectId = id),
        onShare: (project) => _copyProject(snapshot, project),
        scopeLabel:
            ref.watch(localSpacesProvider).valueOrNull?.selectedSpace?.kind ==
                LocalSpaceKind.personal
            ? null
            : ref.watch(localSpacesProvider).valueOrNull?.selectedSpace?.name,
      ),
      _Area.spaceSettings => SpaceSettingsPage(
        selectedScopeId: selection?.allSpacesSelected == true ? null : active,
        onScopeSelected: _openSpaceSettings,
        onConnect: () => _connectCurrentSpace(),
      ),
      _Area.settings => OrganizerSettingsPage(actions: actions),
      _Area.reminderSettings => const InboxPreferences(),
      _Area.ideas => const IdeasPage(),
      _Area.garden =>
        selection?.allSpacesSelected == true
            ? GardenSpaceChooser(
                onLocal: (id) async {
                  final identity = _accountIdentity;
                  await _selectLocalSpace(id);
                  if (mounted && identity == _accountIdentity) {
                    _navigate(_Area.garden);
                  }
                },
                onShared: (id) async {
                  final identity = _accountIdentity;
                  await _selectSpace(id);
                  if (mounted && identity == _accountIdentity) {
                    _navigate(_Area.garden);
                  }
                },
              )
            : const GardenPage(),
      _Area.inbox => OrganizerInboxPage(
        onSettings: () => _navigate(_Area.reminderSettings),
        onAccount: () => _navigate(_Area.sharing),
        onMembers: _openSpaceSettings,
      ),
      _Area.sharing => SharingAccountPage(
        setupIntent: _setupIntent,
        initialInvitation: _incomingInvitation,
        onInvitationHandled: () => setState(() => _incomingInvitation = null),
        onInvitationAccepted: _invitationAccepted,
        selectedScopeId: _navigationState.sharedScopeId,
        onScopeSelected: _selectScope,
        initialView: _navigationState.sharingView,
        authActive: _navigationState.sharingAuth,
        onAuthChanged: (active) =>
            _changeNavigation(() => _navigationState.sharingAuth = active),
        onViewChanged: (view) => _changeNavigation(() {
          _navigationState.sharingView = view;
        }),
        onSpaceSettings: _openSpaceSettings,
        selectedListId: _navigationState.sharedListId,
        selectedProjectId: _navigationState.sharedProjectId,
        onListSelected: (id) =>
            _changeNavigation(() => _navigationState.sharedListId = id),
        onProjectSelected: (id) =>
            _changeNavigation(() => _navigationState.sharedProjectId = id),
      ),
      _Area.space => _spaceHub(context),
      _Area.backups => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OrganizerHeading(
            title: l.organizerBackups,
            subtitle: l.backupDescription,
          ),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: () => showBackupWizard(context, restore: false),
                icon: const Icon(Icons.lock_outline),
                label: Text(l.backupCreate),
              ),
              OutlinedButton.icon(
                onPressed: () => showBackupWizard(context, restore: true),
                icon: const Icon(Icons.restore),
                label: Text(l.backupRestore),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const BackupRecoveryPanel(),
        ],
      ),
      _Area.more => _moreHub(context),
    };
  }
}
