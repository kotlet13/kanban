import '../account_work_coordinator.dart';
import 'dart:convert';
import 'dart:typed_data';

import 'package:sodium/sodium.dart';
import 'package:cryptography/cryptography.dart' show Sha256;

import '../collaboration_transport.dart';
import '../device_session_store.dart';
import 'account_crypto_store.dart';
import 'crypto_codec.dart';
import 'crypto_json.dart';
import 'recovery_file_codec.dart';

class AccountCryptoException implements Exception {
  const AccountCryptoException(this.code);
  final String code;
  @override
  String toString() => 'AccountCryptoException($code)';
}

abstract interface class AccountCryptoWorkflow {
  Future<Map<String, dynamic>> status();
  Future<String> localPhase();
  Future<Uint8List> prepareRecoveryFile();
  Future<void> verifyAndInitialize(Uint8List externalFile);
  Future<void> recover(Uint8List externalFile);
  Future<void> resume();
}

/// A separate authenticated account protocol. This service does not rewrite
/// legacy outboxes, enable plaintext downgrade, or declare a live scope E2EE.
/// Every mutation persists its exact signed body before the first transmission.
class AccountCryptoRepository implements AccountCryptoWorkflow {
  AccountCryptoRepository({
    required this.crypto,
    required this.session,
    required this.transport,
    required this.store,
    required this.isCurrent,
  });
  final CryptoCodec crypto;
  final DeviceSession session;
  final CollaborationTransport transport;
  final AccountCryptoStore store;
  final bool Function() isCurrent;
  static final _queues = <String, Future<void>>{};

  String get _partition => base64UrlEncode(
    crypto.sodium.crypto.genericHash(
      message: CryptoJson.encode({
        'serverId': session.profile.serverId,
        'accountId': session.profile.accountId,
        'deviceId': session.profile.deviceId,
      }),
      outLen: 32,
    ),
  );

  Future<T> _exclusive<T>(Future<T> Function() action) async {
    final partition = _partition;
    final waiting = _queues[partition] ?? Future<void>.value();
    final completion = waiting.then((_) => action());
    final marker = completion.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    _queues[partition] = marker;
    try {
      return await completion;
    } finally {
      if (identical(_queues[partition], marker)) _queues.remove(partition);
    }
  }

  void _current() {
    if (!isCurrent()) {
      throw const AccountCryptoException('crypto_stale_identity');
    }
  }

  Future<Map<String, dynamic>> _call(
    String operation, [
    Map<String, dynamic> params = const {},
  ]) => withAccountWorkJob(
    transport,
    AccountWorkKind.legacyCrypto,
    () => _accountWorkCall(operation, params),
  );

  Future<Map<String, dynamic>> _accountWorkCall(
    String operation, [
    Map<String, dynamic> params = const {},
  ]) async {
    _current();
    final response = await transport.call(
      serverUrl: session.profile.serverUrl,
      operation: operation,
      params: params,
      token: session.token,
      allowLocalHttp: session.profile.allowLocalHttp,
    );
    _current();
    return response;
  }

  Future<Map<String, dynamic>?> _read() async {
    _current();
    final raw = await store.read(_partition);
    _current();
    if (raw == null) return null;
    final state =
        CryptoJson.decode(Uint8List.fromList(utf8.encode(raw)))
            as Map<String, dynamic>;
    if (state['version'] != 1 ||
        state['serverId'] != session.profile.serverId ||
        state['accountId'] != session.profile.accountId ||
        state['deviceId'] != session.profile.deviceId) {
      throw const AccountCryptoException('crypto_local_identity');
    }
    return state;
  }

  Future<void> _write(Map<String, dynamic> state) async {
    _current();
    final bytes = CryptoJson.encode(state);
    // Preview key state has an explicit ceiling; do not grow an unbounded
    // Keychain value. A production keyring needs a separate encrypted journal.
    if (bytes.length > 64 * 1024) {
      throw const AccountCryptoException('crypto_local_capacity');
    }
    await store.write(_partition, utf8.decode(bytes));
    _current();
  }

  Map<String, dynamic> _command(
    String operation,
    Map<String, dynamic> payload, {
    String signer = 'device',
  }) => {
    'version': 1,
    'operation': operation,
    'requestId': crypto.randomId(),
    'serverId': session.profile.serverId,
    'accountId': session.profile.accountId,
    'deviceId': session.profile.deviceId,
    'signer': signer,
    'payload': payload,
  };

  @override
  Future<Map<String, dynamic>> status() => _exclusive(_status);

  @override
  Future<String> localPhase() async =>
      (await _read())?['phase'] as String? ?? 'locked';

  Future<Map<String, dynamic>> _status({
    Map<String, dynamic>? localState,
  }) async {
    final remote = await _call('crypto.account.status');
    final local = localState ?? await _read();
    if (remote['initialized'] == true && local != null) {
      verifyStatus(
        remote,
        fingerprint: local['fingerprint'] as String,
        minimumGeneration: local['generationFloor'] as int,
      );
      _rememberRevocations(local, remote);
      local['generationFloor'] = remote['generation'];
      await _write(local);
    } else if (remote['initialized'] != true && local?['phase'] == 'ready') {
      throw const AccountCryptoException('crypto_identity_missing');
    }
    return remote;
  }

  /// Creates a pending identity once. Repeated save/cancel/restart returns the
  /// same file. An existing remote root is never replaced by missing local keys.
  @override
  Future<Uint8List> prepareRecoveryFile() => _exclusive(() async {
    final local = await _read();
    final remote = await _call('crypto.account.status');
    if (remote['initialized'] == true) {
      throw const AccountCryptoException('crypto_recovery_required');
    }
    if (local != null) {
      if (local['phase'] != 'prepared') {
        throw const AccountCryptoException('crypto_pending_request');
      }
      return cryptoBase64(
        local['recoveryFileBase64'],
        max: RecoveryFileCodec.maxBytes,
      );
    }
    final material = RecoveryFileCodec(crypto).create(
      serverId: session.profile.serverId,
      accountId: session.profile.accountId,
    );
    final signing = crypto.sodium.crypto.sign.keyPair();
    final encryption = crypto.sodium.crypto.box.keyPair();
    try {
      final state = _newState(signing, encryption, material);
      state['recoveryFileBase64'] = base64Encode(material.file);
      await _write(state);
      return Uint8List.fromList(material.file);
    } finally {
      material.dispose();
      signing.secretKey.dispose();
      encryption.secretKey.dispose();
    }
  });

  Map<String, dynamic> _newState(
    KeyPair signing,
    KeyPair encryption,
    AccountRecoveryMaterial material,
  ) {
    final sign = signing.secretKey.extractBytes();
    final enc = encryption.secretKey.extractBytes();
    try {
      return {
        'version': 1,
        'phase': 'prepared',
        'serverId': session.profile.serverId,
        'accountId': session.profile.accountId,
        'deviceId': session.profile.deviceId,
        'fingerprint': material.fingerprint,
        'rootSigningKeyBase64': base64Encode(material.signingPublicKey),
        'rootEncryptionKeyBase64': base64Encode(material.encryptionPublicKey),
        'encryptedRoot': material.encryptedRoot,
        'deviceSigningKeyBase64': base64Encode(signing.publicKey),
        'deviceEncryptionKeyBase64': base64Encode(encryption.publicKey),
        'deviceSigningSecretBase64': base64Encode(sign),
        'deviceEncryptionSecretBase64': base64Encode(enc),
        'generationFloor': 0,
      };
    } finally {
      sign.fillRange(0, sign.length, 0);
      enc.fillRange(0, enc.length, 0);
    }
  }

  /// The caller supplies bytes freshly picked from outside the app. This is the
  /// only path from a prepared account to a root-signed activation request.
  @override
  Future<void> verifyAndInitialize(Uint8List externalFile) => _exclusive(
    () async {
      final local = await _read();
      if (local == null || local['phase'] != 'prepared') {
        throw const AccountCryptoException('crypto_setup_required');
      }
      final remote = await _call('crypto.account.status');
      if (remote['initialized'] == true) {
        throw const AccountCryptoException('crypto_identity_exists');
      }
      final root = RecoveryFileCodec(crypto).open(
        file: externalFile,
        encryptedRoot: local['encryptedRoot'] as Map<String, dynamic>,
        serverId: session.profile.serverId,
        accountId: session.profile.accountId,
        expectedFingerprint: local['fingerprint'] as String,
      );
      try {
        final signed = crypto.sign(
          _command('crypto.account.initialize', {
            'expectedGeneration': 0,
            'rootSigningKeyBase64': local['rootSigningKeyBase64'],
            'rootEncryptionKeyBase64': local['rootEncryptionKeyBase64'],
            'deviceSigningKeyBase64': local['deviceSigningKeyBase64'],
            'deviceEncryptionKeyBase64': local['deviceEncryptionKeyBase64'],
            'keyringCiphertextBase64': base64Encode(
              CryptoJson.encode({
                'version': 1,
                'suite': CryptoCodec.suite,
                'encryptedRoot': local['encryptedRoot'],
              }),
            ),
          }, signer: 'root'),
          root.signing.secretKey,
        );
        // Drop the bearer recovery file before sending the first request. The
        // signed command alone suffices for every retry after a lost response.
        local.remove('recoveryFileBase64');
        local['phase'] = 'verified';
        local['pending'] = signed;
        await _write(local);
      } finally {
        root.dispose();
      }
      await _sendPending(local);
    },
  );

  @override
  Future<void> resume() => _exclusive(() async {
    final state = await _read();
    if (state == null) {
      throw const AccountCryptoException('crypto_setup_required');
    }
    if (state['pending'] != null) await _sendPending(state);
  });

  /// The proposed key fingerprints must be compared over an independent
  /// trusted channel by the user before invoking this approval action. A server
  /// membership row alone is never used as permission to deliver a key.
  Future<void> authorizeDevice({
    required String deviceId,
    required Uint8List signingPublicKey,
    required Uint8List encryptionPublicKey,
    required String confirmedFingerprint,
    bool keyringWrite = true,
    bool manageDevices = false,
  }) => _exclusive(() async {
    if (crypto.fingerprint(signingPublicKey, encryptionPublicKey) !=
        confirmedFingerprint) {
      throw const AccountCryptoException('crypto_fingerprint_unconfirmed');
    }
    final local = await _ready();
    final remote = await _status(localState: local);
    final self = (remote['devices'] as List)
        .cast<Map<String, dynamic>>()
        .where((d) => d['deviceId'] == session.profile.deviceId)
        .single;
    if (self['revoked'] != false ||
        self['manageDevices'] != true ||
        (keyringWrite && self['keyringWrite'] != true)) {
      throw const AccountCryptoException('crypto_device_forbidden');
    }
    final secret = _secret(local['deviceSigningSecretBase64'], 64);
    try {
      local['pending'] = crypto.sign(
        _command('crypto.device.add', {
          'expectedGeneration': remote['generation'],
          'deviceId': deviceId,
          'signingKeyBase64': base64Encode(signingPublicKey),
          'encryptionKeyBase64': base64Encode(encryptionPublicKey),
          'keyringWrite': keyringWrite,
          'manageDevices': manageDevices,
        }),
        secret,
      );
      await _write(local);
    } finally {
      secret.dispose();
    }
    await _sendPending(local);
  });

  Future<void> revokeDevice(String deviceId) => _exclusive(() async {
    final local = await _ready();
    final remote = await _status(localState: local);
    final self = (remote['devices'] as List)
        .cast<Map<String, dynamic>>()
        .where((d) => d['deviceId'] == session.profile.deviceId)
        .single;
    if (self['revoked'] != false ||
        self['manageDevices'] != true ||
        deviceId == session.profile.deviceId) {
      throw const AccountCryptoException('crypto_device_forbidden');
    }
    final secret = _secret(local['deviceSigningSecretBase64'], 64);
    try {
      local['pending'] = crypto.sign(
        _command('crypto.device.revoke', {
          'expectedGeneration': remote['generation'],
          'deviceId': deviceId,
        }),
        secret,
      );
      await _write(local);
    } finally {
      secret.dispose();
    }
    await _sendPending(local);
  });

  Future<Map<String, dynamic>> _ready() async {
    final local = await _read();
    if (local == null || local['phase'] != 'ready') {
      throw const AccountCryptoException('crypto_locked');
    }
    if (local['pending'] != null) {
      throw const AccountCryptoException('crypto_pending_request');
    }
    return local;
  }

  SecureKey _secret(Object? encoded, int length) {
    final bytes = cryptoBase64(encoded, length: length);
    try {
      return crypto.sodium.secureCopy(bytes);
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  /// Prepares an account-private content key with a distinct sealed wrapper for
  /// every currently approved device and the original recovery public key.
  /// The recovery wrapper is committed before this method returns the key.
  /// Shared-space delivery additionally requires its own signed scope grant.
  Future<({String id, SecureKey key})> createContentKey({
    required String scopeId,
    required int epoch,
    required String purpose,
  }) => _exclusive(() async {
    if (scopeId.isEmpty ||
        scopeId.length > 128 ||
        epoch < 1 ||
        !const {'scopeKey', 'financeKey', 'documentKey'}.contains(purpose)) {
      throw const AccountCryptoException('crypto_key_context');
    }
    final local = await _ready();
    final remote = await _status(localState: local);
    final devices = (remote['devices'] as List)
        .cast<Map<String, dynamic>>()
        .where((d) => d['revoked'] == false)
        .toList();
    final self = devices
        .where((d) => d['deviceId'] == session.profile.deviceId)
        .single;
    if (self['keyringWrite'] != true) {
      throw const AccountCryptoException('crypto_keyring_forbidden');
    }
    if (devices.length > 31) {
      throw const AccountCryptoException('crypto_device_limit');
    }
    final key = crypto.sodium.secureRandom(32);
    final id = crypto.randomId();
    final entries = <Map<String, dynamic>>[];
    final recipients = <({String id, Uint8List publicKey})>[
      (
        id: 'recovery',
        publicKey: cryptoBase64(remote['rootEncryptionKeyBase64'], length: 32),
      ),
      for (final device in devices)
        (
          id: device['deviceId'] as String,
          publicKey: cryptoBase64(device['encryptionKeyBase64'], length: 32),
        ),
    ];
    final secret = _secret(local['deviceSigningSecretBase64'], 64);
    final raw = key.extractBytes();
    try {
      for (final recipient in recipients) {
        final context = <String, dynamic>{
          'serverId': session.profile.serverId,
          'accountId': session.profile.accountId,
          'scopeId': scopeId,
          'epoch': epoch,
          'purpose': purpose,
          'keyId': id,
          'recipientId': recipient.id,
        };
        entries.add({
          'id': id,
          'recipientId': recipient.id,
          'recipientPublicKeyBase64': base64Encode(recipient.publicKey),
          'sealedEnvelopeBase64': crypto.sealKey(
            key: key,
            recipientPublicKey: recipient.publicKey,
            context: context,
          ),
        });
      }
      local['pending'] = crypto.sign(
        _command('crypto.account.keyringEntriesPut', {
          'expectedGeneration': remote['generation'],
          'entries': entries,
        }),
        secret,
      );
      final keys = local['contentKeys'] as Map<String, dynamic>? ?? {};
      keys['k${id.replaceAll('-', '_')}'] = {
        'id': id,
        'scopeId': scopeId,
        'epoch': epoch,
        'purpose': purpose,
        'keyBase64': base64Encode(raw),
      };
      local['contentKeys'] = keys;
      await _write(local);
      await _sendPending(local);
      return (id: id, key: key);
    } catch (_) {
      key.dispose();
      rethrow;
    } finally {
      raw.fillRange(0, raw.length, 0);
      secret.dispose();
    }
  });

  /// Retrieves the persisted key only after its immutable pending wrapper
  /// command has received a valid response. Missing keys never create empties.
  Future<SecureKey> contentKey(String id) async {
    final local = await _ready();
    final keys = local['contentKeys'] as Map<String, dynamic>?;
    final entry = keys?['k${id.replaceAll('-', '_')}'] as Map<String, dynamic>?;
    if (entry == null) throw const AccountCryptoException('crypto_key_missing');
    return _secret(entry['keyBase64'], 32);
  }

  /// Decrypts an explicitly selected recovery wrapper only after checking its
  /// signed keyring authorization and account/device revocation history. This
  /// restores a known key; completeness of an entire account is a separate
  /// manifest obligation and is never inferred from an empty page.
  Future<SecureKey> recoverContentKey({
    required Uint8List externalFile,
    required Map<String, dynamic> entry,
    required Map<String, dynamic> expectedContext,
  }) => _exclusive(() async {
    final remote = await _call('crypto.account.status');
    final inspected = RecoveryFileCodec(crypto).inspect(
      externalFile,
      serverId: session.profile.serverId,
      accountId: session.profile.accountId,
    );
    final local = await _read();
    final fingerprint = inspected['fingerprint'] as String;
    if (local != null && local['fingerprint'] != fingerprint) {
      throw const AccountCryptoException('crypto_root_changed');
    }
    verifyStatus(
      remote,
      fingerprint: fingerprint,
      minimumGeneration: local?['generationFloor'] as int? ?? 0,
    );
    if (local != null) {
      _rememberRevocations(local, remote);
      local['generationFloor'] = remote['generation'];
      await _write(local);
    }
    verifyEntry(entry, remote);
    if (entry['recipientId'] != 'recovery' ||
        entry['recipientPublicKeyBase64'] !=
            remote['rootEncryptionKeyBase64'] ||
        expectedContext['keyId'] != entry['id'] ||
        expectedContext['recipientId'] != 'recovery' ||
        expectedContext['serverId'] != session.profile.serverId ||
        expectedContext['accountId'] != session.profile.accountId) {
      throw const AccountCryptoException('crypto_key_context');
    }
    final bundle =
        CryptoJson.decode(cryptoBase64(remote['keyringCiphertextBase64']))
            as Map<String, dynamic>;
    final root = RecoveryFileCodec(crypto).open(
      file: externalFile,
      encryptedRoot: bundle['encryptedRoot'] as Map<String, dynamic>,
      serverId: session.profile.serverId,
      accountId: session.profile.accountId,
      expectedFingerprint: fingerprint,
    );
    try {
      return crypto.openKey(
        sealed: entry['sealedEnvelopeBase64'] as String,
        recipient: root.encryption,
        context: expectedContext,
      );
    } finally {
      root.dispose();
    }
  });

  Future<Map<String, dynamic>> entries({String? afterId}) =>
      _exclusive(() async {
        final local = await _ready();
        final remote = await _status(localState: local);
        final page = await _call('crypto.account.entries', {
          'limit': 50,
          if (afterId != null) 'afterId': afterId,
        });
        if (page['generation'] != remote['generation']) {
          throw const AccountCryptoException('crypto_generation_changed');
        }
        for (final entry
            in (page['entries'] as List).cast<Map<String, dynamic>>()) {
          _hydrateAuthorization(entry, page);
          verifyEntry(entry, remote);
        }
        local['generationFloor'] = remote['generation'];
        await _write(local);
        return page;
      });

  void _hydrateAuthorization(
    Map<String, dynamic> entry,
    Map<String, dynamic> page,
  ) {
    if (entry['authorization'] != null) return;
    final proof =
        (page['authorizations']
            as Map<String, dynamic>?)?[entry['authorizationId']];
    if (proof is! Map<String, dynamic>) {
      throw const AccountCryptoException('crypto_entry_proof_missing');
    }
    entry['authorization'] = proof;
  }

  void verifyEntry(Map<String, dynamic> entry, Map<String, dynamic> remote) {
    final proof = entry['authorization'] as Map<String, dynamic>;
    final raw =
        CryptoJson.decode(cryptoBase64(proof['commandBase64']))
            as Map<String, dynamic>;
    final signer = (remote['devices'] as List)
        .cast<Map<String, dynamic>>()
        .where((d) => d['deviceId'] == raw['deviceId'])
        .single;
    if (raw['signer'] != 'device' ||
        signer['keyringWrite'] != true ||
        _authorizationGeneration(signer) >=
            ((raw['payload'] as Map)['expectedGeneration'] as int) ||
        (signer['revoked'] == true &&
            _revocationGeneration(signer) <=
                ((raw['payload'] as Map)['expectedGeneration'] as int))) {
      throw const AccountCryptoException('crypto_entry_authorization');
    }
    final command = crypto.verify(
      proof,
      cryptoBase64(signer['signingKeyBase64'], length: 32),
    );
    _bound(command);
    final payload = command['payload'] as Map<String, dynamic>;
    final signedEntries = payload['entries'] as List;
    final expected = {
      'id': entry['id'],
      'recipientId': entry['recipientId'],
      'recipientPublicKeyBase64': entry['recipientPublicKeyBase64'],
      'sealedEnvelopeBase64': entry['sealedEnvelopeBase64'],
    };
    if (command['operation'] != 'crypto.account.keyringEntriesPut' ||
        (payload['expectedGeneration'] as int) >=
            (remote['generation'] as int) ||
        !signedEntries.any(
          (e) =>
              utf8.decode(CryptoJson.encode(e)) ==
              utf8.decode(CryptoJson.encode(expected)),
        )) {
      throw const AccountCryptoException('crypto_entry_signature');
    }
  }

  Future<void> _sendPending(Map<String, dynamic> local) async {
    final signed = local['pending'] as Map<String, dynamic>;
    final bytes = cryptoBase64(signed['commandBase64']);
    final command = CryptoJson.decode(bytes) as Map<String, dynamic>;
    final before = await _call('crypto.account.status');
    if (before['initialized'] == true) {
      verifyStatus(
        before,
        fingerprint: local['fingerprint'] as String,
        minimumGeneration: local['generationFloor'] as int,
      );
      _rememberRevocations(local, before);
      local['generationFloor'] = before['generation'];
      await _write(local);
    } else if (command['operation'] != 'crypto.account.initialize') {
      throw const AccountCryptoException('crypto_identity_missing');
    }
    if (local['pendingRecoveryStart'] != null) {
      await _sendRecoveryStart(local);
    }
    await _call(command['operation'] as String, signed);
    final remote = await _call('crypto.account.status');
    verifyStatus(
      remote,
      fingerprint: local['fingerprint'] as String,
      minimumGeneration:
          (local['generationFloor'] as int) >
              ((command['payload'] as Map)['expectedGeneration'] as int) + 1
          ? local['generationFloor'] as int
          : ((command['payload'] as Map)['expectedGeneration'] as int) + 1,
    );
    _rememberRevocations(local, remote);
    final device = (remote['devices'] as List)
        .cast<Map<String, dynamic>>()
        .where((d) => d['deviceId'] == session.profile.deviceId)
        .single;
    if (device['revoked'] != false ||
        device['signingKeyBase64'] != local['deviceSigningKeyBase64'] ||
        device['encryptionKeyBase64'] != local['deviceEncryptionKeyBase64']) {
      throw const AccountCryptoException('crypto_device_revoked');
    }
    await _confirmPending(command, signed, remote);
    local['phase'] = 'ready';
    local['generationFloor'] = remote['generation'];
    local.remove('pending');
    await _write(local);
  }

  Future<void> _sendRecoveryStart(Map<String, dynamic> local) async {
    final signed = local['pendingRecoveryStart'] as Map<String, dynamic>;
    final bytes = cryptoBase64(signed['commandBase64']);
    final command = CryptoJson.decode(bytes) as Map<String, dynamic>;
    _bound(command);
    if (command['operation'] != 'crypto.account.recoveryStart' ||
        command['signer'] != 'root') {
      throw const AccountCryptoException('crypto_recovery_command');
    }
    await _call('crypto.account.recoveryStart', signed);
    final digest = (await Sha256().hash(
      bytes,
    )).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final receipt = await _call('crypto.receipt.get', {
      'requestId': command['requestId'],
      'requestHash': digest,
    });
    final expected =
        ((command['payload'] as Map)['expectedGeneration'] as int) + 1;
    if (receipt['requestId'] != command['requestId'] ||
        receipt['requestHash'] != digest ||
        receipt['status'] != 200 ||
        !_sameProof(receipt['authorization'], signed) ||
        (receipt['response'] as Map?)?['generation'] != expected) {
      throw const AccountCryptoException('crypto_outcome_unknown');
    }
    final remote = await _call('crypto.account.status');
    final floor = local['generationFloor'] as int;
    verifyStatus(
      remote,
      fingerprint: local['fingerprint'] as String,
      minimumGeneration: floor > expected ? floor : expected,
    );
    _rememberRevocations(local, remote);
    local['generationFloor'] = remote['generation'];
    local.remove('pendingRecoveryStart');
    await _write(local);
  }

  bool _sameProof(Object? left, Map<String, dynamic> right) =>
      left is Map &&
      utf8.decode(CryptoJson.encode(left)) ==
          utf8.decode(CryptoJson.encode(right));

  Future<List<dynamic>> _retireRejectedRecovery(
    Map<String, dynamic> local,
  ) async {
    final signed =
        (local['pendingRecoveryStart'] ?? local['pending'])
            as Map<String, dynamic>;
    final bytes = cryptoBase64(signed['commandBase64']);
    final command = CryptoJson.decode(bytes) as Map<String, dynamic>;
    if (command['signer'] != 'root' ||
        !const {
          'crypto.account.recoveryStart',
          'crypto.device.add',
        }.contains(command['operation'])) {
      throw const AccountCryptoException('crypto_pending_request');
    }
    final digest = (await Sha256().hash(
      bytes,
    )).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final receipt = await _call('crypto.receipt.get', {
      'requestId': command['requestId'],
      'requestHash': digest,
    });
    if (receipt['requestId'] != command['requestId'] ||
        receipt['requestHash'] != digest ||
        receipt['status'] != 409 ||
        (receipt['response'] as Map?)?['errorCode'] !=
            'crypto_generation_conflict' ||
        !_sameProof(receipt['authorization'], signed)) {
      // Unknown or applied requests are never silently replaced, even after a
      // file import. The existing exact request must first be reconciled.
      throw const AccountCryptoException('crypto_pending_request');
    }
    return [
      ...?local['retiredRecoveryRequests'] as List?,
      {
        'pending': local['pending'],
        if (local['pendingRecoveryStart'] != null)
          'start': local['pendingRecoveryStart'],
        'rejectionReceipt': receipt,
      },
    ];
  }

  void _rememberRevocations(
    Map<String, dynamic> local,
    Map<String, dynamic> remote,
  ) {
    final remembered = local['revocations'] as List? ?? <dynamic>[];
    final devices = (remote['devices'] as List).cast<Map<String, dynamic>>();
    for (final previous in remembered.cast<Map<String, dynamic>>()) {
      final current = devices.where(
        (d) => d['deviceId'] == previous['deviceId'],
      );
      if (current.length != 1 ||
          current.single['revoked'] != true ||
          !_sameProof(
            current.single['revocationCertificate'],
            previous['certificate'] as Map<String, dynamic>,
          )) {
        throw const AccountCryptoException('crypto_revocation_rollback');
      }
    }
    local['revocations'] = [
      for (final device in devices.where((d) => d['revoked'] == true))
        {
          'deviceId': device['deviceId'],
          'certificate': device['revocationCertificate'],
        },
    ];
  }

  /// A larger generation is not an ACK. Confirm this exact immutable command
  /// in the durable state, including every recovery wrapper, before clearing it.
  Future<void> _confirmPending(
    Map<String, dynamic> command,
    Map<String, dynamic> signed,
    Map<String, dynamic> remote,
  ) async {
    final payload = command['payload'] as Map<String, dynamic>;
    final operation = command['operation'];
    if (operation == 'crypto.account.initialize') {
      if (_sameProof(remote['genesisCertificate'], signed)) return;
    } else if (operation == 'crypto.device.add' ||
        operation == 'crypto.device.revoke') {
      final matches = (remote['devices'] as List)
          .cast<Map<String, dynamic>>()
          .where((device) => device['deviceId'] == payload['deviceId']);
      if (matches.length == 1 &&
          _sameProof(
            matches.single[operation == 'crypto.device.add'
                ? 'certificate'
                : 'revocationCertificate'],
            signed,
          )) {
        return;
      }
    } else if (operation == 'crypto.account.keyringEntriesPut') {
      final required = (payload['entries'] as List)
          .cast<Map<String, dynamic>>();
      final confirmed = <String>{};
      String? cursor;
      final seenCursors = <String>{};
      do {
        final page = await _call('crypto.account.entries', {
          'limit': 50,
          if (cursor != null) 'afterId': cursor,
        });
        for (final entry
            in (page['entries'] as List).cast<Map<String, dynamic>>()) {
          _hydrateAuthorization(entry, page);
          final candidate = {
            'id': entry['id'],
            'recipientId': entry['recipientId'],
            'recipientPublicKeyBase64': entry['recipientPublicKeyBase64'],
            'sealedEnvelopeBase64': entry['sealedEnvelopeBase64'],
          };
          if (_sameProof(entry['authorization'], signed) &&
              required.any(
                (r) =>
                    utf8.decode(CryptoJson.encode(r)) ==
                    utf8.decode(CryptoJson.encode(candidate)),
              )) {
            confirmed.add('${entry['id']}:${entry['recipientId']}');
          }
        }
        if (confirmed.length == required.length) return;
        if (page['hasMore'] != true) break;
        cursor = page['nextAfterId'] as String?;
        if (cursor == null || !seenCursors.add(cursor)) break;
      } while (seenCursors.length <= 10000);
    }
    throw const AccountCryptoException('crypto_outcome_unknown');
  }

  /// Restores only this account and delegates fresh device keys. The root is
  /// held in guarded memory only while it signs this one authorization.
  @override
  Future<void> recover(Uint8List externalFile) => _exclusive(() async {
    final previous = await _read();
    List<dynamic>? retired;
    if (previous?['pending'] != null) {
      retired = await _retireRejectedRecovery(previous!);
    }
    final remote = await _call('crypto.account.status');
    if (remote['initialized'] != true) {
      throw const AccountCryptoException('crypto_identity_missing');
    }
    final inspected = RecoveryFileCodec(crypto).inspect(
      externalFile,
      serverId: session.profile.serverId,
      accountId: session.profile.accountId,
    );
    final fingerprint = inspected['fingerprint'] as String;
    if (previous != null && previous['fingerprint'] != fingerprint) {
      throw const AccountCryptoException('crypto_root_changed');
    }
    verifyStatus(
      remote,
      fingerprint: fingerprint,
      minimumGeneration: previous?['generationFloor'] as int? ?? 0,
    );
    if (previous != null) {
      _rememberRevocations(previous, remote);
      previous['generationFloor'] = remote['generation'];
      await _write(previous);
    }
    if ((remote['devices'] as List).any(
      (d) => (d as Map)['deviceId'] == session.profile.deviceId,
    )) {
      throw const AccountCryptoException('crypto_device_already_registered');
    }
    final bundle =
        CryptoJson.decode(cryptoBase64(remote['keyringCiphertextBase64']))
            as Map<String, dynamic>;
    final root = RecoveryFileCodec(crypto).open(
      file: externalFile,
      encryptedRoot: bundle['encryptedRoot'] as Map<String, dynamic>,
      serverId: session.profile.serverId,
      accountId: session.profile.accountId,
      expectedFingerprint: fingerprint,
    );
    final signing = crypto.sodium.crypto.sign.keyPair();
    final encryption = crypto.sodium.crypto.box.keyPair();
    late Map<String, dynamic> local;
    try {
      local = _newState(
        signing,
        encryption,
        AccountRecoveryMaterial(
          file: Uint8List(0),
          encryptedRoot: bundle['encryptedRoot'] as Map<String, dynamic>,
          signingPublicKey: root.signing.publicKey,
          encryptionPublicKey: root.encryption.publicKey,
          fingerprint: fingerprint,
        ),
      );
      local['phase'] = 'verified';
      local['generationFloor'] = remote['generation'];
      local['revocations'] = previous?['revocations'] ?? [];
      if (retired != null) local['retiredRecoveryRequests'] = retired;
      _rememberRevocations(local, remote);
      local['pendingRecoveryStart'] = crypto.sign(
        _command('crypto.account.recoveryStart', {
          'expectedGeneration': remote['generation'],
        }, signer: 'root'),
        root.signing.secretKey,
      );
      local['pending'] = crypto.sign(
        _command('crypto.device.add', {
          'expectedGeneration': (remote['generation'] as int) + 1,
          'deviceId': session.profile.deviceId,
          'signingKeyBase64': base64Encode(signing.publicKey),
          'encryptionKeyBase64': base64Encode(encryption.publicKey),
          'keyringWrite': true,
          'manageDevices': true,
        }, signer: 'root'),
        root.signing.secretKey,
      );
      await _write(local);
    } finally {
      root.dispose();
      signing.secretKey.dispose();
      encryption.secretKey.dispose();
    }
    // No root or recovery secret survives the limited authorization step.
    await _sendPending(local);
  });

  /// Verifies the independently pinned root and every device authorization.
  /// The minimum generation prevents rollback on an already trusted device;
  /// fresh-device freshness still requires the documented independent review.
  void verifyStatus(
    Map<String, dynamic> remote, {
    required String fingerprint,
    required int minimumGeneration,
  }) {
    if (remote['initialized'] != true ||
        remote['serverId'] != session.profile.serverId ||
        remote['accountId'] != session.profile.accountId ||
        remote['generation'] is! int ||
        (remote['generation'] as int) < minimumGeneration) {
      throw const AccountCryptoException('crypto_rollback');
    }
    final rootSigning = cryptoBase64(
      remote['rootSigningKeyBase64'],
      length: 32,
    );
    final rootEncryption = cryptoBase64(
      remote['rootEncryptionKeyBase64'],
      length: 32,
    );
    if (crypto.fingerprint(rootSigning, rootEncryption) != fingerprint) {
      throw const AccountCryptoException('crypto_root_changed');
    }
    final genesis = crypto.verify(
      remote['genesisCertificate'] as Map<String, dynamic>,
      rootSigning,
    );
    _bound(genesis);
    final genesisPayload = genesis['payload'] as Map<String, dynamic>;
    if (genesis['operation'] != 'crypto.account.initialize' ||
        genesis['signer'] != 'root' ||
        genesisPayload['expectedGeneration'] != 0 ||
        genesisPayload['rootSigningKeyBase64'] !=
            remote['rootSigningKeyBase64'] ||
        genesisPayload['rootEncryptionKeyBase64'] !=
            remote['rootEncryptionKeyBase64'] ||
        genesisPayload['keyringCiphertextBase64'] !=
            remote['keyringCiphertextBase64']) {
      throw const AccountCryptoException('crypto_genesis');
    }
    final devices = (remote['devices'] as List).cast<Map<String, dynamic>>();
    if (devices.map((d) => d['deviceId']).toSet().length != devices.length) {
      throw const AccountCryptoException('crypto_duplicate_device');
    }
    for (final device in devices) {
      _verifyDevice(
        device,
        devices,
        rootSigning,
        <String>{},
        remote['genesisCertificate'] as Map<String, dynamic>,
      );
    }
    final head = _verifyAccountProof(
      remote['generationCertificate'],
      devices,
      rootSigning,
    );
    if (((head['payload'] as Map)['expectedGeneration'] as int) + 1 !=
        remote['generation']) {
      throw const AccountCryptoException('crypto_generation_proof');
    }
    final keyring = _verifyAccountProof(
      remote['keyringCertificate'],
      devices,
      rootSigning,
    );
    if (!const {
          'crypto.account.initialize',
          'crypto.account.keyringEntriesPut',
        }.contains(keyring['operation']) ||
        ((keyring['payload'] as Map)['expectedGeneration'] as int) >=
            (remote['generation'] as int)) {
      throw const AccountCryptoException('crypto_keyring_proof');
    }
  }

  Map<String, dynamic> _verifyAccountProof(
    Object? proof,
    List<Map<String, dynamic>> devices,
    Uint8List root,
  ) {
    final signed = proof as Map<String, dynamic>;
    final raw =
        CryptoJson.decode(cryptoBase64(signed['commandBase64']))
            as Map<String, dynamic>;
    Uint8List publicKey = root;
    if (raw['signer'] == 'device') {
      final signer = devices
          .where((d) => d['deviceId'] == raw['deviceId'])
          .single;
      final operation = raw['operation'];
      if (!const {
            'crypto.account.keyringEntriesPut',
            'crypto.device.add',
            'crypto.device.revoke',
          }.contains(operation) ||
          (operation == 'crypto.account.keyringEntriesPut' &&
              signer['keyringWrite'] != true) ||
          _authorizationGeneration(signer) >=
              ((raw['payload'] as Map)['expectedGeneration'] as int) ||
          (const {
                'crypto.device.add',
                'crypto.device.revoke',
              }.contains(operation) &&
              signer['manageDevices'] != true) ||
          (signer['revoked'] == true &&
              _revocationGeneration(signer) <=
                  ((raw['payload'] as Map)['expectedGeneration'] as int))) {
        throw const AccountCryptoException('crypto_head_authorization');
      }
      publicKey = cryptoBase64(signer['signingKeyBase64'], length: 32);
    } else if (raw['signer'] != 'root' ||
        !const {
          'crypto.account.initialize',
          'crypto.device.add',
          'crypto.device.revoke',
          'crypto.account.recoveryStart',
        }.contains(raw['operation'])) {
      throw const AccountCryptoException('crypto_head_authorization');
    }
    final verified = crypto.verify(signed, publicKey);
    _bound(verified);
    return verified;
  }

  void _bound(Map<String, dynamic> command) {
    if (command['version'] != 1 ||
        command['serverId'] != session.profile.serverId ||
        command['accountId'] != session.profile.accountId) {
      throw const AccountCryptoException('crypto_command_identity');
    }
  }

  Map<String, dynamic> _verifyDevice(
    Map<String, dynamic> device,
    List<Map<String, dynamic>> devices,
    Uint8List root,
    Set<String> visited,
    Map<String, dynamic> genesisCertificate,
  ) {
    final id = device['deviceId'] as String;
    if (!visited.add(id)) {
      throw const AccountCryptoException('crypto_certificate_cycle');
    }
    final certificate = device['certificate'] as Map<String, dynamic>;
    final raw =
        CryptoJson.decode(cryptoBase64(certificate['commandBase64']))
            as Map<String, dynamic>;
    Uint8List signingKey = root;
    Map<String, dynamic>? manager;
    if (raw['signer'] == 'device') {
      manager = devices.where((d) => d['deviceId'] == raw['deviceId']).single;
      final managerCertificate = _verifyDevice(manager, devices, root, {
        ...visited,
      }, genesisCertificate);
      if (manager['manageDevices'] != true ||
          ((managerCertificate['payload'] as Map)['expectedGeneration']
                  as int) >=
              ((raw['payload'] as Map)['expectedGeneration'] as int)) {
        throw const AccountCryptoException('crypto_device_delegation');
      }
      if (manager['revoked'] == true &&
          _revocationGeneration(manager) <=
              ((raw['payload'] as Map)['expectedGeneration'] as int)) {
        throw const AccountCryptoException('crypto_revoked_delegation');
      }
      signingKey = cryptoBase64(manager['signingKeyBase64'], length: 32);
    } else if (raw['signer'] != 'root') {
      throw const AccountCryptoException('crypto_signer');
    }
    final command = crypto.verify(certificate, signingKey);
    _bound(command);
    final payload = command['payload'] as Map<String, dynamic>;
    if (command['operation'] == 'crypto.account.initialize') {
      if (command['signer'] != 'root' ||
          payload['expectedGeneration'] != 0 ||
          !_sameProof(certificate, genesisCertificate) ||
          command['deviceId'] != id ||
          payload['deviceSigningKeyBase64'] != device['signingKeyBase64'] ||
          payload['deviceEncryptionKeyBase64'] !=
              device['encryptionKeyBase64'] ||
          device['manageDevices'] != true ||
          device['keyringWrite'] != true) {
        throw const AccountCryptoException('crypto_device_certificate');
      }
    } else if (command['operation'] != 'crypto.device.add' ||
        payload['deviceId'] != id ||
        payload['signingKeyBase64'] != device['signingKeyBase64'] ||
        payload['encryptionKeyBase64'] != device['encryptionKeyBase64'] ||
        payload['manageDevices'] != device['manageDevices'] ||
        payload['keyringWrite'] != device['keyringWrite'] ||
        (manager != null &&
            payload['keyringWrite'] == true &&
            manager['keyringWrite'] != true)) {
      throw const AccountCryptoException('crypto_device_certificate');
    }
    if (device['revoked'] == true) {
      final revoke = device['revocationCertificate'] as Map<String, dynamic>;
      final decoded =
          CryptoJson.decode(cryptoBase64(revoke['commandBase64']))
              as Map<String, dynamic>;
      Uint8List revoker = root;
      if (decoded['signer'] == 'device') {
        final source = devices
            .where((d) => d['deviceId'] == decoded['deviceId'])
            .single;
        if (source['manageDevices'] != true) {
          throw const AccountCryptoException('crypto_revoke');
        }
        final revokeGeneration =
            (decoded['payload'] as Map)['expectedGeneration'] as int;
        if (_authorizationGeneration(source) >= revokeGeneration ||
            (source['revoked'] == true &&
                (_revocationGeneration(source) < revokeGeneration ||
                    (_revocationGeneration(source) == revokeGeneration &&
                        source['deviceId'] != id)))) {
          throw const AccountCryptoException('crypto_revocation_authorization');
        }
        // All device certificates are separately walked by verifyStatus. This
        // avoids recursive cycles in valid mutual revocations.
        revoker = cryptoBase64(source['signingKeyBase64'], length: 32);
      } else if (decoded['signer'] != 'root') {
        throw const AccountCryptoException('crypto_revoke');
      }
      final verified = crypto.verify(revoke, revoker);
      _bound(verified);
      if (verified['operation'] != 'crypto.device.revoke' ||
          (verified['payload'] as Map)['deviceId'] != id ||
          ((verified['payload'] as Map)['expectedGeneration'] as int) <=
              (payload['expectedGeneration'] as int)) {
        throw const AccountCryptoException('crypto_revoke');
      }
    } else if (device['revoked'] != false ||
        device['revocationCertificate'] != null) {
      throw const AccountCryptoException('crypto_revoke');
    }
    return command;
  }

  int _revocationGeneration(Map<String, dynamic> device) {
    final certificate = device['revocationCertificate'] as Map<String, dynamic>;
    final command =
        CryptoJson.decode(cryptoBase64(certificate['commandBase64']))
            as Map<String, dynamic>;
    return (command['payload'] as Map)['expectedGeneration'] as int;
  }

  int _authorizationGeneration(Map<String, dynamic> device) {
    final certificate = device['certificate'] as Map<String, dynamic>;
    final command =
        CryptoJson.decode(cryptoBase64(certificate['commandBase64']))
            as Map<String, dynamic>;
    return (command['payload'] as Map)['expectedGeneration'] as int;
  }
}
