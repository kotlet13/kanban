import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/crypto_identity_store.dart';
import 'package:kanban/organizer/data/e2ee/invite_crypto_repository.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/data/pending_invitation_store.dart';
import 'package:kanban/organizer/platform/invitation_links/invitation_link.dart';
import 'package:kanban/organizer/presentation/shared/invitation_wizard.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';

import 'sharing_ui_fixture.dart';

const _invitationId = '50000000-0000-4000-8000-000000000001';
final _link = InvitationLink(
  serverUrl: 'https://sharing.example.test/',
  token: 'fhi4_${'d' * 64}',
);

class _Identity extends Fake implements CryptoIdentityStore {
  @override
  String get partition => sharingSession().partition;
}

class _Account extends Fake implements AccountCryptoV2Workflow {
  @override
  final CryptoIdentityStore store = _Identity();
  @override
  Future<String> localPhase() async => 'ready';
}

class _Repository extends Fake implements CollaborationRepository {
  _Repository(this.account);
  final _Account account;
  @override
  Future<AccountCryptoV2Workflow> connectedCryptoAccount() async => account;
}

class _Invites extends InviteCryptoRepository {
  _Invites(_Account account) : super(SessionCryptoAccess(account: account));
  final resumedIds = <String>[];
  Object? resumeError;
  @override
  Future<String?> resumeAccepted(String invitationId) async {
    resumedIds.add(invitationId);
    if (resumeError != null) throw resumeError!;
    return sharingScopeId;
  }

  @override
  Future<Map<String, dynamic>> accept(
    VerifiedCryptoInvitation invitation, {
    required String actionId,
  }) async => throw StateError('Accepted checkpoint must never accept again');

  @override
  Future<VerifiedCryptoInvitation> inspect({
    String? token,
    String? invitationId,
  }) async => throw StateError('No fresh preview is needed for this resume');
}

class _Controller extends SharingUiController {
  _Controller(this.store)
    : super(initial: CollaborationState(session: sharingSession()));
  final MemoryPendingInvitationStore store;
  bool accessAvailable = false;
  int syncs = 0, clears = 0, selections = 0, previews = 0;
  @override
  Future<void> rememberInvitation({
    required String serverUrl,
    required String token,
    bool allowLocalHttp = false,
  }) => store
      .receiveLink(serverUrl: serverUrl, token: token, isCurrent: () => true)
      .then((_) {});

  @override
  Future<SharedInvitationPreview> previewInvitation({
    required String serverUrl,
    required String token,
    bool allowLocalHttp = false,
  }) async {
    previews++;
    throw StateError('Resume must not request a new invitation preview');
  }

  @override
  Future<void> syncNow() async {
    syncs++;
    if (accessAvailable) {
      replace(
        CollaborationState(session: sharingSession(), scopes: [sharingScope()]),
      );
    }
  }

  @override
  Future<void> selectSpace(String? id) async {
    selections++;
    await super.selectSpace(id);
  }

  @override
  Future<void> clearPendingInvitation({String? expectedToken}) async {
    expect(expectedToken, _link.token);
    clears++;
    await store.write(null);
  }
}

void main() {
  for (final resumeError in [true, false]) {
    testWidgets(
      'restored accepted checkpoint keeps retry without preview after ${resumeError ? 'resume error' : 'incomplete sync'} and opens same checkpoint',
      (tester) async {
        final saved = PendingInvitation(
          serverUrl: _link.serverUrl,
          token: _link.token,
          serverId: sharingSession().serverId,
          accountPartition: sharingSession().partition,
          invitationId: _invitationId,
        );
        final store = MemoryPendingInvitationStore()..value = saved;
        final account = _Account();
        final invites = _Invites(account);
        if (resumeError) {
          invites.resumeError = const CollaborationException('network');
        }
        final controller = _Controller(store);
        final accepted = <String>[];
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              collaborationProvider.overrideWith(() => controller),
              pendingInvitationStoreProvider.overrideWithValue(store),
              collaborationRepositoryProvider.overrideWith(
                (ref) async => _Repository(account),
              ),
            ],
            child: MaterialApp(
              locale: const Locale('en'),
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => InvitationWizard(
                          cryptoRepository: (_) => invites,
                          onAccepted: accepted.add,
                        ),
                      ),
                    ),
                    child: const Text('Open saved checkpoint'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Open saved checkpoint'));
        await tester.pumpAndSettle();
        final retry = find.byKey(const ValueKey('invitation-flow-join'));
        expect(
          find.byKey(const ValueKey('invitation-flow-input')),
          findsNothing,
        );
        expect(retry, findsOneWidget);
        expect(tester.widget<FilledButton>(retry).onPressed, isNotNull);
        expect(invites.resumedIds, [_invitationId]);
        expect(controller.previews, 0);
        expect(controller.clears, 0);
        expect(accepted, isEmpty);
        expect(store.value?.toJson(), saved.toJson());
        invites.resumeError = null;
        controller.accessAvailable = true;
        await tester.ensureVisible(retry);
        await tester.tap(retry);
        await tester.pumpAndSettle();
        expect(invites.resumedIds, [_invitationId, _invitationId]);
        expect(controller.syncs, resumeError ? 1 : 2);
        expect(controller.selections, 1);
        expect(controller.clears, 1);
        expect(controller.previews, 0);
        expect(accepted, [sharingScopeId]);
        expect(store.value, isNull);
        expect(find.byType(InvitationWizard), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
