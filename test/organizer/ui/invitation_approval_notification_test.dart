import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_repository.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/invite_crypto_repository.dart';
import 'package:kanban/organizer/data/e2ee/scope_crypto_manager.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/platform/remote_push/foreground_invitation_approval_coordinator.dart';
import 'package:kanban/organizer/platform/remote_push/remote_push_providers.dart';
import 'package:kanban/organizer/presentation/recovery/crypto_invitation_page.dart';
import 'package:kanban/organizer/presentation/shared/hosting_disclosure.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'sharing_ui_fixture.dart';

const inviteId = '10000000-0000-4000-8000-000000000002';
String hash(String letter) => List.filled(64, letter).join();
InvitationAcceptanceNotification hint() => InvitationAcceptanceNotification(
  scopeId: sharingScopeId,
  invitationId: inviteId,
  acceptanceProofHash: hash('a'),
  creatorProofHash: hash('b'),
  tokenHash: hash('c'),
);
SharedInboxEntry event(int id) => SharedInboxEntry(
  id: id,
  scopeId: sharingScopeId,
  kind: InvitationAcceptanceNotification.kind,
  category: 'membership',
  audience: InboxAudience.personal,
  targetType: 'membership',
  targetId: inviteId,
  groupKey: inviteId,
  createdAt: DateTime.utc(2026),
  invitationAcceptance: hint(),
);
SharedScope scope() => SharedScope(
  id: sharingScopeId,
  name: 'Local title',
  kind: SharedScopeKind.household,
  role: SharedRole.owner,
  accessPolicyVersion: 3,
);
CollaborationState shared({
  bool second = false,
  bool locked = false,
  bool syncing = false,
  List<SharedInboxEntry> inbox = const [],
  DateTime? synced,
}) => CollaborationState(
  session: sharingSession(second: second),
  scopes: [scope()],
  localAccessAllowed: !locked,
  inbox: inbox,
  isSyncing: syncing,
  lastSuccessfulSyncAt: synced,
);
Widget coordinator(
  SharingUiController controller,
  ForegroundInvitationApprovalRunner run,
) => ProviderScope(
  overrides: [
    collaborationProvider.overrideWith(() => controller),
    foregroundInvitationApprovalRunnerProvider.overrideWithValue(run),
  ],
  child: const MaterialApp(
    home: ForegroundInvitationApprovalCoordinator(child: SizedBox()),
  ),
);

class _Directory extends Fake implements AccountDirectoryRepository {
  @override
  bool Function() get isCurrent =>
      () => true;
  @override
  DeviceSession get session => DeviceSession(sharingSession(), 'synthetic');
}

class _Account extends Fake implements AccountCryptoV2Workflow {
  @override
  final AccountDirectoryRepository directory = _Directory();
}

class _VerifiedDirectory extends Fake implements VerifiedAccountDirectory {}

class _ApprovalManager extends Fake implements ScopeCryptoManager {
  @override
  Future<List<ScopeRotationReview>> pendingRotationReviews(
    String scopeId,
  ) async => [];
  @override
  Future<ScopeRotationReview> reviewRotation(
    String scopeId, {
    dynamic recoveryFile,
    bool financeOnly = false,
    dynamic inheritedInvitationAdmission,
    dynamic preauthorizedInvitationAdmission,
    String? fixedReviewId,
  }) async => ScopeRotationReview({
    'reviewId': 'review',
    'scopeId': sharingScopeId,
    'domains': <String, dynamic>{},
  });
}

class _Invites extends Fake implements InviteCryptoRepository {
  _Invites(this.changed);
  final String changed;
  int trusted = 0;
  int admitted = 0, automaticAttempts = 0;
  Object? grantError;
  Completer<ForegroundInvitationApprovalResult>? automaticGate;
  bool Function()? foregroundGuard;
  List<ForegroundInvitationApprovalResult> automaticResults = const [
    ForegroundInvitationApprovalResult(
      ForegroundInvitationApprovalStatus.manualReview,
      'crypto_invitation_original_intent_missing',
    ),
  ];
  @override
  ScopeCryptoManager get manager => _ApprovalManager();
  @override
  Future<ForegroundInvitationApprovalResult>
  finishForegroundInvitationApproval({
    required String scopeId,
    required String invitationId,
    required bool Function() isForegroundCurrent,
    InvitationAcceptanceNotification? expectedAcceptance,
  }) async {
    foregroundGuard = isForegroundCurrent;
    final index = automaticAttempts++;
    final result = automaticGate != null
        ? await automaticGate!.future
        : automaticResults[index < automaticResults.length
              ? index
              : automaticResults.length - 1];
    if (!isForegroundCurrent()) {
      throw const CryptoAuthorityPending(
        'crypto_invitation_foreground_required',
      );
    }
    return result;
  }

  @override
  Future<VerifiedCryptoInvitation> acceptedRecipient(
    String scopeId,
    String invitationId, {
    String? acceptanceProofHash,
  }) async {
    final h = hint();
    return VerifiedCryptoInvitation(
      {
        'invitation': {'id': invitationId, 'scopeId': scopeId},
        'acceptanceProofHash': changed == 'acceptance'
            ? hash('d')
            : h.acceptanceProofHash,
        'creatorAuthorization': {
          'commandBase64': base64Encode(
            CryptoJson.encode({
              'payload': {
                'role': 'viewer',
                'creatorProofHash': changed == 'creator'
                    ? hash('d')
                    : h.creatorProofHash,
                'tokenHash': changed == 'token' ? hash('d') : h.tokenHash,
              },
            }),
          ),
        },
      },
      _VerifiedDirectory(),
      [],
    );
  }

  @override
  Future<void> trustCreatorFromDirectory(
    VerifiedCryptoInvitation invitation,
  ) async {
    trusted++;
  }

  @override
  Future<void> admit(
    VerifiedCryptoInvitation recipient,
    ScopeRotationReview reviewedInventory, {
    Future<void> Function(VerifiedCryptoInvitation)? beforeDisclosure,
    Future<void> Function()? freshDisclosureBoundary,
  }) async {
    admitted++;
    if (grantError != null) throw grantError!;
  }
}

Future<void> _ownerPage(WidgetTester tester, _Invites invites) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        hostingInformationProvider.overrideWith(
          (ref, target) async => const HostingInformation(),
        ),
      ],
      child: MaterialApp(
        locale: const Locale('sl'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: CryptoInvitationPage(
          account: _Account(),
          invitationId: inviteId,
          scopeId: sharingScopeId,
          expectedAcceptance: hint(),
          repository: invites,
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets(
    'oct31 owner push shows progress then verified completion without redundant confirmation',
    (tester) async {
      final invites = _Invites('');
      invites.automaticGate = Completer<ForegroundInvitationApprovalResult>();
      await _ownerPage(tester, invites);
      expect(find.text('Omogočanje dostopa …'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('crypto-invitation-confirm')),
        findsNothing,
      );
      expect(invites.foregroundGuard!(), isTrue);
      invites.automaticGate!.complete(
        const ForegroundInvitationApprovalResult(
          ForegroundInvitationApprovalStatus.completed,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Dostop omogočen'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('crypto-invitation-approved-close')),
        findsOneWidget,
      );
      expect(invites.admitted, 0);
      expect(invites.trusted, 0);
      expect(invites.automaticAttempts, 1);
    },
  );

  testWidgets(
    'oct31 pending automatic approval retains retry and does not expose a manual grant',
    (tester) async {
      final invites = _Invites('')
        ..automaticResults = const [
          ForegroundInvitationApprovalResult(
            ForegroundInvitationApprovalStatus.pending,
            'scope_receipt_pending',
          ),
          ForegroundInvitationApprovalResult(
            ForegroundInvitationApprovalStatus.completed,
          ),
        ];
      await _ownerPage(tester, invites);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('crypto-invitation-confirm')),
        findsNothing,
      );
      expect(find.text('Dostop omogočen'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('crypto-invitation-retry')));
      await tester.pumpAndSettle();
      expect(find.text('Dostop omogočen'), findsOneWidget);
      expect(invites.automaticAttempts, 2);
      expect(invites.admitted, 0);
    },
  );

  testWidgets(
    'oct31 stale manual consumed error reconciles verified automatic completion',
    (tester) async {
      final invites = _Invites('')
        ..grantError = const CollaborationApiException('invitation_invalid')
        ..automaticResults = const [
          ForegroundInvitationApprovalResult(
            ForegroundInvitationApprovalStatus.manualReview,
            'crypto_invitation_auto_policy_changed',
          ),
          ForegroundInvitationApprovalResult(
            ForegroundInvitationApprovalStatus.completed,
          ),
        ];
      await _ownerPage(tester, invites);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('crypto-invitation-confirm')),
        160,
      );
      await tester.tap(find.byKey(const ValueKey('crypto-invitation-confirm')));
      await tester.pumpAndSettle();
      expect(find.text('Dostop omogočen'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('crypto-invitation-confirm')),
        findsNothing,
      );
      expect(invites.admitted, 1);
      expect(invites.automaticAttempts, 2);
    },
  );

  testWidgets(
    'oct31 generic invalid manual request cannot imply successful access',
    (tester) async {
      final invites = _Invites('')
        ..grantError = const CollaborationApiException('invitation_invalid')
        ..automaticResults = const [
          ForegroundInvitationApprovalResult(
            ForegroundInvitationApprovalStatus.manualReview,
            'crypto_invitation_original_intent_missing',
          ),
          ForegroundInvitationApprovalResult(
            ForegroundInvitationApprovalStatus.pending,
            'invitation_invalid',
          ),
        ];
      await _ownerPage(tester, invites);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('crypto-invitation-confirm')),
        160,
      );
      await tester.tap(find.byKey(const ValueKey('crypto-invitation-confirm')));
      await tester.pumpAndSettle();
      expect(find.text('Dostop omogočen'), findsNothing);
      expect(
        find.byKey(const ValueKey('crypto-invitation-retry')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('crypto-invitation-confirm')),
        findsNothing,
      );
      expect(invites.automaticAttempts, 2);
    },
  );

  testWidgets(
    'oct31 automatic owner capability expires on background and disposal',
    (tester) async {
      final invites = _Invites('')
        ..automaticGate = Completer<ForegroundInvitationApprovalResult>();
      await _ownerPage(tester, invites);
      expect(invites.foregroundGuard!(), isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      expect(invites.foregroundGuard!(), isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(invites.foregroundGuard!(), isFalse);
      invites.automaticGate!.complete(
        const ForegroundInvitationApprovalResult(
          ForegroundInvitationApprovalStatus.completed,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Dostop omogočen'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      expect(invites.foregroundGuard!(), isFalse);
    },
  );

  testWidgets(
    'oct31 explicit push retries an already-seen failed approval event',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final controller = SharingUiController(
        initial: shared(inbox: [event(1)]),
      );
      var attempts = 0;
      await tester.pumpWidget(
        coordinator(controller, (current, ids) async {
          attempts++;
          if (attempts == 1) throw const FormatException('PRIVATE data');
        }),
      );
      await tester.pumpAndSettle();
      expect(attempts, 1);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ForegroundInvitationApprovalCoordinator)),
      );
      container
          .read(foregroundInvitationApprovalRequestProvider.notifier)
          .state++;
      await tester.pumpAndSettle();
      expect(attempts, 2);
      controller.replace(
        shared(inbox: [event(1)], synced: DateTime.utc(2026, 2)),
      );
      await tester.pumpAndSettle();
      expect(attempts, 2);
    },
  );

  testWidgets('oct31 deferred push during sync retains the explicit retry', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final controller = SharingUiController(initial: shared(inbox: [event(1)]));
    var attempts = 0;
    await tester.pumpWidget(
      coordinator(controller, (current, ids) async {
        attempts++;
        if (attempts == 1) throw const FormatException('transient');
      }),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ForegroundInvitationApprovalCoordinator)),
    );
    controller.replace(shared(inbox: [event(1)], syncing: true));
    await tester.pumpAndSettle();
    container
        .read(foregroundInvitationApprovalRequestProvider.notifier)
        .state++;
    await tester.pumpAndSettle();
    expect(attempts, 1);
    controller.replace(shared(inbox: [event(1)]));
    await tester.pumpAndSettle();
    expect(attempts, 2);
  });

  test(
    'actual host wire strips crypto2 prefix before typed acceptance parsing',
    () {
      final wire = event(8).toJson();
      wire['kind'] = 'crypto2.invitation.accepted'.substring(8);
      final parsed = SharedInboxEntry.fromJson(wire);
      expect(parsed.kind, 'invitation.accepted');
      expect(parsed.invitationAcceptance!.same(hint()), isTrue);
      expect(
        SharedInboxGroup([
          parsed,
        ]).targetFor(sharingSession()).invitationAcceptance,
        isNotNull,
      );
    },
  );
  test(
    'accepted invitation metadata survives persistence, read and exact group target',
    () {
      final original = event(7);
      final read = SharedInboxEntry.fromJson(
        original.toJson(),
      ).withReadAt(DateTime.utc(2026));
      final target = SharedInboxGroup([read]).targetFor(sharingSession());
      final restored = NotificationTarget.fromJson(target.toJson());
      expect(restored.invitationAcceptance!.same(hint()), isTrue);
      expect(restored.records.single.recordId, inviteId);
      expect(restored.inboxIds, [7]);
    },
  );
  test(
    'accepted invitation metadata rejects substitutions and malformed fields',
    () {
      final valid = event(7).toJson();
      final invalid = <Map<String, dynamic>>[
        {...valid, 'scopeId': inviteId},
        {...valid, 'targetId': sharingScopeId},
        {...valid, 'targetType': 'task'},
        {...valid, 'audience': 'scope'},
        {...valid, 'kind': 'member.joined'},
        {...valid, 'category': 'tasks'},
        {...valid, 'invitationAcceptance': null},
        {
          ...valid,
          'invitationAcceptance': {...hint().toJson(), 'tokenHash': 'bad'},
        },
        {
          ...valid,
          'invitationAcceptance': {...hint().toJson(), 'title': 'private'},
        },
      ];
      for (final value in invalid) {
        expect(() => SharedInboxEntry.fromJson(value), throwsFormatException);
      }
      expect(
        () => NotificationTarget(
          serverUrl: sharingSession().serverUrl,
          serverId: sharingSession().serverId,
          accountId: sharingSession().accountId,
          scopeId: sharingScopeId,
          records: [
            const NotificationRecordTarget(
              type: 'membership',
              recordId: inviteId,
            ),
          ],
          invitationAcceptance: hint(),
        ),
        throwsFormatException,
      );
    },
  );
  group('', () {
    for (final changed in ['acceptance', 'creator', 'token']) {
      testWidgets(
        'exact manual review rejects changed $changed before trust or grant',
        (tester) async {
          final invites = _Invites(changed);
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                hostingInformationProvider.overrideWith(
                  (ref, target) async => const HostingInformation(),
                ),
              ],
              child: MaterialApp(
                locale: const Locale('en'),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: CryptoInvitationPage(
                  account: _Account(),
                  invitationId: inviteId,
                  scopeId: sharingScopeId,
                  expectedAcceptance: hint(),
                  repository: invites,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(invites.trusted, 0);
          expect(invites.admitted, 0);
          await tester.scrollUntilVisible(
            find.byKey(const ValueKey('crypto-invitation-retry')),
            160,
          );
          expect(
            find.byKey(const ValueKey('crypto-invitation-confirm')),
            findsNothing,
          );
          expect(
            find.byKey(const ValueKey('crypto-invitation-retry')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  });
  testWidgets(
    'foreground coordinator ignores ordinary sync, duplicate and removed events',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final controller = SharingUiController(initial: shared());
      var calls = 0;
      await tester.pumpWidget(
        coordinator(controller, (current, invitationIds) async {
          expect(current(), isTrue);
          calls++;
        }),
      );
      await tester.pumpAndSettle();
      expect(calls, 1);
      controller.replace(shared(synced: DateTime.utc(2026)));
      await tester.pumpAndSettle();
      expect(calls, 1);
      controller.replace(shared(inbox: [event(1)], syncing: true));
      await tester.pumpAndSettle();
      expect(calls, 1);
      controller.replace(shared(inbox: [event(1)]));
      await tester.pumpAndSettle();
      expect(calls, 2);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ForegroundInvitationApprovalCoordinator)),
      );
      container
          .read(foregroundInvitationApprovalRequestProvider.notifier)
          .state++;
      controller.replace(shared(inbox: [event(1)]));
      await tester.pumpAndSettle();
      controller.replace(shared());
      await tester.pumpAndSettle();
      expect(calls, 3);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(calls, 4);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'foreground guard expires during background, lock and account switch',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      final controller = SharingUiController(initial: shared());
      final gate = Completer<void>();
      bool Function()? active;
      var calls = 0;
      await tester.pumpWidget(
        coordinator(controller, (current, invitationIds) async {
          calls++;
          active = current;
          await gate.future;
        }),
      );
      await tester.pumpAndSettle();
      expect(calls, 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(calls, 1);
      expect(active!(), isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      expect(active!(), isFalse);
      controller.replace(shared(second: true));
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(calls, 1);
      expect(active!(), isFalse);
      gate.complete();
      await tester.pumpAndSettle();
      expect(calls, 2);
      controller.replace(shared(second: true, locked: true));
      await tester.pumpAndSettle();
      expect(active!(), isFalse);
      await tester.pumpWidget(const SizedBox());
      expect(active!(), isFalse);
    },
  );

  testWidgets(
    'accepted event deferred before scheduled execution remains eligible once',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final controller = SharingUiController(initial: shared());
      var calls = 0;
      await tester.pumpWidget(
        coordinator(controller, (current, invitationIds) async {
          expect(current(), isTrue);
          calls++;
        }),
      );
      await tester.pumpAndSettle();
      expect(calls, 1);
      controller.replace(shared(inbox: [event(9)]));
      controller.replace(shared(inbox: [event(9)], syncing: true));
      await tester.pumpAndSettle();
      expect(calls, 1);
      controller.replace(shared(inbox: [event(9)]));
      await tester.pumpAndSettle();
      expect(calls, 2);
      controller.replace(shared(inbox: [event(9)], syncing: true));
      controller.replace(shared(inbox: [event(9)]));
      await tester.pumpAndSettle();
      expect(calls, 2);
    },
  );
  testWidgets(
    'new exact acceptance hints coalesce while busy without backlog sweep',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final controller = SharingUiController(initial: shared());
      final calls = <Set<String>>[];
      final gate = Completer<void>();
      await tester.pumpWidget(
        coordinator(controller, (current, ids) async {
          calls.add({...ids});
          if (calls.length == 2) await gate.future;
        }),
      );
      await tester.pumpAndSettle();
      expect(calls, [<String>{}]);
      controller.replace(shared(inbox: [event(1)]));
      await tester.pumpAndSettle();
      expect(calls.last, {inviteId});
      const secondId = '10000000-0000-4000-8000-000000000004';
      final second = SharedInboxEntry.fromJson({
        ...event(2).toJson(),
        'targetId': secondId,
        'invitationAcceptance': {...hint().toJson(), 'invitationId': secondId},
      });
      controller.replace(shared(inbox: [event(1), second]));
      await tester.pumpAndSettle();
      expect(calls.length, 2);
      gate.complete();
      await tester.pumpAndSettle();
      expect(calls, [
        <String>{},
        {inviteId},
        {secondId},
      ]);
    },
  );
}
