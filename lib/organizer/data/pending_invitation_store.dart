import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'local_vault_secure_storage.dart';
import '../domain/collaboration_models.dart';
import 'collaboration_transport.dart';

/// A pending capability is kept outside backups, URLs, and ordinary preferences.
/// Server identity is pinned before presenting/sending the capability. Account
/// identity is pinned before acceptance so a lost reply can safely be retried.
class PendingInvitation {
  const PendingInvitation({
    required this.serverUrl,
    required this.token,
    this.serverId,
    this.expiresAt,
    this.accountPartition,
    this.invitationId,
    this.autoOpen = true,
  });
  final String serverUrl, token;
  final String? serverId, accountPartition, invitationId;
  final DateTime? expiresAt;
  final bool autoOpen;
  PendingInvitation deferred() => PendingInvitation(
    serverUrl: serverUrl,
    token: token,
    serverId: serverId,
    expiresAt: expiresAt,
    accountPartition: accountPartition,
    invitationId: invitationId,
    autoOpen: false,
  );
  Map<String, Object?> toJson() => {
    'serverUrl': serverUrl,
    'token': token,
    'serverId': serverId,
    'expiresAt': expiresAt?.toUtc().millisecondsSinceEpoch,
    'accountPartition': accountPartition,
    'invitationId': invitationId,
    if (!autoOpen) 'autoOpen': false,
  };
  factory PendingInvitation.fromJson(Map<String, dynamic> json) {
    final token = json['token'] as String;
    if (!RegExp(r'^fhi[1234]_[a-f0-9]{64}$').hasMatch(token)) {
      throw const FormatException();
    }
    return PendingInvitation(
      serverUrl: normalizeCollaborationServer(json['serverUrl'] as String),
      token: token,
      serverId: json['serverId'] as String?,
      expiresAt: json['expiresAt'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              json['expiresAt'] as int,
              isUtc: true,
            ),
      accountPartition: json['accountPartition'] as String?,
      invitationId: json['invitationId'] as String?,
      autoOpen: json['autoOpen'] as bool? ?? true,
    );
  }
}

abstract interface class PendingInvitationStore {
  Future<PendingInvitation?> read();
  Future<void> write(PendingInvitation? invitation);
}

/// Navigation hints only: never membership or acceptance evidence. Bounded,
/// device-only fingerprints avoid retaining consumed capability secrets.
abstract interface class InvitationReplayStore {
  Future<List<String>> retiredLinks();
  Future<void> retireLink(String fingerprint);
}

Future<String> _linkFingerprint(String server, String token) async =>
    (await Sha256().hash(
      utf8.encode(jsonEncode([normalizeCollaborationServer(server), token])),
    )).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

PendingInvitation _preserveDeferral(
  PendingInvitation next,
  PendingInvitation? previous,
) =>
    previous?.autoOpen == false &&
        previous?.token == next.token &&
        normalizeCollaborationServer(previous!.serverUrl) ==
            normalizeCollaborationServer(next.serverUrl)
    ? next.deferred()
    : next;

// Native link receivers and repositories share this queue for the same backing
// record. A complete read/check/write stays atomic even across repository reloads.
// All secure-store instances address the same key and therefore share one queue.
final _pendingInvitationQueues = Expando<Future<void>>();
final _securePendingInvitationQueueIdentity = Object();

extension PendingInvitationStoreSerialization on PendingInvitationStore {
  Future<bool> mayAutoOpen(PendingInvitation invitation) async =>
      invitation.autoOpen &&
      !(this is InvitationReplayStore &&
          (await (this as InvitationReplayStore).retiredLinks()).contains(
            await _linkFingerprint(invitation.serverUrl, invitation.token),
          ));

  /// Persist a parsed native link inside the same atomic queue as account work.
  Future<bool> receiveLink({
    required String serverUrl,
    required String token,
    required bool Function() isCurrent,
    bool automatic = false,
  }) => serialized(() async {
    final base = normalizeCollaborationServer(serverUrl);
    final old = await read();
    if (!isCurrent()) return false;
    if (automatic) {
      if (old?.token == token &&
          old?.serverUrl == base &&
          old?.autoOpen == false) {
        return false;
      }
      if (this is InvitationReplayStore &&
          (await (this as InvitationReplayStore).retiredLinks()).contains(
            await _linkFingerprint(base, token),
          )) {
        return false;
      }
      if (!isCurrent()) return false;
    }
    if (old?.token == token && old?.serverUrl != base) {
      throw const CollaborationException('invitation_identity_mismatch');
    }
    if (old?.token != token || old?.serverUrl != base) {
      await write(PendingInvitation(serverUrl: base, token: token));
    }
    return isCurrent();
  });

  Future<void> deferLink({required String serverUrl, required String token}) =>
      serialized(() async {
        final previous = await read();
        if (previous?.token == token &&
            previous?.serverUrl == normalizeCollaborationServer(serverUrl)) {
          await write(previous!.deferred());
        }
      });

  Future<T> serialized<T>(Future<T> Function() action) {
    final identity = this is SecurePendingInvitationStore
        ? _securePendingInvitationQueueIdentity
        : this;
    final previous = _pendingInvitationQueues[identity] ?? Future<void>.value();
    final result = previous.then((_) => action());
    _pendingInvitationQueues[identity] = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return result;
  }
}

class SecurePendingInvitationStore
    implements PendingInvitationStore, InvitationReplayStore {
  const SecurePendingInvitationStore();
  static const _storage = localVaultSecureStorage;
  static const _key = 'jivie_pending_invitation_v1';
  static const _retiredKey = 'jivie_retired_invitation_links_v1';
  @override
  Future<List<String>> retiredLinks() async {
    try {
      final raw = await _storage.read(key: _retiredKey);
      if (raw == null) return [];
      final values = (jsonDecode(raw) as List).cast<String>();
      if (values.length > 32 ||
          values.any((v) => !RegExp(r'^[a-f0-9]{64}$').hasMatch(v))) {
        throw const FormatException();
      }
      return values;
    } catch (_) {
      throw const CollaborationException('secure_storage');
    }
  }

  @override
  Future<void> retireLink(String fingerprint) async {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(fingerprint)) {
      throw const CollaborationException('secure_storage');
    }
    try {
      final values = await retiredLinks();
      final next = [
        fingerprint,
        ...values.where((v) => v != fingerprint),
      ].take(32).toList();
      final encoded = jsonEncode(next);
      await _storage.write(key: _retiredKey, value: encoded);
      if (await _storage.read(key: _retiredKey) != encoded) {
        throw const FormatException();
      }
    } catch (_) {
      throw const CollaborationException('secure_storage');
    }
  }

  @override
  Future<PendingInvitation?> read() async {
    try {
      final value = await _storage.read(key: _key);
      return value == null
          ? null
          : PendingInvitation.fromJson(
              jsonDecode(value) as Map<String, dynamic>,
            );
    } catch (_) {
      throw const CollaborationException('secure_storage');
    }
  }

  @override
  Future<void> write(PendingInvitation? invitation) async {
    try {
      final previous = await read();
      if (invitation != null) {
        invitation = _preserveDeferral(invitation, previous);
      }
      // Record before clearing: a crash cannot revive a consumed startup link.
      // If this fails, retain the capability for explicit recovery.
      if (invitation == null && previous != null) {
        await retireLink(
          await _linkFingerprint(previous.serverUrl, previous.token),
        );
      }
      final value = invitation == null ? null : jsonEncode(invitation.toJson());
      if (value == null) {
        await _storage.delete(key: _key);
      } else {
        await _storage.write(key: _key, value: value);
      }
      if (await _storage.read(key: _key) != value) {
        throw const CollaborationException('secure_storage');
      }
    } catch (_) {
      throw const CollaborationException('secure_storage');
    }
  }
}

class MemoryPendingInvitationStore
    implements PendingInvitationStore, InvitationReplayStore {
  PendingInvitation? value;
  final _retired = <String>[];
  @override
  Future<List<String>> retiredLinks() async => List.of(_retired);
  @override
  Future<void> retireLink(String fingerprint) async {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(fingerprint)) {
      throw const CollaborationException('secure_storage');
    }
    _retired.remove(fingerprint);
    _retired.insert(0, fingerprint);
    if (_retired.length > 32) _retired.removeLast();
  }

  @override
  Future<PendingInvitation?> read() async => value;
  @override
  Future<void> write(PendingInvitation? invitation) async {
    if (invitation == null && value != null) {
      await retireLink(await _linkFingerprint(value!.serverUrl, value!.token));
    }
    value = invitation == null ? null : _preserveDeferral(invitation, value);
  }
}
