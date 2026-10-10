import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kanban/app.dart';
import 'package:kanban/app_router.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/pending_invitation_store.dart';
import 'package:kanban/organizer/platform/backup_preferences_replay.dart';
import 'package:kanban/organizer/platform/invitation_links/invitation_link.dart';
import 'package:kanban/organizer/platform/invitation_links/invitation_link_providers.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'package:kanban/organizer/state/local_database_provider.dart';
import 'package:kanban/organizer/state/notification_local_spaces_provider.dart';
import 'package:kanban/organizer/state/organizer_provider.dart';
import 'package:kanban/organizer/state/portable_backup_provider.dart';

import '../data/collaboration_repository_test.dart'
    show FakeTransport, MemorySessionStore;
import '../data/email_invitation_repository_test.dart' show EmailServer;
import '../platform/invitation_links/invitation_link_coordinator_test.dart'
    show FakeLinks;
import 'backup_ui_fixture.dart';
import 'organizer_ui_test.dart' show MemoryOrganizerStorage;
import 'sharing_ui_test.dart' show tapSharing;

class ScopedEmailServer extends EmailServer {
  @override
  String get token => 'fhi3_${'b' * 64}';
  @override
  Map<String, dynamic> get invitation => {
    ...super.invitation,
    'contractVersion': 3,
    'accessScope': 'space',
  };
  @override
  Future<Map<String, dynamic>> call(
    String operation,
    Map<String, Object?> params,
    String? bearer,
  ) async {
    if (operation == 'capabilities') {
      final caps = await super.call(operation, params, bearer);
      return {
        ...caps,
        'invitationContractVersions': [1, 2, 3],
        'spaceAccessPolicyVersions': [1, 2, 3],
        'features': {
          ...caps['features'] as Map<String, dynamic>,
          'scopedInvitations': true,
          'spaceProjectMembership': true,
        },
      };
    }
    if (operation.startsWith('invitations3.')) {
      return super.call(
        operation.replaceFirst('invitations3.', 'invitations2.'),
        params,
        bearer,
      );
    }
    if (operation == 'auth.registerInvitation3') {
      return super.call('auth.registerInvitation2', params, bearer);
    }
    return super.call(operation, params, bearer);
  }
}

void main() {
  for (final version in [2, 3]) {
    for (final width in [390.0, 1280.0]) {
      testWidgets(
        'native email link v$version and preview use real providers $width signed out',
        (tester) async {
          tester.view.physicalSize = Size(width, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          SharedPreferences.setMockInitialValues({
            'app_locale_code': 'sl',
            'app_theme_mode': 'light',
          });
          final server = version == 3 ? ScopedEmailServer() : EmailServer();
          final pending = MemoryPendingInvitationStore();
          final sessions = MemorySessionStore();
          late CollaborationRepository repository;
          await tester.runAsync(() async {
            final owner = CollaborationRepository(
              CollaborationDatabase(NativeDatabase.memory()),
              FakeTransport(server),
              MemorySessionStore(),
              invitationStore: MemoryPendingInvitationStore(),
            );
            await owner.initialize();
            await owner.login(
              serverUrl: 'https://synthetic.invalid/kanboard',
              username: 'alice',
              password: 'synthetic-password',
            );
            server.scopeId = await owner.createScope('Synthetic household');
            if (version == 3) {
              server.scopes[server.scopeId]!['accessPolicyVersion'] = 3;
            }
            await owner.close();
            repository = CollaborationRepository(
              CollaborationDatabase(NativeDatabase.memory()),
              FakeTransport(server),
              sessions,
              invitationStore: pending,
              ownsDatabase: false,
            );
            await repository.initialize();
          });
          final source = FakeLinks();
          source.initial.complete(null);
          final container = ProviderContainer(
            overrides: [
              collaborationRepositoryProvider.overrideWith(
                (ref) async => repository,
              ),
              localDatabaseProvider.overrideWith(
                (ref) async => repository.database,
              ),
              deviceSessionStoreProvider.overrideWithValue(sessions),
              pendingInvitationStoreProvider.overrideWithValue(pending),
              invitationLinkSourceProvider.overrideWithValue(source),
              notificationLocalSnapshotsProvider.overrideWith(
                (ref) async => [await ref.watch(organizerProvider.future)],
              ),
              portableBackupProvider.overrideWith(EmptyBackupUiController.new),
              backupPreferencesReplayProvider.overrideWith((ref) async => {}),
              organizerStorageProvider.overrideWithValue(
                () async => MemoryOrganizerStorage(),
              ),
            ],
          );
          // Keep the real dependent provider active throughout controller calls.
          final listener = container.listen(
            securePendingInvitationProvider,
            (_, _) {},
          );
          await tester.runAsync(
            () => container.read(collaborationProvider.future),
          );
          appRouter.go('/');
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: const KanbanApp(),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            container.read(collaborationProvider).requireValue.session,
            isNull,
          );
          source.stream.add(
            InvitationLink(
              serverUrl: 'https://synthetic.invalid/kanboard',
              token: server.token,
            ).toUri(),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Nadaljuj do povabila'));
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('sharing-preview-invite')),
            findsOneWidget,
          );
          await tapSharing(tester, 'sharing-preview-invite');
          expect(server.previewCalls, 1);
          expect(find.text('Synthetic household'), findsOneWidget);
          if (version == 3) {
            expect(find.text('Cel prostor'), findsOneWidget);
            expect(
              find.textContaining('obstoječih in prihodnjih projektov'),
              findsOneWidget,
            );
            expect(
              find.textContaining('nastavitve, povabila in člane'),
              findsOneWidget,
            );
          }
          expect(
            find.byKey(const ValueKey('sharing-username')),
            findsOneWidget,
          );
          expect(
            find.text('Spremembe ni bilo mogoče shraniti. Poskusi znova.'),
            findsNothing,
          );
          expect(
            find.widgetWithText(FilledButton, 'Ustvari račun'),
            findsOneWidget,
          );
          expect(find.text('Ustvari račun in sprejmi'), findsNothing);
          expect(find.text('Že imam račun'), findsOneWidget);
          expect(pending.value?.invitationId, server.invitationId);
          expect(
            container.read(securePendingInvitationProvider).hasError,
            false,
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          listener.close();
          container.dispose();
          await source.stream.close();
          await tester.runAsync(() async {
            await repository.close();
            await repository.database.close();
          });
        },
      );
    }
  }
}
