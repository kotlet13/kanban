import 'dart:async';

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
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/data/pending_invitation_store.dart';
import 'package:kanban/organizer/platform/invitation_links/invitation_link.dart';
import 'package:kanban/organizer/platform/invitation_links/invitation_link_providers.dart';
import 'package:kanban/organizer/presentation/shared/invitation_wizard.dart';
import 'package:kanban/organizer/presentation/shared/sharing_errors.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';

import 'sharing_ui_fixture.dart';

final _link = InvitationLink(
  serverUrl: 'https://sharing.example.test/',
  token: 'fhi3_${'a' * 64}',
);

class _Store extends MemoryPendingInvitationStore {
  Completer<void>? deferGate;
  bool failDefer = false;
  int deferWrites = 0;
  @override
  Future<void> write(PendingInvitation? invitation) async {
    if (invitation?.autoOpen == false && value?.autoOpen != false) {
      deferWrites++;
      await deferGate?.future;
      if (failDefer) throw const CollaborationException('secure_storage');
    }
    await super.write(invitation);
  }
}

class _Controller extends SharingUiController {
  _Controller(this.store, {this.encrypted = false}) {
    emailPreview = true;
  }
  final _Store store;
  final bool encrypted;
  Completer<void>? acceptGate;
  Completer<void>? clearGate;
  @override
  Future<void> acceptInvitation(String token) async {
    await acceptGate?.future;
    await super.acceptInvitation(token);
  }

  @override
  Future<void> rememberInvitation({
    required String serverUrl,
    required String token,
    bool allowLocalHttp = false,
  }) async {
    await store.receiveLink(
      serverUrl: serverUrl,
      token: token,
      isCurrent: () => true,
    );
    savedInvitation = await store.read();
  }

  @override
  Future<void> clearPendingInvitation({String? expectedToken}) async {
    await clearGate?.future;
    if (store.value?.token == expectedToken) await store.write(null);
    savedInvitation = await store.read();
  }

  @override
  Future<SharedInvitationPreview> previewInvitation({
    required String serverUrl,
    required String token,
    bool allowLocalHttp = false,
  }) async {
    final p = await super.previewInvitation(serverUrl: serverUrl, token: token);
    return SharedInvitationPreview(
      scopeName: p.scopeName,
      scopeId: p.scopeId,
      kind: p.kind,
      recipientUsername: p.recipientUsername,
      recipientEmail: p.recipientEmail,
      inviterName: p.inviterName,
      invitationId: p.invitationId,
      role: SharedRole.viewer,
      expiresAt: p.expiresAt,
      registrationAllowed: p.registrationAllowed,
      contractVersion: encrypted ? 4 : 3,
      requiresExplicitAcceptance: true,
    );
  }
}

class _UiIdentityStore implements CryptoIdentityStore {
  @override
  String get partition => sharingSession().partition;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UiCryptoAccount implements AccountCryptoV2Workflow {
  @override
  final CryptoIdentityStore store = _UiIdentityStore();
  @override
  Future<String> localPhase() async => 'ready';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UiCryptoRepository implements CollaborationRepository {
  _UiCryptoRepository(this.account);
  final _UiCryptoAccount account;
  @override
  Future<AccountCryptoV2Workflow> connectedCryptoAccount() async => account;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UiDirectory implements VerifiedAccountDirectory {
  @override
  String get accountId => sharingSession().accountId;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UiInvites extends InviteCryptoRepository {
  _UiInvites(_UiCryptoAccount account)
    : super(SessionCryptoAccess(account: account));
  int accepts = 0;
  String? resumedScope;
  @override
  Future<VerifiedCryptoInvitation> inspect({
    String? token,
    String? invitationId,
  }) async => VerifiedCryptoInvitation(
    {
      'invitation': {
        'id': 'accepted-ui-invitation',
        'scopeId': sharingScopeId,
        'role': 'viewer',
      },
      'creatorAuthorization': {
        'commandBase64':
            'eyJhY2NvdW50SWQiOiIzMDAwMDAwMC0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAwMDEiLCJvcGVyYXRpb24iOiJjcnlwdG8yLmludml0YXRpb25zLmNyZWF0ZSIsInBheWxvYWQiOnsiZXhwaXJlc0F0Ijo0MDcwOTA4ODAwLCJpbnZpdGF0aW9uSWQiOiJhY2NlcHRlZC11aS1pbnZpdGF0aW9uIiwicmVjaXBpZW50Ijp7ImtpbmQiOiJ1c2VybmFtZSIsInZhbHVlIjoicmVjaXBpZW50In0sInJvbGUiOiJ2aWV3ZXIiLCJzY29wZUlkIjoiMTAwMDAwMDAtMDAwMC00MDAwLTgwMDAtMDAwMDAwMDAwMDAxIn0sInZlcnNpb24iOjJ9',
      },
    },
    _UiDirectory(),
    [],
  );
  @override
  Future<void> trustCreatorFromDirectory(
    VerifiedCryptoInvitation invite,
  ) async {}
  @override
  Future<Map<String, dynamic>> accept(
    VerifiedCryptoInvitation invite, {
    required String actionId,
  }) async {
    accepts++;
    return {};
  }

  @override
  Future<String?> resumeAccepted(String invitationId) async => resumedScope;
}

PendingInvitation _saved({
  bool acceptedOtherAccount = false,
  String? serverId,
}) => PendingInvitation(
  serverUrl: _link.serverUrl,
  token: _link.token,
  serverId: serverId ?? sharingSession().serverId,
  expiresAt: DateTime.utc(2099),
  accountPartition: sharingSession(second: acceptedOtherAccount).partition,
  invitationId: acceptedOtherAccount ? 'accepted-awaiting-keys' : null,
);

Future<ProviderContainer> _open(
  WidgetTester tester,
  _Store store, {
  _UiInvites? crypto,
}) async {
  final controller = _Controller(store, encrypted: crypto != null);
  late ProviderContainer container;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        collaborationProvider.overrideWith(() => controller),
        pendingInvitationStoreProvider.overrideWithValue(store),
        if (crypto != null)
          collaborationRepositoryProvider.overrideWith(
            (ref) async =>
                _UiCryptoRepository(crypto.access.account as _UiCryptoAccount),
          ),
        securePendingInvitationProvider.overrideWith(
          (ref) async => store.value,
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
        home: Consumer(
          builder: (context, ref, _) {
            container = ProviderScope.containerOf(context);
            return Scaffold(
              body: TextButton(
                onPressed: () {
                  ref.read(pendingInvitationLinkProvider.notifier).state =
                      _link;
                  if (crypto == null) {
                    showInvitationWizard(context, ref, initialLink: _link);
                  } else {
                    Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => InvitationWizard(
                          initialLink: _link,
                          cryptoRepository: (_) => crypto,
                        ),
                      ),
                    );
                  }
                },
                child: const Text('launch'),
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('launch'));
  await tester.pumpAndSettle();
  expect(find.byType(InvitationWizard), findsOneWidget);
  return container;
}

void main() {
  for (final encrypted in [false, true]) {
    testWidgets(
      'successful invitation routing hint clears same-cap duplicate after ${encrypted ? 'encrypted resume' : 'legacy join'}',
      (tester) async {
        final store = _Store()..value = _saved();
        final crypto = encrypted ? _UiInvites(_UiCryptoAccount()) : null;
        if (encrypted) {
          store.value = PendingInvitation.fromJson({
            ...store.value!.toJson(),
            'invitationId': 'already-accepted-ui-invitation',
          });
        }
        final container = await _open(tester, store, crypto: crypto);
        final controller =
            container.read(collaborationProvider.notifier) as _Controller;
        controller.clearGate = Completer<void>();
        if (crypto != null) crypto.resumedScope = sharingScopeId;
        // Model the shell consuming the initial route hint while its wizard stays open.
        container.read(pendingInvitationLinkProvider.notifier).state = null;
        final join = find.byKey(const ValueKey('invitation-flow-join'));
        await tester.ensureVisible(join);
        await tester.tap(join);
        await tester.pump();
        expect(
          store.value,
          isNotNull,
        ); // Durable clear is deliberately still pending.
        container
            .read(pendingInvitationLinkProvider.notifier)
            .state = InvitationLink(
          serverUrl: 'https://sharing.example.test',
          token: _link.token,
        );
        await tester.pump();
        controller.clearGate!.complete();
        await tester.pumpAndSettle();
        expect(find.byType(InvitationWizard), findsNothing);
        expect(store.value, isNull);
        expect(container.read(pendingInvitationLinkProvider), isNull);
        expect(store.deferWrites, 0);
        if (crypto != null) {
          expect(crypto.accepts, 0); // Resume never accepts again.
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'successful invitation routing hint preserves a newer capability during clear',
    (tester) async {
      final store = _Store()..value = _saved();
      final container = await _open(tester, store);
      final controller =
          container.read(collaborationProvider.notifier) as _Controller;
      controller.clearGate = Completer<void>();
      container.read(pendingInvitationLinkProvider.notifier).state = null;
      final join = find.byKey(const ValueKey('invitation-flow-join'));
      await tester.ensureVisible(join);
      await tester.tap(join);
      await tester.pump();
      final newer = InvitationLink(
        serverUrl: _link.serverUrl,
        token: 'fhi3_${'c' * 64}',
      );
      await store.receiveLink(
        serverUrl: newer.serverUrl,
        token: newer.token,
        isCurrent: () => true,
      );
      container.read(pendingInvitationLinkProvider.notifier).state = newer;
      await tester.pump();
      controller.clearGate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(InvitationWizard), findsNothing);
      expect(store.value!.token, newer.token);
      expect(store.value!.autoOpen, true);
      expect(container.read(pendingInvitationLinkProvider)?.token, newer.token);
      expect(store.deferWrites, 0);
      expect(tester.takeException(), isNull);
    },
  );

  for (final systemPop in [false, true]) {
    testWidgets(
      'user ${systemPop ? 'system' : 'Back'} exit persists exact deferred invitation before closing',
      (tester) async {
        final store = _Store()
          ..value = _saved(acceptedOtherAccount: true)
          ..deferGate = Completer<void>();
        final before = store.value!.toJson();
        final container = await _open(tester, store);
        if (systemPop) {
          await tester.binding.handlePopRoute();
        } else {
          await tester.tap(find.byType(BackButton));
        }
        await tester.pump();
        expect(store.deferWrites, 1);
        expect(store.value!.autoOpen, true);
        expect(find.byType(InvitationWizard), findsOneWidget);
        // A duplicate Back while saving cannot race another secure write.
        await tester.binding.handlePopRoute();
        await tester.pump();
        expect(store.deferWrites, 1);
        store.deferGate!.complete();
        await tester.pumpAndSettle();
        expect(find.byType(InvitationWizard), findsNothing);
        expect(store.value!.toJson(), {...before, 'autoOpen': false});
        expect(container.read(pendingInvitationLinkProvider), isNull);
        expect(find.text('launch'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'failed deferral stays visible and retains the route signal until a saved retry',
    (tester) async {
      final store = _Store()
        ..value = _saved(acceptedOtherAccount: true)
        ..failDefer = true;
      final before = store.value!.toJson();
      final container = await _open(tester, store);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(InvitationWizard), findsOneWidget);
      final context = tester.element(find.byType(InvitationWizard));
      expect(
        find.text(AppLocalizations.of(context)!.secureStorageUnavailable),
        findsOneWidget,
      );
      expect(store.value!.toJson(), before);
      expect(container.read(pendingInvitationLinkProvider)?.token, _link.token);
      store.failDefer = false;
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(InvitationWizard), findsNothing);
      expect(store.value!.autoOpen, false);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'superseded route exits without deferring or consuming the newer capability',
    (tester) async {
      final store = _Store()..value = _saved(acceptedOtherAccount: true);
      final container = await _open(tester, store);
      final newer = InvitationLink(
        serverUrl: _link.serverUrl,
        token: 'fhi3_${'b' * 64}',
      );
      await store.receiveLink(
        serverUrl: newer.serverUrl,
        token: newer.token,
        isCurrent: () => true,
      );
      container.read(pendingInvitationLinkProvider.notifier).state = newer;
      await tester.pumpAndSettle();
      expect(find.byType(InvitationWizard), findsNothing);
      expect(store.deferWrites, 0);
      expect(store.value!.token, newer.token);
      expect(store.value!.autoOpen, true);
      expect(container.read(pendingInvitationLinkProvider)?.token, newer.token);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'successful programmatic completion never marks its capability deferred',
    (tester) async {
      final store = _Store()..value = _saved();
      final container = await _open(tester, store);
      final controller =
          container.read(collaborationProvider.notifier) as _Controller;
      controller.acceptGate = Completer<void>();
      final join = find.byKey(const ValueKey('invitation-flow-join'));
      await tester.ensureVisible(join);
      await tester.tap(join);
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(InvitationWizard), findsOneWidget);
      expect(store.deferWrites, 0);
      expect(store.value, isNotNull);
      controller.acceptGate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(InvitationWizard), findsNothing);
      expect(store.deferWrites, 0);
      expect(store.value, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'accepted encrypted continuation retains its saved ID and binding when deferred',
    (tester) async {
      final store = _Store()..value = _saved();
      final crypto = _UiInvites(_UiCryptoAccount());
      await _open(tester, store, crypto: crypto);
      final join = find.byKey(const ValueKey('invitation-flow-join'));
      await tester.ensureVisible(join);
      await tester.tap(join);
      await tester.pumpAndSettle();
      expect(crypto.accepts, 1);
      expect(find.byType(InvitationWizard), findsOneWidget);
      expect(store.value!.invitationId, 'accepted-ui-invitation');
      expect(store.value!.accountPartition, sharingSession().partition);
      final accepted = store.value!.toJson();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(InvitationWizard), findsNothing);
      expect(store.value!.toJson(), {...accepted, 'autoOpen': false});
      expect(crypto.accepts, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'bound account and server identity mismatches do not claim a valid session expired',
    (tester) async {
      final store = _Store()..value = _saved(acceptedOtherAccount: true);
      await _open(tester, store);
      var context = tester.element(find.byType(InvitationWizard));
      expect(
        find.text(AppLocalizations.of(context)!.sharingAccountChanged),
        findsOneWidget,
      );
      expect(
        find.text(AppLocalizations.of(context)!.sharingSessionExpired),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('invitation-flow-join')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      final changedServer = _Store()
        ..value = _saved(serverId: 'changed-server-id');
      await _open(tester, changedServer);
      context = tester.element(find.byType(InvitationWizard));
      expect(
        find.text(AppLocalizations.of(context)!.cryptoSharingIdentityChanged),
        findsOneWidget,
      );
      expect(
        find.text(AppLocalizations.of(context)!.sharingSessionExpired),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final locale in ['en', 'sl']) {
    testWidgets(
      'account-change and genuine expiry error text remain distinct in $locale',
      (tester) async {
        late String changed, expired;
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(locale),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: Builder(
              builder: (context) {
                final l = AppLocalizations.of(context)!;
                changed = l.sharingAccountChanged;
                expired = l.sharingSessionExpired;
                return Scaffold(
                  body: SingleChildScrollView(
                    child: Column(
                      children: [
                        for (final error in [
                          const CollaborationException('session_changed'),
                          const CryptoDirectoryException(
                            'directory_stale_identity',
                          ),
                          const CryptoAuthorityPending('crypto_stale_identity'),
                          const CollaborationException('session_expired'),
                          const CollaborationException('auth_required'),
                        ])
                          Text(sharingErrorMessage(context, error)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(changed, isNot(expired));
        expect(find.text(changed), findsNWidgets(3));
        expect(find.text(expired), findsNWidgets(2));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
