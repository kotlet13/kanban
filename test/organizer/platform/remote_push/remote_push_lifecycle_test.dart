import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'package:kanban/organizer/platform/remote_push/firebase_mobile_config.dart';
import 'package:kanban/organizer/platform/remote_push/remote_push_lifecycle.dart';
import 'package:kanban/organizer/platform/remote_push/remote_push_sdk.dart';
import '../../ui/sharing_ui_fixture.dart';

const config = FirebaseMobileConfig(
  apiKey: 'fixture',
  appId: 'fixture',
  projectId: 'fixture-project',
  senderId: '123456',
  applicationId: 'fixture',
  platform: 'ios',
);

class FakeSdk implements RemotePushSdk {
  @override
  bool supported = true;
  @override
  String platform = 'ios';
  final calls = <String>[];
  RemotePushPermission permission = RemotePushPermission.granted;
  bool apns = true, failDelete = false;
  String value = 'first-token';
  Completer<String?>? tokenGate;
  void Function(Map<String, Object?>)? foreground, opened;
  void Function(String)? rotated;
  Map<String, Object?>? initial;
  @override
  Future<Map<String, Object?>?> initialize(
    FirebaseMobileConfig config, {
    required void Function(Map<String, Object?>) onForeground,
    required void Function(Map<String, Object?>) onOpened,
    required void Function(String) onToken,
    required void Function() onError,
  }) async {
    calls.add('initialize');
    foreground = onForeground;
    opened = onOpened;
    rotated = onToken;
    final result = initial;
    initial = null;
    return result;
  }

  @override
  Future<RemotePushPermission> permissionStatus() async {
    calls.add('permission');
    return permission;
  }

  @override
  Future<RemotePushPermission> requestPermission() async {
    calls.add('prompt');
    return permission = RemotePushPermission.granted;
  }

  @override
  Future<bool> prepareApns() async {
    calls.add('apns');
    return apns;
  }

  @override
  Future<void> setAutoInit(bool enabled) async {
    calls.add('auto:$enabled');
  }

  @override
  Future<String?> token() async {
    calls.add('token');
    final gate = tokenGate;
    tokenGate = null;
    return gate == null ? value : gate.future;
  }

  @override
  Future<void> deleteToken() async {
    calls.add('delete');
    if (failDelete) throw StateError('offline');
    value = 'fresh-token';
  }

  @override
  Future<void> stopListening() async {
    calls.add('stop');
  }
}

RemotePushBinding binding({
  bool second = false,
  bool enabled = true,
  bool supported = true,
  String project = 'fixture-project',
  bool accountUsable = true,
  String? blockedReason,
}) {
  final session = sharingSession(second: second);
  return RemotePushBinding(
    identity: RemotePushIdentity.fromSession(session),
    session: session,
    optedIn: enabled,
    serverSupported: supported,
    serverProjectId: project,
    accountUsable: accountUsable,
    blockedReason: blockedReason,
    language: 'sl',
  );
}

class Harness {
  Harness(this.sdk, this.lifecycle);
  final FakeSdk sdk;
  final RemotePushLifecycle lifecycle;
  final registrations = <String>[];
  final disables = <String>[];
  final receives = <RemotePushReference>[];
  final opens = <RemotePushReference>[];
  bool failServerCleanup = false, failConfigure = false;
  RemotePushRegistrationStatus registrationStatus =
      RemotePushRegistrationStatus.registered;
  static Future<Harness> create({
    FirebaseMobileConfig? configuration = config,
  }) async {
    final sdk = FakeSdk();
    late Harness result;
    final lifecycle = RemotePushLifecycle(
      sdk: sdk,
      preferences: await SharedPreferences.getInstance(),
      config: configuration,
      onState: (_) {},
      configure: (identity, token, platform, language, projectId) async {
        if (result.failConfigure) {
          throw const CollaborationException('secure_storage');
        }
        result.registrations.add('${identity.deviceId}:$token:$projectId');
        return RemotePushRegistrationState(
          identity: identity,
          status: result.registrationStatus,
        );
      },
      disable: (identity) async {
        result.disables.add(identity.deviceId);
        if (result.failServerCleanup) throw StateError('offline');
        return const RemotePushRegistrationState();
      },
      receive: (reference) async {
        result.receives.add(reference);
        return true;
      },
      onOpened: (reference) => result.opens.add(reference),
    );
    result = Harness(sdk, lifecycle);
    return result;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'unconfigured, unsupported, signed out and disabled never initialize SDK',
    () async {
      final noConfig = await Harness.create(configuration: null);
      await noConfig.lifecycle.update(binding());
      expect(noConfig.sdk.calls, isEmpty);
      expect(
        noConfig.lifecycle.state.phase,
        RemotePushDevicePhase.unconfigured,
      );
      final h = await Harness.create();
      await h.lifecycle.update(null);
      await h.lifecycle.update(binding(enabled: false));
      expect(h.sdk.calls, isEmpty);
      h.sdk.supported = false;
      await h.lifecycle.update(binding());
      expect(h.sdk.calls, isEmpty);
    },
  );
  test(
    'cold persisted ownership is initialized and deleted even with server unavailable or project mismatch',
    () async {
      for (final mismatch in [false, true]) {
        SharedPreferences.setMockInitialValues({
          'organizer_remote_push_sdk_identity_v1': binding().key,
        });
        final h = await Harness.create();
        await h.lifecycle.update(
          binding(
            supported: mismatch,
            project: mismatch ? 'another-project' : 'fixture-project',
          ),
        );
        expect(
          h.sdk.calls,
          containsAllInOrder(['initialize', 'stop', 'auto:false', 'delete']),
        );
        expect(h.sdk.calls, isNot(contains('token')));
        expect(h.registrations, isEmpty);
      }
    },
  );
  test(
    'project mismatch rejected before token or Firebase initialization',
    () async {
      final h = await Harness.create();
      await h.lifecycle.update(binding(project: 'another-project'));
      expect(h.sdk.calls, isEmpty);
      expect(h.registrations, isEmpty);
      expect(h.lifecycle.state.errorCode, 'push_project_mismatch');
    },
  );
  test(
    'no startup permission prompt; explicit opt in may request permission',
    () async {
      final h = await Harness.create();
      h.sdk.permission = RemotePushPermission.unknown;
      await h.lifecycle.update(binding());
      expect(h.sdk.calls, isNot(contains('prompt')));
      expect(h.registrations, isEmpty);
      await h.lifecycle.update(binding(), force: true, requestPermission: true);
      expect(h.sdk.calls, contains('prompt'));
    },
  );
  test('APNs readiness precedes auto-init and token retrieval', () async {
    final h = await Harness.create();
    h.sdk.apns = false;
    await h.lifecycle.update(binding());
    expect(h.sdk.calls, isNot(contains('auto:true')));
    expect(h.sdk.calls, isNot(contains('token')));
    expect(h.lifecycle.state.phase, RemotePushDevicePhase.waitingApns);
    h.sdk.apns = true;
    await h.lifecycle.update(binding(), force: true);
    expect(
      h.sdk.calls.indexOf('apns'),
      lessThan(h.sdk.calls.indexOf('auto:true')),
    );
    expect(h.lifecycle.state.ready, isTrue);
  });
  test('rotation registers refreshed token under captured identity', () async {
    final h = await Harness.create();
    await h.lifecycle.update(binding());
    h.sdk.rotated!('rotated-token');
    await h.lifecycle.update(binding());
    expect(
      h.registrations.last,
      contains('${binding().identity.deviceId}:rotated-token'),
    );
  });
  test(
    'account switch during token await discards A and deletes before obtaining B token',
    () async {
      final h = await Harness.create(), gate = Completer<String?>();
      h.sdk.tokenGate = gate;
      final a = h.lifecycle.update(binding());
      while (!h.sdk.calls.contains('token')) {
        await Future<void>.delayed(Duration.zero);
      }
      final b = h.lifecycle.update(binding(second: true));
      gate.complete('late-A-token');
      await a;
      await b;
      expect(h.registrations, hasLength(1));
      expect(
        h.registrations.single,
        contains('${binding(second: true).identity.deviceId}:fresh-token'),
      );
      expect(
        h.sdk.calls.lastIndexOf('delete'),
        lessThan(h.sdk.calls.lastIndexOf('token')),
      );
    },
  );
  test(
    'failed SDK cleanup blocks B registration until successful retry',
    () async {
      final h = await Harness.create();
      await h.lifecycle.update(binding());
      h.sdk.failDelete = true;
      await h.lifecycle.update(binding(second: true));
      expect(h.registrations, hasLength(1));
      expect(h.lifecycle.state.phase, RemotePushDevicePhase.cleanupRequired);
      h.sdk.failDelete = false;
      await h.lifecycle.update(binding(second: true), force: true);
      expect(h.registrations, hasLength(2));
    },
  );
  test(
    'opt-out deletes token and stops renewal even when server cleanup is offline',
    () async {
      final h = await Harness.create();
      await h.lifecycle.update(binding());
      h.failServerCleanup = true;
      await h.lifecycle.update(binding(enabled: false));
      expect(h.sdk.calls, contains('auto:false'));
      expect(h.sdk.calls, contains('delete'));
      expect(h.lifecycle.state.phase, RemotePushDevicePhase.disabled);
      expect(h.disables, hasLength(1));
    },
  );
  test('permission revocation cleans existing registration', () async {
    final h = await Harness.create();
    await h.lifecycle.update(binding());
    h.sdk.permission = RemotePushPermission.denied;
    await h.lifecycle.update(binding(), force: true);
    expect(h.sdk.calls, contains('delete'));
    expect(h.disables, isNotEmpty);
    expect(h.lifecycle.state.phase, RemotePushDevicePhase.denied);
  });
  test(
    'known auth rejection or expiry disables renewal and deletes prior token',
    () async {
      final h = await Harness.create();
      await h.lifecycle.update(binding());
      await h.lifecycle.update(binding(accountUsable: false));
      expect(h.sdk.calls, contains('auto:false'));
      expect(h.sdk.calls, contains('delete'));
      expect(h.lifecycle.state.phase, RemotePushDevicePhase.needsAccount);
      h.lifecycle.applyRegistration(
        const RemotePushRegistrationState(
          status: RemotePushRegistrationStatus.registered,
        ),
      );
      expect(h.lifecycle.state.ready, isFalse);
      final b = binding();
      final expiredSession = AccountSession.fromJson({
        ...b.session.toJson(),
        'expiresAt': DateTime.utc(2000).toIso8601String(),
      });
      final expired = await Harness.create();
      await expired.lifecycle.update(
        RemotePushBinding(
          identity: b.identity,
          session: expiredSession,
          optedIn: true,
          serverSupported: true,
          serverProjectId: 'fixture-project',
          language: 'sl',
        ),
      );
      expect(expired.sdk.calls, isEmpty);
      expect(expired.lifecycle.state.phase, RemotePushDevicePhase.needsAccount);
    },
  );
  test(
    'rotated token secure write failure suppresses stale ACK but later rotation can recover',
    () async {
      final h = await Harness.create();
      await h.lifecycle.update(binding());
      h.failConfigure = true;
      h.sdk.rotated!('uncommitted-token');
      await h.lifecycle.update(binding());
      expect(h.lifecycle.state.phase, RemotePushDevicePhase.error);
      h.lifecycle.applyRegistration(
        const RemotePushRegistrationState(
          status: RemotePushRegistrationStatus.registered,
        ),
      );
      expect(h.lifecycle.state.phase, RemotePushDevicePhase.error);
      expect(h.lifecycle.state.ready, isFalse);
      h.failConfigure = false;
      h.sdk.rotated!('newer-token');
      await h.lifecycle.update(binding());
      expect(h.lifecycle.state.ready, isTrue);
      expect(h.registrations.last, contains('newer-token'));
    },
  );
  test(
    'background lost registration cleans SDK without resetting core block; explicit retry obtains fresh token',
    () async {
      final h = await Harness.create();
      await h.lifecycle.update(binding());
      await h.lifecycle.update(
        binding(blockedReason: 'push_registration_lost'),
      );
      expect(h.sdk.calls, contains('delete'));
      expect(h.disables, isEmpty);
      expect(h.lifecycle.state.ready, isFalse);
      expect(h.registrations, hasLength(1));
      await h.lifecycle.update(
        binding(blockedReason: 'push_registration_lost'),
      );
      expect(h.registrations, hasLength(1));
      await h.lifecycle.update(
        binding(blockedReason: 'push_registration_lost'),
        force: true,
        requestPermission: true,
      );
      expect(h.registrations, hasLength(2));
      expect(h.registrations.last, contains('fresh-token'));
      expect(h.lifecycle.state.ready, isTrue);
    },
  );
  test(
    'foreground only refreshes matching inbox; cold and opened references queue',
    () async {
      final h = await Harness.create();
      final s = sharingSession();
      final r = RemotePushReference(
        serverId: s.serverId,
        accountId: s.accountId,
        notificationId: 12,
      );
      h.sdk.initial = r.toData();
      await h.lifecycle.update(binding());
      expect(h.opens, hasLength(1));
      h.sdk.foreground!(r.toData());
      await Future<void>.delayed(Duration.zero);
      expect(h.receives, hasLength(1));
      expect(h.opens, hasLength(1));
      h.sdk.foreground!({
        ...r.toData(),
        'accountId': sharingSession(second: true).accountId,
      });
      expect(h.receives, hasLength(1));
      h.sdk.opened!({...r.toData(), 'url': 'https://evil.test'});
      expect(h.opens, hasLength(1));
      h.sdk.opened!(r.toData());
      expect(h.opens, hasLength(2));
    },
  );
  test(
    'offline core registration does not claim registered and poll cannot override denial',
    () async {
      final h = await Harness.create();
      h.registrationStatus = RemotePushRegistrationStatus.pendingRegistration;
      await h.lifecycle.update(binding());
      expect(h.lifecycle.state.phase, RemotePushDevicePhase.offline);
      h.sdk.permission = RemotePushPermission.denied;
      await h.lifecycle.update(binding(), force: true);
      h.lifecycle.applyRegistration(
        const RemotePushRegistrationState(
          status: RemotePushRegistrationStatus.registered,
        ),
      );
      expect(h.lifecycle.state.phase, RemotePushDevicePhase.denied);
    },
  );
}
