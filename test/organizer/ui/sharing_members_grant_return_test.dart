import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_repository.dart';
import 'package:kanban/organizer/presentation/recovery/crypto_invitation_page.dart';
import 'package:kanban/organizer/presentation/shared/sharing_members.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';

import '../data/collaboration_repository_test.dart' show MemorySessionStore;
import 'sharing_ui_fixture.dart';

class _Directory extends Fake implements AccountDirectoryRepository {
  // The child route is only opened and dismissed. No grant or network workflow
  // is needed to exercise the real caller's post-navigation refresh.
  @override
  bool Function() get isCurrent =>
      () => false;

  @override
  DeviceSession get session =>
      DeviceSession(sharingSession(), 'synthetic-test');
}

class _Account extends Fake implements AccountCryptoV2Workflow {
  @override
  final AccountDirectoryRepository directory = _Directory();
}

class _NoNetwork implements CollaborationTransport {
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async => throw StateError('Unexpected test network operation');

  @override
  void close() {}
}

class _Repository extends CollaborationRepository {
  _Repository(CollaborationDatabase database)
    : super(database, _NoNetwork(), MemorySessionStore(), ownsDatabase: false);

  @override
  Future<AccountCryptoV2Workflow> connectedCryptoAccount() async => _Account();
}

class _Controller extends SharingUiController {
  _Controller()
    : super(
        initial: CollaborationState(
          session: sharingSession(),
          selectedSpaceId: sharingScopeId,
          scopes: [sharingScope()],
        ),
      );

  @override
  Future<List<SharedInvitation>> invitations(String scopeId) async => [
    SharedInvitation(
      id: 'pending-keys',
      scopeId: sharingScopeId,
      recipientUsername: 'recipient',
      role: SharedRole.member,
      expiresAt: DateTime.utc(2099),
      contractVersion: 4,
      pendingKeys: true,
    ),
  ];
}

void main() {
  testWidgets(
    'returning from key approval refreshes members without a Future setState callback',
    (tester) async {
      late CollaborationDatabase database;
      late _Repository repository;
      await tester.runAsync(() async {
        database = CollaborationDatabase(NativeDatabase.memory());
        repository = _Repository(database);
        await repository.initialize();
      });
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() async {
          await repository.close();
          await database.close();
        });
      });
      final controller = _Controller()..includeSecondMember = false;
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            collaborationRepositoryProvider.overrideWith(
              (ref) async => repository,
            ),
            collaborationProvider.overrideWith(() => controller),
          ],
          child: MaterialApp(
            navigatorKey: navigator,
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SingleChildScrollView(
                child: SharingMembersPage(
                  scope: sharingScope(),
                  session: sharingSession(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(controller.memberLoads, 1);
      expect(find.text('Member Beta'), findsNothing);
      await tester.ensureVisible(find.byIcon(Icons.key_outlined));
      await tester.tap(find.byIcon(Icons.key_outlined));
      await tester.pumpAndSettle();
      expect(find.byType(CryptoInvitationPage), findsOneWidget);
      controller.includeSecondMember = true;
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(controller.memberLoads, 2);
      expect(find.text('Member Beta'), findsOneWidget);
    },
  );
}
