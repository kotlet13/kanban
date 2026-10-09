import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../domain/collaboration_models.dart';

/// A receipt only proves the outcome of one request; no password or OTP is kept.
class PendingAccountDeletion {
  const PendingAccountDeletion({
    required this.profile,
    required this.operationId,
    required this.previewHash,
    required this.receiptToken,
    this.ownershipTransfers = const [],
    this.resolutions = const [],
    this.ownedScopeDeletions = const [],
    this.serverAccepted = false,
    this.review = const {},
    this.policyVersion = 1,
  });
  final AccountSession profile;
  final String operationId, previewHash, receiptToken;
  final List<Map<String, Object?>> ownershipTransfers, resolutions;
  final List<String> ownedScopeDeletions;
  final bool serverAccepted;
  final Map<String, dynamic> review;
  final int policyVersion;
  Map<String, Object?> toJson() => {
    'profile': profile.toJson(),
    'operationId': operationId,
    'previewHash': previewHash,
    'receiptToken': receiptToken,
    'ownershipTransfers': ownershipTransfers,
    'resolutions': resolutions,
    'ownedScopeDeletions': ownedScopeDeletions,
    'serverAccepted': serverAccepted,
    'review': review,
    'policyVersion': policyVersion,
  };
  factory PendingAccountDeletion.fromJson(Map<String, dynamic> j) =>
      PendingAccountDeletion(
        profile: AccountSession.fromJson(j['profile'] as Map<String, dynamic>),
        operationId: j['operationId'] as String,
        previewHash: j['previewHash'] as String,
        receiptToken: j['receiptToken'] as String,
        ownershipTransfers: (j['ownershipTransfers'] as List? ?? [])
            .map((r) => Map<String, Object?>.from(r as Map))
            .toList(),
        resolutions: (j['resolutions'] as List? ?? [])
            .map((r) => Map<String, Object?>.from(r as Map))
            .toList(),
        ownedScopeDeletions: (j['ownedScopeDeletions'] as List? ?? [])
            .cast<String>(),
        serverAccepted: j['serverAccepted'] == true,
        review: Map<String, dynamic>.from(j['review'] as Map? ?? {}),
        policyVersion:
            j['policyVersion'] as int? ??
            (j['review'] as Map?)?['policyVersion'] as int? ??
            1,
      );
}

abstract interface class AccountDeletionStore {
  Future<List<PendingAccountDeletion>> read();
  Future<void> write(List<PendingAccountDeletion> requests);
}

class SecureAccountDeletionStore implements AccountDeletionStore {
  const SecureAccountDeletionStore();
  static const _storage = FlutterSecureStorage();
  static const _key = 'jivie_account_deletion_receipts_v1';
  @override
  Future<List<PendingAccountDeletion>> read() async {
    try {
      final v = await _storage.read(key: _key);
      return v == null
          ? []
          : (jsonDecode(v) as List)
                .map(
                  (j) => PendingAccountDeletion.fromJson(
                    j as Map<String, dynamic>,
                  ),
                )
                .toList();
    } catch (_) {
      throw const CollaborationException('secure_storage');
    }
  }

  @override
  Future<void> write(List<PendingAccountDeletion> requests) async {
    try {
      final v = jsonEncode(requests.map((r) => r.toJson()).toList());
      await _storage.write(key: _key, value: v);
      if (await _storage.read(key: _key) != v) throw const FormatException();
    } catch (_) {
      throw const CollaborationException('secure_storage');
    }
  }
}

class MemoryAccountDeletionStore implements AccountDeletionStore {
  List<PendingAccountDeletion> requests = [];
  @override
  Future<List<PendingAccountDeletion>> read() async => List.of(requests);
  @override
  Future<void> write(List<PendingAccountDeletion> values) async =>
      requests = List.of(values);
}
