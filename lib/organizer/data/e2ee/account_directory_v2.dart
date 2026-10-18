import 'dart:convert';
import 'dart:typed_data';
import 'dart:collection';

import 'package:cryptography/cryptography.dart' show Sha256;
import 'package:sodium/sodium.dart' show SecureKey;

import 'crypto_codec.dart';
import 'crypto_json.dart';

const cryptoDirectoryDomain = 'JivieE2EE/v2\n';
const cryptoDirectoryLogDomain = 'JivieAccountLog/v2\n';
const cryptoZeroHash =
    '0000000000000000000000000000000000000000000000000000000000000000';

Future<String> cryptoSha256(List<int> bytes) async => (await Sha256().hash(
  bytes,
)).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

class CryptoDirectoryException implements Exception {
  const CryptoDirectoryException(this.code);
  final String code;
  @override
  String toString() => 'CryptoDirectoryException($code)';
}

/// An immutable, completely replayed account directory, not a server assertion
/// that an omitted device or revocation never existed.
class _DirectoryLineage {
  const _DirectoryLineage(
    this.generation,
    this.hash,
    this.operation,
    this.previous,
  );
  final int generation;
  final String hash;
  final String operation;
  final _DirectoryLineage? previous;
}

class VerifiedAccountDirectory {
  const VerifiedAccountDirectory._({
    required this.snapshot,
    required this.generation,
    required this.headHash,
    required this.snapshotHash,
    required this.deviceSnapshotHash,
    required this.rootFingerprint,
    required _DirectoryLineage lineage,
  }) : _lineage = lineage;
  final Map<String, dynamic> snapshot;
  final int generation;
  final String headHash, snapshotHash, deviceSnapshotHash, rootFingerprint;
  final _DirectoryLineage _lineage;
  bool includesAnchor(int generation, String hash) {
    if (generation == 0) return hash == cryptoZeroHash;
    _DirectoryLineage? cursor = _lineage;
    while (cursor != null && cursor.generation > generation) {
      cursor = cursor.previous;
    }
    return cursor?.generation == generation && cursor?.hash == hash;
  }

  Iterable<({int generation, String headHash})> get verifiedHeaders sync* {
    _DirectoryLineage? cursor = _lineage;
    while (cursor != null) {
      yield (generation: cursor.generation, headHash: cursor.hash);
      cursor = cursor.previous;
    }
  }

  /// Derived only while the reducer verifies every signed command. SQL event
  /// indexes may accelerate discovery but cannot prove an operation absent.
  Iterable<({int generation, String headHash})> verifiedHeadersFor(
    String operation,
  ) sync* {
    _DirectoryLineage? cursor = _lineage;
    while (cursor != null) {
      if (cursor.operation == operation) {
        yield (generation: cursor.generation, headHash: cursor.hash);
      }
      cursor = cursor.previous;
    }
  }

  String get serverId => snapshot['serverId'] as String;
  String get accountId => snapshot['accountId'] as String;
  String get identityEpochId => snapshot['identityEpochId'] as String;
  List<Map<String, dynamic>> get devices =>
      (snapshot['devices'] as List).cast<Map<String, dynamic>>();
  List<Map<String, dynamic>> get keyringEntries =>
      (snapshot['keyringEntries'] as List).cast<Map<String, dynamic>>();
  Map<String, dynamic> activeDevice(String id) {
    final matches = devices.where(
      (device) =>
          device['deviceId'] == id &&
          device['revokedGeneration'] == null &&
          device['identityEpochId'] == identityEpochId,
    );
    if (matches.length != 1) {
      throw const CryptoDirectoryException('directory_device_revoked');
    }
    return matches.single;
  }
}

class PreparedDirectoryMutation {
  const PreparedDirectoryMutation(this.authorization, this.entry, this.result);
  final Map<String, dynamic> authorization, entry;
  final VerifiedAccountDirectory result;
}

/// Deterministic reducer shared by the client and PHP. Authority is evaluated
/// against the preceding verified state; SQL ACL and returned booleans are not
/// cryptographic authorization. A fresh recovery still cannot prove freshness
/// of a server-selected historical prefix without a peer or a new recovery epoch.
class AccountDirectoryV2 {
  AccountDirectoryV2(this.crypto);
  final CryptoCodec crypto;

  Future<PreparedDirectoryMutation> prepare({
    required VerifiedAccountDirectory? previous,
    required String serverId,
    required String accountId,
    required String deviceId,
    required String identityEpochId,
    required String operation,
    required String signer,
    required Map<String, dynamic> payload,
    required String pinnedRootFingerprint,
    required SecureKey signingKey,
    String? requestId,
    SecureKey? incomingRootSigningKey,
    SecureKey? newDeviceSigningKey,
  }) async {
    if (payload.keys.any(
      const {
        'expectedGeneration',
        'previousHeadHash',
        'identityEpochId',
        'resultingSnapshotHash',
      }.contains,
    )) {
      throw const CryptoDirectoryException('directory_reserved_field');
    }
    final command = <String, dynamic>{
      'version': 2,
      'operation': operation,
      'requestId': requestId ?? crypto.randomId(),
      'serverId': serverId,
      'accountId': accountId,
      'deviceId': deviceId,
      'signer': signer,
      'payload': <String, dynamic>{
        ...payload,
        if (operation == 'crypto2.account.rotateRoot')
          'incomingRootProof': <String, dynamic>{},
        if (operation == 'crypto2.device.rebind')
          'newDeviceProof': <String, dynamic>{},
        'expectedGeneration': previous?.generation ?? 0,
        'previousHeadHash': previous?.headHash ?? cryptoZeroHash,
        'identityEpochId': previous?.identityEpochId ?? identityEpochId,
        'resultingSnapshotHash': cryptoZeroHash,
      },
    };
    final projected = await project(previous: previous, command: command);
    (command['payload'] as Map)['resultingSnapshotHash'] = await cryptoSha256(
      CryptoJson.encodeDerivedState(projected),
    );
    if (operation == 'crypto2.account.rotateRoot') {
      if (previous == null || incomingRootSigningKey == null) {
        throw const CryptoDirectoryException(
          'directory_incoming_root_required',
        );
      }
      (command['payload'] as Map)['incomingRootProof'] = crypto.signDomain(
        await rootTransitionBody(previous, command),
        incomingRootSigningKey,
        'JivieE2EE/rootTransition/v2\n',
      );
    }
    if (operation == 'crypto2.device.rebind') {
      if (newDeviceSigningKey == null) {
        throw const CryptoDirectoryException('directory_new_device_proof');
      }
      (command['payload'] as Map)['newDeviceProof'] = crypto.signDomain(
        rebindBody(command),
        newDeviceSigningKey,
        'JivieE2EE/deviceRebind/v2\n',
      );
    }
    final signed = crypto.signDomain(
      command,
      signingKey,
      cryptoDirectoryDomain,
    );
    final commandHash = await cryptoSha256(
      cryptoBase64(signed['commandBase64']),
    );
    final generation = (previous?.generation ?? 0) + 1;
    final previousHead = previous?.headHash ?? cryptoZeroHash;
    final hash = await cryptoSha256(
      utf8.encode(cryptoDirectoryLogDomain) +
          CryptoJson.encode({
            'serverId': serverId,
            'accountId': accountId,
            'generation': generation,
            'previousHeadHash': previousHead,
            'commandHash': commandHash,
            'signatureBase64': signed['signatureBase64'],
          }),
    );
    final entry = <String, dynamic>{
      'generation': generation,
      'headHash': hash,
      'previousHeadHash': previousHead,
      'commandHash': commandHash,
      'authorization': signed,
    };
    final result = await apply(
      previous: previous,
      entry: entry,
      serverId: serverId,
      accountId: accountId,
      pinnedRootFingerprint: pinnedRootFingerprint,
    );
    return PreparedDirectoryMutation(signed, entry, result);
  }

  Future<VerifiedAccountDirectory> apply({
    required VerifiedAccountDirectory? previous,
    required Map<String, dynamic> entry,
    required String serverId,
    required String accountId,
    required String pinnedRootFingerprint,
  }) async {
    final signed = entry['authorization'] as Map<String, dynamic>;
    final commandBytes = cryptoBase64(signed['commandBase64']);
    final command = CryptoJson.decode(commandBytes) as Map<String, dynamic>;
    _fields(command, {
      'version',
      'operation',
      'requestId',
      'serverId',
      'accountId',
      'deviceId',
      'signer',
      'payload',
    });
    _uuid(command['requestId']);
    _uuid(command['deviceId']);
    if (command['version'] != 2 ||
        command['serverId'] != serverId ||
        command['accountId'] != accountId ||
        (previous != null &&
            (previous.serverId != serverId ||
                previous.accountId != accountId))) {
      throw const CryptoDirectoryException('directory_identity');
    }
    final payload = command['payload'] as Map<String, dynamic>;
    final expected = previous?.generation ?? 0;
    final previousHead = previous?.headHash ?? cryptoZeroHash;
    if (payload['expectedGeneration'] != expected ||
        payload['previousHeadHash'] != previousHead ||
        entry['generation'] != expected + 1 ||
        entry['previousHeadHash'] != previousHead) {
      throw const CryptoDirectoryException('directory_chain_gap');
    }
    Uint8List publicKey;
    if (previous == null) {
      if (command['operation'] != 'crypto2.account.initialize' ||
          command['signer'] != 'root') {
        throw const CryptoDirectoryException('directory_genesis');
      }
      publicKey = cryptoBase64(payload['rootSigningKeyBase64'], length: 32);
      final encryption = cryptoBase64(
        payload['rootEncryptionKeyBase64'],
        length: 32,
      );
      if (crypto.fingerprint(publicKey, encryption) != pinnedRootFingerprint) {
        throw const CryptoDirectoryException('directory_root_changed');
      }
    } else if (command['signer'] == 'root') {
      if (!const {
        'crypto2.account.recoveryStart',
        'crypto2.account.recoverEpoch',
        'crypto2.account.rotateRoot',
        'crypto2.device.add',
        'crypto2.device.revoke',
      }.contains(command['operation'])) {
        throw const CryptoDirectoryException('directory_root_operation');
      }
      publicKey = cryptoBase64(
        previous.snapshot['rootSigningKeyBase64'],
        length: 32,
      );
    } else if (command['signer'] == 'device') {
      final device = previous.activeDevice(
        (command['operation'] == 'crypto2.device.rebind'
                ? payload['approvingDeviceId']
                : command['deviceId'])
            as String,
      );
      final operation = command['operation'];
      if (!const {
            'crypto2.account.keyringEntriesPut',
            'crypto2.device.add',
            'crypto2.device.revoke',
            'crypto2.device.rebind',
            'crypto2.account.protectionReady',
            'crypto2.account.scheduleUse',
            'crypto2.account.scopeDeletion',
            'crypto2.account.projectRelocation',
            'crypto2.account.migrationAttest',
            'crypto2.account.scopeObserve',
          }.contains(operation) ||
          ([
                'crypto2.account.keyringEntriesPut',
                'crypto2.account.migrationAttest',
                'crypto2.account.scopeObserve',
                'crypto2.account.scopeDeletion',
                'crypto2.account.projectRelocation',
              ].contains(operation) &&
              device['keyringWrite'] != true) ||
          (operation != 'crypto2.account.keyringEntriesPut' &&
              operation != 'crypto2.account.protectionReady' &&
              operation != 'crypto2.account.migrationAttest' &&
              operation != 'crypto2.account.scopeObserve' &&
              operation != 'crypto2.account.scheduleUse' &&
              operation != 'crypto2.account.scopeDeletion' &&
              operation != 'crypto2.account.projectRelocation' &&
              device['manageDevices'] != true)) {
        throw const CryptoDirectoryException('directory_device_operation');
      }
      publicKey = cryptoBase64(device['signingKeyBase64'], length: 32);
    } else {
      throw const CryptoDirectoryException('directory_signer');
    }
    crypto.verifyDomain(signed, publicKey, cryptoDirectoryDomain);
    final snapshot = await project(previous: previous, command: command);
    final snapshotHash = await cryptoSha256(
      CryptoJson.encodeDerivedState(snapshot),
    );
    if (command['operation'] == 'crypto2.account.rotateRoot') {
      final incoming = crypto.verifyDomain(
        Map<String, dynamic>.from(payload['incomingRootProof'] as Map),
        cryptoBase64(payload['newRootSigningKeyBase64'], length: 32),
        'JivieE2EE/rootTransition/v2\n',
      );
      if (base64Encode(CryptoJson.encode(incoming)) !=
          base64Encode(
            CryptoJson.encode(await rootTransitionBody(previous!, command)),
          )) {
        throw const CryptoDirectoryException('directory_root_transition');
      }
    }
    if (command['operation'] == 'crypto2.device.rebind') {
      final body = crypto.verifyDomain(
        Map<String, dynamic>.from(payload['newDeviceProof'] as Map),
        cryptoBase64(payload['signingKeyBase64'], length: 32),
        'JivieE2EE/deviceRebind/v2\n',
      );
      if (base64Encode(CryptoJson.encode(body)) !=
          base64Encode(CryptoJson.encode(rebindBody(command)))) {
        throw const CryptoDirectoryException('directory_new_device_proof');
      }
    }
    if (payload['resultingSnapshotHash'] != snapshotHash) {
      throw const CryptoDirectoryException('directory_snapshot_mismatch');
    }
    final commandHash = await cryptoSha256(commandBytes);
    final headHash = await cryptoSha256(
      utf8.encode(cryptoDirectoryLogDomain) +
          CryptoJson.encode({
            'serverId': serverId,
            'accountId': accountId,
            'generation': expected + 1,
            'previousHeadHash': previousHead,
            'commandHash': commandHash,
            'signatureBase64': signed['signatureBase64'],
          }),
    );
    if (entry['commandHash'] != commandHash || entry['headHash'] != headHash) {
      throw const CryptoDirectoryException('directory_head_mismatch');
    }
    return VerifiedAccountDirectory._(
      rootFingerprint: crypto.fingerprint(
        cryptoBase64(snapshot['rootSigningKeyBase64'], length: 32),
        cryptoBase64(snapshot['rootEncryptionKeyBase64'], length: 32),
      ),
      lineage: _DirectoryLineage(
        expected + 1,
        headHash,
        command['operation'],
        previous?._lineage,
      ),
      snapshot: _freezeMap(snapshot),
      generation: expected + 1,
      headHash: headHash,
      snapshotHash: snapshotHash,
      deviceSnapshotHash: await cryptoSha256(
        CryptoJson.encodeDerivedState(deviceSnapshot(snapshot)),
      ),
    );
  }

  Map<String, dynamic> rebindBody(Map command) {
    final p = command['payload'] as Map;
    return {
      'version': 2,
      'serverId': command['serverId'],
      'accountId': command['accountId'],
      'requestId': command['requestId'],
      'approvingDeviceId': p['approvingDeviceId'],
      'newDeviceId': command['deviceId'],
      for (final k in [
        'expectedGeneration',
        'previousHeadHash',
        'identityEpochId',
        'signingKeyBase64',
        'encryptionKeyBase64',
        'keyringWrite',
        'manageDevices',
        'retireApprovingDevice',
        'resultingSnapshotHash',
      ])
        k: p[k],
    };
  }

  Object? _clone(Object? value) => value is Map<String, dynamic>
      ? value.map((key, item) => MapEntry(key, _clone(item)))
      : value is List
      ? value.map(_clone).toList()
      : value;

  Map<String, dynamic> _freezeMap(Map<String, dynamic> input) =>
      UnmodifiableMapView(
        input.map((key, value) => MapEntry(key, _freeze(value))),
      );
  Object? _freeze(Object? value) => value is Map<String, dynamic>
      ? _freezeMap(value)
      : value is List
      ? List<Object?>.unmodifiable(value.map(_freeze))
      : value;

  /// Computes the exact next snapshot before the command is signed. It does not
  /// grant authority: apply() separately checks signatures and preceding rights.
  Future<Map<String, dynamic>> project({
    required VerifiedAccountDirectory? previous,
    required Map<String, dynamic> command,
  }) async {
    final payload = command['payload'] as Map<String, dynamic>;
    final operation = command['operation'];
    final generation = (previous?.generation ?? 0) + 1;
    final common = {
      'expectedGeneration',
      'previousHeadHash',
      'identityEpochId',
      'resultingSnapshotHash',
    };
    _uuid(payload['identityEpochId']);
    if (previous != null &&
        payload['identityEpochId'] != previous.identityEpochId) {
      throw const CryptoDirectoryException('directory_old_identity_epoch');
    }
    if (previous == null) {
      _fields(payload, {
        ...common,
        'rootSigningKeyBase64',
        'rootEncryptionKeyBase64',
        'deviceSigningKeyBase64',
        'deviceEncryptionKeyBase64',
        'keyringCiphertextBase64',
      });
      if (operation != 'crypto2.account.initialize' ||
          payload['expectedGeneration'] != 0 ||
          payload['previousHeadHash'] != cryptoZeroHash) {
        throw const CryptoDirectoryException('directory_genesis');
      }
      for (final name in [
        'rootSigningKeyBase64',
        'rootEncryptionKeyBase64',
        'deviceSigningKeyBase64',
        'deviceEncryptionKeyBase64',
      ]) {
        cryptoBase64(payload[name], length: 32);
      }
      if (command['deviceId'] == payload['identityEpochId']) {
        throw const CryptoDirectoryException('directory_recipient_collision');
      }
      return {
        'version': 2,
        'serverId': command['serverId'],
        'accountId': command['accountId'],
        'rootSigningKeyBase64': payload['rootSigningKeyBase64'],
        'rootEncryptionKeyBase64': payload['rootEncryptionKeyBase64'],
        'recoveryRootCiphertextHash': await cryptoSha256(
          cryptoBase64(payload['keyringCiphertextBase64'], max: 256 * 1024),
        ),
        'identityEpochId': payload['identityEpochId'],
        'recoveryRootEpochId': payload['identityEpochId'],
        'devices': [
          _device(
            command['deviceId'] as String,
            payload['deviceSigningKeyBase64'],
            payload['deviceEncryptionKeyBase64'],
            true,
            true,
            generation,
            payload['identityEpochId'] as String,
          ),
        ],
        'keyringEntries': <dynamic>[],
      };
    }
    final snapshot = _clone(previous.snapshot) as Map<String, dynamic>;
    final devices = (snapshot['devices'] as List).cast<Map<String, dynamic>>();
    final entries = (snapshot['keyringEntries'] as List)
        .cast<Map<String, dynamic>>();
    switch (operation) {
      case 'crypto2.account.recoveryStart':
        _fields(payload, common);
      case 'crypto2.account.migrationAttest':
        _fields(payload, {
          ...common,
          'migrationId',
          'scopeToken',
          'domain',
          'attestationHash',
        });
        _uuid(payload['migrationId']);
        if (!['content', 'finance'].contains(payload['domain']) ||
            [payload['scopeToken'], payload['attestationHash']].any(
              (v) => v is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(v),
            ))
          throw const CryptoDirectoryException(
            'directory_migration_attestation',
          );
      case 'crypto2.account.scopeObserve':
        _fields(payload, {
          ...common,
          'scopeToken',
          'headHash',
          'observationHash',
        });
        if ([
          payload['scopeToken'],
          payload['headHash'],
          payload['observationHash'],
        ].any((v) => v is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(v)))
          throw const CryptoDirectoryException('directory_scope_observation');
      case 'crypto2.account.projectRelocation':
        _fields(payload, {...common, 'actionId', 'publicationRoot'});
        _uuid(payload['actionId']);
        if (payload['publicationRoot'] is! String ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(payload['publicationRoot'])) {
          throw const CryptoDirectoryException('directory_project_relocation');
        }
      case 'crypto2.account.scopeDeletion':
        _fields(payload, {...common, 'scopeToken', 'certificateHash'});
        if ([
          payload['scopeToken'],
          payload['certificateHash'],
        ].any((v) => v is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(v))) {
          throw const CryptoDirectoryException('directory_scope_deletion');
        }
      case 'crypto2.account.scheduleUse':
        _fields(payload, {...common, 'useToken', 'useProofHash', 'active'});
        if (payload['active'] is! bool ||
            [payload['useToken'], payload['useProofHash']].any(
              (v) => v is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(v),
            ))
          throw const CryptoDirectoryException('directory_schedule_use');
      case 'crypto2.account.protectionReady':
        _fields(payload, {
          ...common,
          'deviceSnapshotHash',
          'scopeManifestHash',
        });
        if (payload['deviceSnapshotHash'] != previous.deviceSnapshotHash ||
            payload['scopeManifestHash'] is! String ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(payload['scopeManifestHash'])) {
          throw const CryptoDirectoryException('directory_protection_catalog');
        }
      case 'crypto2.device.add':
        _fields(payload, {
          ...common,
          'deviceId',
          'signingKeyBase64',
          'encryptionKeyBase64',
          'keyringWrite',
          'manageDevices',
        });
        _uuid(payload['deviceId']);
        if (payload['deviceId'] == snapshot['recoveryRootEpochId'] ||
            devices.any((d) => d['deviceId'] == payload['deviceId'])) {
          throw const CryptoDirectoryException('directory_device_exists');
        }
        if (payload['keyringWrite'] is! bool ||
            payload['manageDevices'] is! bool) {
          throw const CryptoDirectoryException('directory_capabilities');
        }
        if (command['signer'] == 'device') {
          final actor = previous.activeDevice(command['deviceId'] as String);
          if ((payload['keyringWrite'] == true &&
                  actor['keyringWrite'] != true) ||
              (payload['manageDevices'] == true &&
                  actor['manageDevices'] != true)) {
            throw const CryptoDirectoryException(
              'directory_capability_escalation',
            );
          }
        }
        devices.add(
          _device(
            payload['deviceId'] as String,
            payload['signingKeyBase64'],
            payload['encryptionKeyBase64'],
            payload['keyringWrite'] as bool,
            payload['manageDevices'] as bool,
            generation,
            previous.identityEpochId,
          ),
        );
      case 'crypto2.device.rebind':
        _fields(payload, {
          ...common,
          'approvingDeviceId',
          'signingKeyBase64',
          'encryptionKeyBase64',
          'keyringWrite',
          'manageDevices',
          'retireApprovingDevice',
          'newDeviceProof',
        });
        _uuid(payload['approvingDeviceId']);
        final old = previous.activeDevice(payload['approvingDeviceId']);
        if (command['signer'] != 'device' ||
            old['manageDevices'] != true ||
            payload['retireApprovingDevice'] != true ||
            payload['keyringWrite'] is! bool ||
            payload['manageDevices'] is! bool ||
            (payload['keyringWrite'] == true && old['keyringWrite'] != true) ||
            (payload['manageDevices'] == true &&
                old['manageDevices'] != true)) {
          throw const CryptoDirectoryException('directory_rebind_authority');
        }
        if (command['deviceId'] == snapshot['recoveryRootEpochId'] ||
            devices.any((d) => d['deviceId'] == command['deviceId'])) {
          throw const CryptoDirectoryException('directory_device_exists');
        }
        if (devices.any(
          (d) =>
              d['signingKeyBase64'] == payload['signingKeyBase64'] ||
              d['encryptionKeyBase64'] == payload['encryptionKeyBase64'],
        )) {
          throw const CryptoDirectoryException('directory_device_key_reuse');
        }
        devices.singleWhere(
          (d) => d['deviceId'] == payload['approvingDeviceId'],
        )['revokedGeneration'] = generation;
        devices.add(
          _device(
            command['deviceId'],
            payload['signingKeyBase64'],
            payload['encryptionKeyBase64'],
            payload['keyringWrite'],
            payload['manageDevices'],
            generation,
            previous.identityEpochId,
          ),
        );
      case 'crypto2.device.revoke':
        _fields(payload, {...common, 'deviceId'});
        _uuid(payload['deviceId']);
        if (payload['deviceId'] == command['deviceId']) {
          throw const CryptoDirectoryException('directory_self_revocation');
        }
        final target = previous.activeDevice(payload['deviceId'] as String);
        devices.singleWhere(
          (d) => d['deviceId'] == target['deviceId'],
        )['revokedGeneration'] = generation;
      case 'crypto2.account.recoverEpoch':
        _fields(payload, {
          ...common,
          'newIdentityEpochId',
          'newDeviceSigningKeyBase64',
          'newDeviceEncryptionKeyBase64',
        });
        _uuid(payload['newIdentityEpochId']);
        if (command['signer'] != 'root' ||
            command['deviceId'] == snapshot['recoveryRootEpochId'] ||
            devices.any(
              (d) =>
                  d['deviceId'] == command['deviceId'] ||
                  d['identityEpochId'] == payload['newIdentityEpochId'] ||
                  d['deviceId'] == payload['newIdentityEpochId'],
            )) {
          throw const CryptoDirectoryException('directory_recovery_epoch');
        }
        for (final device in devices) {
          device['revokedGeneration'] ??= generation;
        }
        snapshot['identityEpochId'] = payload['newIdentityEpochId'];
        devices.add(
          _device(
            command['deviceId'] as String,
            payload['newDeviceSigningKeyBase64'],
            payload['newDeviceEncryptionKeyBase64'],
            true,
            true,
            generation,
            payload['newIdentityEpochId'] as String,
          ),
        );
      case 'crypto2.account.rotateRoot':
        _fields(payload, {
          ...common,
          'transitionId',
          'newRootSigningKeyBase64',
          'newRootEncryptionKeyBase64',
          'newIdentityEpochId',
          'newDeviceSigningKeyBase64',
          'newDeviceEncryptionKeyBase64',
          'keyringCiphertextBase64',
          'incomingRootProof',
        });
        _uuid(payload['transitionId']);
        _uuid(payload['newIdentityEpochId']);
        for (final name in [
          'newRootSigningKeyBase64',
          'newRootEncryptionKeyBase64',
          'newDeviceSigningKeyBase64',
          'newDeviceEncryptionKeyBase64',
        ]) {
          cryptoBase64(payload[name], length: 32);
        }
        if (command['signer'] != 'root' ||
            payload['newRootSigningKeyBase64'] ==
                snapshot['rootSigningKeyBase64'] ||
            payload['newRootEncryptionKeyBase64'] ==
                snapshot['rootEncryptionKeyBase64'] ||
            command['deviceId'] == payload['newIdentityEpochId'] ||
            devices.any(
              (d) =>
                  d['deviceId'] == command['deviceId'] ||
                  d['identityEpochId'] == payload['newIdentityEpochId'] ||
                  d['deviceId'] == payload['newIdentityEpochId'],
            )) {
          throw const CryptoDirectoryException('directory_root_transition');
        }
        final cipher = cryptoBase64(
          payload['keyringCiphertextBase64'],
          max: 256 * 1024,
        );
        if (cipher.length < 48) {
          throw const CryptoDirectoryException('directory_envelope');
        }
        for (final device in devices) {
          device['revokedGeneration'] ??= generation;
        }
        snapshot['rootSigningKeyBase64'] = payload['newRootSigningKeyBase64'];
        snapshot['rootEncryptionKeyBase64'] =
            payload['newRootEncryptionKeyBase64'];
        snapshot['identityEpochId'] = payload['newIdentityEpochId'];
        snapshot['recoveryRootEpochId'] = payload['newIdentityEpochId'];
        snapshot['recoveryRootCiphertextHash'] = await cryptoSha256(cipher);
        devices.add(
          _device(
            command['deviceId'] as String,
            payload['newDeviceSigningKeyBase64'],
            payload['newDeviceEncryptionKeyBase64'],
            true,
            true,
            generation,
            payload['newIdentityEpochId'] as String,
          ),
        );
      case 'crypto2.account.keyringEntriesPut':
        _fields(payload, {...common, 'entries'});
        final additions = payload['entries'];
        if (additions is! List || additions.isEmpty || additions.length > 32) {
          throw const CryptoDirectoryException('directory_entries_limit');
        }
        final seen = <String>{};
        final touched = <String>{};
        for (final item in additions.cast<Map<String, dynamic>>()) {
          _fields(item, {
            'id',
            'recipientId',
            'recipientKind',
            'recipientPublicKeyBase64',
            'sealedEnvelopeBase64',
          });
          _uuid(item['id']);
          final recipient = item['recipientId'] as String;
          _uuid(recipient);
          final kind = item['recipientKind'];
          if (kind != 'device' && kind != 'recovery') {
            throw const CryptoDirectoryException('directory_recipient_kind');
          }
          if (kind == 'recovery' &&
              recipient != snapshot['recoveryRootEpochId']) {
            throw const CryptoDirectoryException(
              'directory_recovery_root_epoch',
            );
          }
          final expectedKey = kind == 'recovery'
              ? snapshot['rootEncryptionKeyBase64']
              : previous.activeDevice(recipient)['encryptionKeyBase64'];
          if (item['recipientPublicKeyBase64'] != expectedKey ||
              !seen.add('${item['id']}:$kind:$recipient')) {
            throw const CryptoDirectoryException('directory_recipient');
          }
          final sealed = cryptoBase64(item['sealedEnvelopeBase64'], max: 4096);
          if (sealed.length < 48) {
            throw const CryptoDirectoryException('directory_envelope');
          }
          final hash = await cryptoSha256(sealed);
          final old = entries.where(
            (e) =>
                e['id'] == item['id'] &&
                e['recipientKind'] == kind &&
                e['recipientId'] == recipient,
          );
          if (old.isNotEmpty) {
            if (old.single['recipientKind'] != kind ||
                old.single['recipientPublicKeyBase64'] != expectedKey ||
                old.single['envelopeHash'] != hash) {
              throw const CryptoDirectoryException(
                'directory_envelope_immutable',
              );
            }
          } else {
            entries.add({
              'id': item['id'],
              'recipientId': recipient,
              'recipientKind': kind,
              'recipientPublicKeyBase64': expectedKey,
              'envelopeHash': hash,
              'createdGeneration': generation,
              'identityEpochId': previous.identityEpochId,
            });
          }
          touched.add(item['id'] as String);
        }
        if (touched.any(
          (id) => !entries.any(
            (e) =>
                e['id'] == id &&
                e['recipientKind'] == 'recovery' &&
                e['recipientId'] == snapshot['recoveryRootEpochId'] &&
                e['recipientPublicKeyBase64'] ==
                    snapshot['rootEncryptionKeyBase64'],
          ),
        )) {
          throw const CryptoDirectoryException(
            'directory_recovery_envelope_missing',
          );
        }
      default:
        throw const CryptoDirectoryException('directory_operation');
    }
    if (devices.where((d) => d['revokedGeneration'] == null).length > 128) {
      throw const CryptoDirectoryException('directory_active_device_limit');
    }
    devices.sort(
      (a, b) => (a['deviceId'] as String).compareTo(b['deviceId'] as String),
    );
    entries.sort((a, b) {
      final id = (a['id'] as String).compareTo(b['id'] as String);
      if (id != 0) return id;
      final kind = (a['recipientKind'] as String).compareTo(
        b['recipientKind'] as String,
      );
      return kind != 0
          ? kind
          : (a['recipientId'] as String).compareTo(b['recipientId'] as String);
    });
    snapshot['devices'] = devices;
    snapshot['keyringEntries'] = entries;
    return snapshot;
  }

  Future<Map<String, dynamic>> rootTransitionBody(
    VerifiedAccountDirectory previous,
    Map<String, dynamic> command,
  ) async {
    final p = command['payload'] as Map<String, dynamic>;
    return {
      'version': 2,
      'serverId': previous.serverId,
      'accountId': previous.accountId,
      'transitionId': p['transitionId'],
      'previousHeadHash': previous.headHash,
      'previousSnapshotHash': previous.snapshotHash,
      'oldRootSigningKeyBase64': previous.snapshot['rootSigningKeyBase64'],
      'oldRootEncryptionKeyBase64':
          previous.snapshot['rootEncryptionKeyBase64'],
      'newRecoveryRootEpochId': p['newIdentityEpochId'],
      'oldFingerprint': crypto.fingerprint(
        cryptoBase64(previous.snapshot['rootSigningKeyBase64'], length: 32),
        cryptoBase64(previous.snapshot['rootEncryptionKeyBase64'], length: 32),
      ),
      'newRootSigningKeyBase64': p['newRootSigningKeyBase64'],
      'newRootEncryptionKeyBase64': p['newRootEncryptionKeyBase64'],
      'newIdentityEpochId': p['newIdentityEpochId'],
      'newDeviceSigningKeyBase64': p['newDeviceSigningKeyBase64'],
      'newDeviceEncryptionKeyBase64': p['newDeviceEncryptionKeyBase64'],
      'newEncryptedRootCiphertextHash': await cryptoSha256(
        cryptoBase64(p['keyringCiphertextBase64'], max: 256 * 1024),
      ),
      'resultingSnapshotHash': p['resultingSnapshotHash'],
    };
  }

  Map<String, dynamic> deviceSnapshot(Map<String, dynamic> snapshot) => {
    for (final key in [
      'version',
      'serverId',
      'accountId',
      'rootSigningKeyBase64',
      'rootEncryptionKeyBase64',
      'identityEpochId',
      'recoveryRootEpochId',
      'devices',
    ])
      key: snapshot[key],
  };

  Map<String, dynamic> _device(
    String id,
    Object? signing,
    Object? encryption,
    bool keyringWrite,
    bool manageDevices,
    int generation,
    String epoch,
  ) {
    _uuid(id);
    cryptoBase64(signing, length: 32);
    cryptoBase64(encryption, length: 32);
    return {
      'deviceId': id,
      'signingKeyBase64': signing,
      'encryptionKeyBase64': encryption,
      'keyringWrite': keyringWrite,
      'manageDevices': manageDevices,
      'addedGeneration': generation,
      'revokedGeneration': null,
      'identityEpochId': epoch,
    };
  }

  String _uuid(Object? value) {
    if (value is! String ||
        !RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
        ).hasMatch(value)) {
      throw const CryptoDirectoryException('directory_uuid');
    }
    return value;
  }

  void _fields(Map<String, dynamic> value, Set<String> expected) {
    if (value.length != expected.length ||
        value.keys.any((key) => !expected.contains(key))) {
      throw const CryptoDirectoryException('directory_fields');
    }
  }
}
