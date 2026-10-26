import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/domain/sharing_refresh_state.dart';
import 'package:kanban/organizer/presentation/shared/sharing_members.dart';
import 'package:kanban/organizer/presentation/shared/sharing_pending_invitations.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'sharing_ui_fixture.dart';

CollaborationState view(SharingRefreshState refresh, {bool syncing = false}) =>
    CollaborationState(
      session: sharingSession(),
      scopes: [sharingScope()],
      selectedSpaceId: sharingScopeId,
      emailInvitationsSupported: true,
      sharingRefresh: refresh,
      isSyncing: syncing,
    );

class _Controller extends SharingUiController {
  _Controller()
    : super(initial: view(const SharingRefreshState(coordinated: true)));
  int pendingLoads = 0;
  Completer<void>? gate;
  @override
  Future<List<SharedMember>> members(String id) async {
    final value = await super.members(id);
    await gate?.future;
    return value;
  }

  @override
  Future<List<SharedInvitationPreview>> pendingInvitations() async {
    pendingLoads++;
    await gate?.future;
    return [];
  }
}

void main() {
  for (final members in [true, false]) {
    testWidgets(
      'P6 coordinator refreshes ${members ? 'members' : 'pending'} only on matching generations',
      (tester) async {
        final c = _Controller();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ...await sharingUiInfrastructureOverrides(tester, c),
              collaborationProvider.overrideWith(() => c),
            ],
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: members
                    ? SharingMembersPage(
                        scope: sharingScope(),
                        session: sharingSession(),
                      )
                    : SharingPendingInvitations(
                        session: sharingSession(),
                        supported: true,
                        onAccepted: (_) {},
                      ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        int loads() => members ? c.memberLoads : c.pendingLoads;
        expect(loads(), 1);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(loads(), 1);
        c.replace(
          view(const SharingRefreshState(coordinated: true), syncing: true),
        );
        await tester.pump();
        c.replace(view(const SharingRefreshState(coordinated: true)));
        await tester.pumpAndSettle();
        expect(loads(), 1);
        var refresh = const SharingRefreshState(coordinated: true).next(
          all: false,
          invitationChange: false,
          affectedScopes: {'unrelated'},
        );
        c.replace(view(refresh));
        await tester.pumpAndSettle();
        expect(loads(), 1);
        refresh = refresh.next(
          all: false,
          invitationChange: true,
          affectedScopes: {},
        );
        c.replace(view(refresh, syncing: true));
        await tester.pump();
        expect(loads(), 1);
        c.gate = Completer<void>();
        c.replace(view(refresh));
        // Allow the real memory SQLite lookup on the members page to complete.
        for (var i = 0; i < 5; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
          await tester.pump();
        }
        expect(loads(), 2);
        refresh = refresh.next(
          all: false,
          invitationChange: true,
          affectedScopes: {},
        );
        c.replace(view(refresh));
        await tester.pump();
        expect(loads(), 2);
        final gate = c.gate!;
        c.gate = null;
        gate.complete();
        await tester.pumpAndSettle();
        expect(
          loads(),
          3,
        ); // Arrived during read: one deferred refresh, no lost event.
        c.switchAccount();
        await tester.pumpAndSettle();
        expect(loads(), 3);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
