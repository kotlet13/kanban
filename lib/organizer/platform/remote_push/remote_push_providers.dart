import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../state/collaboration_provider.dart';
import 'firebase_mobile_config.dart';
import 'firebase_push_sdk.dart';
import 'remote_push_lifecycle.dart';
import 'remote_push_sdk.dart';

final remotePushSdkProvider = Provider<RemotePushSdk>(
  (ref) => FirebasePushSdk(),
);
final remotePushConfigurationProvider = Provider<FirebaseMobileConfig?>((ref) {
  final sdk = ref.watch(remotePushSdkProvider);
  try {
    return sdk.supported
        ? FirebaseMobileConfig.fromDefines(sdk.platform)
        : null;
  } on FormatException {
    return null;
  }
});
final remotePushConfigurationInvalidProvider = Provider<bool>((ref) {
  final sdk = ref.watch(remotePushSdkProvider);
  try {
    if (sdk.supported) FirebaseMobileConfig.fromDefines(sdk.platform);
    return false;
  } on FormatException {
    return true;
  }
});
final remotePushDeviceStateProvider = StateProvider<RemotePushDeviceState>(
  (ref) => const RemotePushDeviceState(RemotePushDevicePhase.disabled),
);
bool remotePushAccountUsable(CollaborationState? state) {
  if (state?.session == null ||
      state!.sessionInvalid ||
      !state.session!.expiresAt.isAfter(DateTime.now())) {
    return false;
  }
  const terminal = {
    'auth_required',
    'device_revoked',
    'session_expired',
    'invalid_credentials',
  };
  final error = state.lastError;
  return !(error is CollaborationException && terminal.contains(error.code)) &&
      !terminal.contains(state.remotePushRegistration.errorCode);
}

final remotePushDeviceReadyProvider = Provider<bool>((ref) {
  final device = ref.watch(remotePushDeviceStateProvider);
  final session = ref.watch(collaborationProvider).valueOrNull?.session;
  return session != null &&
      remotePushAccountUsable(ref.watch(collaborationProvider).valueOrNull) &&
      device.ready &&
      device.bindingKey == pushDeviceKey(session);
});
final remotePushLaunchReferenceProvider = StateProvider<RemotePushReference?>(
  (ref) => null,
);
final remotePushPermissionRequestProvider = StateProvider<int>((ref) => 0);

String pushDeviceKey(AccountSession session) =>
    '${session.partition}:${session.deviceId}';
final remotePushOptInProvider =
    AsyncNotifierProvider<RemotePushOptInController, Map<String, bool>>(
      RemotePushOptInController.new,
    );

class RemotePushOptInController extends AsyncNotifier<Map<String, bool>> {
  static const _key = 'organizer_remote_push_device_opt_in_v1';
  @override
  Future<Map<String, bool>> build() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return {};
    final data = jsonDecode(raw) as Map<String, dynamic>;
    return data.map((key, value) => MapEntry(key, value == true));
  }

  Future<void> save(AccountSession session, bool enabled) async {
    final existing = await future;
    final next = {...existing, pushDeviceKey(session): enabled};
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(_key, jsonEncode(next))) {
      throw StateError('Remote push preferences could not be saved');
    }
    state = AsyncData(Map.unmodifiable(next));
  }
}

final remotePushLifecycleProvider = FutureProvider<RemotePushLifecycle>((
  ref,
) async {
  var alive = true;
  RemotePushLifecycle? lifecycle;
  ref.onDispose(() {
    alive = false;
    lifecycle?.dispose();
  });
  final preferences = await SharedPreferences.getInstance();
  lifecycle = RemotePushLifecycle(
    sdk: ref.read(remotePushSdkProvider),
    preferences: preferences,
    config: ref.read(remotePushConfigurationProvider),
    onState: (state) {
      if (alive) ref.read(remotePushDeviceStateProvider.notifier).state = state;
    },
    configure: (identity, token, platform, language, projectId) => ref
        .read(collaborationProvider.notifier)
        .configureRemotePush(
          identity: identity,
          token: token,
          platform: platform,
          language: language,
          projectId: projectId,
        ),
    disable: (identity) => ref
        .read(collaborationProvider.notifier)
        .disableRemotePush(identity: identity),
    receive: (reference) => ref
        .read(collaborationProvider.notifier)
        .receiveRemotePushReference(reference),
    onOpened: (reference) {
      if (alive) {
        ref.read(remotePushLaunchReferenceProvider.notifier).state = reference;
      }
    },
  );
  if (!alive) lifecycle.dispose();
  return lifecycle;
});
