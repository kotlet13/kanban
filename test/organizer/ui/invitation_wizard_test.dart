import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:kanban/theme/jivie_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/data/pending_invitation_store.dart';
import 'package:kanban/organizer/platform/invitation_links/invitation_link.dart';
import 'package:kanban/organizer/platform/invitation_links/invitation_link_providers.dart';
import 'package:kanban/organizer/presentation/shared/invitation_wizard.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/crypto_identity_store.dart';
import 'package:kanban/organizer/data/e2ee/invite_crypto_repository.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart'
    show CryptoAuthorityPending;

import 'sharing_ui_fixture.dart';
import 'local_spaces_navigation_test.dart' show loadCaptureFonts;

final _link = InvitationLink(
  serverUrl: 'https://sharing.example.test',
  token: 'fhi3_${'b' * 64}',
);

class _Controller extends SharingUiController {
  _Controller({
    super.initial,
    this.viewer = false,
    this.encrypted = false,
    this.awaitingApproval = false,
  }) {
    emailPreview = true;
  }
  final bool viewer, encrypted, awaitingApproval;
  int previews = 0;
  Completer<void>? previewGate, acceptGate;
  int selectFailures = 0;
  @override
  Future<void> acceptInvitation(String token) async {
    await acceptGate?.future;
    await super.acceptInvitation(token);
  }

  @override
  Future<void> selectSpace(String? id) async {
    if (selectFailures > 0) {
      selectFailures--;
      throw const CollaborationException('network');
    }
    await super.selectSpace(id);
  }

  @override
  Future<SharedInvitationPreview> previewInvitation({
    required String serverUrl,
    required String token,
    bool allowLocalHttp = false,
  }) async {
    previews++;
    await previewGate?.future;
    final p = await super.previewInvitation(serverUrl: serverUrl, token: token);
    return SharedInvitationPreview(
      scopeName: p.scopeName,
      scopeId: p.scopeId,
      kind: p.kind,
      recipientUsername: p.recipientUsername,
      recipientEmail: p.recipientEmail,
      inviterName: p.inviterName,
      invitationId: encrypted ? 'saved-invite' : p.invitationId,
      role: viewer ? SharedRole.viewer : SharedRole.member,
      expiresAt: p.expiresAt,
      registrationAllowed: p.registrationAllowed,
      contractVersion: encrypted ? 4 : 3,
      awaitingApproval: awaitingApproval,
      accessScope: 'space',
      requiresExplicitAcceptance: true,
    );
  }

  @override
  Future<void> loginForInvitation({
    required String serverUrl,
    required String invitationToken,
    required String username,
    required String password,
    String? otp,
    String deviceName = 'Jivie',
  }) => login(
    serverUrl: serverUrl,
    username: username,
    password: password,
    otp: otp,
  );
}

class _CryptoStore implements CryptoIdentityStore {
  @override
  String get partition => sharingSession().partition;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CryptoAccount implements AccountCryptoV2Workflow {
  @override
  final CryptoIdentityStore store = _CryptoStore();
  @override
  Future<String> localPhase() async => 'ready';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CryptoCollaboration implements CollaborationRepository {
  _CryptoCollaboration(this.account);
  final AccountCryptoV2Workflow account;
  @override
  Future<AccountCryptoV2Workflow> connectedCryptoAccount() async => account;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CryptoDirectory implements VerifiedAccountDirectory {
  @override
  String get accountId => sharingSession().accountId;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CryptoInvites extends InviteCryptoRepository {
  _CryptoInvites(_CryptoAccount account)
    : super(SessionCryptoAccess(account: account));
  int trusts = 0, accepts = 0, resumes = 0;
  Object? trustError, resumeError;
  Completer<void>? trustGate;
  Future<void> Function()? afterAccept;
  String? resumedScope, resumedAfterAccept;
  Completer<void>? resumeGate;
  Completer<void>? inspectionGate;
  Object? inspectionError;
  VerifiedCryptoInvitation? inspectedInvitation;
  int inspections = 0;
  @override
  Future<String?> resumeAccepted(String invitationId) async {
    resumes++;
    await resumeGate?.future;
    if (resumeError != null) throw resumeError!;
    return resumedScope;
  }

  @override
  Future<VerifiedCryptoInvitation> inspect({
    String? token,
    String? invitationId,
  }) async {
    inspections++;
    await inspectionGate?.future;
    if (inspectionError != null) throw inspectionError!;
    return inspectedInvitation ??
        VerifiedCryptoInvitation(
          {
            'invitation': {
              'id': 'saved-invite',
              'scopeId': sharingScopeId,
              'role': 'viewer',
            },
            'creatorAuthorization': {
              'commandBase64':
                  'eyJhY2NvdW50SWQiOiIzMDAwMDAwMC0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAwMDEiLCJvcGVyYXRpb24iOiJjcnlwdG8yLmludml0YXRpb25zLmNyZWF0ZSIsInBheWxvYWQiOnsiZXhwaXJlc0F0Ijo0MDcwOTA4ODAwLCJpbnZpdGF0aW9uSWQiOiJzYXZlZC1pbnZpdGUiLCJyZWNpcGllbnQiOnsia2luZCI6InVzZXJuYW1lIiwidmFsdWUiOiJyZWNpcGllbnQifSwicm9sZSI6InZpZXdlciIsInNjb3BlSWQiOiIxMDAwMDAwMC0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAwMDEifSwidmVyc2lvbiI6Mn0=',
            },
          },
          _CryptoDirectory(),
          [],
        );
  }

  @override
  Future<void> trustCreatorFromDirectory(
    VerifiedCryptoInvitation invite,
  ) async {
    trusts++;
    await trustGate?.future;
    if (trustError != null) throw trustError!;
  }

  @override
  Future<Map<String, dynamic>> accept(
    VerifiedCryptoInvitation invite, {
    required String actionId,
  }) async {
    await trustCreatorFromDirectory(invite);
    accepts++;
    if (resumedAfterAccept != null) resumedScope = resumedAfterAccept;
    await afterAccept?.call();
    return {};
  }
}

class _GatedPendingStore extends MemoryPendingInvitationStore {
  Completer<void>? readGate;
  Completer<void>? readEntered;
  @override
  Future<PendingInvitation?> read() async {
    if (readGate != null) {
      if (readEntered?.isCompleted == false) readEntered!.complete();
      await readGate!.future;
    }
    return super.read();
  }
}

GlobalKey? _captureKey;
Future<void> _capture(WidgetTester tester, String name) async {
  if (Platform.environment['JIVIE_UI_CAPTURE'] != '1') return;
  final render =
      _captureKey!.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await render.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory('build/qa/invitation-simplification');
    await dir.create(recursive: true);
    await File(
      '${dir.path}/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> _pump(
  WidgetTester tester,
  _Controller controller, {
  InvitationLink? link,
  double width = 390,
  String locale = 'sl',
  MemoryPendingInvitationStore? store,
  _CryptoInvites? crypto,
  bool settle = true,
}) async {
  await loadCaptureFonts(tester);
  if (Platform.environment['JIVIE_UI_CAPTURE'] == '1') {
    await tester.runAsync(() async {
      final sdk = Platform.resolvedExecutable.split('/bin/cache/').first;
      final bytes = await File(
        '$sdk/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
      ).readAsBytes();
      await (FontLoader(
        'Roboto',
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    });
  }
  _captureKey = GlobalKey();
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        collaborationProvider.overrideWith(() => controller),
        if (crypto != null)
          collaborationRepositoryProvider.overrideWith(
            (ref) async => _CryptoCollaboration(crypto.access.account),
          ),
        pendingInvitationStoreProvider.overrideWithValue(
          store ?? MemoryPendingInvitationStore(),
        ),
        securePendingInvitationProvider.overrideWith(
          (ref) async => controller.savedInvitation,
        ),
      ],
      child: RepaintBoundary(
        key: _captureKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildJivieTheme(Brightness.light),
          locale: Locale(locale),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: TextButton(
                onPressed: () => crypto == null
                    ? showInvitationWizard(context, ref, initialLink: link)
                    : Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => InvitationWizard(
                            initialLink: link,
                            cryptoRepository: (_) => crypto,
                          ),
                        ),
                      ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }
}

Future<void> _tap(WidgetTester tester, String key) async {
  final target = find.byKey(ValueKey(key));
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _enter(WidgetTester tester, String key, String value) async {
  final target = find.byKey(ValueKey('invitation-flow-$key'));
  await tester.ensureVisible(target);
  await tester.enterText(target, value);
}

void main() {
  VerifiedCryptoInvitation preauthorizedReview() => VerifiedCryptoInvitation(
    {
      'invitation': {
        'id': 'saved-invite',
        'scopeId': sharingScopeId,
        'role': 'viewer',
      },
      'creatorAuthorization': {
        'commandBase64': base64Encode(
          CryptoJson.encode({
            'accountId': sharingSession().accountId,
            'operation': 'crypto2.invitations.create',
            'payload': {
              'expiresAt': 4070908800,
              'invitationId': 'saved-invite',
              'preauthorization': {'version': 1},
              'recipient': {'kind': 'username', 'value': 'recipient'},
              'role': 'viewer',
              'scopeId': sharingScopeId,
            },
            'version': 2,
          }),
        ),
      },
    },
    _CryptoDirectory(),
    [],
  );

  testWidgets(
    'preauthorization-link26 account change during activation cannot select',
    (tester) async {
      final controller = _Controller(encrypted: true);
      final crypto = _CryptoInvites(_CryptoAccount())
        ..inspectedInvitation = preauthorizedReview()
        ..resumedAfterAccept = sharingScopeId
        ..resumeGate = Completer<void>();
      final store = MemoryPendingInvitationStore()
        ..value = PendingInvitation(
          serverUrl: _link.serverUrl,
          token: _link.token,
          serverId: sharingSession().serverId,
        );
      await _pump(
        tester,
        controller,
        link: _link,
        crypto: crypto,
        store: store,
      );
      final button = tester.widget<FilledButton>(
        find.byKey(const ValueKey('invitation-flow-join')),
      );
      final continuing = (button.onPressed as dynamic)() as Future<void>;
      await tester.pump();
      expect(crypto.accepts, 1);
      expect(crypto.resumes, 1);
      controller.switchAccount();
      await tester.pump();
      crypto.resumeGate!.complete();
      await continuing;
      await tester.pumpAndSettle();
      expect(
        controller.state.valueOrNull?.session?.accountId,
        sharingSession(second: true).accountId,
      );
      expect(controller.state.valueOrNull?.selectedSpaceId, isNull);
      expect(store.value?.invitationId, 'saved-invite');
      expect(crypto.accepts, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'preauthorization-link26 one consent selects target using ready account',
    (tester) async {
      final controller = _Controller(encrypted: true);
      final crypto = _CryptoInvites(_CryptoAccount())
        ..inspectedInvitation = preauthorizedReview()
        ..resumedAfterAccept = sharingScopeId;
      final store = MemoryPendingInvitationStore()
        ..value = PendingInvitation(
          serverUrl: _link.serverUrl,
          token: _link.token,
          serverId: sharingSession().serverId,
        );
      await _pump(
        tester,
        controller,
        link: _link,
        crypto: crypto,
        store: store,
      );
      expect(crypto.accepts, 0);
      await _tap(tester, 'invitation-flow-join');
      expect(crypto.accepts, 1);
      expect(crypto.resumes, 1);
      expect(crypto.inspections, 1);
      expect(controller.state.valueOrNull?.selectedSpaceId, sharingScopeId);
      expect(
        controller.state.valueOrNull?.session?.deviceId,
        sharingSession().deviceId,
      );
      expect(controller.savedInvitation, isNull);
      expect(find.byType(InvitationWizard), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'preauthorization-link26 activation error offers status without second consent',
    (tester) async {
      final controller = _Controller(encrypted: true);
      final crypto = _CryptoInvites(_CryptoAccount())
        ..inspectedInvitation = preauthorizedReview()
        ..resumeError = const CryptoAuthorityPending(
          'crypto_reconciliation_required',
        );
      final store = MemoryPendingInvitationStore()
        ..value = PendingInvitation(
          serverUrl: _link.serverUrl,
          token: _link.token,
          serverId: sharingSession().serverId,
        );
      await _pump(
        tester,
        controller,
        link: _link,
        crypto: crypto,
        store: store,
        locale: 'en',
      );
      await _tap(tester, 'invitation-flow-join');
      expect(crypto.accepts, 1);
      expect(store.value?.invitationId, 'saved-invite');
      expect(find.text('Agree and accept invitation'), findsNothing);
      expect(find.text('Check access'), findsOneWidget);
      expect(find.textContaining('owner still needs'), findsNothing);
      expect(
        find.textContaining('Access has not been verified'),
        findsOneWidget,
      );
      crypto.resumeError = null;
      crypto.resumedScope = sharingScopeId;
      await _tap(tester, 'invitation-flow-join');
      expect(crypto.accepts, 1);
      expect(find.byType(InvitationWizard), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final locale in ['en', 'sl']) {
    testWidgets(
      'invitation-review26 link renders signed review before one consent $locale',
      (tester) async {
        final controller = _Controller(encrypted: true);
        final crypto = _CryptoInvites(_CryptoAccount());
        final store = MemoryPendingInvitationStore()
          ..value = PendingInvitation(
            serverUrl: _link.serverUrl,
            token: _link.token,
            serverId: sharingSession().serverId,
          );
        await _pump(
          tester,
          controller,
          link: _link,
          crypto: crypto,
          store: store,
          locale: locale,
        );
        expect(
          find.text(locale == 'sl' ? 'Dostop: Bere' : 'Access: Can view'),
          findsOneWidget,
        );
        expect(find.text('recipient'), findsOneWidget);
        expect(crypto.inspections, 1);
        expect(crypto.trusts, 0);
        expect(crypto.accepts, 0);
        expect(find.text('Review invitation'), findsNothing);
        final label = locale == 'sl'
            ? 'Strinjam se in sprejmi povabilo'
            : 'Agree and accept invitation';
        expect(find.text(label), findsOneWidget);
        await _tap(tester, 'invitation-flow-join');
        expect(crypto.accepts, 1);
        expect(crypto.inspections, 1);
        expect(crypto.trusts, 1);
        expect(store.value?.invitationId, 'saved-invite');
        expect(find.text(label), findsNothing);
        expect(
          find.textContaining(
            locale == 'sl'
                ? 'Lastnik mora še odobriti'
                : 'owner still needs to approve',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'invitation-review26 same-server account switch invalidates review',
    (tester) async {
      final controller = _Controller(encrypted: true);
      final crypto = _CryptoInvites(_CryptoAccount());
      final store = MemoryPendingInvitationStore()
        ..value = PendingInvitation(
          serverUrl: _link.serverUrl,
          token: _link.token,
          serverId: sharingSession().serverId,
        );
      await _pump(
        tester,
        controller,
        link: _link,
        crypto: crypto,
        store: store,
        locale: 'en',
      );
      expect(find.text('Access: Can view'), findsOneWidget);
      controller.switchAccount();
      await tester.pumpAndSettle();
      expect(find.text('Access: Can view'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('invitation-flow-join')),
            )
            .onPressed,
        isNull,
      );
      expect(crypto.accepts, 0);
      expect(store.value?.invitationId, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'invitation-review26 superseded hydration never publishes review',
    (tester) async {
      final controller = _Controller(encrypted: true);
      final crypto = _CryptoInvites(_CryptoAccount())
        ..inspectionGate = Completer<void>();
      final store = MemoryPendingInvitationStore()
        ..value = PendingInvitation(
          serverUrl: _link.serverUrl,
          token: _link.token,
          serverId: sharingSession().serverId,
        );
      await _pump(
        tester,
        controller,
        link: _link,
        crypto: crypto,
        store: store,
        locale: 'en',
        settle: false,
      );
      expect(crypto.inspections, 1);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(MaterialApp)),
      );
      final newer = InvitationLink(
        serverUrl: _link.serverUrl,
        token: 'fhi4_${'d' * 64}',
      );
      container.read(pendingInvitationLinkProvider.notifier).state = newer;
      await tester.pump();
      crypto.inspectionGate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(InvitationWizard), findsNothing);
      expect(container.read(pendingInvitationLinkProvider), same(newer));
      expect(crypto.accepts, 0);
      expect(crypto.trusts, 0);
      expect(tester.takeException(), isNull);
    },
  );

  final rootEmailLink = InvitationLink.tryParseInput(
    'https://sharing.example.test/index.php?controller=InvitationController&action=show&plugin=FamilyHub&language=en#token=fhi4_${'a' * 64}',
  )!;

  testWidgets(
    'ux26 accepted preview without link checkpoint checks status and surfaces proof error',
    (tester) async {
      final controller = _Controller(
        encrypted: true,
        viewer: true,
        awaitingApproval: true,
      );
      final crypto = _CryptoInvites(_CryptoAccount());
      final store = MemoryPendingInvitationStore()
        ..value = PendingInvitation(
          serverUrl: 'https://sharing.example.test/',
          token: rootEmailLink.token,
          serverId: sharingSession().serverId,
        );
      await _pump(
        tester,
        controller,
        link: rootEmailLink,
        crypto: crypto,
        store: store,
        locale: 'en',
      );
      expect(find.text('Check access'), findsOneWidget);
      expect(store.value?.accountPartition, isNull);
      expect(crypto.resumes, 0);
      await _tap(tester, 'invitation-flow-join');
      expect(crypto.resumes, 1);
      expect(crypto.accepts, 0);
      crypto.resumeError = const CryptoAuthorityPending(
        'invitation_proof_pending',
      );
      await _tap(tester, 'invitation-flow-join');
      expect(crypto.resumes, 2);
      expect(crypto.accepts, 0);
      expect(
        find.textContaining('cannot verify the saved acceptance'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'canonical HTTPS Join persists pending keys and resumes same accepted invitation',
    (tester) async {
      expect(rootEmailLink.serverUrl, 'https://sharing.example.test');
      final controller = _Controller(encrypted: true, viewer: true);
      final crypto = _CryptoInvites(_CryptoAccount());
      final store = MemoryPendingInvitationStore()
        ..value = PendingInvitation(
          serverUrl: 'https://sharing.example.test/',
          token: rootEmailLink.token,
          serverId: sharingSession().serverId,
        );
      await _pump(
        tester,
        controller,
        link: rootEmailLink,
        crypto: crypto,
        store: store,
        locale: 'en',
      );
      await _tap(tester, 'invitation-flow-join');
      expect(crypto.accepts, 1);
      expect(store.value?.serverUrl, 'https://sharing.example.test/');
      expect(store.value?.invitationId, 'saved-invite');
      expect(store.value?.accountPartition, sharingSession().partition);
      expect(find.text('Check access'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await _tap(tester, 'invitation-flow-join');
      expect(crypto.accepts, 1);
      expect(crypto.resumes, greaterThanOrEqualTo(1));
      expect(find.text('Check access'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  for (final changed in ['host', 'path', 'token', 'serverId', 'partition']) {
    testWidgets(
      'canonical HTTPS Join preserves newer pending $changed after accept',
      (tester) async {
        final controller = _Controller(encrypted: true, viewer: true);
        final crypto = _CryptoInvites(_CryptoAccount());
        final store = MemoryPendingInvitationStore()
          ..value = PendingInvitation(
            serverUrl: 'https://sharing.example.test/',
            token: rootEmailLink.token,
            serverId: sharingSession().serverId,
          );
        final newer = PendingInvitation(
          serverUrl: changed == 'host'
              ? 'https://other.example.test/'
              : changed == 'path'
              ? 'https://sharing.example.test/other/'
              : 'https://sharing.example.test/',
          token: changed == 'token' ? 'fhi4_${'c' * 64}' : rootEmailLink.token,
          serverId: changed == 'serverId'
              ? 'different-server'
              : sharingSession().serverId,
          accountPartition: changed == 'partition'
              ? 'different-partition'
              : null,
        );
        crypto.afterAccept = () async => store.value = newer;
        await _pump(
          tester,
          controller,
          link: rootEmailLink,
          crypto: crypto,
          store: store,
          locale: 'en',
        );
        await _tap(tester, 'invitation-flow-join');
        expect(crypto.accepts, 1);
        expect(store.value, same(newer));
        expect(store.value?.invitationId, isNull);
        expect(find.text('Check access'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'canonical HTTPS Join ignores session change during awaited pending read',
    (tester) async {
      final controller = _Controller(encrypted: true, viewer: true);
      final crypto = _CryptoInvites(_CryptoAccount());
      final store = _GatedPendingStore()
        ..value = PendingInvitation(
          serverUrl: 'https://sharing.example.test/',
          token: rootEmailLink.token,
          serverId: sharingSession().serverId,
        );
      crypto.afterAccept = () async {
        store.readGate = Completer<void>();
        store.readEntered = Completer<void>();
      };
      await _pump(
        tester,
        controller,
        link: rootEmailLink,
        crypto: crypto,
        store: store,
        locale: 'en',
      );
      final button = tester.widget<FilledButton>(
        find.byKey(const ValueKey('invitation-flow-join')),
      );
      final joining = (button.onPressed as dynamic)() as Future<void>;
      await tester.pump();
      await store.readEntered!.future;
      controller.switchAccount();
      store.readGate!.complete();
      await joining;
      await tester.pumpAndSettle();
      expect(crypto.accepts, 1);
      expect(store.value?.accountPartition, isNull);
      expect(store.value?.invitationId, isNull);
      expect(find.text('Check access'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'encrypted wizard joins without card and resumes without repeating acceptance',
    (tester) async {
      final controller = _Controller(encrypted: true, viewer: true);
      final crypto = _CryptoInvites(_CryptoAccount());
      final store = MemoryPendingInvitationStore()
        ..value = PendingInvitation(
          serverUrl: _link.serverUrl,
          token: _link.token,
        );
      await _pump(
        tester,
        controller,
        link: _link,
        crypto: crypto,
        store: store,
      );
      expect(crypto.accepts, 0);
      await _tap(tester, 'invitation-flow-join');
      expect(crypto.trusts, 1);
      expect(crypto.accepts, 1);
      expect(find.byType(AlertDialog), findsNothing);
      expect(store.value?.invitationId, 'saved-invite');
      expect(store.value?.accountPartition, sharingSession().partition);
      expect(find.text('Preveri dostop'), findsOneWidget);
      await _tap(tester, 'invitation-flow-join');
      expect(crypto.resumes, 1);
      expect(crypto.accepts, 1);
      expect(store.value?.token, _link.token);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('encrypted wizard blocks changed root without generic retry', (
    tester,
  ) async {
    final controller = _Controller(encrypted: true, viewer: true);
    final crypto = _CryptoInvites(_CryptoAccount())
      ..trustError = const CryptoDirectoryException('directory_root_changed');
    final store = MemoryPendingInvitationStore()
      ..value = PendingInvitation(
        serverUrl: _link.serverUrl,
        token: _link.token,
      );
    await _pump(tester, controller, link: _link, crypto: crypto, store: store);
    await _tap(tester, 'invitation-flow-join');
    expect(
      find.textContaining('Identiteta računa se je spremenila'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('invitation-flow-join')),
          )
          .onPressed,
      isNull,
    );
    expect(crypto.accepts, 0);
    expect(store.value?.token, _link.token);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'encrypted wizard ignores old identity completion after account switch',
    (tester) async {
      final controller = _Controller(encrypted: true, viewer: true);
      final crypto = _CryptoInvites(_CryptoAccount())
        ..trustGate = Completer<void>();
      final store = MemoryPendingInvitationStore()
        ..value = PendingInvitation(
          serverUrl: _link.serverUrl,
          token: _link.token,
        );
      await _pump(
        tester,
        controller,
        link: _link,
        crypto: crypto,
        store: store,
      );
      final button = tester.widget<FilledButton>(
        find.byKey(const ValueKey('invitation-flow-join')),
      );
      final joining = (button.onPressed as dynamic)() as Future<void>;
      await tester.pump();
      controller.switchAccount();
      crypto.trustGate!.complete();
      await joining;
      await tester.pumpAndSettle();
      expect(crypto.accepts, 0);
      expect(store.value?.invitationId, isNull);
      expect(controller.state.requireValue.selectedSpaceId, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [320.0, 390.0, 1280.0]) {
    for (final locale in ['sl', 'en']) {
      testWidgets(
        'same-server recipient previews automatically and explicitly joins $width $locale',
        (tester) async {
          final controller = _Controller(viewer: true);
          await _pump(
            tester,
            controller,
            link: _link,
            width: width,
            locale: locale,
          );
          expect(controller.previews, 1);
          expect(
            find.byKey(const ValueKey('invitation-flow-username')),
            findsNothing,
          );
          expect(controller.calls, isNot(contains('accept')));
          if (width == 390 && locale == 'sl') {
            await _capture(tester, 'invitation-prejoin-390');
          }
          await _tap(tester, 'invitation-flow-join');
          expect(controller.calls, contains('accept'));
          expect(controller.state.requireValue.selectedSpaceId, sharingScopeId);
          expect(find.byType(InvitationWizard), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets('fresh link confirms destination before preview or credentials', (
    tester,
  ) async {
    final controller = _Controller(initial: CollaborationState());
    await _pump(tester, controller, link: _link);
    expect(controller.previews, 0);
    expect(
      find.byKey(const ValueKey('invitation-flow-origin')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('invitation-flow-password')),
      findsNothing,
    );
    await _tap(tester, 'invitation-flow-confirm-origin');
    expect(controller.previews, 1);
    await _tap(tester, 'invitation-flow-login-choice');
    expect(find.byKey(const ValueKey('invitation-flow-name')), findsNothing);
    await _enter(tester, 'username', 'first');
    await _enter(tester, 'password', 'synthetic-password');
    await _tap(tester, 'invitation-flow-authenticate');
    expect(controller.loginAttempts, [null]);
    expect(controller.calls, isNot(contains('accept')));
    expect(find.byKey(const ValueKey('invitation-flow-join')), findsOneWidget);
    expect(controller.savedInvitation?.token, _link.token);
    expect(tester.takeException(), isNull);
  });
  testWidgets('registration is separate and retains invitation before Join', (
    tester,
  ) async {
    final controller = _Controller(initial: CollaborationState());
    await _pump(tester, controller, link: _link);
    await _tap(tester, 'invitation-flow-confirm-origin');
    await _tap(tester, 'invitation-flow-register-choice');
    await _enter(tester, 'username', 'second');
    await _enter(tester, 'name', 'Second');
    await _enter(tester, 'password', 'synthetic-password');
    await _enter(tester, 'confirm', 'synthetic-password');
    await _tap(tester, 'invitation-flow-authenticate');
    expect(controller.registeredUsername, 'second');
    expect(controller.calls, isNot(contains('accept')));
    expect(controller.savedInvitation?.token, _link.token);
    expect(find.byKey(const ValueKey('invitation-flow-join')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'restored pinned invitation previews without requiring paste or confirmation again',
    (tester) async {
      final store = MemoryPendingInvitationStore()
        ..value = PendingInvitation(
          serverUrl: _link.serverUrl,
          token: _link.token,
          serverId: 'pinned',
        );
      final controller = _Controller(initial: CollaborationState());
      await _pump(tester, controller, store: store);
      expect(controller.previews, 1);
      expect(
        find.byKey(const ValueKey('invitation-flow-confirm-origin')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('invitation-flow-login-choice')),
        findsOneWidget,
      );
      expect(controller.calls, isNot(contains('accept')));
    },
  );
  testWidgets('reset request keeps invitation and returns to same login', (
    tester,
  ) async {
    final controller = _Controller(initial: CollaborationState());
    await _pump(tester, controller, link: _link);
    await _tap(tester, 'invitation-flow-confirm-origin');
    await _tap(tester, 'invitation-flow-login-choice');
    await _enter(tester, 'username', 'first');
    final forgot = find.widgetWithText(TextButton, 'Pozabljeno geslo');
    await tester.ensureVisible(forgot);
    await tester.tap(forgot);
    await tester.pumpAndSettle();
    expect(controller.savedInvitation?.token, _link.token);
    await tester.tap(find.widgetWithText(TextButton, 'Prekliči').last);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('invitation-flow-username')),
      findsOneWidget,
    );
    expect(controller.savedInvitation?.token, _link.token);
    expect(tester.takeException(), isNull);
  });
  testWidgets('manual original HTTPS invitation uses same confirmation path', (
    tester,
  ) async {
    final controller = _Controller(initial: CollaborationState());
    await _pump(tester, controller);
    await _enter(
      tester,
      'input',
      '${_link.serverUrl}/index.php?controller=InvitationController&action=show&plugin=FamilyHub#token=${_link.token}',
    );
    await _tap(tester, 'invitation-flow-open');
    expect(controller.previews, 0);
    await _tap(tester, 'invitation-flow-confirm-origin');
    expect(controller.previewToken, _link.token);
    expect(controller.previewServer, _link.serverUrl);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'invalid session cannot Join and authentication failure keeps context',
    (tester) async {
      final controller = _Controller(
        initial: CollaborationState(
          session: sharingSession(),
          sessionInvalid: true,
        ),
      )..requireOtp = true;
      await _pump(tester, controller, link: _link);
      expect(find.byKey(const ValueKey('invitation-flow-join')), findsNothing);
      await _tap(tester, 'invitation-flow-confirm-origin');
      await _tap(tester, 'invitation-flow-login-choice');
      await _capture(tester, 'invitation-login-390');
      await _enter(tester, 'username', 'first');
      await _enter(tester, 'password', 'synthetic-password');
      await _tap(tester, 'invitation-flow-authenticate');
      expect(find.byKey(const ValueKey('invitation-flow-otp')), findsOneWidget);
      expect(controller.savedInvitation?.token, _link.token);
      expect(controller.calls, isNot(contains('accept')));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'new link while wizard is open preserves new routing capability',
    (tester) async {
      final controller = _Controller();
      await _pump(tester, controller, link: _link);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(InvitationWizard)),
      );
      final second = InvitationLink(
        serverUrl: _link.serverUrl,
        token: 'fhi3_${'c' * 64}',
      );
      container.read(pendingInvitationLinkProvider.notifier).state = second;
      await tester.pumpAndSettle();
      expect(find.byType(InvitationWizard), findsNothing);
      expect(
        container.read(pendingInvitationLinkProvider)?.token,
        second.token,
      );
      expect(controller.calls, isNot(contains('accept')));
    },
  );
  testWidgets('a trailing slash in copied links matches the signed-in server', (
    tester,
  ) async {
    final controller = _Controller(viewer: true);
    await _pump(
      tester,
      controller,
      link: InvitationLink(
        serverUrl: '${_link.serverUrl}/',
        token: _link.token,
      ),
    );
    expect(
      find.byKey(const ValueKey('invitation-flow-confirm-origin')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('invitation-flow-join')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('accepted invitation with opening failure retries only opening', (
    tester,
  ) async {
    final controller = _Controller(viewer: true)..selectFailures = 1;
    await _pump(tester, controller, link: _link);
    await _tap(tester, 'invitation-flow-join');
    expect(controller.calls.where((c) => c == 'accept'), hasLength(1));
    expect(find.text('Odpri prostor'), findsOneWidget);
    await _tap(tester, 'invitation-flow-join');
    expect(controller.calls.where((c) => c == 'accept'), hasLength(1));
    expect(find.byType(InvitationWizard), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'known accepted refresh error offers open without resubmitting Join',
    (tester) async {
      final controller = _Controller(viewer: true)
        ..invitationAcceptError = const CollaborationException(
          'invitation_accepted_refresh_failed',
        );
      await _pump(tester, controller, link: _link);
      await _tap(tester, 'invitation-flow-join');
      expect(find.text('Odpri prostor'), findsOneWidget);
      await _tap(tester, 'invitation-flow-join');
      expect(controller.calls, isNot(contains('accept')));
      expect(find.byType(InvitationWizard), findsNothing);
    },
  );
  testWidgets(
    'Join is disabled in flight and late old account response cannot select target',
    (tester) async {
      final controller = _Controller(viewer: true)
        ..acceptGate = Completer<void>();
      await _pump(tester, controller, link: _link);
      final button = tester.widget<FilledButton>(
        find.byKey(const ValueKey('invitation-flow-join')),
      );
      final accepting = (button.onPressed as dynamic)() as Future<void>;
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('invitation-flow-join')),
            )
            .onPressed,
        isNull,
      );
      controller.switchAccount();
      controller.acceptGate!.complete();
      await accepting;
      await tester.pumpAndSettle();
      expect(controller.state.requireValue.session?.username, 'second');
      expect(controller.state.requireValue.selectedSpaceId, isNull);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'registration validates username before sending account request',
    (tester) async {
      final controller = _Controller(initial: CollaborationState());
      await _pump(tester, controller, link: _link);
      await _tap(tester, 'invitation-flow-confirm-origin');
      await _tap(tester, 'invitation-flow-register-choice');
      await _capture(tester, 'invitation-register-390');
      await _enter(tester, 'username', 'bad user');
      await _enter(tester, 'name', 'Second');
      await _enter(tester, 'password', 'synthetic-password');
      await _enter(tester, 'confirm', 'synthetic-password');
      await _tap(tester, 'invitation-flow-authenticate');
      expect(controller.registeredUsername, isNull);
      expect(controller.savedInvitation?.token, _link.token);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'canceling unconfirmed origin retains capability without network preview',
    (tester) async {
      final controller = _Controller(initial: CollaborationState());
      await _pump(tester, controller, link: _link);
      expect(controller.savedInvitation?.token, _link.token);
      expect(controller.previews, 0);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(controller.savedInvitation?.token, _link.token);
      expect(controller.previews, 0);
    },
  );
  testWidgets('joined open retry is unavailable after switching accounts', (
    tester,
  ) async {
    final controller = _Controller(viewer: true)..selectFailures = 1;
    await _pump(tester, controller, link: _link);
    await _tap(tester, 'invitation-flow-join');
    controller.switchAccount();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('invitation-flow-join')), findsNothing);
    expect(controller.state.requireValue.selectedSpaceId, isNull);
    expect(controller.calls.where((c) => c == 'accept'), hasLength(1));
  });
  testWidgets('writer preview shows complete access before Join at390', (
    tester,
  ) async {
    final controller = _Controller();
    await _pump(tester, controller, link: _link);
    expect(find.text('Polni dostop'), findsOneWidget);
    expect(find.textContaining('vabi in odstranjuje člane'), findsOneWidget);
    expect(controller.calls, isNot(contains('accept')));
    await _capture(tester, 'invitation-writer-prejoin-390');
    expect(tester.takeException(), isNull);
  });
}
