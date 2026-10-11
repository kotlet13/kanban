import 'dart:async';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/pending_invitation_store.dart';
import 'package:kanban/organizer/presentation/shared/sharing_pending_invitations.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import '../data/collaboration_repository_test.dart'
    show FakeTransport, MemorySessionStore;
import '../data/email_invitation_repository_test.dart' show EmailServer;

class PausedAcceptanceEmailServer extends EmailServer {
  final acceptStarted = Completer<void>(), acceptRelease = Completer<void>();
  final nextToken = 'fhi2_${'b' * 64}', nextInvitationId = newSharedId();
  bool pauseAccept = false, invalidSaved = false;
  @override
  Future<Map<String, dynamic>> call(
    String operation,
    Map<String, Object?> params,
    String? bearer,
  ) async {
    if (operation == 'invitations2.preview' &&
        invalidSaved &&
        params['token'] == token) {
      previewCalls++;
      throw const CollaborationException('invitation_invalid');
    }
    if (operation == 'invitations2.accept' && pauseAccept) {
      pauseAccept = false;
      acceptStarted.complete();
      await acceptRelease.future;
      await super.call(operation, params, bearer);
      throw const CollaborationException('network');
    }
    if (operation == 'invitations2.preview' && params['token'] == nextToken) {
      previewCalls++;
      return {
        ...preview,
        'invitation': {...invitation, 'id': nextInvitationId},
      };
    }
    if (operation == 'invitations2.pending') {
      return {'invitations': <Map<String, dynamic>>[]};
    }
    return super.call(operation, params, bearer);
  }
}

class PausedClearPendingStore extends MemoryPendingInvitationStore {
  final clearStarted = Completer<void>(), clearRelease = Completer<void>();
  bool pauseClear = false;
  @override
  Future<void> write(PendingInvitation? invitation) async {
    if (invitation == null && pauseClear) {
      pauseClear = false;
      clearStarted.complete();
      await clearRelease.future;
    }
    await super.write(invitation);
  }
}

void main() {
  for (final mode in ['stable', 'lost_accept', 'dismiss', 'dismiss_newer']) {
    final lostAcceptance = mode == 'lost_accept';
    final dismissSaved = mode.startsWith('dismiss');
    final dismissWithNewer = mode == 'dismiss_newer';
    testWidgets(
      dismissWithNewer
          ? 'newer invitation arriving during dismissal survives and becomes visible'
          : dismissSaved
          ? 'invalid saved invitation dismiss does not resurrect its token'
          : lostAcceptance
          ? 'new saved invitation appears after lost acceptance while busy'
          : 'real registration pending preview settles instead of reloading on each persistence refresh',
      (tester) async {
        final server = PausedAcceptanceEmailServer(),
            pending = PausedClearPendingStore();
        late CollaborationRepository repository;
        late ProviderContainer container;
        await tester.runAsync(() async {
          final owner = CollaborationRepository(
            CollaborationDatabase(NativeDatabase.memory()),
            FakeTransport(server),
            MemorySessionStore(),
          );
          await owner.initialize();
          await owner.login(
            serverUrl: 'https://synthetic.invalid/kanboard/',
            username: 'alice',
            password: 'synthetic-password',
          );
          server.scopeId = await owner.createScope(
            'Synthetic pending household',
          );
          await owner.close();
          repository = CollaborationRepository(
            CollaborationDatabase(NativeDatabase.memory()),
            FakeTransport(server),
            MemorySessionStore(),
            invitationStore: pending,
          );
          await repository.initialize();
          container = ProviderContainer(
            overrides: [
              collaborationRepositoryProvider.overrideWith(
                (ref) async => repository,
              ),
              pendingInvitationStoreProvider.overrideWithValue(pending),
            ],
          );
          container.listen(
            collaborationProvider,
            (_, __) {},
            fireImmediately: true,
          );
          container.listen(
            securePendingInvitationProvider,
            (_, __) {},
            fireImmediately: true,
          );
          await container.read(collaborationProvider.future);
          await container
              .read(collaborationProvider.notifier)
              .registerWithInvitation(
                serverUrl: 'https://synthetic.invalid/kanboard/',
                invitationToken: server.token,
                username: 'charlie',
                name: 'Synthetic recipient',
                password: 'synthetic-password',
              );
        });
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox());
          container.dispose();
          await tester.runAsync(repository.close);
        });
        if (dismissSaved) server.invalidSaved = true;
        final registrationPreviews = server.previewCalls;
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              locale: const Locale('sl'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: Consumer(
                  builder: (context, ref, _) {
                    final state = ref.watch(collaborationProvider).requireValue;
                    return SharingPendingInvitations(
                      session: state.session!,
                      supported: true,
                      onAccepted: (_) {},
                    );
                  },
                ),
              ),
            ),
          ),
        );
        // A fixed number of frames also detects an infinite FutureBuilder feedback
        // loop, without waiting on its animated progress indicator indefinitely.
        for (var frame = 0; frame < 20; frame++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
          await tester.pump();
        }
        expect(server.previewCalls - registrationPreviews, 1);
        if (dismissSaved) {
          final previewsBeforeDismiss = server.previewCalls;
          final dismiss = find.byKey(
            const ValueKey('dismiss-saved-invitation'),
          );
          expect(dismiss, findsOneWidget);
          if (dismissWithNewer) pending.pauseClear = true;
          tester.widget<TextButton>(dismiss).onPressed!();
          if (dismissWithNewer) {
            for (
              var frame = 0;
              frame < 40 && !pending.clearStarted.isCompleted;
              frame++
            ) {
              await tester.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 5)),
              );
              await tester.pump();
            }
            expect(pending.clearStarted.isCompleted, true);
            final arrival = container
                .read(collaborationProvider.notifier)
                .rememberInvitation(
                  serverUrl: 'https://synthetic.invalid/kanboard/',
                  token: server.nextToken,
                );
            pending.clearRelease.complete();
            await tester.runAsync(() => arrival);
          }
          for (var frame = 0; frame < 30; frame++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 5)),
            );
            await tester.pump();
          }
          if (dismissWithNewer) {
            expect(pending.value?.token == server.nextToken, true);
            expect(
              find.byKey(ValueKey('accept-pending-${server.nextInvitationId}')),
              findsOneWidget,
            );
            expect(dismiss, findsNothing);
            expect(find.byType(LinearProgressIndicator), findsNothing);
            expect(tester.takeException(), isNull);
            return;
          }
          expect(
            pending.value == null,
            true,
            reason:
                'Dismissal must not re-save the previous invalid capability',
          );
          expect(
            server.previewCalls,
            previewsBeforeDismiss,
            reason:
                'The old token must never be submitted again after dismissal',
          );
          expect(dismiss, findsNothing);
          expect(find.byType(LinearProgressIndicator), findsNothing);
          expect(tester.takeException(), isNull);
          return;
        }
        expect(
          find.byKey(ValueKey('accept-pending-${server.invitationId}')),
          findsOneWidget,
        );
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(repository.state.scopes, isEmpty);
        expect(tester.takeException(), isNull);
        final previews = server.previewCalls;
        container.read(pendingInvitationRevisionProvider.notifier).state++;
        for (var frame = 0; frame < 5; frame++) {
          await tester.pump();
        }
        expect(
          server.previewCalls,
          previews,
          reason:
              'Same invitation reconstructed from secure storage must not trigger another HTTP preview',
        );
        if (lostAcceptance) {
          server.pauseAccept = true;
          final button = tester.widget<FilledButton>(
            find.byKey(ValueKey('accept-pending-${server.invitationId}')),
          );
          button.onPressed!();
          for (
            var frame = 0;
            frame < 40 && !server.acceptStarted.isCompleted;
            frame++
          ) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 5)),
            );
            await tester.pump();
          }
          expect(server.acceptStarted.isCompleted, true);
          await tester.runAsync(
            () => container
                .read(collaborationProvider.notifier)
                .rememberInvitation(
                  serverUrl: 'https://synthetic.invalid/kanboard/',
                  token: server.nextToken,
                ),
          );
          for (var frame = 0; frame < 3; frame++) {
            await tester.pump();
          }
          server.acceptRelease.complete();
          for (var frame = 0; frame < 30; frame++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 5)),
            );
            await tester.pump();
          }
          expect(pending.value?.token, server.nextToken);
          expect(
            find.byKey(ValueKey('accept-pending-${server.nextInvitationId}')),
            findsOneWidget,
          );
          expect(
            find.byKey(ValueKey('accept-pending-${server.invitationId}')),
            findsNothing,
          );
          expect(find.byType(LinearProgressIndicator), findsNothing);
          final finalPreviews = server.previewCalls;
          container.read(pendingInvitationRevisionProvider.notifier).state++;
          for (var frame = 0; frame < 5; frame++) {
            await tester.pump();
          }
          expect(server.previewCalls, finalPreviews);
          expect(tester.takeException(), isNull);
          return;
        }
        final newer = 'fhi2_${'b' * 64}';
        await tester.runAsync(
          () => container
              .read(collaborationProvider.notifier)
              .rememberInvitation(
                serverUrl: 'https://synthetic.invalid/kanboard/',
                token: newer,
              ),
        );
        for (var frame = 0; frame < 20; frame++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
          await tester.pump();
        }
        expect(
          server.previewCalls,
          previews + 1,
          reason: 'A genuinely new capability must receive one new preview',
        );
        expect(pending.value?.token, newer);
        expect(find.byType(LinearProgressIndicator), findsNothing);
        await pending.write(
          PendingInvitation(
            serverUrl: pending.value!.serverUrl,
            token: newer,
            serverId: pending.value!.serverId,
            accountPartition: repository.state.session!.partition,
          ),
        );
        container.read(pendingInvitationRevisionProvider.notifier).state++;
        for (var frame = 0; frame < 20; frame++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
          await tester.pump();
        }
        final boundPreviews = server.previewCalls;
        await tester.runAsync(
          () => container
              .read(collaborationProvider.notifier)
              .login(
                serverUrl: 'https://synthetic.invalid/kanboard/',
                username: 'bob',
                password: 'synthetic-password',
              ),
        );
        for (var frame = 0; frame < 20; frame++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
          await tester.pump();
        }
        expect(
          server.previewCalls,
          boundPreviews,
          reason:
              'A saved invitation bound to the previous account must not be previewed for the new account',
        );
        expect(
          find.byKey(ValueKey('accept-pending-${server.nextInvitationId}')),
          findsNothing,
        );
        expect(server.acceptCalls, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
