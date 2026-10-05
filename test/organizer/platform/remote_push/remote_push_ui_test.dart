import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'package:kanban/organizer/platform/remote_push/remote_push_coordinator.dart';
import 'package:kanban/organizer/platform/remote_push/remote_push_providers.dart';
import 'package:kanban/organizer/presentation/planning/remote_push_device_settings.dart';
import 'package:kanban/organizer/presentation/organizer_shell.dart';
import 'package:kanban/organizer/state/organizer_provider.dart';
import '../../ui/organizer_ui_test.dart' as personal;
import '../../ui/sharing_ui_fixture.dart';
import 'remote_push_lifecycle_test.dart' as fixture;
import 'package:kanban/organizer/platform/remote_push/remote_push_sdk.dart';
import 'package:kanban/organizer/platform/remote_push/remote_push_lifecycle.dart';

CollaborationState shared({bool second = false}) => CollaborationState(
  session: sharingSession(second: second),
  externalPushSupported: true,
  pushProjectId: fixture.config.projectId,
  scopes: [sharingScope()],
  data: {sharingScopeId: sharingData()},
);

class PushController extends SharingUiController {
  PushController() : super(initial: shared());
  int registered = 0, disabled = 0, opened = 0;
  Completer<void>? loadGate, openGate;
  @override
  Future<CollaborationState> build() async {
    await loadGate?.future;
    return initial;
  }

  @override
  Future<RemotePushRegistrationState> configureRemotePush({
    required RemotePushIdentity identity,
    required String token,
    required String platform,
    required String language,
    required String projectId,
  }) async {
    registered++;
    return RemotePushRegistrationState(
      identity: identity,
      status: RemotePushRegistrationStatus.registered,
    );
  }

  @override
  Future<RemotePushRegistrationState> disableRemotePush({
    required RemotePushIdentity identity,
  }) async {
    disabled++;
    return const RemotePushRegistrationState();
  }

  @override
  Future<RemotePushOpenResult> openRemotePushReference(
    RemotePushReference reference,
  ) async {
    opened++;
    final session = state.requireValue.session;
    await openGate?.future;
    if (session == null) {
      return const RemotePushOpenResult(
        status: RemotePushOpenStatus.requiresLogin,
      );
    }
    if (!reference.matches(session)) {
      return const RemotePushOpenResult(
        status: RemotePushOpenStatus.wrongAccount,
      );
    }
    return RemotePushOpenResult(
      status: RemotePushOpenStatus.available,
      target: NotificationTarget(
        serverUrl: session.serverUrl,
        serverId: session.serverId,
        accountId: session.accountId,
        scopeId: sharingScopeId,
        records: const [
          NotificationRecordTarget(type: 'shoppingItem', recordId: 'item'),
        ],
      ),
    );
  }

  @override
  Future<NotificationOpenResult> openNotificationTarget(
    NotificationTarget target,
  ) async => NotificationOpenResult(
    status: NotificationOpenStatus.available,
    target: target,
  );
}

Widget host(
  PushController controller,
  fixture.FakeSdk sdk, {
  String lang = 'sl',
  bool dark = false,
  Widget child = const RemotePushDeviceSettings(),
  RemotePushReference? reference,
  bool configured = true,
}) => ProviderScope(
  overrides: [
    collaborationProvider.overrideWith(() => controller),
    remotePushSdkProvider.overrideWithValue(sdk),
    remotePushConfigurationProvider.overrideWithValue(
      configured ? fixture.config : null,
    ),
    remotePushConfigurationInvalidProvider.overrideWithValue(false),
    organizerStorageProvider.overrideWithValue(
      () async => personal.MemoryOrganizerStorage(),
    ),
    remotePushLaunchReferenceProvider.overrideWith((ref) => reference),
  ],
  child: MaterialApp(
    locale: Locale(lang),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
    home: RemotePushCoordinator(
      child: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  ),
);
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final spec in [
    (320.0, 'sl', false),
    (390.0, 'en', true),
    (1280.0, 'sl', true),
  ]) {
    testWidgets(
      'unconfigured settings fit ${spec.$1} ${spec.$2} dark=${spec.$3} without SDK calls',
      (tester) async {
        tester.view.physicalSize = Size(spec.$1, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final sdk = fixture.FakeSdk(), controller = PushController();
        await tester.pumpWidget(
          host(
            controller,
            sdk,
            lang: spec.$2,
            dark: spec.$3,
            configured: false,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(sdk.calls, isEmpty);
        expect(
          tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
          isNull,
        );
      },
    );
  }
  testWidgets(
    'device opt-in requests permission only after user action, opt-out deletes token',
    (tester) async {
      final sdk = fixture.FakeSdk(), controller = PushController();
      sdk.permission = RemotePushPermission.unknown;
      await tester.pumpWidget(host(controller, sdk));
      await tester.pumpAndSettle();
      expect(sdk.calls, isEmpty);
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(controller.registered, 1);
      expect(sdk.calls, contains('prompt'));
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(controller.disabled, 1);
      expect(sdk.calls, contains('delete'));
    },
  );
  testWidgets('old account readiness does not enable new account device', (
    tester,
  ) async {
    final sdk = fixture.FakeSdk(), controller = PushController();
    await tester.pumpWidget(host(controller, sdk));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(RemotePushDeviceSettings)),
    );
    expect(container.read(remotePushDeviceReadyProvider), isTrue);
    controller.replace(shared(second: true));
    await tester.pumpAndSettle();
    expect(container.read(remotePushDeviceReadyProvider), isFalse);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isFalse,
    );
    expect(sdk.calls, contains('delete'));
  });
  for (final expired in [false, true]) {
    testWidgets(
      'known ${expired ? 'expiry' : 'device revocation'} removes SDK token and hides stale registered readiness',
      (tester) async {
        final sdk = fixture.FakeSdk(), controller = PushController();
        await tester.pumpWidget(host(controller, sdk));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(SwitchListTile));
        await tester.pumpAndSettle();
        final container = ProviderScope.containerOf(
          tester.element(find.byType(RemotePushDeviceSettings)),
        );
        expect(container.read(remotePushDeviceReadyProvider), isTrue);
        final profile = sharingSession();
        final session = expired
            ? AccountSession.fromJson({
                ...profile.toJson(),
                'expiresAt': DateTime.utc(2000).toIso8601String(),
              })
            : profile;
        controller.replace(
          CollaborationState(
            session: session,
            externalPushSupported: true,
            pushProjectId: fixture.config.projectId,
            remotePushRegistration: RemotePushRegistrationState(
              identity: RemotePushIdentity.fromSession(session),
              status: RemotePushRegistrationStatus.registered,
            ),
            lastError: expired
                ? null
                : const CollaborationException('device_revoked'),
          ),
        );
        expect(container.read(remotePushDeviceReadyProvider), isFalse);
        await tester.pumpAndSettle();
        expect(sdk.calls, contains('auto:false'));
        expect(sdk.calls, contains('delete'));
        expect(
          container.read(remotePushDeviceStateProvider).phase,
          RemotePushDevicePhase.needsAccount,
        );
        expect(
          find.text(
            'Za oddaljena obvestila se prijavi v svoj račun. Osebna uporaba ostaja brez računa.',
          ),
          findsOneWidget,
        );
        expect(controller.registered, 1);
      },
    );
  }
  testWidgets(
    'sticky invalid session remains blocked even after lastError is cleared',
    (tester) async {
      final controller = PushController(), sdk = fixture.FakeSdk();
      await tester.pumpWidget(host(controller, sdk));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      controller.replace(
        CollaborationState(
          session: sharingSession(),
          sessionInvalid: true,
          externalPushSupported: true,
          pushProjectId: fixture.config.projectId,
        ),
      );
      await tester.pumpAndSettle();
      expect(sdk.calls, contains('delete'));
      final container = ProviderScope.containerOf(
        tester.element(find.byType(RemotePushDeviceSettings)),
      );
      expect(container.read(remotePushDeviceReadyProvider), isFalse);
      await tester.tap(find.text('Preveri obvestila znova'));
      await tester.pumpAndSettle();
      expect(controller.registered, 1);
    },
  );
  testWidgets(
    'cold reference before mount waits cached identity then opens exact verified item',
    (tester) async {
      final controller = PushController(),
          gate = Completer<void>(),
          sdk = fixture.FakeSdk(),
          session = sharingSession();
      controller.loadGate = gate;
      final reference = RemotePushReference(
        serverId: session.serverId,
        accountId: session.accountId,
        notificationId: 12,
      );
      // Shell owns its scroll viewport; do not wrap it in the host scroll view.
      await tester.pumpWidget(
        host(
          controller,
          sdk,
          child: const SizedBox(height: 900, child: OrganizerShell()),
          reference: reference,
        ),
      );
      await tester.pump();
      expect(controller.opened, 0);
      gate.complete();
      await tester.pumpAndSettle();
      expect(controller.opened, 1);
      expect(find.text('Mleko za skupno gospodinjstvo'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('late open result from A is discarded after B account switch', (
    tester,
  ) async {
    final controller = PushController(),
        sdk = fixture.FakeSdk(),
        session = sharingSession(),
        gate = Completer<void>();
    controller.openGate = gate;
    await tester.pumpWidget(
      host(
        controller,
        sdk,
        child: const SizedBox(height: 900, child: OrganizerShell()),
        reference: RemotePushReference(
          serverId: session.serverId,
          accountId: session.accountId,
          notificationId: 12,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(controller.opened, 1);
    controller.replace(shared(second: true));
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Mleko za skupno gospodinjstvo'), findsNothing);
    expect(
      find.text('Obvestilo pripada drugemu računu. Prijavi se v pravi račun.'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}
