import 'dart:convert';
import 'dart:typed_data';

import 'package:sodium/sodium.dart';

import 'account_crypto_repository.dart' show AccountCryptoWorkflow;
import 'account_directory_repository.dart';
import 'account_directory_v2.dart';
import 'crypto_identity_store.dart';
import 'crypto_json.dart';
import 'crypto_sync_repository.dart' show CryptoKeyLease;
import 'recovery_file_codec.dart';
import 'crypto_scope_observations.dart';

/// Recovery setup backed by the encrypted database journal. Routine sessions
/// have only their own device secrets, never account-root signing authority.
class AccountCryptoV2Workflow implements AccountCryptoWorkflow {
  AccountCryptoV2Workflow(this.directory);
  final AccountDirectoryRepository directory;
  CryptoIdentityStore get store => directory.store;
  RecoveryFileCodec get files => RecoveryFileCodec(directory.reducer.crypto);
  String get deviceId => directory.session.profile.deviceId;
  Future<bool> hasIncompleteScopeRecovery() =>
      CryptoScopeObservations.recoveryIncomplete(this);
  Future<void> restoreScopesFromFile(Uint8List file) =>
      CryptoScopeObservations(this).hydrateObservedScopes(file);
  Future<Map<String, Object?>?> _local() async => (await store.database.rows(
    'SELECT * FROM crypto_identity_secrets WHERE partition=? AND device_id=?',
    [store.partition, deviceId],
  )).firstOrNull;
  Uint8List _bytes(Object? value) =>
      Uint8List.fromList((value as List).cast<int>());
  Map<String, dynamic> _root(Map<String, Object?> local) =>
      CryptoJson.decode(_bytes(local['encrypted_root']))
          as Map<String, dynamic>;
  @override
  Future<Map<String, dynamic>> status() =>
      directory.call('crypto2.account.status');
  @override
  Future<String> localPhase() async {
    if ((await store.pending()).isNotEmpty ||
        (await store.rejected()).isNotEmpty) {
      return 'pending';
    }
    final row = await _local();
    if (row?['phase'] == 'ready') {
      try {
        (await directory.cachedVerifiedDirectory()).activeDevice(deviceId);
      } on CryptoDirectoryException {
        return 'recoveryRequired';
      }
    }
    return row?['phase'] as String? ?? 'missing';
  }

  @override
  Future<Uint8List> prepareRecoveryFile() => directory.exclusive(() async {
    final local = await _local();
    if (local?['prepared_recovery'] != null) {
      return _bytes(local!['prepared_recovery']);
    }
    if ((await status())['initialized'] == true) {
      throw const CryptoDirectoryException('directory_already_initialized');
    }
    final material = files.create(
      serverId: directory.session.profile.serverId,
      accountId: directory.accountId,
    );
    try {
      await _createDevice(material.encryptedRoot, preparedFile: material.file);
      return Uint8List.fromList(material.file);
    } finally {
      material.dispose();
    }
  });
  Future<void> _createDevice(
    Map<String, dynamic> encryptedRoot, {
    Uint8List? preparedFile,
  }) async {
    if (await _local() != null) {
      throw const CryptoDirectoryException('directory_local_device_exists');
    }
    final crypto = directory.reducer.crypto;
    final signing = crypto.sodium.crypto.sign.keyPair();
    final encryption = crypto.sodium.crypto.box.keyPair();
    final rawSign = signing.secretKey.extractBytes(),
        rawEncryption = encryption.secretKey.extractBytes();
    try {
      await store.database.execute(
        'INSERT INTO crypto_identity_secrets VALUES(?,?,?,?,?,?,?,?,?,?)',
        [
          store.partition,
          deviceId,
          rawSign,
          rawEncryption,
          base64Encode(signing.publicKey),
          base64Encode(encryption.publicKey),
          preparedFile == null ? 'recoveryRequired' : 'prepared',
          preparedFile,
          CryptoJson.encode(encryptedRoot),
          null,
        ],
      );
    } finally {
      rawSign.fillRange(0, rawSign.length, 0);
      rawEncryption.fillRange(0, rawEncryption.length, 0);
      signing.secretKey.dispose();
      encryption.secretKey.dispose();
    }
  }

  @override
  Future<void> verifyAndInitialize(Uint8List externalFile) async {
    final local = await _local();
    if (local == null ||
        local['prepared_recovery'] == null ||
        base64Encode(_bytes(local['prepared_recovery'])) !=
            base64Encode(externalFile)) {
      throw const CryptoDirectoryException('directory_file_not_verified');
    }
    final file = files.inspect(
      externalFile,
      serverId: directory.session.profile.serverId,
      accountId: directory.accountId,
    );
    final epoch = directory.reducer.crypto.randomId();
    await directory.stageAndSend(
      (previous) async {
        if (previous != null) {
          throw const CryptoDirectoryException('directory_already_initialized');
        }
        final root = files.open(
          file: externalFile,
          encryptedRoot: _root(local),
          serverId: directory.session.profile.serverId,
          accountId: directory.accountId,
          expectedFingerprint: file['fingerprint'] as String,
        );
        try {
          return await directory.reducer.prepare(
            previous: null,
            serverId: directory.session.profile.serverId,
            accountId: directory.accountId,
            deviceId: deviceId,
            identityEpochId: epoch,
            operation: 'crypto2.account.initialize',
            signer: 'root',
            pinnedRootFingerprint: file['fingerprint'] as String,
            signingKey: root.signing.secretKey,
            payload: {
              'rootSigningKeyBase64': file['signingPublicKeyBase64'],
              'rootEncryptionKeyBase64': file['encryptionPublicKeyBase64'],
              'deviceSigningKeyBase64': local['signing_public'],
              'deviceEncryptionKeyBase64': local['encryption_public'],
              'keyringCiphertextBase64': base64Encode(
                CryptoJson.encode(_root(local)),
              ),
            },
          );
        } finally {
          root.dispose();
        }
      },
      externalFingerprint: file['fingerprint'] as String,
      establishesFreshness: true,
      beforeSendTransaction: () => store.database.execute(
        "UPDATE crypto_identity_secrets SET prepared_recovery=NULL,phase='verified' WHERE partition=? AND device_id=?",
        [store.partition, deviceId],
      ),
    );
    await _ready();
  }

  /// A fresh authenticated device plus the external file explicitly starts a new
  /// identity epoch. This revokes every old device; it is not root replacement.
  @override
  Future<void> recover(Uint8List externalFile) async {
    final file = files.inspect(
      externalFile,
      serverId: directory.session.profile.serverId,
      accountId: directory.accountId,
    );
    final status = await this.status();
    if (status['initialized'] != true) {
      throw const CryptoDirectoryException('directory_missing');
    }
    final encrypted =
        CryptoJson.decode(cryptoBase64(status['keyringCiphertextBase64']))
            as Map<String, dynamic>;
    if (await _local() == null) {
      await directory.exclusive(() => _createDevice(encrypted));
    }
    final local = (await _local())!;
    final validation = files.open(
      file: externalFile,
      encryptedRoot: encrypted,
      serverId: directory.session.profile.serverId,
      accountId: directory.accountId,
      expectedFingerprint: file['fingerprint'],
    );
    validation.dispose();
    await directory.exclusive(() => store.retireRejectedRecovery());
    final epoch = directory.reducer.crypto.randomId();
    await directory.stageSequenceAndSend(
      (previous) async {
        if (previous == null) {
          throw const CryptoDirectoryException('directory_missing');
        }
        final root = files.open(
          file: externalFile,
          encryptedRoot: encrypted,
          serverId: directory.session.profile.serverId,
          accountId: directory.accountId,
          expectedFingerprint: file['fingerprint'] as String,
        );
        try {
          final start = await directory.reducer.prepare(
            previous: previous,
            serverId: directory.session.profile.serverId,
            accountId: directory.accountId,
            deviceId: deviceId,
            identityEpochId: previous.identityEpochId,
            operation: 'crypto2.account.recoveryStart',
            signer: 'root',
            pinnedRootFingerprint: file['fingerprint'] as String,
            signingKey: root.signing.secretKey,
            payload: {},
          );
          final recovered = await directory.reducer.prepare(
            previous: start.result,
            serverId: directory.session.profile.serverId,
            accountId: directory.accountId,
            deviceId: deviceId,
            identityEpochId: previous.identityEpochId,
            operation: 'crypto2.account.recoverEpoch',
            signer: 'root',
            pinnedRootFingerprint: file['fingerprint'] as String,
            signingKey: root.signing.secretKey,
            payload: {
              'newIdentityEpochId': epoch,
              'newDeviceSigningKeyBase64': local['signing_public'],
              'newDeviceEncryptionKeyBase64': local['encryption_public'],
            },
          );
          return [start, recovered];
        } finally {
          root.dispose();
        }
      },
      externalFingerprint: file['fingerprint'] as String,
      establishesFreshness: true,
      beforeSendTransaction: () => store.database.execute(
        'INSERT INTO crypto_membership_intents VALUES(?,?,?,?,?,NULL) ON CONFLICT(partition,scope_id,intent_id) DO UPDATE SET state=excluded.state,payload=excluded.payload',
        [
          store.partition,
          directory.accountId,
          'fileScopeRecoverySummary',
          'scopeRecoveryPending',
          CryptoJson.encode({'reason': 'scope_recovery_verification_required'}),
        ],
      ),
    );
    await _ready();
  }

  Future<String> prepareDeviceRequest() async {
    final remote = await status();
    if (remote['initialized'] != true) {
      throw const CryptoDirectoryException('directory_missing');
    }
    return directory.exclusive(() async {
      final prior = await store.database.rows(
        "SELECT payload FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND state='deviceApprovalRequest' ORDER BY rowid DESC LIMIT 1",
        [store.partition, directory.accountId],
      );
      if (prior.isNotEmpty) {
        final card = CryptoJson.decode(_bytes(prior.single['payload'])) as Map;
        if (card['deviceId'] == deviceId) {
          return utf8.decode(CryptoJson.encode(card));
        }
      }
      if (await _local() == null) {
        await _createDevice(
          CryptoJson.decode(cryptoBase64(remote['keyringCiphertextBase64']))
              as Map<String, dynamic>,
        );
      }
      final local = (await _local())!;
      if (local['phase'] == 'ready') {
        throw const CryptoDirectoryException('directory_already_approved');
      }
      final card = {
        'version': 2,
        'purpose': 'deviceApprovalRequest',
        'serverId': directory.session.profile.serverId,
        'accountId': directory.accountId,
        'deviceId': deviceId,
        'requestId': directory.reducer.crypto.randomId(),
        'signingKeyBase64': local['signing_public'],
        'encryptionKeyBase64': local['encryption_public'],
      };
      await store.database.transaction(() async {
        await store.database.execute(
          'INSERT INTO crypto_membership_intents VALUES(?,?,?,?,?,NULL)',
          [
            store.partition,
            directory.accountId,
            card['requestId'],
            'deviceApprovalRequest',
            CryptoJson.encode(card),
          ],
        );
        await store.database.execute(
          "UPDATE crypto_identity_secrets SET phase='awaitingApproval' WHERE partition=? AND device_id=?",
          [store.partition, deviceId],
        );
      });
      return utf8.decode(CryptoJson.encode(card));
    });
  }

  Future<String> authorizeDeviceRequest(String externallyReceivedCard) async {
    final card =
        CryptoJson.decode(
              Uint8List.fromList(utf8.encode(externallyReceivedCard)),
              limit: 4096,
            )
            as Map<String, dynamic>;
    if (card.length != 8 ||
        card['version'] != 2 ||
        card['purpose'] != 'deviceApprovalRequest' ||
        card['serverId'] != directory.session.profile.serverId ||
        card['accountId'] != directory.accountId ||
        card['deviceId'] == deviceId) {
      throw const CryptoDirectoryException('directory_device_request');
    }
    cryptoBase64(card['signingKeyBase64'], length: 32);
    cryptoBase64(card['encryptionKeyBase64'], length: 32);
    final known = await directory.requireFresh();
    final existing = known.devices
        .where((d) => d['deviceId'] == card['deviceId'])
        .toList();
    if (existing.isNotEmpty) {
      if (existing.single['revokedGeneration'] != null ||
          existing.single['signingKeyBase64'] != card['signingKeyBase64'] ||
          existing.single['encryptionKeyBase64'] !=
              card['encryptionKeyBase64']) {
        throw const CryptoDirectoryException('directory_device_key_changed');
      }
      return _deviceConfirmation(card, known);
    }
    final lease = await signingKey();
    try {
      await directory.stageAndSend((previous) async {
        if (previous == null ||
            previous.activeDevice(deviceId)['manageDevices'] != true) {
          throw const CryptoDirectoryException(
            'directory_device_management_forbidden',
          );
        }
        final actor = previous.activeDevice(deviceId);
        return directory.reducer.prepare(
          previous: previous,
          serverId: directory.session.profile.serverId,
          accountId: directory.accountId,
          deviceId: deviceId,
          identityEpochId: previous.identityEpochId,
          operation: 'crypto2.device.add',
          signer: 'device',
          pinnedRootFingerprint: (await store.anchor(
            directory.accountId,
          ))!['fingerprint'],
          signingKey: lease.key,
          payload: {
            'deviceId': card['deviceId'],
            'signingKeyBase64': card['signingKeyBase64'],
            'encryptionKeyBase64': card['encryptionKeyBase64'],
            'keyringWrite': actor['keyringWrite'],
            'manageDevices': actor['manageDevices'],
          },
        );
      });
    } finally {
      lease.release();
    }
    final current = await directory.requireFresh();
    return _deviceConfirmation(card, current);
  }

  /// Emergency revocation immediately removes future device authority. Existing
  /// scopes remain readable candidates and require fresh key epochs before new
  /// writes; this does not certify the timing of an unknown historical tail.
  Future<Map<String, dynamic>> attestMigration({
    required String migrationId,
    required String scopeToken,
    required String domain,
    required String attestationHash,
  }) => _attestDirectoryEvent('crypto2.account.migrationAttest', {
    'migrationId': migrationId,
    'scopeToken': scopeToken,
    'domain': domain,
    'attestationHash': attestationHash,
  });

  Future<Map<String, dynamic>> observeScope({
    required String scopeToken,
    required String headHash,
    required String observationHash,
  }) => _attestDirectoryEvent('crypto2.account.scopeObserve', {
    'scopeToken': scopeToken,
    'headHash': headHash,
    'observationHash': observationHash,
  });

  /// Prepared companion only. The notifier journals this inside its complete
  /// signed outer request and commits it atomically with reminder consent.
  /// Never send it through the account mutation RPC/receipt namespace.
  Future<PreparedDirectoryMutation> prepareScheduleUseEvent({
    required String requestId,
    required String useToken,
    required String useProofHash,
    required bool active,
  }) => _prepareCompanion('crypto2.account.scheduleUse', requestId, {
    'useToken': useToken,
    'useProofHash': useProofHash,
    'active': active,
  });

  /// Prepared and journaled inside the exact deletion request only. The server
  /// appends this event atomically with scope deletion; it is never an RPC.
  Future<PreparedDirectoryMutation> prepareScopeDeletionEvent({
    required String requestId,
    required String scopeToken,
    required String certificateHash,
  }) => _prepareCompanion('crypto2.account.scopeDeletion', requestId, {
    'scopeToken': scopeToken,
    'certificateHash': certificateHash,
  });

  /// Companion only: the relocation caller journals the complete immutable
  /// final command before transport. This helper never sends an account RPC.
  Future<PreparedDirectoryMutation> prepareProjectRelocationEvent({
    required String requestId,
    required String actionId,
    required String publicationRoot,
  }) => _prepareCompanion('crypto2.account.projectRelocation', requestId, {
    'actionId': actionId,
    'publicationRoot': publicationRoot,
  });

  Future<PreparedDirectoryMutation> _prepareCompanion(
    String operation,
    String requestId,
    Map<String, dynamic> payload,
  ) async {
    if ((await store.pending()).isNotEmpty) {
      throw const CryptoDirectoryException('directory_pending_request');
    }
    final previous = await directory.requireFresh();
    final lease = await signingKey();
    try {
      return await directory.reducer.prepare(
        previous: previous,
        serverId: previous.serverId,
        accountId: previous.accountId,
        deviceId: deviceId,
        identityEpochId: previous.identityEpochId,
        operation: operation,
        signer: 'device',
        requestId: requestId,
        pinnedRootFingerprint: previous.rootFingerprint,
        signingKey: lease.key,
        payload: payload,
      );
    } finally {
      lease.release();
    }
  }

  Future<Map<String, dynamic>> _attestDirectoryEvent(
    String operation,
    Map<String, dynamic> fields,
  ) async {
    bool matches(Map command) =>
        command['operation'] == operation &&
        fields.entries.every((e) => command['payload'][e.key] == e.value);
    Future<Map<String, dynamic>?> included() async {
      final verified = await directory.cachedVerifiedDirectory();
      for (final entry in await store.entries(directory.accountId)) {
        if (entry['generation'] > verified.generation) continue;
        final raw =
            CryptoJson.decode(
                  cryptoBase64(entry['authorization']['commandBase64']),
                )
                as Map;
        if (matches(raw)) return entry;
      }
      return null;
    }

    final known = await included();
    if (known != null) return known;
    final pending = await store.pending();
    if (pending.isNotEmpty) {
      if (pending.length != 1 ||
          !matches(
            CryptoJson.decode(cryptoBase64(pending.single['commandBase64']))
                as Map,
          ))
        throw const CryptoDirectoryException('directory_pending_request');
      await directory.resume();
      final saved = await included();
      if (saved != null) return saved;
      throw const CryptoDirectoryException('directory_receipt_missing');
    }
    await directory.requireFresh();
    final lease = await signingKey();
    try {
      await directory.stageAndSend((previous) async {
        if (previous == null)
          throw const CryptoDirectoryException('directory_missing');
        return directory.reducer.prepare(
          previous: previous,
          serverId: previous.serverId,
          accountId: previous.accountId,
          deviceId: deviceId,
          identityEpochId: previous.identityEpochId,
          operation: operation,
          signer: 'device',
          pinnedRootFingerprint: (await store.anchor(
            previous.accountId,
          ))!['fingerprint'],
          signingKey: lease.key,
          payload: fields,
        );
      });
    } finally {
      lease.release();
    }
    final saved = await included();
    if (saved == null)
      throw const CryptoDirectoryException('directory_receipt_missing');
    return saved;
  }

  Future<void> appendKeyringEntries(List<Map<String, dynamic>> entries) async {
    await directory.requireFresh();
    final lease = await signingKey();
    try {
      await directory.stageAndSend((previous) async {
        if (previous == null ||
            previous.activeDevice(deviceId)['keyringWrite'] != true) {
          throw const CryptoDirectoryException(
            'directory_keyring_write_forbidden',
          );
        }
        return directory.reducer.prepare(
          previous: previous,
          serverId: directory.session.profile.serverId,
          accountId: directory.accountId,
          deviceId: deviceId,
          identityEpochId: previous.identityEpochId,
          operation: 'crypto2.account.keyringEntriesPut',
          signer: 'device',
          pinnedRootFingerprint: (await store.anchor(
            directory.accountId,
          ))!['fingerprint'],
          signingKey: lease.key,
          payload: {'entries': entries},
        );
      });
    } finally {
      lease.release();
    }
  }

  Future<void> revokeDevice(String targetDeviceId) async {
    if (targetDeviceId == deviceId) {
      throw const CryptoDirectoryException(
        'directory_self_revocation_forbidden',
      );
    }
    await directory.requireFresh();
    final lease = await signingKey();
    try {
      await directory.stageAndSend((previous) async {
        if (previous == null ||
            previous.activeDevice(deviceId)['manageDevices'] != true) {
          throw const CryptoDirectoryException(
            'directory_device_management_forbidden',
          );
        }
        previous.activeDevice(targetDeviceId);
        return directory.reducer.prepare(
          previous: previous,
          serverId: directory.session.profile.serverId,
          accountId: directory.accountId,
          deviceId: deviceId,
          identityEpochId: previous.identityEpochId,
          operation: 'crypto2.device.revoke',
          signer: 'device',
          pinnedRootFingerprint: (await store.anchor(
            directory.accountId,
          ))!['fingerprint'],
          signingKey: lease.key,
          payload: {'deviceId': targetDeviceId},
        );
      });
    } finally {
      lease.release();
    }
  }

  Future<String> _deviceConfirmation(
    Map<String, dynamic> card,
    VerifiedAccountDirectory current,
  ) async {
    final pin = await store.anchor(directory.accountId);
    return utf8.decode(
      CryptoJson.encode({
        'version': 2,
        'purpose': 'deviceApprovalConfirmation',
        'serverId': current.serverId,
        'accountId': current.accountId,
        'deviceId': card['deviceId'],
        'requestId': card['requestId'],
        'fingerprint': pin!['fingerprint'],
        'generation': current.generation,
        'headHash': current.headHash,
      }),
    );
  }

  Future<void> acceptDeviceConfirmation(String externallyReceivedCard) async {
    final card =
        CryptoJson.decode(
              Uint8List.fromList(utf8.encode(externallyReceivedCard)),
              limit: 4096,
            )
            as Map<String, dynamic>;
    if (card.length != 9 ||
        card['version'] != 2 ||
        card['purpose'] != 'deviceApprovalConfirmation' ||
        card['serverId'] != directory.session.profile.serverId ||
        card['accountId'] != directory.accountId ||
        card['deviceId'] != deviceId) {
      throw const CryptoDirectoryException('directory_device_confirmation');
    }
    final requests = await store.database.rows(
      "SELECT payload FROM crypto_membership_intents WHERE partition=? AND intent_id=? AND state='deviceApprovalRequest'",
      [store.partition, card['requestId']],
    );
    if (requests.length != 1) {
      throw const CryptoDirectoryException('directory_device_request');
    }
    final local = (await _local())!;
    await directory.compareTrustedPeer(
      fingerprint: card['fingerprint'],
      generation: card['generation'],
      headHash: card['headHash'],
    );
    final approved = (await directory.cachedVerifiedDirectory()).activeDevice(
      deviceId,
    );
    if (approved['signingKeyBase64'] != local['signing_public'] ||
        approved['encryptionKeyBase64'] != local['encryption_public']) {
      throw const CryptoDirectoryException('directory_device_key_changed');
    }
    await _ready();
  }

  Future<Uint8List> prepareRootReplacement(Uint8List oldExternalFile) async {
    final f = files.inspect(
      oldExternalFile,
      serverId: directory.session.profile.serverId,
      accountId: directory.accountId,
    );
    final verified = await directory.refresh(
      externalFingerprint: f['fingerprint'],
    );
    if (verified == null ||
        verified.devices.any((d) => d['deviceId'] == deviceId)) {
      throw const CryptoDirectoryException('directory_fresh_login_required');
    }
    final existing = await _local();
    if (existing?['phase'] == 'preparedReplacement' &&
        existing?['prepared_recovery'] != null) {
      return _bytes(existing!['prepared_recovery']);
    }
    if (existing != null) {
      throw const CryptoDirectoryException('directory_local_device_exists');
    }
    final status = await this.status();
    final root = files.open(
      file: oldExternalFile,
      encryptedRoot:
          CryptoJson.decode(cryptoBase64(status['keyringCiphertextBase64']))
              as Map<String, dynamic>,
      serverId: directory.session.profile.serverId,
      accountId: directory.accountId,
      expectedFingerprint: f['fingerprint'],
    );
    try {
      final material = files.replacement(
        serverId: directory.session.profile.serverId,
        accountId: directory.accountId,
        previous: root,
      );
      try {
        await directory.exclusive(() async {
          await _createDevice(
            material.encryptedRoot,
            preparedFile: material.file,
          );
          await store.database.execute(
            "UPDATE crypto_identity_secrets SET phase='preparedReplacement' WHERE partition=? AND device_id=?",
            [store.partition, deviceId],
          );
        });
        return Uint8List.fromList(material.file);
      } finally {
        material.dispose();
      }
    } finally {
      root.dispose();
    }
  }

  Future<bool> rootReplacementConfirmed() async {
    final current = await directory.cachedVerifiedDirectory();
    final rows = await store.database.rows(
      "SELECT authorization,receipt FROM crypto_identity_requests WHERE partition=? AND stage='confirmed'",
      [store.partition],
    );
    for (final row in rows) {
      final c =
          CryptoJson.decode(
                cryptoBase64(
                  (CryptoJson.decode(_bytes(row['authorization']))
                      as Map)['commandBase64'],
                ),
              )
              as Map;
      if (c['operation'] != 'crypto2.account.rotateRoot' ||
          c['deviceId'] != deviceId) {
        continue;
      }
      final p = c['payload'] as Map;
      if (p['newRootSigningKeyBase64'] ==
              current.snapshot['rootSigningKeyBase64'] &&
          p['newRootEncryptionKeyBase64'] ==
              current.snapshot['rootEncryptionKeyBase64'] &&
          (CryptoJson.decode(_bytes(row['receipt'])) as Map)['status'] == 200) {
        return true;
      }
    }
    return false;
  }

  Future<void> verifyAndRotateRoot({
    required Uint8List oldExternalFile,
    required Uint8List newExternalFile,
  }) async {
    final local = await _local();
    final rejected = await store.rejected();
    var externallyRebased = false;
    if (local != null &&
        local['prepared_recovery'] == null &&
        rejected.isNotEmpty) {
      final nextFile = files.inspect(
        newExternalFile,
        serverId: directory.session.profile.serverId,
        accountId: directory.accountId,
      );
      final opened = files.open(
        file: newExternalFile,
        encryptedRoot: _root(local),
        serverId: directory.session.profile.serverId,
        accountId: directory.accountId,
        expectedFingerprint: nextFile['fingerprint'],
      );
      opened.dispose();
      final proofs = [
        ...await store.pending(),
        for (final row in rejected)
          CryptoJson.decode(_bytes(row['authorization']))
              as Map<String, dynamic>,
      ];
      final rotations = proofs
          .map(
            (proof) =>
                CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map,
          )
          .where((c) => c['operation'] == 'crypto2.account.rotateRoot')
          .toList();
      if (rotations.length != 1 ||
          (rotations.single['payload'] as Map)['newRootSigningKeyBase64'] !=
              nextFile['signingPublicKeyBase64'] ||
          (rotations.single['payload'] as Map)['newRootEncryptionKeyBase64'] !=
              nextFile['encryptionPublicKeyBase64']) {
        throw const CryptoDirectoryException('directory_new_file_not_verified');
      }
      // Authenticate BOTH external files before retiring any rejected proof.
      final prior = files.inspect(
        oldExternalFile,
        serverId: directory.session.profile.serverId,
        accountId: directory.accountId,
      );
      final status = await this.status();
      final old = files.open(
        file: oldExternalFile,
        encryptedRoot:
            CryptoJson.decode(cryptoBase64(status['keyringCiphertextBase64']))
                as Map<String, dynamic>,
        serverId: directory.session.profile.serverId,
        accountId: directory.accountId,
        expectedFingerprint: prior['fingerprint'],
      );
      old.dispose();
      await directory.exclusive(store.retireRejectedRecovery);
      externallyRebased = true;
    }
    if (local != null &&
        local['prepared_recovery'] == null &&
        !externallyRebased) {
      final pending = await store.pending();
      final rotations = pending
          .where(
            (proof) =>
                (CryptoJson.decode(cryptoBase64(proof['commandBase64']))
                    as Map)['operation'] ==
                'crypto2.account.rotateRoot',
          )
          .toList();
      if (rotations.length == 1) {
        final nextFile = files.inspect(
          newExternalFile,
          serverId: directory.session.profile.serverId,
          accountId: directory.accountId,
        );
        final opened = files.open(
          file: newExternalFile,
          encryptedRoot: _root(local),
          serverId: directory.session.profile.serverId,
          accountId: directory.accountId,
          expectedFingerprint: nextFile['fingerprint'],
        );
        opened.dispose();
        final c =
            CryptoJson.decode(cryptoBase64(rotations.single['commandBase64']))
                as Map;
        final p = c['payload'] as Map;
        if (nextFile['signingPublicKeyBase64'] !=
                p['newRootSigningKeyBase64'] ||
            nextFile['encryptionPublicKeyBase64'] !=
                p['newRootEncryptionKeyBase64']) {
          throw const CryptoDirectoryException(
            'directory_new_file_not_verified',
          );
        }
        await directory.exclusive(
          () => store.authorizeRootHandoff(
            rotations.single,
            nextFile['fingerprint'],
          ),
        );
        await resume();
        return;
      }
    }
    if (local == null ||
        (!externallyRebased &&
            (local['phase'] != 'preparedReplacement' ||
                local['prepared_recovery'] == null ||
                base64Encode(_bytes(local['prepared_recovery'])) !=
                    base64Encode(newExternalFile)))) {
      throw const CryptoDirectoryException('directory_new_file_not_verified');
    }
    final oldFile = files.inspect(
      oldExternalFile,
      serverId: directory.session.profile.serverId,
      accountId: directory.accountId,
    );
    final newFile = files.inspect(
      newExternalFile,
      serverId: directory.session.profile.serverId,
      accountId: directory.accountId,
    );
    final remote = await status();
    final oldEncrypted =
        CryptoJson.decode(cryptoBase64(remote['keyringCiphertextBase64']))
            as Map<String, dynamic>;
    final newEpoch = directory.reducer.crypto.randomId();
    await directory.stageSequenceAndSend(
      (previous) async {
        if (previous == null) {
          throw const CryptoDirectoryException('directory_missing');
        }
        final old = files.open(
          file: oldExternalFile,
          encryptedRoot: oldEncrypted,
          serverId: directory.session.profile.serverId,
          accountId: directory.accountId,
          expectedFingerprint: oldFile['fingerprint'],
        );
        final next = files.open(
          file: newExternalFile,
          encryptedRoot: _root(local),
          serverId: directory.session.profile.serverId,
          accountId: directory.accountId,
          expectedFingerprint: newFile['fingerprint'],
        );
        try {
          final start = await directory.reducer.prepare(
            previous: previous,
            serverId: directory.session.profile.serverId,
            accountId: directory.accountId,
            deviceId: deviceId,
            identityEpochId: previous.identityEpochId,
            operation: 'crypto2.account.recoveryStart',
            signer: 'root',
            payload: {},
            pinnedRootFingerprint: oldFile['fingerprint'],
            signingKey: old.signing.secretKey,
          );
          final rotated = await directory.reducer.prepare(
            previous: start.result,
            serverId: directory.session.profile.serverId,
            accountId: directory.accountId,
            deviceId: deviceId,
            identityEpochId: previous.identityEpochId,
            operation: 'crypto2.account.rotateRoot',
            signer: 'root',
            pinnedRootFingerprint: oldFile['fingerprint'],
            signingKey: old.signing.secretKey,
            incomingRootSigningKey: next.signing.secretKey,
            payload: {
              'transitionId': directory.reducer.crypto.randomId(),
              'newRootSigningKeyBase64': newFile['signingPublicKeyBase64'],
              'newRootEncryptionKeyBase64':
                  newFile['encryptionPublicKeyBase64'],
              'newIdentityEpochId': newEpoch,
              'newDeviceSigningKeyBase64': local['signing_public'],
              'newDeviceEncryptionKeyBase64': local['encryption_public'],
              'keyringCiphertextBase64': base64Encode(
                CryptoJson.encode(_root(local)),
              ),
            },
          );
          return [start, rotated];
        } finally {
          old.dispose();
          next.dispose();
        }
      },
      externalFingerprint: oldFile['fingerprint'],
      verifiedNewRootFingerprint: newFile['fingerprint'],
      establishesFreshness: true,
      beforeSendTransaction: () => store.database.execute(
        "UPDATE crypto_identity_secrets SET prepared_recovery=NULL,phase='verified' WHERE partition=? AND device_id=?",
        [store.partition, deviceId],
      ),
    );
    await _ready();
  }

  Future<void> _ready() async {
    final verified = await directory.requireFresh();
    await store.database.execute(
      "UPDATE crypto_identity_secrets SET phase='ready',prepared_recovery=NULL,identity_epoch_id=? WHERE partition=? AND device_id=?",
      [verified.identityEpochId, store.partition, deviceId],
    );
  }

  @override
  Future<void> resume() async {
    await directory.resume();
    await _ready();
  }

  Future<List<Map<String, Object?>>> _rebindApprovers(
    VerifiedAccountDirectory state,
  ) async {
    final local = await store.database.rows(
      'SELECT * FROM crypto_identity_secrets WHERE partition=? AND device_id<>?',
      [store.partition, deviceId],
    );
    return local.where((row) {
      final matches = state.devices.where(
        (d) =>
            d['deviceId'] == row['device_id'] &&
            d['revokedGeneration'] == null &&
            d['identityEpochId'] == state.identityEpochId &&
            d['manageDevices'] == true &&
            d['signingKeyBase64'] == row['signing_public'] &&
            d['encryptionKeyBase64'] == row['encryption_public'],
      );
      return row['phase'] == 'ready' && matches.length == 1;
    }).toList();
  }

  Future<bool> canRebindLocalDevice() async {
    if ((await store.anchor(directory.accountId))?['trustState'] !=
        'verified') {
      return false;
    }
    final state = await directory.refresh();
    if (state == null ||
        (await store.anchor(directory.accountId))?['trustState'] !=
            'verified') {
      return false;
    }
    return (await _rebindApprovers(state)).isNotEmpty;
  }

  /// Reauthentication is a fresh transport session, not loss of this phone's
  /// approved cryptographic keys. The old key authorizes only this exact new
  /// session/key tuple and is retired atomically. Its decryption keys remain
  /// local until historical wrappers have safely moved to the new device.
  Future<void> rebindLocalDevice() async {
    await directory.stageAndSend(
      (previous) async {
        if (previous == null) {
          throw const CryptoDirectoryException('directory_missing');
        }
        final approvers = await _rebindApprovers(previous);
        if (approvers.isEmpty) {
          throw const CryptoDirectoryException(
            'directory_local_approval_unavailable',
          );
        }
        final old = approvers.first;
        if (await _local() == null) await _createDevice(_root(old));
        final own = (await _local())!,
            oldBytes = _bytes(old['signing_secret']),
            newBytes = _bytes(own['signing_secret']);
        final crypto = directory.reducer.crypto,
            oldKey = crypto.sodium.secureCopy(oldBytes),
            newKey = crypto.sodium.secureCopy(newBytes);
        oldBytes.fillRange(0, oldBytes.length, 0);
        newBytes.fillRange(0, newBytes.length, 0);
        try {
          final authority = previous.activeDevice(old['device_id'] as String);
          return await directory.reducer.prepare(
            previous: previous,
            serverId: previous.serverId,
            accountId: previous.accountId,
            deviceId: deviceId,
            identityEpochId: previous.identityEpochId,
            operation: 'crypto2.device.rebind',
            signer: 'device',
            payload: {
              'approvingDeviceId': old['device_id'],
              'signingKeyBase64': own['signing_public'],
              'encryptionKeyBase64': own['encryption_public'],
              'keyringWrite': authority['keyringWrite'],
              'manageDevices': authority['manageDevices'],
              'retireApprovingDevice': true,
            },
            pinnedRootFingerprint: crypto.fingerprint(
              cryptoBase64(
                previous.snapshot['rootSigningKeyBase64'],
                length: 32,
              ),
              cryptoBase64(
                previous.snapshot['rootEncryptionKeyBase64'],
                length: 32,
              ),
            ),
            signingKey: oldKey,
            newDeviceSigningKey: newKey,
          );
        } finally {
          oldKey.dispose();
          newKey.dispose();
        }
      },
      beforeSendTransaction: () async {
        await store.database.execute(
          "UPDATE crypto_identity_secrets SET phase='rebinding' WHERE partition=? AND device_id=?",
          [store.partition, deviceId],
        );
      },
    );
    await _ready();
  }

  Future<KeyPair?> retainedEncryptionKey(
    String id,
    String publicKeyBase64,
  ) async {
    final rows = await store.database.rows(
      'SELECT encryption_secret,encryption_public FROM crypto_identity_secrets WHERE partition=? AND device_id=?',
      [store.partition, id],
    );
    if (rows.length != 1 ||
        rows.single['encryption_public'] != publicKeyBase64) {
      return null;
    }
    final bytes = _bytes(rows.single['encryption_secret']);
    try {
      return KeyPair(
        publicKey: cryptoBase64(publicKeyBase64, length: 32),
        secretKey: directory.reducer.crypto.sodium.secureCopy(bytes),
      );
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  Future<CryptoKeyLease> signingKey() async {
    final cached = await directory.cachedVerifiedDirectory();
    cached.activeDevice(deviceId);
    final local = await _local();
    if (local == null || local['phase'] != 'ready') {
      throw const CryptoDirectoryException('directory_device_locked');
    }
    final bytes = _bytes(local['signing_secret']);
    try {
      return CryptoKeyLease.owned(
        directory.reducer.crypto.sodium.secureCopy(bytes),
      );
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  Future<KeyPair> encryptionKey() async {
    final local = await _local();
    if (local == null) {
      throw const CryptoDirectoryException('directory_device_locked');
    }
    final bytes = _bytes(local['encryption_secret']);
    try {
      return KeyPair(
        publicKey: cryptoBase64(local['encryption_public'], length: 32),
        secretKey: directory.reducer.crypto.sodium.secureCopy(bytes),
      );
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }
}
