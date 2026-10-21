import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/widgets.dart'
    show WidgetsBinding, WidgetsBindingObserver, AppLifecycleState;
import 'package:cryptography/cryptography.dart' show Sha256;
import 'package:sodium/sodium.dart' show KeyPair;
import 'recovery_file_codec.dart';

import 'account_crypto_v2_workflow.dart';
import 'account_directory_v2.dart';
import 'account_directory_repository.dart'
    show CryptoDirectoryAuthoritySnapshot;
import 'crypto_identity_verification.dart';
import 'crypto_json.dart';
import 'crypto_record_proof_codec.dart';
import 'crypto_record_address.dart' show isCryptoCanonicalUuid;
import 'crypto_sync_repository.dart';
import 'crypto_blob_window_policy.dart';
import 'scope_crypto_codec.dart';
import 'crypto_scoped_exports.dart';
import 'crypto_directory_promotion.dart';
import 'crypto_lifecycle_evidence.dart';
import 'crypto_authority_operation_policy.dart';
import 'crypto_scope_anchor.dart';
import 'crypto_scope_observations.dart';
import 'crypto_business_lifecycle.dart';
import 'crypto_business_moderation.dart';
import 'crypto_business_deletion.dart';
import 'crypto_inline_deletion_evidence.dart';
import 'crypto_business_inline_deletion.dart';
import 'crypto_migration_committed_origin.dart';
import 'crypto_migration_own_attestation.dart';
import 'crypto_project_relocation_evidence.dart';
import 'crypto_project_relocation_recovery.dart';
import 'crypto_project_relocation_codec.dart';
import 'crypto_business_project_relocation.dart';
import 'crypto_business_router.dart' show CryptoBusinessSession;
import 'crypto_finance_policy_actions.dart' show CryptoFinancePolicySnapshot;
import 'invite_crypto_repository.dart';

final _readOnlyFrozenScopeZone = Object();
final _deletedScopeEvidenceZone = Object();
final _scopeDescriptorVerificationZone = Object();

class _ScopeDescriptorVerification {
  _ScopeDescriptorVerification(
    this.owner,
    this.descriptors,
    this.genesisAnchors,
    this.publications,
    this.genesisDescriptors,
  );
  final SessionCryptoAccess owner;
  final Map<String, Map<String, dynamic>> descriptors;
  final Map<String, Map<String, String>> genesisAnchors;
  final Map<String, List<Map<String, dynamic>>> publications;
  final Map<String, VerifiedCryptoMigrationGenesisDescriptor>
  genesisDescriptors;
  bool active = true;
}

/// Completeness/discovery evidence created only after a full normal recovery
/// verification succeeds. It grants no head, key, signing or write capability.
class VerifiedRecoveredMigrationGenesis {
  VerifiedRecoveredMigrationGenesis._(
    this.scopeId,
    this.headHash,
    this.migrationId,
  );
  final String scopeId, headHash, migrationId;
}

final class _DescriptorPolicyCarrierPending implements Exception {
  const _DescriptorPolicyCarrierPending();
}

final class _DescriptorCarrierBudget {
  int heads = 0, bytes = 0;
}

final class _DescriptorObservationHistory {
  _DescriptorObservationHistory(this.scope, this.ownHead, this.observations);
  final String scope, ownHead;
  final List<Map<String, dynamic>> observations;
}

/// Private descriptor transport only: a cryptographically checked scoped
/// admission whose policy semantics must be rechecked after the baseline opens.
/// It cannot authorize ordinary records, a floor, or persistent key material.
final class CryptoMigrationDescriptorAdmission {
  CryptoMigrationDescriptorAdmission._(
    this._access,
    this._genesis,
    this._carrier,
    this._wire,
    this._ownHead,
    List<VerifiedScopeHead> chain,
    this._invitationAnchor,
    this._observationHash,
    this._observationGeneration,
    this._observationHistory,
  ) : _chain = List.unmodifiable(chain);
  final SessionCryptoAccess _access;
  final VerifiedScopeHead _genesis, _carrier;
  final List<VerifiedScopeHead> _chain;
  final String? _invitationAnchor, _observationHash;
  final int? _observationGeneration;
  final _DescriptorObservationHistory? _observationHistory;
  final Map<String, dynamic> _wire;
  final String _ownHead;
  bool _active = true;
  Future<void> requireContext(
    SessionCryptoAccess access,
    String scope,
    String genesisHash,
  ) async {
    if (!_active ||
        !identical(access, _access) ||
        scope != _genesis.scopeId ||
        genesisHash != _genesis.headHash ||
        _carrier.scopeId != scope ||
        _chain.first.headHash != genesisHash ||
        _chain.last.headHash != _carrier.headHash ||
        !access.account.directory.isCurrent() ||
        (await access.account.directory.cachedVerifiedDirectory()).headHash !=
            _ownHead) {
      throw const CryptoAuthorityPending('scope_descriptor_admission_changed');
    }
    if (_observationHash != null) {
      final history = _observationHistory;
      if (_invitationAnchor != null ||
          history == null ||
          history.scope != scope ||
          history.ownHead != _ownHead ||
          !history.observations.any(
            (o) =>
                o['headHash'] == _carrier.headHash &&
                o['observationHash'] == _observationHash &&
                o['generation'] == _observationGeneration,
          )) {
        throw const CryptoAuthorityPending(
          'scope_descriptor_admission_changed',
        );
      }
      return;
    }
    if (_invitationAnchor == null ||
        !_chain.any((h) => h.headHash == _invitationAnchor) ||
        access._invitationScope != scope ||
        access._invitationHead != _invitationAnchor) {
      throw const CryptoAuthorityPending('scope_descriptor_admission_changed');
    }
    await access.identities.requireVerified(
      access._inviterAccount!,
      access._inviterFingerprint!,
    );
  }
}

/// An exact finalized publication anchored by OWN signed lineage or an
/// independently verified scoped invitation/observation. The private constructor
/// prevents a wire marker, SQL flag or caller-supplied map granting the non-owner
/// genesis exception. It is never a prepared-target or key-disclosure capability.
class VerifiedProjectRelocationGenesis {
  VerifiedProjectRelocationGenesis._(
    this.scopeId,
    this.headHash,
    Map<String, dynamic> header,
    this.ownerAccountId,
  ) : header = Map<String, dynamic>.unmodifiable(header);
  final String scopeId, headHash, ownerAccountId;
  final Map<String, dynamic> header;
  Map<String, dynamic> get proposalContext => Map.unmodifiable({
    'version': 2,
    'actionId': header['actionId'],
    'planHash': header['planHash'],
    'expectedOwnerAccountId': ownerAccountId,
  });
  Map<String, dynamic> get activationContext => Map.unmodifiable({
    'version': 2,
    'actionId': header['actionId'],
    'planHash': header['planHash'],
  });
}

/// Deliberately separate from finalized admission. This token is returned only
/// for private shadow validation and is never installed in Session head/floor
/// caches. Its key bytes remain pending until the atomic published move.
class PreparedProjectRelocationGenesis
    extends VerifiedProjectRelocationGenesis {
  PreparedProjectRelocationGenesis._(
    super.scopeId,
    super.headHash,
    super.header,
    super.ownerAccountId,
  ) : super._();
}

/// Preparation evidence only. It cannot install a scope floor or authorize
/// normal records. Every use rechecks the captured own directory generation.
class CryptoMigrationCandidate {
  CryptoMigrationCandidate._(
    this._access,
    this.head,
    this.migrationId,
    this.captureId,
    this._ownHead,
    this._wire,
    this._domains,
  );
  final SessionCryptoAccess _access;
  final VerifiedScopeHead head;
  final String migrationId, captureId, _ownHead;
  final Map<String, dynamic> _wire;
  final Set<String> _domains;
  bool isFor(SessionCryptoAccess access, String scopeId) =>
      identical(_access, access) && head.scopeId == scopeId;
  Future<void> _guard() async {
    final own = await _access.account.directory.requireFresh();
    if (!_access.account.directory.isCurrent() ||
        own.headHash != _ownHead ||
        head.member(own.accountId)['deviceSnapshotHash'] !=
            own.deviceSnapshotHash) {
      throw const CryptoAuthorityPending('crypto_migration_candidate_changed');
    }
  }

  Future<CryptoKeyLease> key(String domain) async {
    await _guard();
    if (!_domains.contains(domain) ||
        domain == 'finance' &&
            head.member(_access.account.directory.accountId)['financeRole'] ==
                'none') {
      throw const CryptoAuthorityPending('crypto_migration_candidate_read');
    }
    return _access.candidateKey(head, domain);
  }

  Future<String> lifecycleHash() async {
    await _guard();
    final page = await _access._scopeCall('crypto2.scope.lifecycle.list', {
      'scopeId': head.scopeId,
      'afterRevision': 0,
      'limit': 20,
    });
    if (page['states'] is! List ||
        (page['states'] as List).isNotEmpty ||
        page['hasMore'] != false ||
        page['currentRevision'] != 0) {
      throw const CryptoAuthorityPending(
        'crypto_migration_candidate_lifecycle_pending',
      );
    }
    return cryptoZeroHash;
  }
}

class _DeletedScopeEvidence {
  _DeletedScopeEvidence(this.scopeId);
  final String scopeId;
  bool active = true;
}

class _ReadOnlyFrozenScope {
  _ReadOnlyFrozenScope(this.scopeId, this.headHash, this.own, this.ownAnchor);
  final String scopeId, headHash, ownAnchor;
  final VerifiedAccountDirectory own;
  bool active = true;
}

class _BlobLifecycleEpoch with WidgetsBindingObserver {
  _BlobLifecycleEpoch() {
    WidgetsBinding.instance.addObserver(this);
  }
  static _BlobLifecycleEpoch? _shared;
  static _BlobLifecycleEpoch? get shared {
    try {
      return _shared ??= _BlobLifecycleEpoch();
    } catch (_) {
      return null;
    }
  }

  int generation = 0;
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) generation++;
  }
}

class _BlobAuthorityWindow {
  _BlobAuthorityWindow(
    this.common,
    this.ownSnapshot,
    this.scopePin,
    this.members,
    this.lifecycle,
    this.manifestHash,
    this.sourceProofHash,
  ) : timer = Stopwatch()..start();
  final Map<String, dynamic> common;
  final String ownSnapshot;
  final String? scopePin;
  final Map<String, String> members;
  final int lifecycle;
  final Stopwatch timer;
  final String manifestHash, sourceProofHash;
  int bytes = 0;
}

class CryptoCheckpointAuthority {
  const CryptoCheckpointAuthority({
    required this.head,
    required this.historyBasis,
  });
  final VerifiedScopeHead head;
  final String historyBasis;
}

class CryptoWriteContext {
  const CryptoWriteContext({
    required this.headHash,
    required this.epoch,
    required this.accessRevision,
    required this.contentContract,
    required this.keyId,
    required this.key,
  });
  final String headHash, keyId;
  final int epoch, accessRevision, contentContract;
  final CryptoKeyLease key;
}

/// Opaque original-operation authority for one combined materialized read.
class CryptoVerifiedReadLease {
  CryptoVerifiedReadLease._(
    this._owner,
    this._generation,
    this._lifecycle,
    this._watch,
    this._pins,
  );
  final SessionCryptoAccess _owner;
  final int _generation;
  final int? _lifecycle;
  final Stopwatch _watch;
  final Map<String, String?> _pins;
}

/// The production bridge between signed membership, local vault keys and sync.
/// Missing authority remains pending; malformed cryptographic evidence fails.
class _AuthorityOperation {
  _AuthorityOperation(this.owner)
    : generation = owner._authorityGeneration,
      lifecycle = _BlobLifecycleEpoch.shared?.generation;
  final SessionCryptoAccess owner;
  final int generation;
  final int? lifecycle;
  final watch = Stopwatch()..start();
  bool active = true;
  final heads = <String, VerifiedScopeHead>{};
  final directories = <String, VerifiedAccountDirectory>{};
  final pins = <String, String?>{};
}

/// Retains the SAME proof memo, transport snapshot and original clock across
/// sequential consumers of one combined financial read. Closed handles never
/// resume; their callers fall back to ordinary independently verified reads.
class CryptoVerifiedReadOperation {
  CryptoVerifiedReadOperation._(this._owner);
  final SessionCryptoAccess _owner;
  _AuthorityOperation? _operation;
  CryptoDirectoryAuthoritySnapshot? _snapshot;
  bool _active = true, _running = false;

  void close() {
    _active = false;
    final operation = _operation;
    if (operation != null) {
      operation.active = false;
      operation.heads.clear();
      operation.directories.clear();
      operation.pins.clear();
    }
    _snapshot?.close();
  }

  void _discard() {
    if (!_active) return;
    close();
    _owner.invalidateAuthorityOperation();
  }

  Future<T> run<T>(Future<T> Function() body) async {
    if (_running) _discard();
    if (!_active) return _owner.withVerifiedOperation(body);
    _running = true;
    final operation = _operation ??= _AuthorityOperation(_owner);
    final snapshot = _snapshot ??= _owner.account.directory
        .createAuthoritySnapshot(
          isValid: () async =>
              _active &&
              identical(_owner._operation, operation) &&
              await _owner._operationPinsValid(operation),
          onMutation: _discard,
          onFailure: _discard,
        );
    try {
      return await runZoned(
        () => snapshot.run(() async {
          if (!await _owner._operationPinsValid(operation)) {
            _discard();
            return _owner.withVerifiedOperation(body);
          }
          final result = await body();
          if (_active && !await _owner._operationPinsValid(operation)) {
            _discard();
          }
          return result;
        }),
        zoneValues: {
          SessionCryptoAccess._operationKey: operation,
          SessionCryptoAccess._retainedReadKey: this,
        },
      );
    } catch (_) {
      _discard();
      rethrow;
    } finally {
      _running = false;
    }
  }
}

/// A read-only capability for one exact authenticated predecessor chain.
/// Only SessionCryptoAccess can construct it; no caller-supplied cursor or hash
/// can establish historical authority on its own.
class CryptoHistoryChain {
  CryptoHistoryChain._(
    this._access,
    this.scopeId,
    this.domain,
    this.id,
    this._revision,
    this._hash,
    this.historyBasis,
    this._guard,
    this._historicalAnchored,
    this._goalRevision,
    this._goalHash,
    this._evidenceFor,
  );
  final SessionCryptoAccess _access;
  final String scopeId, domain, id, historyBasis;
  int _revision;
  String _hash;
  bool _historicalAnchored;
  final int? _goalRevision;
  final String? _goalHash;
  final Map<String, dynamic> _evidenceFor;
  final Future<void> Function() _guard;
  Future<void> _tail = Future<void>.value();
  int get nextRevision => _revision;
  String get nextHash => _hash;
  bool get complete => _revision == 0 && _hash == cryptoZeroHash;

  Future<CryptoRecordAuthority> authority(Map<String, dynamic> wire) async {
    final prior = _tail, finished = Completer<void>();
    _tail = finished.future;
    await prior;
    try {
      await _guard();
      if (_revision == 0)
        throw const FormatException('crypto_history_chain_complete');
      if (_revision == _goalRevision && _hash != _goalHash) {
        throw const FormatException('crypto_history_reference_fork');
      }
      final codec = CryptoRecordProofCodec(
        _access.account.directory.reducer.crypto,
      );
      final proof = Map<String, dynamic>.from(
        (wire['authorization'] as Map)['recordProof'] as Map,
      );
      final body = Map<String, dynamic>.from(
        CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map,
      );
      codec.validateUntrustedRecord(body);

      if (body['scopeId'] != scopeId ||
          body['domain'] != domain ||
          body['id'] != id ||
          wire['revision'] != _revision ||
          body['expectedRevision'] != _revision - 1 ||
          await codec.digest(proof) != _hash) {
        throw const FormatException('crypto_history_chain_substitution');
      }
      if ((body['metadata'] as Map).containsKey('inlineDeletion') ||
          (body['metadata'] as Map).containsKey('projectRelocation')) {
        final publication =
            (body['metadata'] as Map).containsKey('projectRelocation')
            ? await _access._projectRelocation.authority(body)
            : await _access._inlineDeletion.authority(body);
        await codec.verifyWire(
          serverId: _access.account.directory.session.profile.serverId,
          wire: wire,
          trustedSigningKey: publication.signingKey,
          currentEpoch: false,
          closedRecordProofHash: publication.closedRecordProofHash,
        );
        await _guard();
        final next = body['previousRecordHash'] as String;
        if (_revision - 1 == _goalRevision && next != _goalHash) {
          throw const FormatException('crypto_history_reference_fork');
        }
        if (_revision == 1 && next != cryptoZeroHash) {
          throw const FormatException('crypto_history_genesis_chain');
        }
        // This exact included publication proves existence of the tombstone,
        // and hence the signed same-record predecessor chain, only here.
        _historicalAnchored = true;
        _revision--;
        _hash = next;
        return publication;
      }
      if ((body['metadata'] as Map).containsKey('migrationOrigin')) {
        // Even an exact authenticated ancestor cannot turn a READ-authored
        // migration base into an ordinary writer. Its finalized origin is
        // mandatory in both current and historical paths.
        final origin = await _access._committedOrigin.authority(
          body,
          evidenceFor: _evidenceFor,
        );
        if (_revision != 1 ||
            body['previousRecordHash'] != cryptoZeroHash ||
            origin.closedRecordProofHash != _hash) {
          throw const FormatException('crypto_migration_history_origin');
        }
        await codec.verifyWire(
          serverId: _access.account.directory.session.profile.serverId,
          wire: wire,
          trustedSigningKey: origin.signingKey,
          currentEpoch: origin.currentEpoch,
          closedRecordProofHash: origin.closedRecordProofHash,
        );
        await _guard();
        _revision = 0;
        _hash = cryptoZeroHash;
        return origin;
      }
      final head = await _access.headAt(scopeId, body['membershipHeadHash']);
      if (head.epoch != body['epoch'] ||
          head.accessRevision != body['accessRevision']) {
        throw const FormatException('record_membership_substitution');
      }
      final member = head.member(body['accountId']);
      if (member['role'] == 'viewer' ||
          domain == 'finance' && member['financeRole'] != 'write') {
        throw const FormatException('record_author_role');
      }
      final author = await _access.directoryAt(
        scopeId: scopeId,
        scopeHeadHash: head.headHash,
        accountId: body['accountId'],
        directoryHeadHash: member['directoryHeadHash'],
      );
      final key = cryptoBase64(
        author.activeDevice(body['deviceId'])['signingKeyBase64'],
        length: 32,
      );
      final independent = _historicalAnchored
          ? null
          : await _access.recordAuthority(body);
      await codec.verifyWire(
        serverId: _access.account.directory.session.profile.serverId,
        wire: wire,
        trustedSigningKey: key,
        currentEpoch: independent?.currentEpoch ?? false,
        closedRecordProofHash: _historicalAnchored
            ? _hash
            : independent?.closedRecordProofHash,
      );
      final currentHead = await _access.currentHead(scopeId);
      final newlyAnchored =
          (currentHead.headHash != body['membershipHeadHash'] &&
              independent?.closedRecordProofHash == _hash) ||
          await _access._observedRecordHash(scopeId, domain, body) == _hash;
      final result = CryptoRecordAuthority(
        signingKey: key,
        currentEpoch: independent?.currentEpoch ?? false,
        closedRecordProofHash: _historicalAnchored
            ? _hash
            : independent?.closedRecordProofHash,
        historyBasis: independent?.historyBasis ?? historyBasis,
      );
      await _guard();
      final next = body['previousRecordHash'] as String;
      if (_revision - 1 == _goalRevision && next != _goalHash) {
        throw const FormatException('crypto_history_reference_fork');
      }
      if (_revision == 1 && next != cryptoZeroHash) {
        throw const FormatException('crypto_history_genesis_chain');
      }
      _historicalAnchored = _historicalAnchored || newlyAnchored;
      _revision--;
      _hash = next;
      return result;
    } on TypeError {
      throw const FormatException('crypto_history_chain_shape');
    } finally {
      finished.complete();
    }
  }
}

/// Proposal-policy context for one explicitly reviewed historical candidate.
/// It cannot establish a normal current head, scope floor, key or WRITE lease.
final class VerifiedScopeRecoveryPolicy {
  VerifiedScopeRecoveryPolicy._(
    this._access,
    this._source,
    this._ownHeadHash,
    this._scopePin,
    this._accessPolicyVersion,
  );
  final SessionCryptoAccess _access;
  final VerifiedScopeHead _source;
  final String _ownHeadHash;
  final String? _scopePin;
  final int _accessPolicyVersion;
  bool _active = true;
  int get accessPolicyVersion {
    if (!_active) {
      throw const CryptoAuthorityPending('scope_review_changed');
    }
    return _accessPolicyVersion;
  }

  Future<void> _guard() async {
    if (!_active || !_access.account.directory.isCurrent()) {
      throw const CryptoAuthorityPending('scope_review_changed');
    }
    final current = await _access.recoveryCandidateHead(_source.scopeId);
    final own = await _access.account.directory.requireFresh();
    if (!_active ||
        !_access.account.directory.isCurrent() ||
        current.headHash != _source.headHash ||
        own.headHash != _ownHeadHash ||
        await _access.account.store.secure.read(
              'scope2:${_access.account.store.partition}:${_source.scopeId}',
            ) !=
            _scopePin ||
        _access._knownPolicyVersion(_source.scopeId, current) !=
            accessPolicyVersion) {
      throw const CryptoAuthorityPending('scope_review_changed');
    }
    current.member(own.accountId);
  }
}

class SessionCryptoAccess {
  SessionCryptoAccess({
    required this.account,
    this.pendingCapability,
    Map<String, dynamic>? invitationAnchor,
  }) : _scopeAnchorProof = invitationAnchor;

  /// A recipient-scoped accepted invitation capability grants proof reads only.
  final Map<String, dynamic>? pendingCapability;

  /// A verified inviter's signature binds an exact scoped history anchor. It
  /// grants no global identity pin and no authority to issue new key grants.
  Map<String, dynamic>? _scopeAnchorProof;
  String? _inviterAccount, _inviterFingerprint;
  String? _invitationScope, _invitationHead;
  final _observedScopes = <String, List<Map<String, dynamic>>>{};
  final _ownRelocationAnchors = <String, Map<String, dynamic>>{};
  final _relocationGenesis = <String, VerifiedProjectRelocationGenesis>{};
  String? _checkedRelocationOwnHead;
  bool _hasScopedIdentityAnchor(String scope) =>
      _invitationScope == scope ||
      _observedScopes.containsKey(scope) ||
      _ownRelocationAnchors.containsKey(scope);

  Future<bool> _hasCommittedMigrationIdentity(String scope, String head) async {
    final anchor = _committedGenesisAnchors[scope];
    if (anchor == null || anchor['headHash'] != head) return false;
    if (!account.directory.isCurrent() ||
        (await account.directory.cachedVerifiedDirectory()).headHash !=
            anchor['ownHeadHash']) {
      throw const CryptoAuthorityPending('scope_recovery_publication_changed');
    }
    return true;
  }

  Future<void> _requireCurrentMemberIdentity(
    String scope,
    String head,
    VerifiedAccountDirectory directory,
  ) async {
    if (directory.accountId == account.directory.accountId) return;
    try {
      await identities.requireVerified(
        directory.accountId,
        identities.fingerprint(directory),
      );
      return;
    } on CryptoAuthorityPending catch (error) {
      if (error.reason != 'identity_verification_required') rethrow;
    }
    if (!await _hasCommittedMigrationIdentity(scope, head)) {
      throw const CryptoAuthorityPending('identity_verification_required');
    }
    final baseline =
        (_descriptorVerification?.genesisDescriptors ??
        _verifiedGenesisDescriptors)[scope];
    final members = baseline?.identityMembers
        .where((m) => m['accountId'] == directory.accountId)
        .toList();
    if (baseline?.headHash != head ||
        members == null ||
        members.length != 1 ||
        directory.snapshot['rootSigningKeyBase64'] !=
            members.single['rootSigningKeyBase64'] ||
        directory.snapshot['rootEncryptionKeyBase64'] !=
            members.single['rootEncryptionKeyBase64']) {
      throw const CryptoAuthorityPending('identity_verification_required');
    }
    final referenced = await directoryAt(
      scopeId: scope,
      scopeHeadHash: head,
      accountId: directory.accountId,
      directoryHeadHash: members.single['directoryHeadHash'],
      online: true,
    );
    if (!directory.includesAnchor(referenced.generation, referenced.headHash)) {
      throw const FormatException('directory_known_fork');
    }
    if (!await _hasCommittedMigrationIdentity(scope, head)) {
      throw const CryptoAuthorityPending('scope_recovery_publication_changed');
    }
  }

  // Prepares only a proven forward reference, without contact promotion.
  // The returned local-only guard can run inside the scope-anchor lock.
  Future<Future<void> Function()?> _prepareForwardDirectoryReference({
    required String scopeId,
    required String scopeHeadHash,
    required String accountId,
    required String directoryHeadHash,
    required String deviceSnapshotHash,
    required Map<String, dynamic> known,
    VerifiedAccountDirectory? verifiedReference,
  }) async {
    final referenced =
        verifiedReference ??
        await directoryAt(
          scopeId: scopeId,
          scopeHeadHash: scopeHeadHash,
          accountId: accountId,
          directoryHeadHash: directoryHeadHash,
          online: true,
        );
    if (referenced.accountId != accountId ||
        referenced.headHash != directoryHeadHash ||
        referenced.deviceSnapshotHash != deviceSnapshotHash) {
      throw const FormatException('directory_snapshot_substitution');
    }
    // Older references retain the existing own-observation/publication route.
    // They must not acquire new freshness/network requirements from this fix.
    if (!cryptoScopeKnownForwardRoot(known: known, referenced: referenced)) {
      return null;
    }
    final operation = _operation;
    final watch = operation?.watch ?? (Stopwatch()..start());
    final generation = _authorityGeneration;
    final lifecycle = _BlobLifecycleEpoch.shared?.generation;
    final ownPin = await account.store.anchor(account.directory.accountId);
    final knownBytes = base64Encode(CryptoJson.encode(known));
    final ownBytes = ownPin == null
        ? null
        : base64Encode(CryptoJson.encode(ownPin));
    Future<void> guard() async {
      if (!account.directory.isCurrent() ||
          generation != _authorityGeneration ||
          lifecycle != _BlobLifecycleEpoch.shared?.generation ||
          watch.elapsed >= const Duration(seconds: 5) ||
          operation != null &&
              (!identical(_operation, operation) ||
                  !await _operationPinsValid(operation))) {
        throw const CryptoAuthorityPending('authority_operation_incomplete');
      }
      final after = await account.store.anchor(accountId);
      final ownAfter = await account.store.anchor(account.directory.accountId);
      if (after == null ||
          base64Encode(CryptoJson.encode(after)) != knownBytes ||
          (ownAfter == null
                  ? null
                  : base64Encode(CryptoJson.encode(ownAfter))) !=
              ownBytes) {
        throw const CryptoAuthorityPending('directory_known_anchor_changed');
      }
      if (!account.directory.isCurrent() ||
          generation != _authorityGeneration ||
          lifecycle != _BlobLifecycleEpoch.shared?.generation ||
          watch.elapsed >= const Duration(seconds: 5)) {
        throw const CryptoAuthorityPending('authority_operation_incomplete');
      }
    }

    await guard();
    final current = await currentMemberDirectory(
      scopeId,
      scopeHeadHash,
      accountId,
    );
    await guard();
    if (!cryptoScopeForwardDirectoryReference(
      known: known,
      referenced: referenced,
      current: current,
    )) {
      return null;
    }
    return guard;
  }

  Future<bool> _isForwardKnownDirectoryReference({
    required String scopeId,
    required String scopeHeadHash,
    required String accountId,
    required String directoryHeadHash,
    required String deviceSnapshotHash,
    required Map<String, dynamic> known,
  }) async {
    final guard = await _prepareForwardDirectoryReference(
      scopeId: scopeId,
      scopeHeadHash: scopeHeadHash,
      accountId: accountId,
      directoryHeadHash: directoryHeadHash,
      deviceSnapshotHash: deviceSnapshotHash,
      known: known,
    );
    if (guard == null) {
      return false;
    }
    await guard();
    return true;
  }

  /// Scope-local identity continuity for an existing member of an already
  /// verified source head. It creates neither contact trust nor join authority.
  Future<void> requireExistingScopeMemberIdentity(
    VerifiedScopeHead source,
    VerifiedAccountDirectory directory,
  ) async {
    final member = source.members
        .where((m) => m['accountId'] == directory.accountId)
        .firstOrNull;
    bool sameIdentity(VerifiedAccountDirectory value) =>
        member != null &&
        value.snapshot['rootSigningKeyBase64'] ==
            member['rootSigningKeyBase64'] &&
        value.snapshot['rootEncryptionKeyBase64'] ==
            member['rootEncryptionKeyBase64'] &&
        value.snapshot['recoveryRootEpochId'] ==
            member['recoveryRootEpochId'] &&
        value.identityEpochId == member['identityEpochId'];
    if (sameIdentity(directory)) {
      final referenced = await directoryAt(
        scopeId: source.scopeId,
        scopeHeadHash: source.headHash,
        accountId: directory.accountId,
        directoryHeadHash: member!['directoryHeadHash'],
        online: true,
      );
      if (sameIdentity(referenced) &&
          referenced.deviceSnapshotHash == member['deviceSnapshotHash'] &&
          directory.includesAnchor(
            referenced.generation,
            referenced.headHash,
          )) {
        // The verified source roster authorizes only this unchanged identity
        // lineage. It creates no global contact pin or joining authority.
        return;
      }
    }
    await identities.requireVerified(
      directory.accountId,
      identities.fingerprint(directory),
    );
  }

  Future<void> _ensureOwnRelocationAnchors() async {
    final own = await account.directory.cachedVerifiedDirectory();
    if (_checkedRelocationOwnHead == own.headHash) return;
    final anchors = <String, Map<String, dynamic>>{};
    if (own
        .verifiedHeadersFor('crypto2.account.projectRelocation')
        .isNotEmpty) {
      await for (final included in CryptoProjectRelocationRecovery(
        this,
      ).discover()) {
        for (final header in [included.source, included.target]) {
          final scope = header['scopeId'] as String;
          // discover() follows the authenticated own lineage newest first.
          // Multiple inline projects may legitimately leave the same parent.
          anchors.putIfAbsent(scope, () => Map<String, dynamic>.from(header));
        }
      }
    }
    // These are independently included OWN publications, not restored SQL
    // anchor rows or foreign identities promoted into the global directory.
    final after = await account.directory.cachedVerifiedDirectory();
    if (after.headHash != own.headHash) {
      throw const CryptoAuthorityPending(
        'crypto_relocation_own_prefix_changed',
      );
    }
    _ownRelocationAnchors
      ..clear()
      ..addAll(anchors);
    _checkedRelocationOwnHead = own.headHash;
  }

  final _checkedObservedScopes = <String, String>{};
  final _verifiedGenesisAnchors = <String, Map<String, String>>{};
  final _verifiedGenesisPublications = <String, List<Map<String, dynamic>>>{};
  final _verifiedGenesisDescriptors =
      <String, VerifiedCryptoMigrationGenesisDescriptor>{};
  Map<String, Map<String, String>> get _committedGenesisAnchors =>
      _descriptorVerification?.genesisAnchors ?? _verifiedGenesisAnchors;

  /// Restricted evidence reads never expand their directory evidence online.
  bool get canReadAuthorDirectoryOnline =>
      _readOnlyFrozen == null &&
      Zone.current[_deletedScopeEvidenceZone] == null;

  _ReadOnlyFrozenScope? get _readOnlyFrozen =>
      Zone.current[_readOnlyFrozenScopeZone] as _ReadOnlyFrozenScope?;

  Future<void> requireReadOnlyFrozenScope(String scopeId) async {
    final context = _readOnlyFrozen;
    if (context == null || context.scopeId != scopeId) {
      throw const CryptoAuthorityPending(
        'crypto_frozen_source_context_required',
      );
    }
    await _guardReadOnlyFrozen(context);
  }

  /// Identity for an exact FILE-pinned scratch comparison, never live trust.
  Future<VerifiedAccountDirectory?> readOnlyFrozenDirectory(
    String scopeId,
    String candidateHeadHash,
  ) async {
    final context = _readOnlyFrozen;
    if (context == null) return null;
    if (context.scopeId != scopeId || context.headHash != candidateHeadHash) {
      throw const CryptoAuthorityPending(
        'crypto_frozen_source_context_required',
      );
    }
    await _guardReadOnlyFrozen(context);
    return context.own;
  }

  Future<T> withReadOnlyFrozenScope<T>({
    required String scopeId,
    required String candidateHeadHash,
    required Uint8List recoveryFile,
    required Future<T> Function() body,
  }) async {
    if (_readOnlyFrozen != null ||
        !isCryptoCanonicalUuid(scopeId) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(candidateHeadHash)) {
      throw const FormatException('crypto_frozen_source_context');
    }
    final info = account.files.inspect(
      recoveryFile,
      serverId: account.directory.session.profile.serverId,
      accountId: account.directory.accountId,
    );
    final own = await account.directory.replayFileAnchoredCandidate(
      info['fingerprint'],
    );
    final anchor = await account.store.secure.read(
      'directory2:${account.store.partition}:${own.accountId}',
    );
    if (anchor == null)
      throw const CryptoAuthorityPending('crypto_frozen_source_identity');
    final context = _ReadOnlyFrozenScope(
      scopeId,
      candidateHeadHash,
      own,
      anchor,
    );
    return runZoned(() async {
      try {
        await _guardReadOnlyFrozen(context);
        final result = await body();
        await _guardReadOnlyFrozen(context);
        return result;
      } finally {
        context.active = false;
        _heads.removeWhere((key, value) => value.scopeId == scopeId);
        _scopeDescriptors.remove(scopeId);
        _observedScopes.remove(scopeId);
        _checkedObservedScopes.remove(scopeId);
        _directories.clear();
      }
    }, zoneValues: {_readOnlyFrozenScopeZone: context});
  }

  Future<void> _guardReadOnlyFrozen(_ReadOnlyFrozenScope context) async {
    if (!context.active ||
        !account.directory.isCurrent() ||
        await account.store.secure.read(
              'directory2:${account.store.partition}:${context.own.accountId}',
            ) !=
            context.ownAnchor) {
      throw const CryptoAuthorityPending(
        'crypto_frozen_source_identity_changed',
      );
    }
  }

  Future<void> _ensureInvitationAnchor(
    String scopeId, {
    bool online = false,
  }) async {
    final ownHead =
        (await account.store.anchor(account.directory.accountId))?['headHash']
            as String?;
    if (_checkedObservedScopes[scopeId] != ownHead ||
        !_checkedObservedScopes.containsKey(scopeId)) {
      final observations = await CryptoScopeObservations(
        account,
      ).recover(scopeId, readOnlyOwnPrefix: _readOnlyFrozen?.own);
      if (observations.isNotEmpty) {
        _observedScopes[scopeId] = observations;
      } else {
        // recover() enumerates signed operation headers from the immutable
        // verified own lineage; an SQL index cannot manufacture this absence.
        _observedScopes.remove(scopeId);
      }
      _checkedObservedScopes[scopeId] =
          (await account.store.anchor(account.directory.accountId))?['headHash']
              as String? ??
          '';
    }
    if (_readOnlyFrozen == null) await _ensureOwnRelocationAnchors();
    if (_invitationScope != null && _invitationScope != scopeId) {
      _scopeAnchorProof = null;
      _invitationScope = null;
      _invitationHead = null;
      _inviterAccount = null;
      _inviterFingerprint = null;
    }

    // Re-admission keeps earlier invitation proofs as immutable history. The
    // exact own observation already supplies a stronger scoped history anchor;
    // normal descendant checks still run when the head is verified.
    if (_observedScopes.containsKey(scopeId) ||
        _ownRelocationAnchors.containsKey(scopeId))
      return;
    if (_scopeAnchorProof == null) {
      final rows = await account.store.database.rows(
        "SELECT authorization FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND state='invitationScopeAnchor'",
        [account.store.partition, scopeId],
      );
      if (rows.length > 1)
        throw const FormatException('invitation_scope_anchor_conflict');
      if (rows.isNotEmpty)
        _scopeAnchorProof = _decode(rows.single['authorization']);
    }
    if (_scopeAnchorProof == null || _observedScopes.containsKey(scopeId))
      return;
    if (_invitationScope != null) {
      await identities.requireVerified(_inviterAccount!, _inviterFingerprint!);
      if (_invitationScope != scopeId)
        throw const FormatException('invitation_scope_substitution');
      return;
    }
    final raw =
        CryptoJson.decode(cryptoBase64(_scopeAnchorProof!['commandBase64']))
            as Map;
    final payload = raw['payload'] as Map;
    final legacyBridge = raw['operation'] == 'crypto2.invitations.bridgeLegacy';
    if (legacyBridge) {
      // The local row selects an original request only. The retained bridge,
      // final activation and own-log inclusion are reverified independently.
      final rows = await account.store.database.rows(
        "SELECT intent_id,authorization FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND state IN ('invitationPendingAnchor','invitationScopeAnchor')",
        [account.store.partition, scopeId],
      );
      final proofHash = await cryptoSha256(
        CryptoJson.encode(_scopeAnchorProof!),
      );
      final matching = <String>[];
      for (final row in rows) {
        if (await cryptoSha256(
              CryptoJson.encode(_decode(row['authorization'])),
            ) ==
            proofHash) {
          matching.add(row['intent_id'] as String);
        }
      }
      if (matching.length != 1) {
        throw const FormatException('invitation_scope_anchor_conflict');
      }
      final invitation = await InviteCryptoRepository(
        this,
      ).inspect(invitationId: matching.single);
      final verified = invitation.legacyEvidence;
      if (verified == null ||
          verified.creatorProofHash != proofHash ||
          verified.creatorAccountId != raw['accountId'] ||
          verified.acceptancePayload['scopeId'] != scopeId ||
          verified.acceptancePayload['invitationId'] != matching.single ||
          pendingCapability != null &&
              pendingCapability!['invitationId'] != matching.single) {
        throw const FormatException('crypto_invitation_bridge_binding');
      }
      final creator = invitation.creator;
      final fingerprint = identities.fingerprint(creator);
      await identities.requireVerified(creator.accountId, fingerprint);
      if (!account.directory.isCurrent()) {
        throw const CryptoAuthorityPending('crypto_stale_identity');
      }
      _invitationScope = scopeId;
      _invitationHead = verified.acceptancePayload['membershipHeadHash'];
      _inviterAccount = creator.accountId;
      _inviterFingerprint = fingerprint;
      return;
    }
    if (raw['version'] != 2 ||
        raw['serverId'] != account.directory.session.profile.serverId ||
        ![
          'crypto2.invitations.create',
          'crypto2.invitations.resend',
          'crypto2.invitations.bridgeLegacy',
        ].contains(raw['operation']) ||
        payload['scopeId'] != scopeId ||
        (pendingCapability != null &&
            pendingCapability!['invitationId'] != payload['invitationId'])) {
      throw const FormatException('invitation_scope_anchor');
    }
    final directory = await directoryAt(
      scopeId: scopeId,
      scopeHeadHash: payload['membershipHeadHash'],
      accountId: raw['accountId'],
      directoryHeadHash: payload['authorDirectoryHeadHash'],
      online: online,
    );
    await identities.requireVerified(
      directory.accountId,
      identities.fingerprint(directory),
    );
    final actor = directory.activeDevice(raw['deviceId']);
    account.directory.reducer.crypto.verifyDomain(
      _scopeAnchorProof!,
      cryptoBase64(actor['signingKeyBase64'], length: 32),
      cryptoDirectoryDomain,
    );
    _invitationScope = scopeId;
    _invitationHead = payload['membershipHeadHash'];
    _inviterAccount = directory.accountId;
    _inviterFingerprint = identities.fingerprint(directory);
  }

  void _requireInvitationDescendant(VerifiedScopeHead head) {
    final observed = _observedScopes[head.scopeId];
    if (observed != null) {
      var cursor = head;
      final expected = observed.last['headHash'];
      while (cursor.headHash != expected) {
        final previous = _heads[cursor.body['previousHeadHash']];
        if (previous == null || previous.epoch >= cursor.epoch)
          throw const FormatException('scope_observation_anchor_missing');
        cursor = previous;
      }
      return;
    }
    final relocation = _ownRelocationAnchors[head.scopeId];
    if (relocation != null) {
      var cursor = head;
      while (cursor.headHash != relocation['membershipHeadHash']) {
        final previous = _heads[cursor.body['previousHeadHash']];
        if (previous == null || previous.epoch >= cursor.epoch) {
          throw const FormatException('crypto_relocation_own_anchor_missing');
        }
        cursor = previous;
      }
      return;
    }
    if (_scopeAnchorProof == null) return;
    var cursor = head;
    while (cursor.headHash != _invitationHead) {
      final previous = _heads[cursor.body['previousHeadHash']];
      if (previous == null || previous.epoch >= cursor.epoch)
        throw const FormatException('invitation_scope_anchor_missing');
      cursor = previous;
    }
  }

  Future<Map<String, dynamic>> _scopeCall(
    String operation,
    Map<String, dynamic> params,
  ) {
    final retained =
        Zone.current[_deletedScopeEvidenceZone] as _DeletedScopeEvidence?;
    if (retained != null) {
      if (!retained.active || params['scopeId'] != retained.scopeId) {
        throw const CryptoAuthorityPending(
          'crypto_deleted_scope_evidence_expired',
        );
      }
      if (operation == 'crypto2.scope.headGet') {
        return account.directory.call('crypto2.scope.deletionHead', params);
      }
      if (operation == 'crypto2.directory.read') {
        return account.directory.call('crypto2.scope.deletionDirectory', {
          for (final entry in params.entries)
            if (entry.key != 'headHash') entry.key: entry.value,
          'limit': 20,
        });
      }
      throw const CryptoAuthorityPending('crypto_deleted_scope_evidence_only');
    }
    return account.directory.call(operation, {
      ...params,
      if (pendingCapability != null) 'pendingCapability': pendingCapability,
    });
  }

  late final _committedOrigin = CryptoMigrationCommittedOrigin(this);
  late final _inlineDeletion = CryptoInlineDeletionEvidence(
    this,
    ordinaryAuthority: _ordinaryRecordAuthority,
  );
  late final _projectRelocation = CryptoProjectRelocationEvidence(
    this,
    ordinaryAuthority: _ordinaryRecordAuthority,
  );
  final AccountCryptoV2Workflow account;
  final _blobWindows = <String, _BlobAuthorityWindow>{};
  void invalidateBlobDelivery() {
    _blobWindows.clear();
  }

  int _authorityGeneration = 0;

  /// Ends all operation memo leases after an account companion event changes
  /// the verified prefix. Immutable historical proofs remain cached evidence.
  void invalidateAuthorityOperation() {
    _authorityGeneration++;
    invalidateBlobDelivery();
  }

  ScopeCryptoCodec get codec =>
      ScopeCryptoCodec(account.directory.reducer.crypto);
  CryptoIdentityVerification get identities => CryptoIdentityVerification(
    account.directory.reducer.crypto,
    account.store,
  );
  final _heads = <String, VerifiedScopeHead>{};
  final _directories = <String, VerifiedAccountDirectory>{};
  final _directoryAnchors = <String, String>{};
  Future<CryptoKeyLease> signingKey() => account.signingKey();
  Map<String, dynamic> _decode(Object? bytes) =>
      CryptoJson.decode(
            Uint8List.fromList((bytes as List).cast<int>()),
            limit: bytes.length,
          )
          as Map<String, dynamic>;
  Future<VerifiedAccountDirectory> directoryAt({
    required String scopeId,
    required String scopeHeadHash,
    required String accountId,
    required String directoryHeadHash,
    bool online = false,
    bool allowUnverifiedContact = false,
  }) async {
    final retained =
        Zone.current[_deletedScopeEvidenceZone] as _DeletedScopeEvidence?;
    if (retained != null) {
      if (!retained.active || retained.scopeId != scopeId) {
        throw const CryptoAuthorityPending(
          'crypto_deleted_scope_evidence_expired',
        );
      }
      allowUnverifiedContact = true;
    }
    final frozen = _readOnlyFrozen;
    if (frozen != null) {
      await _guardReadOnlyFrozen(frozen);
      if (scopeId != frozen.scopeId)
        throw const FormatException('crypto_frozen_source_scope');
      allowUnverifiedContact = true;
    }
    allowUnverifiedContact =
        allowUnverifiedContact ||
        _hasScopedIdentityAnchor(scopeId) ||
        await _hasCommittedMigrationIdentity(scopeId, scopeHeadHash);
    final cacheKey = '$accountId:$directoryHeadHash';
    if (!allowUnverifiedContact) {
      await finishCryptoDirectoryPromotion(
        store: account.store,
        reducer: account.directory.reducer,
        accountId: accountId,
        serverId: account.directory.session.profile.serverId,
        isCurrent: account.directory.isCurrent,
      );
    }
    final anchor = await account.store.anchor(accountId);
    final anchorToken = anchor?['headHash'] as String? ?? 'unanchored';
    final cached = _directories[cacheKey];
    if (allowUnverifiedContact &&
        cached != null &&
        _directoryAnchors[cacheKey] == anchorToken) {
      if (frozen != null &&
          accountId == frozen.own.accountId &&
          !frozen.own.includesAnchor(cached.generation, cached.headHash))
        throw const FormatException('crypto_frozen_source_own_prefix');
      return cached;
    }
    Future<void> anchorUnchanged() async {
      final latest = await account.store.anchor(accountId);
      if ((latest?['headHash'] as String? ?? 'unanchored') != anchorToken)
        throw const CryptoAuthorityPending('directory_known_anchor_changed');
    }

    var anchorIncluded = anchor == null || (anchor['generation'] as int) == 0;
    void checkKnown(VerifiedAccountDirectory value) {
      if (anchor != null && anchor['generation'] == value.generation) {
        if (anchor['headHash'] != value.headHash ||
            anchor['snapshotHash'] != null &&
                anchor['snapshotHash'] != value.snapshotHash)
          throw const FormatException('directory_known_fork');
        anchorIncluded = true;
      }
    }

    if (!allowUnverifiedContact &&
        cached != null &&
        anchor != null &&
        _directoryAnchors[cacheKey] == anchor['headHash']) {
      if (!allowUnverifiedContact && accountId != account.directory.accountId) {
        await identities.requireVerified(accountId, anchor['fingerprint']);
      }
      return cached;
    }
    var local = await account.store.entries(accountId);
    if (allowUnverifiedContact && local.isEmpty) {
      final scoped = await account.store.database.rows(
        'SELECT entries FROM crypto_restore_scoped_directories WHERE partition=? AND scope_id=? AND head_hash=? AND account_id=? AND directory_head_hash=?',
        [
          account.store.partition,
          scopeId,
          scopeHeadHash,
          accountId,
          directoryHeadHash,
        ],
      );
      if (scoped.length == 1)
        local =
            (CryptoJson.decode(
                      Uint8List.fromList(
                        (scoped.single['entries'] as List).cast<int>(),
                      ),
                      limit: (scoped.single['entries'] as List).length,
                    )
                    as List)
                .cast<Map<String, dynamic>>();
    }

    VerifiedAccountDirectory? state, target;
    String? genesis = anchor?['genesisFingerprint'];
    String genesisFrom(Map<String, dynamic> entry) {
      final c =
          CryptoJson.decode(
                cryptoBase64((entry['authorization'] as Map)['commandBase64']),
              )
              as Map;
      final p = c['payload'] as Map;
      return account.directory.reducer.crypto.fingerprint(
        cryptoBase64(p['rootSigningKeyBase64'], length: 32),
        cryptoBase64(p['rootEncryptionKeyBase64'], length: 32),
      );
    }

    for (final entry in local) {
      genesis ??= genesisFrom(entry);
      state = await account.directory.reducer.apply(
        previous: state,
        entry: entry,
        serverId: account.directory.session.profile.serverId,
        accountId: accountId,
        pinnedRootFingerprint: genesis,
      );
      checkKnown(state);
      if (state.headHash == directoryHeadHash) target = state;
    }
    if (allowUnverifiedContact && target != null && anchorIncluded) {
      if (frozen != null &&
          accountId == frozen.own.accountId &&
          !frozen.own.includesAnchor(target.generation, target.headHash)) {
        throw const FormatException('crypto_frozen_source_own_prefix');
      }
      await anchorUnchanged();
      _directories[cacheKey] = target;
      _directoryAnchors[cacheKey] = anchorToken;
      return target;
    }
    if (target != null &&
        state != null &&
        anchor != null &&
        anchor['headHash'] == state.headHash &&
        anchor['snapshotHash'] == state.snapshotHash) {
      if (!allowUnverifiedContact && accountId != account.directory.accountId) {
        await identities.requireVerified(accountId, anchor['fingerprint']);
      }

      await anchorUnchanged();
      _directories[cacheKey] = target;
      _directoryAnchors[cacheKey] = anchor['headHash'];
      return target;
    }
    if (!online) throw const CryptoAuthorityPending('directory_proof_pending');
    state = null;
    target = null;
    genesis = anchor?['genesisFingerprint'];
    anchorIncluded = anchor == null || (anchor['generation'] as int) == 0;
    final fetched = <Map<String, dynamic>>[];
    var after = 0;
    var fetchReference = directoryHeadHash;
    while (target == null || !anchorIncluded) {
      final page = await _scopeCall('crypto2.directory.read', {
        'scopeId': scopeId,
        if (scopeHeadHash != cryptoZeroHash) 'headHash': scopeHeadHash,
        'accountId': accountId,
        'directoryHeadHash': fetchReference,
        'afterGeneration': after,
        'limit': 50,
      });
      if (page['entries'] is! List || (page['entries'] as List).isEmpty) {
        throw const FormatException('directory_log_shape');
      }
      for (final raw in page['entries'] as List) {
        final entry = Map<String, dynamic>.from(raw as Map);
        genesis ??= genesisFrom(entry);
        state = await account.directory.reducer.apply(
          previous: state,
          entry: entry,
          serverId: account.directory.session.profile.serverId,
          accountId: accountId,
          pinnedRootFingerprint: genesis,
        );
        checkKnown(state);
        fetched.add(entry);
        after = state.generation;
        if (state.headHash == directoryHeadHash) {
          target = state;
        }
      }
      if (page['hasMore'] != true) {
        if (target != null &&
            !anchorIncluded &&
            anchor != null &&
            (anchor['generation'] as int) > state!.generation) {
          // Continue the SAME verified chain to the exact independently known
          // secure head. A forked historical branch cannot reconnect to it.
          // Scoped endpoints may refuse a non-referenced tail: that remains
          // pending and never weakens the known floor or promotes this contact.
          fetchReference = anchor['headHash'] as String;
        } else if (target == null || !anchorIncluded) {
          throw const CryptoAuthorityPending(
            'directory_known_ancestry_pending',
          );
        }
      }
    }
    if (frozen != null &&
        accountId == frozen.own.accountId &&
        !frozen.own.includesAnchor(target.generation, target.headHash)) {
      throw const FormatException('crypto_frozen_source_own_prefix');
    }
    final newestAnchor = await account.store.anchor(accountId);
    if ((newestAnchor?['headHash'] as String? ?? 'unanchored') != anchorToken)
      throw const CryptoAuthorityPending('directory_known_anchor_changed');
    final fp = identities.fingerprint(target);
    if (!allowUnverifiedContact && accountId == account.directory.accountId) {
      final own = await account.store.anchor(accountId);
      if (own?['fingerprint'] != fp) {
        throw const CryptoAuthorityPending('identity_verification_required');
      }
    } else if (!allowUnverifiedContact &&
        anchor != null &&
        target.generation < (anchor['generation'] as int)) {
      await identities.requireVerified(accountId, fp);
    }
    if (_hasScopedIdentityAnchor(scopeId)) {
      _directories[cacheKey] = target;
      _directoryAnchors[cacheKey] = anchorToken;
    }
    if (allowUnverifiedContact) {
      await account.store.database.execute(
        'INSERT INTO crypto_restore_scoped_directories VALUES(?,?,?,?,?,?) ON CONFLICT(partition,scope_id,head_hash,account_id,directory_head_hash) DO UPDATE SET entries=excluded.entries',
        [
          account.store.partition,
          scopeId,
          scopeHeadHash,
          accountId,
          directoryHeadHash,
          CryptoJson.encodeDerivedState(fetched),
        ],
      );
    }
    if (!allowUnverifiedContact) {
      if (anchor == null ||
          target.generation >= (anchor['generation'] as int)) {
        final run = account.directory.reducer.crypto.randomId();
        for (final entry in fetched) {
          await account.store.stageReplay(run, accountId, entry);
        }
        try {
          if (accountId != account.directory.accountId) {
            // This exact scoped account/server/head has been fully replayed
            // above, including the existing secure anchor. Hosting trust pins
            // identity only; the signed scope roster and owner authorization
            // are still verified by the caller before granting any access.
            await identities.trustHostDirectory(
              directory: target,
              expectedServerId: account.directory.session.profile.serverId,
              isCurrent: account.directory.isCurrent,
            );
          }
          await account.store.pinRoot(
            accountId,
            target.serverId,
            fp,
            genesisFingerprint: genesis,
          );
          // Final secure ancestry CAS precedes live immutable log promotion.
          await account.store.remember(
            target,
            anchor?['trustState'] as String? ?? 'freshnessPending',
          );
          await finishCryptoDirectoryPromotion(
            store: account.store,
            reducer: account.directory.reducer,
            accountId: accountId,
            serverId: account.directory.session.profile.serverId,
            isCurrent: account.directory.isCurrent,
          );
        } finally {
          final committed = await account.store.anchor(accountId);
          // Retain the authenticated candidate if its secure commit succeeded
          // but local promotion failed. Restart can finish without this server.
          if (committed == null ||
              !target.includesAnchor(
                committed['generation'] as int,
                committed['headHash'] as String,
              )) {
            await account.store.database.execute(
              'DELETE FROM crypto_directory_replay_staging WHERE partition=? AND run_id=?',
              [account.store.partition, run],
            );
          }
        }
      }
      _directories[cacheKey] = target;
      _directoryAnchors[cacheKey] = (await account.store.anchor(
        accountId,
      ))!['headHash'];
    }
    if (allowUnverifiedContact) {
      await account.store.database.execute(
        'INSERT INTO crypto_restore_scoped_directories VALUES(?,?,?,?,?,?) ON CONFLICT DO NOTHING',
        [
          account.store.partition,
          scopeId,
          scopeHeadHash,
          accountId,
          directoryHeadHash,
          CryptoJson.encodeDerivedState(fetched),
        ],
      );
    }
    return target;
  }

  Future<VerifiedAccountDirectory> inspectContact(
    String scopeId,
    String accountId,
  ) async => (await _inspectContactWithScope(scopeId, accountId)).directory;

  Future<({VerifiedAccountDirectory directory, String scopeHeadHash})>
  _inspectContactWithScope(String scopeId, String accountId) async {
    final status = await _scopeCall('crypto2.directory.status', {
      'scopeId': scopeId,
      'accountId': accountId,
    });
    // A first-contact check also precedes the first encrypted scope head.
    // The catalog pointer only selects the bounded proof route. Full directory
    // signatures and the selected hosting/manual trust policy establish the
    // identity; catalog metadata grants no membership or content keys.
    String? cursor;
    String? scopeHash;
    while (true) {
      final page = await account.directory.call('crypto2.scopes.catalog', {
        'limit': 50,
        if (cursor != null) 'afterId': cursor,
      });
      for (final scope in page['scopes'] as List) {
        if (scope['id'] == scopeId) {
          scopeHash = scope['headHash'] as String? ?? cryptoZeroHash;
          break;
        }
      }
      if (scopeHash != null) break;
      if (page['hasMore'] != true) {
        throw const CryptoAuthorityPending('scope_discovery_pending');
      }
      final next = page['nextAfterId'];
      if (next is! String || cursor != null && next.compareTo(cursor) <= 0) {
        throw const FormatException('scope_catalog_cursor');
      }
      cursor = next;
    }
    final directory = await directoryAt(
      scopeId: scopeId,
      scopeHeadHash: scopeHash,
      accountId: accountId,
      directoryHeadHash: status['headHash'],
      online: true,
      allowUnverifiedContact: true,
    );
    return (directory: directory, scopeHeadHash: scopeHash);
  }

  Future<void> verifyContactCard(
    String scopeId,
    String accountId,
    String externallyReceivedCard,
  ) async {
    final card =
        CryptoJson.decode(
              Uint8List.fromList(utf8.encode(externallyReceivedCard)),
              limit: 4096,
            )
            as Map;
    if (card.length != 7 ||
        card['version'] != 2 ||
        card['purpose'] != 'identityVerification' ||
        card['serverId'] != account.directory.session.profile.serverId ||
        card['accountId'] != accountId) {
      throw const FormatException('identity_card');
    }
    final candidate = await inspectContact(scopeId, accountId);
    await identities.compareAndPin(
      directory: candidate,
      externallyComparedSafetyCode: card['safetyCode'],
      externallyComparedGeneration: card['generation'],
      externallyComparedHeadHash: card['headHash'],
    );
    _directories.clear();
    _heads.clear();
  }

  /// First-use hosting trust for a selected account already visible through
  /// this scope's authorized directory endpoint. Manual card comparison remains
  /// available independently through [verifyContactCard].
  Future<void> trustContactFromDirectory(
    String scopeId,
    String accountId,
  ) async {
    final candidate = await _inspectContactWithScope(scopeId, accountId);
    // Use the normal exact scoped route for the durable replay journal as
    // well as hosting trust. A later historical invitation can then reconnect
    // to this newer secure head without depending on the server's old prefix.
    await directoryAt(
      scopeId: scopeId,
      scopeHeadHash: candidate.scopeHeadHash,
      accountId: accountId,
      directoryHeadHash: candidate.directory.headHash,
      online: true,
    );
    _directories.clear();
    _heads.clear();
  }

  static final _operationKey = Object();
  static final _retainedReadKey = Object();

  CryptoVerifiedReadOperation createReadOperation() =>
      CryptoVerifiedReadOperation._(this);

  /// A bounded logical read uses one verified authority snapshot. Every write
  /// delivery starts a fresh boundary; server ACL checks remain per request.
  Future<T> withVerifiedOperation<T>(
    Future<T> Function() body, {
    bool freshBoundary = false,
  }) async {
    if (freshBoundary) {
      final retained = Zone.current[_retainedReadKey];
      if (retained is CryptoVerifiedReadOperation &&
          identical(retained._owner, this) &&
          retained._active) {
        retained._discard();
      }
    }
    final inherited = Zone.current[_operationKey];
    if (!freshBoundary &&
        inherited is _AuthorityOperation &&
        identical(inherited.owner, this) &&
        inherited.generation == _authorityGeneration &&
        identical(_operation, inherited) &&
        await _operationPinsValid(inherited)) {
      return body();
    }
    final operation = _AuthorityOperation(this);
    try {
      return await runZoned(
        () => account.directory.withAuthoritySnapshot(
          body,
          isValid: () async =>
              identical(_operation, operation) &&
              await _operationPinsValid(operation),
          onMutation: invalidateAuthorityOperation,
        ),
        zoneValues: {_operationKey: operation},
      );
    } finally {
      operation.active = false;
      operation.heads.clear();
      operation.directories.clear();
      operation.pins.clear();
    }
  }

  _AuthorityOperation? get _operation {
    final value = Zone.current[_operationKey];
    return value is _AuthorityOperation &&
            identical(value.owner, this) &&
            value.generation == _authorityGeneration &&
            canReuseCryptoReadAuthority(
              age: value.watch.elapsed,
              identityCurrent: account.directory.isCurrent(),
              lifecycleMatches:
                  value.lifecycle == _BlobLifecycleEpoch.shared?.generation,
              pinsMatch: true,
              onlineVerified: true,
              active: value.active,
            )
        ? value
        : null;
  }

  Future<bool> _operationPinsValid(_AuthorityOperation operation) async {
    for (final pin in operation.pins.entries) {
      if (await account.store.secure.read(pin.key) != pin.value) return false;
    }
    return identical(_operation, operation);
  }

  /// A combined read may carry exact verified material between dispatches.
  /// Its age starts at the original authority operation, never at reuse.
  Future<CryptoVerifiedReadLease?> verifiedReadLease() async {
    final operation = _operation;
    if (operation == null ||
        operation.heads.isEmpty ||
        !await _operationPinsValid(operation)) {
      return null;
    }
    return CryptoVerifiedReadLease._(
      this,
      operation.generation,
      operation.lifecycle,
      operation.watch,
      Map.unmodifiable(operation.pins),
    );
  }

  Future<bool> isVerifiedReadLeaseCurrent(CryptoVerifiedReadLease lease) async {
    if (!identical(lease._owner, this) ||
        lease._generation != _authorityGeneration ||
        !canReuseCryptoReadAuthority(
          age: lease._watch.elapsed,
          identityCurrent: account.directory.isCurrent(),
          lifecycleMatches:
              lease._lifecycle == _BlobLifecycleEpoch.shared?.generation,
          pinsMatch: true,
          onlineVerified: true,
          active: true,
        )) {
      return false;
    }
    for (final pin in lease._pins.entries) {
      if (await account.store.secure.read(pin.key) != pin.value) return false;
    }
    return lease._generation == _authorityGeneration &&
        account.directory.isCurrent() &&
        lease._watch.elapsed < const Duration(seconds: 5) &&
        lease._lifecycle == _BlobLifecycleEpoch.shared?.generation;
  }

  Future<void> _captureOperationPin(
    _AuthorityOperation operation,
    String key,
  ) async {
    final value = await account.store.secure.read(key);
    if (operation.pins.containsKey(key) && operation.pins[key] != value) {
      // A newer local observation invalidates the WHOLE snapshot. Updating a
      // shared pin map must not make other cached scopes look fresh again.
      operation.active = false;
      operation.heads.clear();
      operation.directories.clear();
      return;
    }
    operation.pins[key] = value;
  }

  Future<void> _rememberOperationDirectory(
    _AuthorityOperation operation,
    VerifiedAccountDirectory directory,
  ) => _captureOperationPin(
    operation,
    'directory2:${account.store.partition}:${directory.accountId}',
  );

  /// An own signed append may retire a dormant genesis memo, but cannot replace
  /// proof already admitted by an in-flight verification or extend its lease.
  Future<void> _discardStaleCommittedMigrationMemo(String scope) async {
    if (_readOnlyFrozen != null) return;
    final anchor = _committedGenesisAnchors[scope];
    if (anchor == null) return;
    final own = await account.directory.cachedVerifiedDirectory();
    if (!account.directory.isCurrent()) {
      throw const CryptoAuthorityPending('scope_recovery_publication_changed');
    }
    if (own.headHash == anchor['ownHeadHash']) return;
    final attempt = Zone.current[_operationKey];
    final admittedAttempt =
        attempt is _AuthorityOperation &&
        identical(attempt.owner, this) &&
        attempt.active &&
        (attempt.heads.isNotEmpty || attempt.directories.isNotEmpty);
    if (_descriptorVerification != null || admittedAttempt) {
      if (admittedAttempt) attempt.active = false;
      throw const CryptoAuthorityPending('scope_recovery_publication_changed');
    }
    // No SQL, secure floor, request, or original proof is changed. Re-enter the
    // normal bootstrap/chain/current-member/floor checks with no positive memo.
    _verifiedScopeDescriptors.remove(scope);
    _verifiedGenesisAnchors.remove(scope);
    _verifiedGenesisPublications.remove(scope);
    _verifiedGenesisDescriptors.remove(scope);
    _heads.removeWhere((_, head) => head.scopeId == scope);
    _observedScopes.remove(scope);
    _checkedObservedScopes.remove(scope);
    _directories.clear();
    invalidateBlobDelivery();
  }

  Future<VerifiedScopeHead> currentHead(
    String scopeId, {
    bool online = false,
  }) async {
    await _discardStaleCommittedMigrationMemo(scopeId);
    return _withScopeDescriptorVerification(
      scopeId,
      () => _currentHead(scopeId, online: online),
    );
  }

  Future<VerifiedScopeHead> _currentHead(
    String scopeId, {
    bool online = false,
  }) async {
    if (Zone.current[_deletedScopeEvidenceZone] != null) {
      throw const CryptoAuthorityPending('crypto_deleted_scope_evidence_only');
    }
    final frozen = _readOnlyFrozen;
    if (frozen != null) {
      await _guardReadOnlyFrozen(frozen);
      if (frozen.scopeId != scopeId)
        throw const FormatException('crypto_frozen_source_scope');
      await _ensureInvitationAnchor(scopeId);
      final wire = await _scopeCall('crypto2.scope.headGet', {
        'scopeId': scopeId,
        'headHash': frozen.headHash,
      });
      if (wire['headHash'] != frozen.headHash)
        throw const FormatException('crypto_frozen_source_head');
      final candidate = await _verifyHead(
        scopeId,
        wire,
        online: true,
        historical: true,
      );
      await _guardReadOnlyFrozen(frozen);
      return candidate;
    }
    await _ensureInvitationAnchor(scopeId, online: online);
    final operation = _operation, cached = operation?.heads[scopeId];
    if (cached != null && await _operationPinsValid(operation!)) {
      for (final member in cached.members.where(
        (m) => m['accountId'] != account.directory.accountId,
      )) {
        final directory = operation
            .directories['$scopeId:${cached.headHash}:${member['accountId']}'];
        if (directory == null)
          throw const CryptoAuthorityPending('authority_operation_incomplete');
        await _requireCurrentMemberIdentity(
          scopeId,
          cached.headHash,
          directory,
        );
      }
      if (identical(_operation, operation) &&
          await _operationPinsValid(operation))
        return cached;
    }
    final rows = await account.store.database.rows(
      'SELECT * FROM crypto_scope_heads WHERE partition=? AND scope_id=? ORDER BY epoch DESC',
      [account.store.partition, scopeId],
    );
    if (!online && rows.isEmpty) {
      throw const CryptoAuthorityPending('scope_head_pending');
    }
    final pinnedScope = await account.store.secure.read(
      'scope2:${account.store.partition}:$scopeId',
    );
    final pinnedHash = pinnedScope == null
        ? null
        : (CryptoJson.decode(Uint8List.fromList(utf8.encode(pinnedScope)))
              as Map)['headHash'];
    final pinnedRows = rows
        .where((row) => row['head_hash'] == pinnedHash)
        .toList();
    if (!online && pinnedRows.length != 1) {
      throw const CryptoAuthorityPending('scope_current_anchor_required');
    }
    final wire = online
        ? await _scopeCall('crypto2.scope.headGet', {'scopeId': scopeId})
        : _decode(pinnedRows.single['authorization']);
    if (online) {
      final body = Map<String, dynamic>.from(wire['payload'] as Map);
      codec.validateBody(body);
      if (body['epoch'] == 1 &&
          wire['initialLifecycleBaseline']?['originKind'] == 'legacy' &&
          _scopeDescriptors[scopeId] == null) {
        // Rebuild this exact committed genesis from its retained CONTENT key
        // and FILE-rooted own contribution. Derived SQL rows are not trust.
        // Current peer checks and normal head/floor admission still follow.
        await _bootstrapMigrationDescriptor(scopeId, wire);
      }
      // Establish the independently pinned current chain before authenticating
      // historical ancestors whose root may legitimately have been replaced.
      for (final member
          in (body['members'] as List).cast<Map<String, dynamic>>()) {
        await currentMemberDirectory(
          scopeId,
          wire['headHash'],
          member['accountId'],
        );
      }
    }
    await _ensureInvitationAnchor(scopeId, online: online);
    final verified = await _verifyHead(
      scopeId,
      wire,
      online: online,
      requireDescriptor: true,
    );
    _requireInvitationDescendant(verified);
    final key = 'scope2:${account.store.partition}:$scopeId';
    final proposal =
        CryptoJson.decode(cryptoBase64(verified.authorization['commandBase64']))
            as Map;
    final referenced = await directoryAt(
      scopeId: scopeId,
      scopeHeadHash: verified.headHash,
      accountId: proposal['accountId'],
      directoryHeadHash: verified.body['authorDirectoryHeadHash'],
    );
    var observedExactHead = false;
    for (final observation
        in _observedScopes[scopeId] ?? const <Map<String, dynamic>>[]) {
      if (observation['headHash'] != verified.headHash) continue;
      if (referenced.headHash != verified.body['authorDirectoryHeadHash'] ||
          observation['proposalProofHash'] !=
              await cryptoSha256(CryptoJson.encode(verified.authorization)) ||
          wire['activationAuthorization'] == null ||
          observation['activationProofHash'] !=
              await cryptoSha256(
                CryptoJson.encode(wire['activationAuthorization']),
              )) {
        throw const FormatException('scope_observation_head_substitution');
      }
      observedExactHead = true;
    }
    final relocation = _ownRelocationAnchors[scopeId];
    final relocationExactHead =
        relocation != null &&
        relocation['membershipHeadHash'] == verified.headHash &&
        relocation['proposalProofHash'] ==
            await cryptoSha256(CryptoJson.encode(verified.authorization)) &&
        wire['activationAuthorization'] != null &&
        relocation['activationProofHash'] ==
            await cryptoSha256(
              CryptoJson.encode(wire['activationAuthorization']),
            );
    final prefix = <int, String>{};
    VerifiedScopeHead? cursor = verified;
    while (cursor != null) {
      prefix[cursor.epoch] = cursor.headHash;
      cursor = _heads[cursor.body['previousHeadHash']];
    }
    final knownAuthor = await account.store.anchor(proposal['accountId']);
    final forwardAuthor =
        pinnedHash != verified.headHash &&
            knownAuthor != null &&
            knownAuthor['deviceSnapshotHash'] != referenced.deviceSnapshotHash
        ? await _prepareForwardDirectoryReference(
            scopeId: scopeId,
            scopeHeadHash: verified.headHash,
            accountId: proposal['accountId'],
            directoryHeadHash: referenced.headHash,
            deviceSnapshotHash: referenced.deviceSnapshotHash,
            known: knownAuthor,
            verifiedReference: referenced,
          )
        : null;
    await commitCryptoScopeAnchor(
      partition: account.store.partition,
      key: key,
      secure: account.store.secure,
      epoch: verified.epoch,
      headHash: verified.headHash,
      verifiedPrefix: prefix,
      isCurrent: account.directory.isCurrent,
      validateCurrent: (floor) async {
        final authorPin = await account.store.anchor(proposal['accountId']);
        if (authorPin != null &&
            authorPin['deviceSnapshotHash'] != referenced.deviceSnapshotHash &&
            floor?['headHash'] != verified.headHash) {
          if (forwardAuthor != null) {
            await forwardAuthor();
            return;
          }
          // An own directory-included observation authenticates this exact
          // historical proposal/author reference and activation. It grants no
          // current device membership or permission to mint future records.
          final ownPin = await account.store.anchor(
            account.directory.accountId,
          );
          final committed = _committedGenesisAnchors[scopeId];
          final committedExactHead =
              committed != null &&
              committed['headHash'] == verified.headHash &&
              committed['ownHeadHash'] == ownPin?['headHash'] &&
              committed['proposalHash'] ==
                  await cryptoSha256(
                    CryptoJson.encode(verified.authorization),
                  ) &&
              committed['activationHash'] ==
                  await cryptoSha256(
                    CryptoJson.encode(wire['activationAuthorization']),
                  );
          if ((!observedExactHead ||
                  _checkedObservedScopes[scopeId] != ownPin?['headHash']) &&
              !committedExactHead &&
              !(relocationExactHead &&
                  _checkedRelocationOwnHead == ownPin?['headHash'])) {
            throw const CryptoAuthorityPending(
              'scope_authority_history_pending',
            );
          }
        }
      },
    );
    if (operation != null &&
        operation.active &&
        online &&
        verified.members.every(
          (m) => operation.directories.containsKey(
            '$scopeId:${verified.headHash}:${m['accountId']}',
          ),
        )) {
      operation.heads[scopeId] = verified;
      await _captureOperationPin(operation, key);
    }
    return verified;
  }

  final _verifiedScopeDescriptors = <String, Map<String, dynamic>>{};
  _ScopeDescriptorVerification? get _descriptorVerification {
    final stage =
        Zone.current[_scopeDescriptorVerificationZone]
            as _ScopeDescriptorVerification?;
    if (stage == null || !identical(stage.owner, this)) return null;
    if (!stage.active) {
      throw const CryptoAuthorityPending(
        'scope_descriptor_verification_expired',
      );
    }
    return stage;
  }

  Map<String, Map<String, dynamic>> get _scopeDescriptors =>
      _descriptorVerification?.descriptors ?? _verifiedScopeDescriptors;

  Future<T> _withScopeDescriptorVerification<T>(
    String scope,
    Future<T> Function() body,
  ) async {
    if (_descriptorVerification != null) return body();
    final stage = _ScopeDescriptorVerification(
      this,
      Map.of(_verifiedScopeDescriptors),
      Map.of(_verifiedGenesisAnchors),
      Map.of(_verifiedGenesisPublications),
      Map.of(_verifiedGenesisDescriptors),
    );
    return runZoned(() async {
      try {
        final result = await body();
        if (_readOnlyFrozen == null) {
          final descriptor = stage.descriptors[scope];
          if (descriptor != null) _verifiedScopeDescriptors[scope] = descriptor;
          final anchor = stage.genesisAnchors[scope];
          if (anchor != null) _verifiedGenesisAnchors[scope] = anchor;
          final publications = stage.publications[scope];
          if (publications != null)
            _verifiedGenesisPublications[scope] = publications;
          final genesisDescriptor = stage.genesisDescriptors[scope];
          if (genesisDescriptor != null)
            _verifiedGenesisDescriptors[scope] = genesisDescriptor;
        }
        return result;
      } finally {
        stage.active = false;
        stage.descriptors.clear();
        stage.genesisAnchors.clear();
        stage.publications.clear();
        stage.genesisDescriptors.clear();
      }
    }, zoneValues: {_scopeDescriptorVerificationZone: stage});
  }

  int? _knownPolicyVersion(String scopeId, VerifiedScopeHead? head) {
    while (head != null) {
      final proof = head.body['accessIntentProof'];
      if (proof is Map) {
        final consent =
            CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
        return consent['resultingDescriptor']['accessPolicyVersion'] as int;
      }
      head = _heads[head.body['previousHeadHash']];
    }
    return _scopeDescriptors[scopeId]?['accessPolicyVersion'] as int?;
  }

  /// A legacy genesis can verify its cryptographic proposal before its
  /// structural source certificate exists. Null is no policy authority.
  Future<int?> verifiedCandidatePolicyVersion(
    String scopeId,
    Map<String, dynamic> wire,
  ) async {
    final body = Map<String, dynamic>.from(wire['payload'] as Map);
    final hash = wire['headHash'];
    if (body['scopeId'] != scopeId || await codec.headHash(body) != hash) {
      throw const FormatException('scope_head_substitution');
    }
    final baseline = await verifyInitialLifecycle(
      scopeId,
      wire,
      scopeHeadHash: hash as String,
    );
    if (baseline != body['initialLifecycleHash']) {
      throw const FormatException('scope_lifecycle_baseline_substitution');
    }
    if (body['epoch'] == 1 && body['previousHeadHash'] == cryptoZeroHash) {
      if (body['financePolicyIntentProof'] != null ||
          body['accessIntentProof'] != null) {
        throw const FormatException('scope_genesis_intent');
      }
      return _scopeDescriptors[scopeId]?['accessPolicyVersion'] as int?;
    }
    return (await verifiedScopeDescriptor(
          scopeId,
          online: true,
        ))['accessPolicyVersion']
        as int;
  }

  /// A retained deletion witness is historical evidence for a previously
  /// anchored exact scope head. It cannot establish a new active scope/floor.
  Future<VerifiedScopeHead> verifyDeletedScopeHead(
    String scopeId,
    Map<String, dynamic> wire,
  ) => withVerifiedDeletedScope(scopeId, wire, (head) async => head);

  Future<T> withVerifiedDeletedScope<T>(
    String scopeId,
    Map<String, dynamic> wire,
    Future<T> Function(VerifiedScopeHead head) action,
  ) async {
    await _ensureInvitationAnchor(scopeId);
    final hash = wire['headHash'];
    final rawFloor = await account.store.secure.read(
      'scope2:${account.store.partition}:$scopeId',
    );
    final floor = rawFloor == null ? null : jsonDecode(rawFloor) as Map;
    if (floor?['headHash'] != hash &&
        !(_observedScopes[scopeId] ?? const <Map<String, dynamic>>[]).any(
          (value) => value['headHash'] == hash,
        )) {
      throw const CryptoAuthorityPending(
        'crypto_scope_deletion_history_pending',
      );
    }
    final context = _DeletedScopeEvidence(scopeId);
    try {
      return await runZoned(() async {
        final verified = await _verifyHead(
          scopeId,
          wire,
          online: true,
          historical: true,
        );
        if (!verified.active || verified.headHash != hash) {
          throw const FormatException('crypto_scope_deletion_head');
        }
        return action(verified);
      }, zoneValues: {_deletedScopeEvidenceZone: context});
    } finally {
      context.active = false;
    }
  }

  /// Authenticated genesis descriptor for proposal verification only. This
  /// never installs an active head, grants a key, or satisfies currentHead.
  Future<Map<String, dynamic>> verifiedCandidateDescriptor(
    String scopeId,
    Map<String, dynamic> wire,
  ) async {
    final body = Map<String, dynamic>.from(wire['payload'] as Map);
    final hash = wire['headHash'];
    if (body['scopeId'] != scopeId || await codec.headHash(body) != hash) {
      throw const FormatException('scope_head_substitution');
    }
    final baseline = await verifyInitialLifecycle(
      scopeId,
      wire,
      scopeHeadHash: hash as String,
    );
    if (baseline != body['initialLifecycleHash']) {
      throw const FormatException('scope_lifecycle_baseline_substitution');
    }
    if (body['epoch'] != 1 || body['previousHeadHash'] != cryptoZeroHash) {
      return verifiedScopeDescriptor(scopeId, online: true);
    }
    final descriptor = _scopeDescriptors[scopeId];
    if (descriptor == null || descriptor['initialLifecycleHash'] != baseline) {
      throw const CryptoAuthorityPending('scope_descriptor_migration_pending');
    }
    return Map<String, dynamic>.unmodifiable(descriptor);
  }

  /// Uses only a reverified exact candidate and its authenticated descriptor /
  /// signed access transitions. Ordinary descriptor/current-head gates remain
  /// mandatory everywhere outside this short proposal-codec callback.
  Future<T> withRecoveryCandidatePolicy<T>({
    required String scopeId,
    required String sourceHeadHash,
    required Future<T> Function(VerifiedScopeRecoveryPolicy policy) body,
  }) async {
    final own = await account.directory.requireFresh();
    final scopePin = await account.store.secure.read(
      'scope2:${account.store.partition}:$scopeId',
    );
    final source = await recoveryCandidateHead(scopeId);
    source.member(own.accountId);
    if (source.headHash != sourceHeadHash ||
        _scopeDescriptors[scopeId]?['initialLifecycleHash'] !=
            source.body['initialLifecycleHash']) {
      throw const CryptoAuthorityPending('scope_review_changed');
    }
    if (scopePin != null) {
      final floor =
          CryptoJson.decode(Uint8List.fromList(utf8.encode(scopePin))) as Map;
      var cursor = source;
      if (cursor.epoch < floor['epoch']) {
        throw const FormatException('scope_known_rollback');
      }
      while (cursor.epoch > floor['epoch']) {
        final previous = verifiedCandidateAncestor(
          cursor.body['previousHeadHash'],
        );
        if (previous.scopeId != scopeId ||
            previous.headHash != cursor.body['previousHeadHash'] ||
            previous.epoch >= cursor.epoch) {
          throw const FormatException('scope_known_fork');
        }
        cursor = previous;
      }
      if (cursor.headHash != floor['headHash']) {
        throw const FormatException('scope_known_fork');
      }
    }
    final version = _knownPolicyVersion(scopeId, source);
    if (!const {1, 2, 3}.contains(version)) {
      throw const CryptoAuthorityPending('scope_descriptor_migration_pending');
    }
    final policy = VerifiedScopeRecoveryPolicy._(
      this,
      source,
      own.headHash,
      scopePin,
      version!,
    );
    try {
      await policy._guard();
      final value = await body(policy);
      await policy._guard();
      return value;
    } finally {
      policy._active = false;
    }
  }

  Future<Map<String, dynamic>> verifiedScopeDescriptor(
    String scopeId, {
    bool online = false,
  }) async {
    var head = await currentHead(scopeId, online: online);
    while (true) {
      final consent = head.body['accessIntentProof'];
      if (consent is Map) {
        final body =
            CryptoJson.decode(cryptoBase64(consent['commandBase64'])) as Map;
        return Map<String, dynamic>.unmodifiable({
          'id': scopeId,
          ...Map<String, dynamic>.from(body['resultingDescriptor'] as Map),
          'initialLifecycleHash': head.body['initialLifecycleHash'],
        });
      }
      final previous = _heads[head.body['previousHeadHash']];
      if (previous == null) break;
      head = previous;
    }
    if (_scopeDescriptors[scopeId] == null) {
      if (_readOnlyFrozen != null) {
        throw const CryptoAuthorityPending(
          'scope_descriptor_migration_pending',
        );
      }
      await _bootstrapMigrationDescriptor(scopeId, await _headWire(head));
    }
    final value = _scopeDescriptors[scopeId];
    if (value == null) {
      throw const CryptoAuthorityPending('scope_descriptor_migration_pending');
    }
    return Map<String, dynamic>.unmodifiable(value);
  }

  Set<String> observedLifecycleHashes(String scopeId) => {
    for (final observation
        in _observedScopes[scopeId] ?? const <Map<String, dynamic>>[])
      if (_heads[observation['headHash']]?.scopeId == scopeId &&
          observation['lifecycleHash'] != cryptoZeroHash)
        observation['lifecycleHash'] as String,
  };

  /// Already verified own account observations only. Call after readContext /
  /// currentHead; this accessor performs no network or authority promotion.
  /// A blank reader can bootstrap the exact signed checkpoint inventory before
  /// old-device record signatures need their observed inclusion descriptors.
  List<Map<String, dynamic>> observedDomainCheckpointAnchors(
    String scopeId,
    String domain,
    String headHash,
  ) => [
    if (_heads[headHash]?.scopeId == scopeId)
      for (final observation
          in _observedScopes[scopeId] ?? const <Map<String, dynamic>>[])
        if (_heads[observation['headHash']]?.scopeId == scopeId)
          for (final checkpoint in observation['checkpoints'] as List)
            if (checkpoint['domain'] == domain &&
                checkpoint['membershipHeadHash'] == headHash)
              Map<String, dynamic>.unmodifiable({
                ...Map<String, dynamic>.from(checkpoint as Map),
                'proofHashes': List<String>.unmodifiable(
                  (checkpoint['proofHashes'] as List).cast<String>(),
                ),
              }),
  ];
  Future<String> verifiedLifecycleHash(String scopeId) async =>
      (await CryptoLifecycleEvidence(this).current(scopeId))['headHash']
          as String;

  Future<String> initialLifecycleHash(String scopeId) async {
    final baseline = await _scopeCall('crypto2.scope.lifecycle.baseline', {
      'scopeId': scopeId,
    });
    return verifyInitialLifecycle(
      scopeId,
      baseline,
      scopeHeadHash: cryptoZeroHash,
    );
  }

  Future<PreparedProjectRelocationGenesis> prepareProjectRelocationGenesis({
    required Map<String, dynamic> planProof,
    required Map<String, dynamic> originProof,
    required Map<String, dynamic> proposal,
  }) async {
    final plan = CryptoProjectRelocationCodec.body(planProof);
    final origin = CryptoProjectRelocationCodec.body(originProof);
    final own = await account.directory.requireFresh();
    final device = own.activeDevice(account.deviceId);
    if (plan['version'] != 2 ||
        plan['serverId'] != own.serverId ||
        plan['accountId'] != own.accountId ||
        plan['deviceId'] != account.deviceId ||
        device['keyringWrite'] != true)
      throw const FormatException('crypto_relocation_prepared_identity');
    final planPrefix = await directoryAt(
      scopeId: plan['sourceScopeId'],
      scopeHeadHash: plan['sourceHeadHash'],
      accountId: own.accountId,
      directoryHeadHash: plan['authorDirectoryHeadHash'],
      online: true,
    );
    if (planPrefix.deviceSnapshotHash != own.deviceSnapshotHash ||
        planPrefix.identityEpochId != own.identityEpochId ||
        planPrefix.rootFingerprint != own.rootFingerprint)
      throw const CryptoAuthorityPending('crypto_relocation_identity_changed');
    codec.crypto.verifyDomain(
      planProof,
      cryptoBase64(
        planPrefix.activeDevice(account.deviceId)['signingKeyBase64'],
        length: 32,
      ),
      'JivieProjectRelocationPlan/v2\n',
    );
    final source = await currentHead(plan['sourceScopeId'], online: true);
    final manager = source.member(own.accountId);
    final descriptor = await verifiedScopeDescriptor(source.scopeId);
    if (descriptor['kind'] != 'household' ||
        descriptor['accessPolicyVersion'] != 3 ||
        manager['manageKeys'] != true ||
        source.headHash != plan['sourceHeadHash'] ||
        source.accessRevision != plan['sourceAccessRevision'] ||
        source.members.singleWhere((m) => m['role'] == 'owner')['accountId'] !=
            plan['targetOwnerAccountId'])
      throw const FormatException('crypto_relocation_prepared_parent');
    final lifecycle = await CryptoLifecycleEvidence(
      this,
    ).current(source.scopeId);
    if (lifecycle['headHash'] != plan['sourceLifecycleHash'])
      throw const FormatException('crypto_relocation_prepared_parent');
    final hash = await cryptoSha256(CryptoJson.encode(planProof));
    final marker = {
      'version': 2,
      'actionId': plan['actionId'],
      'planHash': hash,
    };
    if (origin['operation'] != 'crypto2.scope.origin' ||
        origin['serverId'] != own.serverId ||
        origin['scopeId'] != plan['targetScopeId'] ||
        origin['accountId'] != own.accountId ||
        origin['deviceId'] != account.deviceId ||
        origin['kind'] != 'project' ||
        origin['accessPolicyVersion'] != 3 ||
        origin['parentScopeToken'] != plan['targetParentScopeToken'] ||
        base64Encode(CryptoJson.encode(origin['projectRelocation'])) !=
            base64Encode(CryptoJson.encode(marker)))
      throw const FormatException('crypto_relocation_prepared_origin');
    final originPrefix = await directoryAt(
      scopeId: source.scopeId,
      scopeHeadHash: source.headHash,
      accountId: own.accountId,
      directoryHeadHash: origin['authorDirectoryHeadHash'],
      online: true,
    );
    if (originPrefix.deviceSnapshotHash != own.deviceSnapshotHash ||
        originPrefix.identityEpochId != own.identityEpochId ||
        originPrefix.rootFingerprint != own.rootFingerprint)
      throw const CryptoAuthorityPending('crypto_relocation_identity_changed');
    codec.crypto.verifyDomain(
      originProof,
      cryptoBase64(
        originPrefix.activeDevice(account.deviceId)['signingKeyBase64'],
        length: 32,
      ),
      'JivieE2EE/scopeOrigin/v2\n',
    );
    final members = proposal['members'];
    if (proposal['scopeId'] != plan['targetScopeId'] ||
        proposal['epoch'] != 1 ||
        proposal['previousHeadHash'] != cryptoZeroHash ||
        proposal['accessIntentProof'] != null ||
        proposal['financePolicyIntentProof'] != null ||
        members is! List ||
        members.length != source.members.length)
      throw const FormatException('crypto_relocation_prepared_roster');
    for (final previous in source.members) {
      final matching = members
          .where((m) => m['accountId'] == previous['accountId'])
          .toList();
      if (matching.length != 1)
        throw const FormatException('crypto_relocation_prepared_roster');
      final future = matching.single as Map;
      for (final field in [
        'accountId',
        'role',
        'rootSigningKeyBase64',
        'rootEncryptionKeyBase64',
        'recoveryRootEpochId',
        'identityEpochId',
        'deviceSnapshotHash',
      ]) {
        if (future[field] != previous[field])
          throw const FormatException('crypto_relocation_prepared_roster');
      }
      if (future['financeRole'] !=
              (future['role'] == 'viewer' ? 'read' : 'write') ||
          future['manageKeys'] !=
              (future['role'] == 'owner' || future['role'] == 'member'))
        throw const FormatException('crypto_relocation_prepared_roster');
      if (future['accountId'] != own.accountId)
        await identities.requireVerified(
          future['accountId'],
          identities.fingerprint(
            await directoryAt(
              scopeId: source.scopeId,
              scopeHeadHash: source.headHash,
              accountId: future['accountId'],
              directoryHeadHash: future['directoryHeadHash'],
              online: true,
            ),
          ),
        );
    }
    return PreparedProjectRelocationGenesis._(
      plan['targetScopeId'],
      await codec.headHash(proposal),
      {'actionId': plan['actionId'], 'planHash': hash},
      plan['targetOwnerAccountId'],
    );
  }

  /// Verify a target genesis without parent READ, parent IDs or parent keys.
  /// The independently signed scoped anchor binds its complete hash ancestry;
  /// the final publisher then supplies exact proposal/activation and own-event
  /// timing. A server-selected target or unsigned roster supplies no anchor.
  Future<VerifiedProjectRelocationGenesis> _resolveRelocationGenesis(
    String scope,
    Map<String, dynamic> wire,
    Map<String, dynamic> origin,
  ) async {
    final marker = origin['projectRelocation'] as Map;
    final known = _relocationGenesis[scope];
    if (known != null) {
      if (known.header['actionId'] != marker['actionId'] ||
          known.header['planHash'] != marker['planHash']) {
        throw const FormatException('crypto_relocation_origin_substitution');
      }
      return known;
    }
    final ownHeader = _ownRelocationAnchors[scope];
    Map<String, dynamic> header;
    if (ownHeader != null && ownHeader['side'] == 'target') {
      header = ownHeader;
    } else {
      final anchor =
          _observedScopes[scope]?.last['headHash'] ??
          (_invitationScope == scope ? _invitationHead : null);
      if (anchor is! String) {
        throw const CryptoAuthorityPending(
          'crypto_relocation_origin_publication_pending',
        );
      }
      final evidence = await account.directory.call(
        'crypto2.projectRelocation.evidence',
        {'scopeId': scope, 'actionId': marker['actionId'], 'limit': 1},
      );
      final proof = Map<String, dynamic>.from(evidence['authorization'] as Map);
      header = CryptoProjectRelocationCodec.body(proof);
      CryptoProjectRelocationCodec.publication(header);
      if (header['scopeId'] != scope || header['side'] != 'target') {
        throw const FormatException('crypto_relocation_scoped_publication');
      }
      // Only hash ancestry is used here. The normal verifier below still
      // verifies EVERY proposal/signature/roster and current READ after this
      // narrowly scoped genesis exception has been established.
      var cursor = anchor;
      var matched = false;
      for (var n = 0; n < 10000; n++) {
        final ancestor = cursor == wire['headHash']
            ? wire
            : await _scopeCall('crypto2.scope.headGet', {
                'scopeId': scope,
                'headHash': cursor,
              });
        final body = Map<String, dynamic>.from(ancestor['payload'] as Map);
        if (body['scopeId'] != scope ||
            await codec.headHash(body) != cursor ||
            ancestor['headHash'] != cursor) {
          throw const FormatException('crypto_relocation_anchor_substitution');
        }
        if (cursor == header['membershipHeadHash']) {
          matched = true;
          break;
        }
        if (body['previousHeadHash'] == cryptoZeroHash) break;
        cursor = body['previousHeadHash'] as String;
      }
      if (!matched)
        throw const FormatException('crypto_relocation_anchor_missing');
      final genesis = header['membershipHeadHash'] == wire['headHash']
          ? wire
          : await _scopeCall('crypto2.scope.headGet', {
              'scopeId': scope,
              'headHash': header['membershipHeadHash'],
            });
      final body = genesis['payload'] as Map;
      final members = (body['members'] as List)
          .where((m) => m['accountId'] == header['accountId'])
          .toList();
      if (await codec.headHash(Map<String, dynamic>.from(body)) !=
              header['membershipHeadHash'] ||
          members.length != 1 ||
          members.single['manageKeys'] != true ||
          members.single['role'] == 'viewer') {
        throw const FormatException('crypto_relocation_publisher_membership');
      }
      final prefix = await directoryAt(
        scopeId: scope,
        scopeHeadHash: header['membershipHeadHash'],
        accountId: header['accountId'],
        directoryHeadHash: header['authorDirectoryHeadHash'],
        allowUnverifiedContact: true,
        online: true,
      );
      final member = members.single as Map;
      if (prefix.deviceSnapshotHash != member['deviceSnapshotHash'] ||
          prefix.snapshot['rootSigningKeyBase64'] !=
              member['rootSigningKeyBase64'] ||
          prefix.snapshot['rootEncryptionKeyBase64'] !=
              member['rootEncryptionKeyBase64']) {
        throw const FormatException('crypto_relocation_signer_binding');
      }
      final device = prefix.activeDevice(header['deviceId']);
      if (device['keyringWrite'] != true)
        throw const FormatException('crypto_relocation_signer_capability');
      final key = cryptoBase64(device['signingKeyBase64'], length: 32);
      codec.crypto.verifyDomain(
        proof,
        key,
        CryptoProjectRelocationCodec.publicationDomain,
      );
      final event = Map<String, dynamic>.from(
        evidence['eventAuthorization'] as Map,
      );
      final command = CryptoProjectRelocationCodec.body(event);
      CryptoProjectRelocationCodec.exact(command, {
        'version',
        'operation',
        'serverId',
        'accountId',
        'deviceId',
        'requestId',
        'signer',
        'payload',
      });
      final ep = Map<String, dynamic>.from(command['payload'] as Map);
      CryptoProjectRelocationCodec.exact(ep, {
        'expectedGeneration',
        'previousHeadHash',
        'identityEpochId',
        'resultingSnapshotHash',
        'actionId',
        'publicationRoot',
      });
      final pubHash = await CryptoProjectRelocationCodec.proofHash(proof);
      CryptoProjectRelocationCodec.hashValue(evidence['otherPublicationHash']);
      final root = await CryptoProjectRelocationCodec.publicationRoot(
        evidence['otherPublicationHash'],
        pubHash,
      );
      if (command['version'] != 2 ||
          command['operation'] != 'crypto2.account.projectRelocation' ||
          command['signer'] != 'device' ||
          command['serverId'] != header['serverId'] ||
          command['accountId'] != header['accountId'] ||
          command['deviceId'] != header['deviceId'] ||
          command['requestId'] != header['requestId'] ||
          ep['previousHeadHash'] != prefix.headHash ||
          ep['expectedGeneration'] != prefix.generation ||
          ep['identityEpochId'] != prefix.identityEpochId ||
          ep['resultingSnapshotHash'] != prefix.snapshotHash ||
          ep['actionId'] != header['actionId'] ||
          ep['publicationRoot'] != root) {
        throw const FormatException('crypto_relocation_event_binding');
      }
      codec.crypto.verifyDomain(event, key, cryptoDirectoryDomain);
      final commandHash = await cryptoSha256(
        cryptoBase64(event['commandBase64']),
      );
      final eventHash = await cryptoSha256([
        ...utf8.encode(cryptoDirectoryLogDomain),
        ...CryptoJson.encode({
          'serverId': header['serverId'],
          'accountId': header['accountId'],
          'generation': prefix.generation + 1,
          'previousHeadHash': prefix.headHash,
          'commandHash': commandHash,
          'signatureBase64': event['signatureBase64'],
        }),
      ]);
      if (evidence['eventHeadHash'] != eventHash ||
          evidence['eventCommandHash'] != commandHash)
        throw const FormatException('crypto_relocation_event_inclusion');
      final included = await directoryAt(
        scopeId: scope,
        scopeHeadHash: header['membershipHeadHash'],
        accountId: header['accountId'],
        directoryHeadHash: eventHash,
        allowUnverifiedContact: true,
        online: true,
      );
      if (included.generation != prefix.generation + 1 ||
          included.snapshotHash != prefix.snapshotHash ||
          !included.includesAnchor(prefix.generation, prefix.headHash))
        throw const FormatException('crypto_relocation_event_inclusion');
    }
    final genesis = header['membershipHeadHash'] == wire['headHash']
        ? wire
        : await _scopeCall('crypto2.scope.headGet', {
            'scopeId': scope,
            'headHash': header['membershipHeadHash'],
          });
    final body = genesis['payload'] as Map;
    final owners = (body['members'] as List)
        .where((m) => m['role'] == 'owner')
        .toList();
    if (header['serverId'] != account.directory.session.profile.serverId ||
        header['scopeId'] != scope ||
        header['side'] != 'target' ||
        header['actionId'] != marker['actionId'] ||
        header['planHash'] != marker['planHash'] ||
        header['accountId'] != origin['accountId'] ||
        header['deviceId'] != origin['deviceId'] ||
        body['epoch'] != 1 ||
        body['previousHeadHash'] != cryptoZeroHash ||
        body['accessIntentProof'] != null ||
        body['financePolicyIntentProof'] != null ||
        owners.length != 1 ||
        await codec.headHash(Map<String, dynamic>.from(body)) !=
            header['membershipHeadHash'] ||
        header['proposalProofHash'] !=
            await cryptoSha256(CryptoJson.encode(genesis['authorization'])) ||
        genesis['activationAuthorization'] == null ||
        header['activationProofHash'] !=
            await cryptoSha256(
              CryptoJson.encode(genesis['activationAuthorization']),
            )) {
      throw const FormatException('crypto_relocation_genesis_binding');
    }
    final token = VerifiedProjectRelocationGenesis._(
      scope,
      header['membershipHeadHash'],
      header,
      owners.single['accountId'],
    );
    _relocationGenesis[scope] = token;
    return token;
  }

  Future<String> verifyInitialLifecycle(
    String scopeId,
    Map<String, dynamic> wire, {
    required String scopeHeadHash,
  }) async {
    final baseline = wire['initialLifecycleBaseline'];
    final origin = wire['originAuthorization'];
    if (baseline is! Map ||
        baseline.length != 6 ||
        baseline['version'] != 2 ||
        baseline['scopeId'] != scopeId ||
        !['new', 'legacy'].contains(baseline['originKind']) ||
        baseline['ownArchived'] is! bool ||
        baseline['inheritedArchived'] is! bool ||
        origin is! Map)
      throw const FormatException('scope_lifecycle_baseline');
    final proof = Map<String, dynamic>.from(origin);
    final hash = await cryptoSha256(
      utf8.encode('JivieLifecycleBaseline/v2\n') + CryptoJson.encode(baseline),
    );
    if (hash != wire['initialLifecycleHash'] ||
        await cryptoSha256(CryptoJson.encode(proof)) !=
            baseline['originProofHash'])
      throw const FormatException('scope_lifecycle_baseline_hash');
    final raw = CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
    final publicOrigin = raw['operation'] == 'crypto2.scope.origin';
    final legacy = raw['operation'] == 'crypto2.scope.prepare';
    if (raw['version'] != 2 ||
        raw['serverId'] != account.directory.session.profile.serverId ||
        (!publicOrigin && !legacy))
      throw const FormatException('scope_lifecycle_origin');
    final String authorReference;
    if (publicOrigin) {
      final fields = {
        'version',
        'operation',
        'serverId',
        'scopeId',
        'kind',
        'accessPolicyVersion',
        'parentScopeToken',
        'requestId',
        'accountId',
        'deviceId',
        'authorDirectoryHeadHash',
        if (raw.containsKey('projectRelocation')) 'projectRelocation',
      };
      if (raw.length != fields.length ||
          raw.keys.any((k) => !fields.contains(k)) ||
          raw['scopeId'] != scopeId ||
          ![
            'personal',
            'household',
            'organization',
            'project',
          ].contains(raw['kind']) ||
          raw['accessPolicyVersion'] != (raw['kind'] == 'personal' ? 1 : 3) ||
          raw['parentScopeToken'] != null &&
              (raw['kind'] != 'project' ||
                  raw['parentScopeToken'] is! String ||
                  !RegExp(
                    r'^[a-f0-9]{64}$',
                  ).hasMatch(raw['parentScopeToken'])) ||
          baseline['originKind'] != 'new' ||
          baseline['ownArchived'] != false ||
          baseline['inheritedArchived'] != false)
        throw const FormatException('scope_public_origin');
      if (raw.containsKey('projectRelocation')) {
        final marker = raw['projectRelocation'];

        if (marker is! Map ||
            marker.length != 3 ||
            !marker.keys.toSet().containsAll({
              'version',
              'actionId',
              'planHash',
            }) ||
            marker['version'] != 2 ||
            !isCryptoCanonicalUuid(marker['actionId']) ||
            marker['planHash'] is! String ||
            !RegExp(r'^[0-9a-f]{64}$').hasMatch(marker['planHash']) ||
            raw['kind'] != 'project' ||
            raw['parentScopeToken'] == null) {
          throw const FormatException('crypto_relocation_origin_shape');
        }
        await _resolveRelocationGenesis(
          scopeId,
          wire,
          Map<String, dynamic>.from(raw),
        );
      }
      authorReference = raw['authorDirectoryHeadHash'];
      if (authorReference != wire['originAuthorDirectoryHeadHash'])
        throw const FormatException('scope_origin_author');
    } else {
      final p = raw['payload'] as Map;
      if (raw['signer'] != 'device' ||
          p['scopeId'] != scopeId ||
          baseline['originKind'] != 'legacy')
        throw const FormatException('scope_lifecycle_origin');
      authorReference = wire['originAuthorDirectoryHeadHash'];
    }
    final directory = await directoryAt(
      scopeId: scopeId,
      scopeHeadHash: scopeHeadHash,
      accountId: raw['accountId'],
      directoryHeadHash: authorReference,
      online: true,
      allowUnverifiedContact: true,
    );
    final actor = directory.activeDevice(raw['deviceId']);
    account.directory.reducer.crypto.verifyDomain(
      proof,
      cryptoBase64(actor['signingKeyBase64'], length: 32),
      publicOrigin ? 'JivieE2EE/scopeOrigin/v2\n' : cryptoDirectoryDomain,
    );
    if (publicOrigin)
      _scopeDescriptors[scopeId] = {
        'id': scopeId,
        'kind': raw['kind'],
        'accessPolicyVersion': raw['accessPolicyVersion'],
        'parentScopeToken': raw['parentScopeToken'],
        if (raw['kind'] == 'organization') 'leaderAccountIds': <String>[],
        'initialLifecycleHash': hash,
      };
    return hash;
  }

  Future<CryptoMigrationCandidate> migrationCandidate({
    required String scopeId,
    required String migrationId,
    String? captureId,
    String? headHash,
  }) async {
    if (!isCryptoCanonicalUuid(scopeId) ||
        !isCryptoCanonicalUuid(migrationId) ||
        captureId != null && !isCryptoCanonicalUuid(captureId)) {
      throw const FormatException('crypto_migration_candidate_context');
    }
    final own = await account.directory.requireFresh();
    final saved = await account.store.database.rows(
      'SELECT k.action_key,o.signed_body FROM crypto_command_keys k JOIN crypto_outbox o ON o.partition=k.partition AND o.request_id=k.request_id WHERE k.partition=? AND k.action_key LIKE ?',
      [
        account.store.partition,
        captureId == null ? 'capture:%:prepare' : 'capture:$captureId:prepare',
      ],
    );
    String? selectedCapture;
    final selectedDomains = <String>{};
    for (final row in saved) {
      final proof = Map<String, dynamic>.from(
        jsonDecode(row['signed_body'] as String) as Map,
      );
      final c = CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
      final payload = c['payload'];
      if (c['operation'] != 'crypto2.migration.capture.prepare' ||
          payload is! Map ||
          payload['captureVersion'] != 3 ||
          payload['migrationId'] != migrationId ||
          payload['scopeIds'] is! List ||
          payload['receiptSelections'] is! List ||
          captureId != null && payload['captureId'] != captureId) {
        continue;
      }
      final ownedScopes = payload['scopeIds'] as List;
      final selections = payload['receiptSelections'] as List;
      if (ownedScopes.length > 1000 ||
          selections.length > 2000 ||
          ownedScopes.any((id) => !isCryptoCanonicalUuid(id))) {
        throw const FormatException('crypto_migration_candidate_capture');
      }
      final domains = <String>{};
      if (ownedScopes.contains(scopeId)) domains.addAll(['content', 'finance']);
      String? previousSelection;
      for (final selection in selections) {
        if (selection is! Map ||
            selection.length != 2 ||
            !selection.containsKey('scopeId') ||
            !selection.containsKey('domain') ||
            !isCryptoCanonicalUuid(selection['scopeId']) ||
            !const ['content', 'finance'].contains(selection['domain'])) {
          throw const FormatException('crypto_migration_candidate_capture');
        }
        final order = '${selection['scopeId']}/${selection['domain']}';
        if (previousSelection != null &&
            previousSelection.compareTo(order) >= 0) {
          throw const FormatException('crypto_migration_candidate_capture');
        }
        previousSelection = order;
        if (selection['scopeId'] == scopeId)
          domains.add(selection['domain'] as String);
      }
      if (domains.isEmpty) continue;
      if (c['accountId'] != own.accountId ||
          c['serverId'] != own.serverId ||
          row['action_key'] != 'capture:${payload['captureId']}:prepare') {
        throw const FormatException('crypto_migration_candidate_capture');
      }
      final prefix = await directoryAt(
        scopeId: scopeId,
        scopeHeadHash: cryptoZeroHash,
        accountId: own.accountId,
        directoryHeadHash: payload['authorDirectoryHeadHash'],
        online: true,
        allowUnverifiedContact: true,
      );
      if (!own.includesAnchor(prefix.generation, prefix.headHash)) {
        throw const FormatException(
          'crypto_migration_candidate_capture_prefix',
        );
      }
      account.directory.reducer.crypto.verifyDomain(
        proof,
        cryptoBase64(
          prefix.activeDevice(c['deviceId'])['signingKeyBase64'],
          length: 32,
        ),
        cryptoDirectoryDomain,
      );
      if (selectedCapture != null && selectedCapture != payload['captureId']) {
        throw const CryptoAuthorityPending(
          'crypto_migration_candidate_capture_ambiguous',
        );
      }
      selectedCapture = payload['captureId'] as String;
      selectedDomains.addAll(domains);
    }
    if (selectedCapture == null) {
      throw const CryptoAuthorityPending(
        'crypto_migration_candidate_capture_pending',
      );
    }
    final wire = await _scopeCall('crypto2.scope.headGet', {
      'scopeId': scopeId,
      if (headHash != null) 'headHash': headHash,
    });
    if (headHash != null && wire['headHash'] != headHash ||
        wire['initialLifecycleBaseline']?['originKind'] != 'legacy') {
      throw const FormatException('crypto_migration_candidate_head');
    }
    final head = await _verifyHead(
      scopeId,
      wire,
      online: true,
      historical: true,
      descriptorGenesisOnly: true,
    );
    final member = head.member(own.accountId);
    if (member['deviceSnapshotHash'] != own.deviceSnapshotHash) {
      throw const CryptoAuthorityPending('crypto_migration_candidate_changed');
    }
    return CryptoMigrationCandidate._(
      this,
      head,
      migrationId,
      selectedCapture,
      own.headHash,
      wire,
      Set.unmodifiable(selectedDomains),
    );
  }

  Future<void> hydrateMigrationCandidateKeys(
    CryptoMigrationCandidate candidate,
  ) async {
    if (!candidate.isFor(this, candidate.head.scopeId)) {
      throw const FormatException('crypto_migration_candidate_context');
    }
    await candidate._guard();
    await _hydrateHeadKeys(
      candidate.head,
      descriptorGenesisWire: candidate._wire,
      candidateOnly: true,
    );
    await candidate._guard();
  }

  Future<void> _bootstrapMigrationDescriptor(
    String scopeId,
    Map<String, dynamic> wire, {
    RecoveredAccountRoot? recoveryRoot,
  }) async {
    VerifiedCryptoOwnContentContribution? ownContentBootstrap;
    if (!_hasScopedIdentityAnchor(scopeId) &&
        !await _hasCommittedMigrationIdentity(scopeId, wire['headHash'])) {
      for (final member in (wire['payload']['members'] as List).cast<Map>()) {
        if (await account.store.anchor(member['accountId']) == null) {
          ownContentBootstrap = await _committedOrigin
              .ownContentContributionForGenesis(scopeId, wire['headHash']);
          break;
        }
      }
    }
    final genesis = await _verifyHead(
      scopeId,
      wire,
      online: true,
      historical: true,
      descriptorGenesisOnly: true,
      descriptorIdentity: ownContentBootstrap,
    );
    final absentFromGenesis = !genesis.members.any(
      (m) => m['accountId'] == account.directory.accountId,
    );
    final admission = absentFromGenesis
        ? await _descriptorAdmission(scopeId, genesis)
        : null;
    late VerifiedCryptoMigrationGenesisDescriptor baseline;
    try {
      baseline = await _committedOrigin.scopeDescriptorFromGenesis(
        genesis,
        () async {
          try {
            return await candidateKey(genesis, 'content');
          } on CryptoAuthorityPending {
            // Missing retained key: authenticate the exact original wrapper.
          }
          CryptoKeyLease? key;
          try {
            await _hydrateHeadKeys(
              admission?._carrier ?? genesis,
              recoveryRoot: recoveryRoot,
              onlyDomain: 'content',
              descriptorGenesisWire: admission?._wire ?? wire,
              descriptorAdmission: admission,
              receiveDescriptorKey: (bytes) {
                if (key != null) {
                  throw const FormatException('scope_descriptor_key_duplicate');
                }
                key = CryptoKeyLease.owned(
                  account.directory.reducer.crypto.sodium.secureCopy(bytes),
                );
              },
            );
            if (key == null) {
              throw const CryptoAuthorityPending(
                'scope_descriptor_key_pending',
              );
            }
            final result = key!;
            key = null;
            return result;
          } finally {
            key?.release();
          }
        },
        ownContentBootstrap: ownContentBootstrap,
        descriptorAdmission: admission,
      );
      await admission?.requireContext(this, scopeId, genesis.headHash);
    } finally {
      if (admission != null) admission._active = false;
    }
    await ownContentBootstrap?.requireCurrent(
      account,
      scope: scopeId,
      genesisHash: genesis.headHash,
    );
    final descriptor = baseline.descriptor;
    if (baseline.scopeId != scopeId ||
        baseline.headHash != genesis.headHash ||
        descriptor['id'] != scopeId) {
      throw const FormatException('scope_descriptor_migration_context');
    }
    final own = await account.directory.cachedVerifiedDirectory();
    (_descriptorVerification?.genesisDescriptors ??
            _verifiedGenesisDescriptors)[scopeId] =
        baseline;
    (_descriptorVerification?.publications ??
            _verifiedGenesisPublications)[scopeId] =
        baseline.ownPublicationAnchors;
    if (baseline.ownPublicationAnchors.any(
      (anchor) =>
          anchor['scopeId'] == scopeId &&
          anchor['membershipHeadHash'] == genesis.headHash &&
          own.includesAnchor(anchor['generation'], anchor['headHash']),
    )) {
      _committedGenesisAnchors[scopeId] = {
        'headHash': genesis.headHash,
        'ownHeadHash': own.headHash,
        'proposalHash': await cryptoSha256(
          CryptoJson.encode(genesis.authorization),
        ),
        'activationHash': await cryptoSha256(
          CryptoJson.encode(wire['activationAuthorization']),
        ),
      };
    }
    _scopeDescriptors[scopeId] = {
      ...descriptor,
      'initialLifecycleHash': genesis.body['initialLifecycleHash'],
    };
  }

  Future<CryptoMigrationDescriptorAdmission> _descriptorAdmission(
    String scope,
    VerifiedScopeHead genesis,
  ) async {
    if (_observedScopes[scope]?.isNotEmpty == true) {
      final own = await account.directory.cachedVerifiedDirectory();
      final observations = await CryptoScopeObservations(
        account,
      ).recover(scope, descriptorHistory: true);
      if (!account.directory.isCurrent() ||
          (await account.directory.cachedVerifiedDirectory()).headHash !=
              own.headHash) {
        throw const CryptoAuthorityPending(
          'scope_descriptor_admission_changed',
        );
      }
      // Descriptor transport only: ordinary freshness/descendant checks retain
      // the latest-only _observedScopes anchors installed by normal recovery.
      final history = _DescriptorObservationHistory(
        scope,
        own.headHash,
        List.unmodifiable(observations),
      );
      final budget = _DescriptorCarrierBudget(), seen = <String>{};
      for (final observation in history.observations) {
        if (!seen.add(observation['headHash'] as String)) continue;
        try {
          return await _descriptorObservedCarrier(
            scope,
            genesis,
            observation,
            budget,
            history,
          );
        } on _DescriptorPolicyCarrierPending {
          // Only a policy successor needs an earlier authenticated carrier.
          // Current authority still verifies its complete chain after bootstrap.
        }
      }
      throw const CryptoAuthorityPending('scope_descriptor_admission_pending');
    }
    if (_invitationScope != scope ||
        _invitationHead == null ||
        _scopeAnchorProof == null ||
        _inviterAccount == null) {
      throw const CryptoAuthorityPending('scope_descriptor_admission_pending');
    }
    final own = await account.directory.cachedVerifiedDirectory();
    final stored = await account.store.database.rows(
      "SELECT intent_id,authorization FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND state IN ('invitationPendingAnchor','invitationScopeAnchor')",
      [account.store.partition, scope],
    );
    final anchorHash = await cryptoSha256(
      CryptoJson.encode(_scopeAnchorProof!),
    );
    final matching = <String>[];
    for (final row in stored) {
      if (await cryptoSha256(
            CryptoJson.encode(_decode(row['authorization'])),
          ) ==
          anchorHash) {
        matching.add(row['intent_id'] as String);
      }
    }
    if (matching.length != 1) {
      throw const FormatException('invitation_scope_anchor_conflict');
    }
    final invitation = matching.single;
    final inspected = await InviteCryptoRepository(
      this,
    ).inspect(invitationId: invitation);
    if (await cryptoSha256(CryptoJson.encode(inspected.authorization)) !=
        anchorHash) {
      throw const FormatException('invitation_activation_substitution');
    }
    final status = await account.directory.call('crypto2.invitations.status', {
      'invitationId': invitation,
    });
    if (status['state'] != 'consumed' || status['scope']?['id'] != scope) {
      throw const CryptoAuthorityPending('scope_descriptor_admission_pending');
    }
    final proofRaw = inspected.response['recipientAcceptanceAuthorization'];
    if (proofRaw is! Map) {
      throw const CryptoAuthorityPending('invitation_acceptance_pending');
    }
    final proof = Map<String, dynamic>.from(proofRaw);
    final command =
        CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
    final p = Map<String, dynamic>.from(command['payload'] as Map);
    final expected =
        inspected.legacyEvidence?.acceptancePayload ??
        (CryptoJson.decode(cryptoBase64(_scopeAnchorProof!['commandBase64']))
                as Map)['payload']
            as Map;
    final fields = {
      'scopeId',
      'invitationId',
      'tokenHash',
      'creatorProofHash',
      'role',
      'expiresAt',
      'membershipHeadHash',
      'authorDirectoryHeadHash',
    };
    if (command.length != 8 ||
        command['version'] != 2 ||
        command['signer'] != 'device' ||
        command['operation'] != 'crypto2.invitations.accept' ||
        command['serverId'] != own.serverId ||
        command['accountId'] != own.accountId ||
        p.length != fields.length ||
        !fields.every(p.containsKey) ||
        p['scopeId'] != scope ||
        p['invitationId'] != invitation ||
        p['creatorProofHash'] != anchorHash ||
        p['membershipHeadHash'] != _invitationHead ||
        !['tokenHash', 'role', 'expiresAt'].every((k) => p[k] == expected[k]) ||
        await cryptoSha256(CryptoJson.encode(proof)) !=
            status['acceptanceProofHash']) {
      throw const FormatException('invitation_activation_substitution');
    }
    final signer = await directoryAt(
      scopeId: scope,
      scopeHeadHash: status['activatedHeadHash'],
      accountId: own.accountId,
      directoryHeadHash: p['authorDirectoryHeadHash'],
      online: true,
    );
    if (!own.includesAnchor(signer.generation, signer.headHash)) {
      throw const FormatException('invitation_acceptance_fork');
    }
    account.directory.reducer.crypto.verifyDomain(
      proof,
      cryptoBase64(
        signer.activeDevice(command['deviceId'])['signingKeyBase64'],
        length: 32,
      ),
      cryptoDirectoryDomain,
    );
    final transport = await _descriptorCarrierChain(
      scope,
      genesis,
      own,
      status['activatedHeadHash'],
      invitationAnchor: _invitationHead,
    );
    final chain = transport.chain;
    final admitted = chain.last, body = admitted.body;
    final member =
        (body['members'] as List).singleWhere(
              (m) => m['accountId'] == own.accountId,
            )
            as Map;
    final intents = (body['membershipIntents'] as List)
        .where(
          (i) =>
              i['accountId'] == own.accountId &&
              i['invitationId'] == invitation &&
              i['acceptanceProofHash'] == status['acceptanceProofHash'],
        )
        .toList();
    if (intents.length != 1 ||
        member['role'] != p['role'] ||
        member['deviceSnapshotHash'] != own.deviceSnapshotHash ||
        member['rootSigningKeyBase64'] !=
            own.snapshot['rootSigningKeyBase64'] ||
        member['rootEncryptionKeyBase64'] !=
            own.snapshot['rootEncryptionKeyBase64']) {
      throw const FormatException('invitation_activation_substitution');
    }
    final result = CryptoMigrationDescriptorAdmission._(
      this,
      genesis,
      admitted,
      transport.wire,
      own.headHash,
      chain,
      _invitationHead!,
      null,
      null,
      null,
    );
    await result.requireContext(this, scope, genesis.headHash);
    return result;
  }

  Future<CryptoMigrationDescriptorAdmission> _descriptorObservedCarrier(
    String scope,
    VerifiedScopeHead genesis,
    Map<String, dynamic> observation,
    _DescriptorCarrierBudget budget,
    _DescriptorObservationHistory history,
  ) async {
    final own = await account.directory.cachedVerifiedDirectory();
    if (observation['serverId'] != own.serverId ||
        observation['accountId'] != own.accountId ||
        observation['scopeId'] != scope ||
        observation['observationHash'] is! String ||
        observation['generation'] is! int) {
      throw const FormatException('scope_observation_substitution');
    }
    final transport = await _descriptorCarrierChain(
      scope,
      genesis,
      own,
      observation['headHash'],
      routePolicyCarrier: true,
      budget: budget,
    );
    final carrier = transport.chain.last, wire = transport.wire;
    final activation = Map<String, dynamic>.from(
      wire['activationAuthorization'] as Map,
    );
    final command =
        CryptoJson.decode(cryptoBase64(activation['commandBase64'])) as Map;
    if (observation['proposalProofHash'] !=
            await cryptoSha256(CryptoJson.encode(carrier.authorization)) ||
        observation['activationProofHash'] !=
            await cryptoSha256(CryptoJson.encode(activation)) ||
        observation['grantManifestHash'] !=
            command['payload']['grantManifestHash']) {
      throw const FormatException('scope_observation_head_substitution');
    }
    final members = (observation['members'] as List).cast<Map>();
    if (members.length != carrier.members.length) {
      throw const FormatException('scope_observation_members');
    }
    for (var i = 0; i < members.length; i++) {
      final m = carrier.members[i], o = members[i];
      if (o['accountId'] != m['accountId'] ||
          o['directoryHeadHash'] != m['directoryHeadHash'] ||
          o['deviceSnapshotHash'] != m['deviceSnapshotHash'] ||
          o['rootFingerprint'] !=
              account.directory.reducer.crypto.fingerprint(
                cryptoBase64(m['rootSigningKeyBase64']),
                cryptoBase64(m['rootEncryptionKeyBase64']),
              )) {
        throw const FormatException('scope_observation_members');
      }
    }
    final member = carrier.member(own.accountId);
    final historicalOwn = await directoryAt(
      scopeId: scope,
      scopeHeadHash: carrier.headHash,
      accountId: own.accountId,
      directoryHeadHash: member['directoryHeadHash'],
      online: true,
    );
    // A FILE-recovered device has a newer snapshot. This transport accepts only
    // the exact own historical prefix already included in its verified lineage.
    if (!own.includesAnchor(historicalOwn.generation, historicalOwn.headHash) ||
        member['rootSigningKeyBase64'] !=
            own.snapshot['rootSigningKeyBase64'] ||
        member['rootEncryptionKeyBase64'] !=
            own.snapshot['rootEncryptionKeyBase64']) {
      throw const FormatException('scope_observation_members');
    }
    final result = CryptoMigrationDescriptorAdmission._(
      this,
      genesis,
      carrier,
      wire,
      own.headHash,
      transport.chain,
      null,
      observation['observationHash'],
      observation['generation'],
      history,
    );
    await result.requireContext(this, scope, genesis.headHash);
    return result;
  }

  Future<({List<VerifiedScopeHead> chain, Map<String, dynamic> wire})>
  _descriptorCarrierChain(
    String scope,
    VerifiedScopeHead genesis,
    VerifiedAccountDirectory own,
    String carrierHash, {
    String? invitationAnchor,
    bool routePolicyCarrier = false,
    _DescriptorCarrierBudget? budget,
  }) async {
    final wires = <Map<String, dynamic>>[];
    final limits = budget ?? _DescriptorCarrierBudget();
    var cursor = carrierHash;
    while (cursor != genesis.headHash) {
      if (limits.heads >= 128) {
        throw const CryptoAuthorityPending(
          'scope_descriptor_admission_pending',
        );
      }
      final next = await _scopeCall('crypto2.scope.headGet', {
        'scopeId': scope,
        'headHash': cursor,
      });
      final body = Map<String, dynamic>.from(next['payload'] as Map);
      codec.validateBody(body);
      limits.heads++;
      limits.bytes += CryptoJson.encode(next).length;
      // No unknown policy is used to release an intent. The whole signed chain
      // is reverified normally with the decrypted baseline after this transport.
      if (next['headHash'] != cursor ||
          await codec.headHash(body) != cursor ||
          body['scopeId'] != scope ||
          body['epoch'] <= genesis.epoch ||
          limits.bytes > 16 * 1024 * 1024) {
        throw const CryptoAuthorityPending(
          'scope_descriptor_admission_pending',
        );
      }
      if (body['accessIntentProof'] != null ||
          body['financePolicyIntentProof'] != null) {
        if (routePolicyCarrier) throw const _DescriptorPolicyCarrierPending();
        throw const CryptoAuthorityPending(
          'scope_descriptor_admission_pending',
        );
      }
      wires.add(next);
      cursor = body['previousHeadHash'] as String;
    }
    if (wires.isEmpty ||
        invitationAnchor != null &&
            ![
              genesis.headHash,
              ...wires.map((w) => w['headHash']),
            ].contains(invitationAnchor)) {
      throw const FormatException('invitation_activation_substitution');
    }
    final chain = <VerifiedScopeHead>[genesis];
    for (final wire in wires.reversed) {
      final body = Map<String, dynamic>.from(wire['payload'] as Map),
          hash = wire['headHash'] as String;
      final previous = chain.last;
      if (await verifyInitialLifecycle(scope, wire, scopeHeadHash: hash) !=
          body['initialLifecycleHash']) {
        throw const FormatException('invitation_activation_substitution');
      }
      Future<VerifiedAccountDirectory> directory(String id, String ref) =>
          directoryAt(
            scopeId: scope,
            scopeHeadHash: hash,
            accountId: id,
            directoryHeadHash: ref,
            online: true,
          );
      Future<VerifiedAccountDirectory> managerDirectory(
        String id,
        String ref,
      ) async {
        final member = previous.member(id);
        if (member['manageKeys'] != true) {
          throw const FormatException('scope_management_forbidden');
        }
        final prefix = await directory(id, ref);
        final prior = await directoryAt(
          scopeId: scope,
          scopeHeadHash: previous.headHash,
          accountId: id,
          directoryHeadHash: member['directoryHeadHash'],
          online: true,
        );
        if (prefix.snapshot['rootSigningKeyBase64'] !=
                member['rootSigningKeyBase64'] ||
            prefix.snapshot['rootEncryptionKeyBase64'] !=
                member['rootEncryptionKeyBase64'] ||
            !prefix.includesAnchor(prior.generation, prior.headHash)) {
          throw const FormatException('invitation_identity_substitution');
        }
        return prefix;
      }

      final authorization = Map<String, dynamic>.from(
        wire['authorization'] as Map,
      );
      final authorCommand =
          CryptoJson.decode(cryptoBase64(authorization['commandBase64']))
              as Map;
      final author = await managerDirectory(
        authorCommand['accountId'],
        body['authorDirectoryHeadHash'],
      );
      final pending = await codec.verifyProposal(
        serverId: own.serverId,
        authorization: authorization,
        previous: previous,
        authorDirectory: author,
        directoryAtHead: directory,
        checkIdentity: (id, fp) async {
          final member =
              (body['members'] as List).singleWhere((m) => m['accountId'] == id)
                  as Map;
          final expectedFp = account.directory.reducer.crypto.fingerprint(
            cryptoBase64(member['rootSigningKeyBase64'], length: 32),
            cryptoBase64(member['rootEncryptionKeyBase64'], length: 32),
          );
          if (fp != expectedFp ||
              id == own.accountId && fp != identities.fingerprint(own)) {
            throw const FormatException('invitation_identity_substitution');
          }
        },
      );
      final activation = Map<String, dynamic>.from(
        wire['activationAuthorization'] as Map,
      );
      final activationCommand =
          CryptoJson.decode(cryptoBase64(activation['commandBase64'])) as Map;
      final ap = activationCommand['payload'] as Map;
      chain.add(
        await codec.verifyActivation(
          pending: pending,
          previous: previous,
          authorization: activation,
          authorDirectory: await managerDirectory(
            activationCommand['accountId'],
            ap['authorDirectoryHeadHash'],
          ),
          grantManifestHash: ap['grantManifestHash'],
          directoryAtHead: directory,
        ),
      );
    }
    return (
      chain: List<VerifiedScopeHead>.unmodifiable(chain),
      wire: wires.first,
    );
  }

  Set<String> verifiedMigrationPublicationCommandHashes(String scopeId) => {
    for (final anchor
        in _verifiedGenesisPublications[scopeId] ??
            const <Map<String, dynamic>>[])
      anchor['commandHash'] as String,
  };

  Future<VerifiedRecoveredMigrationGenesis?> recoveredMigrationGenesis(
    String scopeId,
  ) async {
    if (!account.directory.isCurrent()) {
      throw const CryptoAuthorityPending('scope_recovery_identity_changed');
    }
    final value = _verifiedGenesisDescriptors[scopeId];
    if (value == null || _readOnlyFrozen != null) return null;
    final own = await account.directory.cachedVerifiedDirectory();
    for (final anchor in value.ownPublicationAnchors) {
      if (!own.includesAnchor(anchor['generation'], anchor['headHash'])) {
        throw const CryptoAuthorityPending(
          'scope_recovery_publication_changed',
        );
      }
    }
    return VerifiedRecoveredMigrationGenesis._(
      value.scopeId,
      value.headHash,
      value.migrationId,
    );
  }

  Future<VerifiedProjectRelocationGenesis> verifiedRelocationGenesis(
    String scopeId,
  ) async {
    await currentHead(scopeId, online: true);
    final value = _relocationGenesis[scopeId];
    if (value == null)
      throw const CryptoAuthorityPending(
        'crypto_relocation_origin_publication_pending',
      );
    return value;
  }

  /// Encrypted target metadata is accepted only through the exact finalized
  /// target record publication. Neither creator identity nor a restored SQL
  /// policy row can establish this initial financial baseline.
  Future<Map<String, dynamic>> verifiedRelocatedScopeBaseline(
    String scopeId,
  ) async {
    await currentHead(scopeId, online: true);
    final genesis = _relocationGenesis[scopeId];
    if (genesis == null)
      throw const CryptoAuthorityPending(
        'crypto_relocation_origin_publication_pending',
      );
    final runtime = CryptoBusinessSession(
      account,
      this,
      account.store.database,
    );
    final canonical = await runtime.reservedRecordId(scopeId, 'scopeMetadata');
    final address = runtime.address(
      scopeId,
      'content',
      'scopeMetadata',
      canonical,
    );
    final read = await readContext(scopeId, 'content');
    final response = await account.directory
        .call('crypto2.records.historyGet', {
          'scopeId': scopeId,
          'domain': 'content',
          'accessRevision': read.accessRevision,
          'id': address.wireId,
          'revision': 1,
        });
    final wire = Map<String, dynamic>.from(response['record'] as Map);
    final proof = Map<String, dynamic>.from(
      wire['authorization']['recordProof'] as Map,
    );
    final record = Map<String, dynamic>.from(
      CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map,
    );
    final purpose = await _projectRelocation.verify(record);
    if (purpose.side != 'target' ||
        record['scopeId'] != scopeId ||
        record['id'] != address.wireId ||
        record['type'] != 'scopeMetadata' ||
        record['expectedRevision'] != 0 ||
        record['deleted'] != false ||
        record['membershipHeadHash'] != genesis.headHash)
      throw const FormatException('crypto_relocation_metadata_binding');
    await runtime.codec.verifyWire(
      serverId: account.directory.session.profile.serverId,
      wire: wire,
      trustedSigningKey: purpose.authority.signingKey,
      currentEpoch: purpose.authority.currentEpoch,
      closedRecordProofHash: purpose.authority.closedRecordProofHash,
    );
    final key = await recordKey(record);
    Uint8List? plaintext;
    try {
      plaintext = runtime.codec.openVerified(record, key.key);
      if (plaintext == null)
        throw const FormatException('crypto_relocation_metadata_binding');
      final envelope = jsonDecode(utf8.decode(plaintext)) as Map;
      final raw = envelope['payload'];
      final policy = raw is Map ? raw['financePolicy'] : null;
      final expected = CryptoFinancePolicySnapshot(
        enabled: true,
        revision: 1,
        requiredContractVersion: 3,
        grants: [
          {'accountId': genesis.ownerAccountId, 'grant': 'write'},
        ],
      );
      final expectedPolicy = {
        ...expected.header,
        'policyHash': await expected.hash(),
        'grantCount': 1,
      };
      if (envelope['format'] != 2 ||
          base64Encode(CryptoJson.encode(envelope['identity'])) !=
              base64Encode(CryptoJson.encode(address.identity)) ||
          raw is! Map ||
          raw['scopeId'] != scopeId ||
          raw['namespaceVersion'] != 1 ||
          raw['kind'] != 'project' ||
          raw['accessPolicyVersion'] != 3 ||
          raw['parentScopeToken'] !=
              _scopeDescriptors[scopeId]?['parentScopeToken'] ||
          base64Encode(CryptoJson.encode(policy)) !=
              base64Encode(CryptoJson.encode(expectedPolicy)))
        throw const FormatException('crypto_relocation_metadata_policy');
      final descriptor = {
        ...?_scopeDescriptors[scopeId],
        'financePolicy': Map<String, dynamic>.from(policy as Map),
      };
      _scopeDescriptors[scopeId] = descriptor;
      return Map<String, dynamic>.unmodifiable(descriptor);
    } finally {
      plaintext?.fillRange(0, plaintext.length, 0);
      key.release();
    }
  }

  Future<Map<String, dynamic>> verifiedMigrationScopeBaseline(
    String scopeId,
  ) async {
    await currentHead(scopeId, online: true);
    final value = _scopeDescriptors[scopeId];
    if (value == null || value['financePolicy'] == null) {
      throw const CryptoAuthorityPending('scope_descriptor_migration_pending');
    }
    return Map<String, dynamic>.unmodifiable(value);
  }

  Future<VerifiedScopeHead> _verifyHead(
    String scopeId,
    Map<String, dynamic> wire, {
    required bool online,
    bool historical = false,
    bool descriptorGenesisOnly = false,
    VerifiedCryptoOwnContentContribution? descriptorIdentity,
    bool requireDescriptor = false,
    RecoveredAccountRoot? descriptorRecoveryRoot,
  }) async {
    final hash = wire['headHash'] as String;
    final p = Map<String, dynamic>.from(wire['payload'] as Map);
    if (descriptorIdentity != null) {
      if (!descriptorGenesisOnly) {
        throw const FormatException('scope_descriptor_genesis_only');
      }
      await descriptorIdentity.requireCurrent(
        account,
        scope: scopeId,
        genesisHash: hash,
      );
    }
    // Bind the baseline/descriptor to this exact authenticated head before
    // touching derived metadata, including when the head itself is cached.
    if (p['scopeId'] != scopeId || await codec.headHash(p) != hash) {
      throw const FormatException('scope_head_substitution');
    }
    if (await verifyInitialLifecycle(scopeId, wire, scopeHeadHash: hash) !=
        p['initialLifecycleHash'])
      throw const FormatException('scope_lifecycle_baseline_substitution');
    final ownRelocation =
        _relocationGenesis[scopeId]?.header ?? _ownRelocationAnchors[scopeId];
    if (ownRelocation != null && ownRelocation['membershipHeadHash'] == hash) {
      if (ownRelocation['proposalProofHash'] !=
              await cryptoSha256(CryptoJson.encode(wire['authorization'])) ||
          wire['activationAuthorization'] == null ||
          ownRelocation['activationProofHash'] !=
              await cryptoSha256(
                CryptoJson.encode(wire['activationAuthorization']),
              )) {
        throw const FormatException('crypto_relocation_head_substitution');
      }
    }
    final scopeAnchor = await account.store.secure.read(
      'scope2:${account.store.partition}:$scopeId',
    );
    if (scopeAnchor != null) {
      final floor =
          CryptoJson.decode(Uint8List.fromList(utf8.encode(scopeAnchor)))
              as Map;
      if (p['epoch'] == floor['epoch'] && hash != floor['headHash']) {
        throw const FormatException('scope_known_fork');
      }
    }
    if (descriptorGenesisOnly &&
        (p['epoch'] != 1 ||
            p['previousHeadHash'] != cryptoZeroHash ||
            p['financePolicyIntentProof'] != null ||
            p['accessIntentProof'] != null)) {
      throw const FormatException('scope_descriptor_genesis_only');
    }
    if (!descriptorGenesisOnly &&
        requireDescriptor &&
        _scopeDescriptors[scopeId] == null &&
        p['epoch'] == 1) {
      await _bootstrapMigrationDescriptor(
        scopeId,
        wire,
        recoveryRoot: descriptorRecoveryRoot,
      );
    }
    if (!descriptorGenesisOnly &&
        _heads[hash]?.active == true &&
        (!requireDescriptor || _scopeDescriptors[scopeId] != null)) {
      return _heads[hash]!;
    }
    VerifiedScopeHead? previous;
    if (p['previousHeadHash'] != cryptoZeroHash) {
      final rows = await account.store.database.rows(
        'SELECT authorization FROM crypto_scope_heads WHERE partition=? AND scope_id=? AND head_hash=?',
        [account.store.partition, scopeId, p['previousHeadHash']],
      );
      if (rows.isNotEmpty) {
        previous = await _verifyHead(
          scopeId,
          _decode(rows.single['authorization']),
          online: online,
          historical: true,
          requireDescriptor: requireDescriptor || p['epoch'] > 1,
          descriptorRecoveryRoot: descriptorRecoveryRoot,
        );
      } else if (online)
        previous = await _verifyHead(
          scopeId,
          await _scopeCall('crypto2.scope.headGet', {
            'scopeId': scopeId,
            'headHash': p['previousHeadHash'],
          }),
          online: true,
          historical: true,
          requireDescriptor: requireDescriptor || p['epoch'] > 1,
          descriptorRecoveryRoot: descriptorRecoveryRoot,
        );
      else {
        throw const CryptoAuthorityPending('scope_history_pending');
      }
    }
    final proof = Map<String, dynamic>.from(wire['authorization'] as Map);
    final c = CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
    final author = await directoryAt(
      scopeId: scopeId,
      scopeHeadHash: hash,
      accountId: c['accountId'],
      directoryHeadHash: p['authorDirectoryHeadHash'],
      online: online,
      allowUnverifiedContact: descriptorGenesisOnly,
    );
    for (final ancestor in _heads.values.where(
      (h) => h.scopeId == scopeId && h.headHash != hash,
    )) {
      for (final domain in ['content', 'finance']) {
        final key = (p['keyIds'] as Map)[domain],
            commitment = (p['keyCommitments'] as Map)[domain];
        if (key != null &&
                (ancestor.body['keyIds'] as Map).values.contains(key) ||
            commitment != null &&
                (ancestor.body['keyCommitments'] as Map).values.contains(
                  commitment,
                )) {
          throw const FormatException('scope_historical_key_reused');
        }
      }
    }
    final policyVersion = _knownPolicyVersion(scopeId, previous);
    if (p['financePolicyIntentProof'] != null && policyVersion == null) {
      throw const CryptoAuthorityPending('scope_descriptor_migration_pending');
    }
    final proposed = await codec.verifyProposal(
      expectedProjectRelocation: p['epoch'] == 1
          ? _relocationGenesis[scopeId]
          : null,
      accessPolicyVersion: policyVersion,
      serverId: account.directory.session.profile.serverId,
      authorization: proof,
      previous: previous,
      authorDirectory: author,
      directoryAtHead: (id, head) => directoryAt(
        scopeId: scopeId,
        scopeHeadHash: hash,
        accountId: id,
        directoryHeadHash: head,
        online: online,
        allowUnverifiedContact: descriptorGenesisOnly,
      ),
      checkIdentity: (id, fp) async {
        if (_readOnlyFrozen?.scopeId == scopeId) return;
        if (_hasScopedIdentityAnchor(scopeId)) return;
        if (await _hasCommittedMigrationIdentity(scopeId, hash)) return;
        if (descriptorGenesisOnly && descriptorIdentity != null) {
          await descriptorIdentity.requireCurrent(
            account,
            scope: scopeId,
            genesisHash: hash,
          );
          return;
        }
        final pin = await account.store.anchor(id);
        if (pin == null) {
          throw const CryptoAuthorityPending('identity_verification_required');
        }
        if (id != account.directory.accountId) {
          await identities.requireVerified(id, pin['fingerprint']);
        }
      },
    );
    if (wire['activationAuthorization'] == null) {
      throw const CryptoAuthorityPending('scope_keys_pending');
    }
    final activation = Map<String, dynamic>.from(
      wire['activationAuthorization'] as Map,
    );
    final ac =
        CryptoJson.decode(cryptoBase64(activation['commandBase64'])) as Map;
    final activationAuthor = await directoryAt(
      scopeId: scopeId,
      scopeHeadHash: hash,
      accountId: ac['accountId'],
      directoryHeadHash: (ac['payload'] as Map)['authorDirectoryHeadHash'],
      online: online,
      allowUnverifiedContact: descriptorGenesisOnly,
    );
    final activated = await codec.verifyActivation(
      pending: proposed,
      previous: previous,
      authorization: activation,
      authorDirectory: activationAuthor,
      grantManifestHash: (ac['payload'] as Map)['grantManifestHash'],
      directoryAtHead: (id, head) => directoryAt(
        scopeId: scopeId,
        scopeHeadHash: hash,
        accountId: id,
        directoryHeadHash: head,
        online: online,
        allowUnverifiedContact: descriptorGenesisOnly,
      ),
      expectedProjectRelocation: p['epoch'] == 1
          ? _relocationGenesis[scopeId]
          : null,
    );
    for (final observation
        in _observedScopes[scopeId] ?? const <Map<String, dynamic>>[]) {
      if (observation['headHash'] != hash) continue;
      if (observation['proposalProofHash'] !=
              await cryptoSha256(CryptoJson.encode(proof)) ||
          observation['activationProofHash'] !=
              await cryptoSha256(CryptoJson.encode(activation)) ||
          observation['grantManifestHash'] !=
              (ac['payload'] as Map)['grantManifestHash'])
        throw const FormatException('scope_observation_head_substitution');
      final members = (observation['members'] as List).cast<Map>();
      if (members.length != activated.members.length)
        throw const FormatException('scope_observation_members');
      for (var i = 0; i < members.length; i++) {
        final m = activated.members[i], o = members[i];
        if (o['accountId'] != m['accountId'] ||
            o['directoryHeadHash'] != m['directoryHeadHash'] ||
            o['deviceSnapshotHash'] != m['deviceSnapshotHash'] ||
            o['rootFingerprint'] !=
                account.directory.reducer.crypto.fingerprint(
                  cryptoBase64(m['rootSigningKeyBase64']),
                  cryptoBase64(m['rootEncryptionKeyBase64']),
                ))
          throw const FormatException('scope_observation_members');
      }
    }
    if (descriptorGenesisOnly) {
      await descriptorIdentity?.requireCurrent(
        account,
        scope: scopeId,
        genesisHash: hash,
      );
      return activated;
    }
    await account.store.database.execute(
      'INSERT INTO crypto_scope_heads VALUES(?,?,?,?,?,?,?,?,?) ON CONFLICT(partition,scope_id,head_hash) DO UPDATE SET authorization=excluded.authorization',
      [
        account.store.partition,
        scopeId,
        hash,
        activated.epoch,
        activated.epoch,
        activated.epoch.toString(),
        p['previousHeadHash'],
        CryptoJson.encode(p),
        CryptoJson.encode(wire),
      ],
    );
    _heads[hash] = activated;
    return activated;
  }

  Future<VerifiedScopeHead> headAt(
    String scopeId,
    String hash, {
    bool online = false,
  }) async {
    await currentHead(scopeId, online: online);
    final result = _heads[hash];
    if (result == null || result.scopeId != scopeId) {
      throw const CryptoAuthorityPending('scope_history_pending');
    }
    return result;
  }

  Future<void> hydrateClosures(String scopeId) async {
    final current = await currentHead(scopeId, online: true);
    if (current.body['previousHeadHash'] == cryptoZeroHash) return;
    final source = await headAt(scopeId, current.body['previousHeadHash']);
    for (final domain in ['content', 'finance']) {
      final hash = (current.body['closures'] as Map)[domain];
      if (hash == null) continue;
      if (domain == 'finance' &&
          current.member(account.directory.accountId)['financeRole'] ==
              'none') {
        continue;
      }
      final descriptors = <Map<String, dynamic>>[];
      String? after;
      Map<String, dynamic>? certificate;
      String? basis;
      var bytes = 0;
      while (true) {
        final page = await _scopeCall('crypto2.scope.closureGet', {
          'scopeId': scopeId,
          'candidateHeadHash': current.headHash,
          'domain': domain,
          'epoch': source.epoch,
          'manifestHash': hash,
          if (after != null) 'afterId': after,
          'limit': 50,
        });
        if (page['scopeId'] != scopeId ||
            page['candidateHeadHash'] != current.headHash ||
            page['domain'] != domain ||
            page['epoch'] != source.epoch ||
            page['manifestHash'] != hash ||
            page['descriptors'] is! List ||
            (page['descriptors'] as List).length > 50) {
          throw const FormatException('closure_page_substitution');
        }
        final proof = Map<String, dynamic>.from(page['authorization'] as Map);
        if (certificate != null &&
            base64Encode(CryptoJson.encode(certificate)) !=
                base64Encode(CryptoJson.encode(proof))) {
          throw const FormatException('closure_changed');
        }
        certificate = proof;
        basis = page['historyBasis'];
        for (final descriptor
            in (page['descriptors'] as List).cast<Map<String, dynamic>>()) {
          bytes += CryptoJson.encode(descriptor).length;
          if (bytes > 64 * 1024 * 1024) {
            throw const CryptoAuthorityPending('closure_inventory_pending');
          }
          if (after != null &&
              (descriptor['id'] as String).compareTo(after) <= 0) {
            throw const FormatException('closure_cursor');
          }
          descriptors.add(descriptor);
          after = descriptor['id'];
        }
        if (page['hasMore'] != true) break;
        if ((page['descriptors'] as List).isEmpty ||
            page['nextAfterId'] != after) {
          throw const FormatException('closure_cursor');
        }
      }
      final row = <String, Object?>{
        'partition': account.store.partition,
        'scope_id': scopeId,
        'domain': domain,
        'epoch': source.epoch,
        'candidate_head_hash': current.headHash,
        'manifest_hash': hash,
        'history_basis': basis,
        'authorization': CryptoJson.encode(certificate),
        'descriptors': CryptoJson.encodeDerivedState(descriptors),
      };
      await _verifyClosure(row, current);
      await account.store.database.execute(
        'INSERT INTO crypto_scope_closures VALUES(?,?,?,?,?,?,?,?,?) ON CONFLICT(partition,scope_id,domain,epoch,candidate_head_hash) DO UPDATE SET authorization=excluded.authorization,descriptors=excluded.descriptors',
        [
          row['partition'],
          row['scope_id'],
          row['domain'],
          row['epoch'],
          row['candidate_head_hash'],
          row['manifest_hash'],
          row['history_basis'],
          row['authorization'],
          row['descriptors'],
        ],
      );
    }
  }

  Future<List<Map<String, dynamic>>> _verifyClosure(
    Map<String, Object?> row,
    VerifiedScopeHead current,
  ) async {
    final proof = _decode(row['authorization']);
    final raw = CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
    final payload = Map<String, dynamic>.from(raw['payload'] as Map);
    final fields = {
      'scopeId',
      'candidateHeadHash',
      'domain',
      'epoch',
      'membershipHeadHash',
      'expectedSequence',
      'recordCount',
      'manifestHash',
      'historyBasis',
      'authorDirectoryHeadHash',
      if (row['domain'] == 'content') 'closingLifecycleHash',
    };
    if (payload.length != fields.length ||
        payload.keys.any((k) => !fields.contains(k)) ||
        raw['version'] != 2 ||
        raw['operation'] != 'crypto2.scope.closeDomain' ||
        raw['signer'] != 'device' ||
        raw['serverId'] != account.directory.session.profile.serverId ||
        payload['scopeId'] != current.scopeId ||
        payload['candidateHeadHash'] != current.headHash ||
        payload['candidateHeadHash'] != row['candidate_head_hash'] ||
        payload['domain'] != row['domain'] ||
        payload['epoch'] != row['epoch'] ||
        payload['manifestHash'] != row['manifest_hash'] ||
        payload['manifestHash'] !=
            (current.body['closures'] as Map)[row['domain']] ||
        payload['historyBasis'] != row['history_basis'] ||
        (row['domain'] == 'content' &&
            payload['closingLifecycleHash'] !=
                current.body['previousLifecycleHash']) ||
        ![
          'verifiedCheckpoint',
          'reviewedRecoveryBaseline',
        ].contains(payload['historyBasis']) ||
        payload['expectedSequence'] is! int ||
        (payload['expectedSequence'] as int) < 0) {
      throw const FormatException('closure_certificate');
    }
    final source = await headAt(
      current.scopeId,
      current.body['previousHeadHash'],
    );
    if (payload['epoch'] != source.epoch ||
        payload['membershipHeadHash'] != source.headHash) {
      throw const FormatException('closure_source_head');
    }
    final author = await directoryAt(
      scopeId: current.scopeId,
      scopeHeadHash: current.headHash,
      accountId: raw['accountId'],
      directoryHeadHash: payload['authorDirectoryHeadHash'],
    );
    final member = source.member(raw['accountId']);
    if (member['role'] == 'viewer' ||
        row['domain'] == 'finance' && member['financeRole'] == 'none') {
      throw const FormatException('closure_author_role');
    }
    final device = author.activeDevice(raw['deviceId']);
    account.directory.reducer.crypto.verifyDomain(
      proof,
      cryptoBase64(device['signingKeyBase64'], length: 32),
      cryptoDirectoryDomain,
    );
    final descriptors =
        (CryptoJson.decode(
                  Uint8List.fromList((row['descriptors'] as List).cast<int>()),
                  limit: (row['descriptors'] as List).length,
                )
                as List)
            .cast<Map<String, dynamic>>();
    if (descriptors.length != payload['recordCount'] ||
        descriptors.any(
          (d) => (d['sequence'] as int) > (payload['expectedSequence'] as int),
        ) ||
        await codec.closureManifestHash(descriptors) !=
            payload['manifestHash']) {
      throw const FormatException('closure_manifest');
    }
    return descriptors;
  }

  /// Certifies an author's exact inventory assertion, never server latestness.
  /// The caller still verifies the complete paginated descriptor stream and
  /// compares every previously trusted local/peer checkpoint before projection.
  Future<CryptoCheckpointAuthority> verifyDomainCheckpoint(
    Map<String, dynamic> proof, {
    bool onlineAuthorDirectory = false,
  }) async {
    final raw = CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
    final payload = Map<String, dynamic>.from(raw['payload'] as Map);
    const fields = {
      'scopeId',
      'domain',
      'epoch',
      'membershipHeadHash',
      'accessRevision',
      'expectedSequence',
      'recordCount',
      'manifestHash',
      'historyBasis',
      'authorDirectoryHeadHash',
    };
    if (raw.length != 8 ||
        raw['version'] != 2 ||
        raw['operation'] != 'crypto2.domain.checkpoint' ||
        raw['signer'] != 'device' ||
        raw['serverId'] != account.directory.session.profile.serverId ||
        payload.length != fields.length ||
        payload.keys.any((k) => !fields.contains(k)) ||
        !['content', 'finance'].contains(payload['domain']) ||
        ![
          'verifiedCheckpoint',
          'reviewedRecoveryBaseline',
        ].contains(payload['historyBasis']) ||
        payload['expectedSequence'] is! int ||
        payload['expectedSequence'] < 0 ||
        payload['recordCount'] is! int ||
        payload['recordCount'] < 0 ||
        payload['manifestHash'] is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(payload['manifestHash'])) {
      throw const FormatException('crypto_checkpoint_shape');
    }
    final current = await currentHead(payload['scopeId']);
    final head = await headAt(
      payload['scopeId'],
      payload['membershipHeadHash'],
    );
    if (payload['epoch'] != head.epoch ||
        payload['accessRevision'] != head.accessRevision) {
      throw const FormatException('crypto_checkpoint_head');
    }
    final author = await directoryAt(
      scopeId: head.scopeId,
      scopeHeadHash: current.headHash,
      accountId: raw['accountId'],
      directoryHeadHash: payload['authorDirectoryHeadHash'],
      online:
          onlineAuthorDirectory &&
          _readOnlyFrozen == null &&
          Zone.current[_deletedScopeEvidenceZone] == null,
    );
    final member = head.member(raw['accountId']);
    if (member['role'] == 'viewer' ||
        payload['domain'] == 'finance' && member['financeRole'] == 'none') {
      throw const FormatException('crypto_checkpoint_role');
    }
    final device = author.activeDevice(raw['deviceId']);
    account.directory.reducer.crypto.verifyDomain(
      proof,
      cryptoBase64(device['signingKeyBase64'], length: 32),
      cryptoDirectoryDomain,
    );
    final proofHash = await cryptoSha256(CryptoJson.encode(proof));
    final observedCheckpoint =
        (_observedScopes[head.scopeId] ?? const <Map<String, dynamic>>[]).any(
          (o) => (o['checkpoints'] as List).any(
            (c) =>
                c['domain'] == payload['domain'] &&
                c['membershipHeadHash'] == head.headHash &&
                c['sequence'] == payload['expectedSequence'] &&
                c['manifestHash'] == payload['manifestHash'] &&
                c['recordCount'] == payload['recordCount'] &&
                (c['proofHashes'] as List).contains(proofHash),
          ),
        );
    for (final m in head.members) {
      final anchor = await account.store.anchor(m['accountId']);
      if (!observedCheckpoint &&
          anchor != null &&
          anchor['deviceSnapshotHash'] != m['deviceSnapshotHash'] &&
          !await _isForwardKnownDirectoryReference(
            scopeId: head.scopeId,
            scopeHeadHash: current.headHash,
            accountId: m['accountId'],
            directoryHeadHash: m['directoryHeadHash'],
            deviceSnapshotHash: m['deviceSnapshotHash'],
            known: anchor,
          )) {
        throw const CryptoAuthorityPending('history_freshness_pending');
      }
    }
    return CryptoCheckpointAuthority(
      head: head,
      historyBasis: payload['historyBasis'],
    );
  }

  Future<CryptoRecordAuthority> recordAuthority(
    Map<String, dynamic> record,
  ) async {
    if ((record['metadata'] as Map).containsKey('projectRelocation')) {
      return _projectRelocation.authority(record);
    }
    if ((record['metadata'] as Map).containsKey('inlineDeletion')) {
      return _inlineDeletion.authority(record);
    }
    if ((record['metadata'] as Map).containsKey('migrationOrigin')) {
      return _committedOrigin.authority(record);
    }
    return _ordinaryRecordAuthority(record);
  }

  Future<VerifiedProjectRelocationRecord> verifyProjectRelocation(
    Map<String, dynamic> record,
  ) => _projectRelocation.verify(record);

  // This base deliberately excludes purpose dispatch. Final publication may
  // resolve only the two explicit historical timing gaps after all current
  // identity, membership, role and closure exclusion checks have run.
  Future<CryptoRecordAuthority> _ordinaryRecordAuthority(
    Map<String, dynamic> record,
  ) async {
    final scopeId = record['scopeId'] as String,
        domain = record['domain'] as String;
    final current = await currentHead(scopeId);
    final head = await headAt(scopeId, record['membershipHeadHash']);
    if (head.epoch != record['epoch'] ||
        head.accessRevision != record['accessRevision']) {
      throw const FormatException('record_membership_substitution');
    }
    final member = head.member(record['accountId']);
    if (member['role'] == 'viewer' ||
        domain == 'finance' && member['financeRole'] != 'write') {
      throw const FormatException('record_author_role');
    }
    final author = await directoryAt(
      scopeId: scopeId,
      scopeHeadHash: head.headHash,
      accountId: record['accountId'],
      directoryHeadHash: member['directoryHeadHash'],
    );
    final device = author.activeDevice(record['deviceId']);
    String? closedHash, historyBasis;
    var currentEpoch = current.headHash == head.headHash;
    for (final member in current.members) {
      final observed = await account.store.anchor(member['accountId']);
      if (observed != null &&
          observed['deviceSnapshotHash'] != member['deviceSnapshotHash'] &&
          !await _isForwardKnownDirectoryReference(
            scopeId: current.scopeId,
            scopeHeadHash: current.headHash,
            accountId: member['accountId'],
            directoryHeadHash: member['directoryHeadHash'],
            deviceSnapshotHash: member['deviceSnapshotHash'],
            known: observed,
          )) {
        currentEpoch = false;
      }
    }
    if (!currentEpoch && current.headHash == head.headHash) {
      // A previously verified exact proof remains readable while a device
      // transition freezes this epoch. A newly supplied old-key signature does
      // not establish that the record existed before revocation.
      final known = await account.store.database.rows(
        "SELECT wire,history_basis FROM crypto_received WHERE partition=? AND scope_id=? AND domain=? AND record_id=? AND revision=? AND verdict='verified'",
        [
          account.store.partition,
          scopeId,
          domain,
          record['id'],
          (record['expectedRevision'] as int) + 1,
        ],
      );
      if (known.length == 1) {
        final old = jsonDecode(known.single['wire'] as String) as Map;
        closedHash = await cryptoSha256(
          CryptoJson.encode((old['authorization'] as Map)['recordProof']),
        );
      } else {
        closedHash = await _observedRecordHash(scopeId, domain, record);
      }
      if (closedHash == null)
        throw const CryptoAuthorityPending('history_freshness_pending');
      historyBasis = 'verifiedCheckpoint';
    }
    if (current.headHash != head.headHash) {
      var rows = await account.store.database.rows(
        'SELECT * FROM crypto_scope_closures WHERE partition=? AND scope_id=? AND domain=? AND candidate_head_hash=? ORDER BY rowid DESC',
        [account.store.partition, scopeId, domain, current.headHash],
      );
      if (rows.isEmpty) await hydrateClosures(scopeId);
      rows = await account.store.database.rows(
        'SELECT * FROM crypto_scope_closures WHERE partition=? AND scope_id=? AND domain=? AND candidate_head_hash=? ORDER BY rowid DESC',
        [account.store.partition, scopeId, domain, current.headHash],
      );
      if (rows.isEmpty) {
        throw const CryptoAuthorityPending('history_checkpoint_pending');
      }
      final descriptors = await _verifyClosure(rows.first, current);
      final exact = descriptors
          .where(
            (d) =>
                d['id'] == record['id'] &&
                d['revision'] == (record['expectedRevision'] as int) + 1,
          )
          .toList();
      if (exact.length != 1) {
        throw const FormatException('record_outside_epoch_closure');
      }
      closedHash = exact.single['recordProofHash'];
      historyBasis = rows.first['history_basis'] as String;
    }
    return CryptoRecordAuthority(
      signingKey: cryptoBase64(device['signingKeyBase64'], length: 32),
      currentEpoch: currentEpoch,
      closedRecordProofHash: closedHash,
      historyBasis: historyBasis,
    );
  }

  /// Historical carrier capability, reconstructed from an independently
  /// anchored higher version of the SAME record. No SQL verdict/cursor is trust.
  Future<CryptoRecordAuthority> historicalCarrierAuthority(
    Map<String, dynamic> wire, {
    required Map<String, dynamic> anchorWire,
  }) async {
    await historicalTargetAuthority(anchorWire);
    final codec = CryptoRecordProofCodec(account.directory.reducer.crypto);
    final goalProof = Map<String, dynamic>.from(
      (wire['authorization'] as Map)['recordProof'] as Map,
    );
    final goal = Map<String, dynamic>.from(
      CryptoJson.decode(cryptoBase64(goalProof['commandBase64'])) as Map,
    );
    codec.validateUntrustedRecord(goal);
    final goalHash = await codec.digest(goalProof),
        goalRevision = wire['revision'];
    final chain = await openHistoryChain(anchorWire);
    if (chain.scopeId != goal['scopeId'] ||
        chain.domain != goal['domain'] ||
        chain.id != goal['id'] ||
        goalRevision is! int ||
        goalRevision > chain.nextRevision) {
      throw const FormatException('crypto_history_carrier_substitution');
    }
    while (chain.nextRevision >= goalRevision) {
      Map<String, dynamic> next;
      if (chain.nextRevision == goalRevision) {
        if (chain.nextHash != goalHash)
          throw const FormatException('crypto_history_carrier_fork');
        next = wire;
      } else {
        List<Map<String, Object?>> retained = [];
        for (final table in const [
          'crypto_received',
          'crypto_business_history_proofs',
          'crypto_business_ack_history',
        ]) {
          final exists = await account.store.database.rows(
            "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
            [table],
          );
          if (exists.isEmpty) continue;
          retained = await account.store.database.rows(
            'SELECT wire FROM $table WHERE partition=? AND scope_id=? AND domain=? AND record_id=? AND revision=?',
            [
              account.store.partition,
              chain.scopeId,
              chain.domain,
              chain.id,
              chain.nextRevision,
            ],
          );
          if (retained.isNotEmpty) break;
        }
        if (retained.length != 1)
          throw const CryptoAuthorityPending('crypto_history_carrier_pending');
        next = Map<String, dynamic>.from(
          jsonDecode(retained.single['wire'] as String) as Map,
        );
      }
      final authority = await chain.authority(next);
      if (next['revision'] == goalRevision) return authority;
    }
    throw const CryptoAuthorityPending('crypto_history_carrier_pending');
  }

  /// Opens from a fully verified record wire, or one exact signed reference
  /// descriptor inside it. Resume callers rewalk retained proofs from here;
  /// persisted job positions and completion flags are never capabilities.
  Future<CryptoHistoryChain> openHistoryChain(
    Map<String, dynamic> anchorWire, {
    Map<String, dynamic>? reference,
    Map<String, dynamic>? referenceAnchorWire,
    Map<String, dynamic>? carrierAnchorWire,
  }) async {
    if (reference == null && referenceAnchorWire != null) {
      throw const FormatException('crypto_history_reference_anchor');
    }
    final recordCodec = CryptoRecordProofCodec(
      account.directory.reducer.crypto,
    );
    final proof = Map<String, dynamic>.from(
      (anchorWire['authorization'] as Map)['recordProof'] as Map,
    );
    final body = Map<String, dynamic>.from(
      CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map,
    );
    recordCodec.validateUntrustedRecord(body);
    final authority = carrierAnchorWire == null
        ? await recordAuthority(body)
        : await historicalCarrierAuthority(
            anchorWire,
            anchorWire: carrierAnchorWire,
          );
    final verified = await recordCodec.verifyWire(
      serverId: account.directory.session.profile.serverId,
      wire: anchorWire,
      trustedSigningKey: authority.signingKey,
      currentEpoch: authority.currentEpoch,
      closedRecordProofHash: authority.closedRecordProofHash,
    );
    var scope = verified['scopeId'] as String,
        domain = verified['domain'] as String,
        id = verified['id'] as String,
        revision = verified['expectedRevision'] as int,
        hash = verified['previousRecordHash'] as String;
    if (reference != null) {
      final exact = (verified['metadata']['referenceVersions'] as List)
          .where(
            (v) =>
                base64Encode(CryptoJson.encode(v)) ==
                base64Encode(CryptoJson.encode(reference)),
          )
          .toList();
      if (exact.length != 1)
        throw const FormatException('crypto_history_reference_substitution');
      scope = reference['scopeId'];
      domain = reference['domain'];
      id = reference['id'];
      revision = reference['revision'];
      hash = reference['recordProofHash'];
    }
    var effectiveWire = anchorWire, effectiveRoot = verified;
    if (referenceAnchorWire != null) {
      final targetProof = Map<String, dynamic>.from(
        (referenceAnchorWire['authorization'] as Map)['recordProof'] as Map,
      );
      final targetBody = Map<String, dynamic>.from(
        CryptoJson.decode(cryptoBase64(targetProof['commandBase64'])) as Map,
      );
      recordCodec.validateUntrustedRecord(targetBody);
      final targetHash = await recordCodec.digest(targetProof);
      if (targetBody['scopeId'] != scope ||
          targetBody['domain'] != domain ||
          targetBody['id'] != id ||
          referenceAnchorWire['revision'] < revision ||
          referenceAnchorWire['revision'] == revision && targetHash != hash) {
        throw const FormatException('crypto_history_reference_anchor');
      }
      await requireHistoricalRecordAnchor(targetBody, targetHash);
      final targetAuthority = await historicalTargetAuthority(
        referenceAnchorWire,
      );
      effectiveRoot = await recordCodec.verifyWire(
        serverId: account.directory.session.profile.serverId,
        wire: referenceAnchorWire,
        trustedSigningKey: targetAuthority.signingKey,
        currentEpoch: targetAuthority.currentEpoch,
        closedRecordProofHash: targetAuthority.closedRecordProofHash,
      );
      effectiveWire = referenceAnchorWire;
      final targetRevision = referenceAnchorWire['revision'] as int;
      if (targetRevision == revision) {
        revision = targetRevision;
        hash = targetHash;
      } else {
        revision = effectiveRoot['expectedRevision'];
        hash = effectiveRoot['previousRecordHash'];
      }
    }
    if (reference != null &&
        revision == reference['revision'] &&
        hash != reference['recordProofHash']) {
      throw const FormatException('crypto_history_reference_fork');
    }
    final generation = _authorityGeneration,
        lifecycle = _BlobLifecycleEpoch.shared?.generation;
    final current = await currentHead(scope);
    final pins = <String, String?>{};
    Future<void> capture(String key) async {
      pins[key] = await account.store.secure.read(key);
    }

    await capture('scope2:${account.store.partition}:$scope');
    if (verified['scopeId'] != scope)
      await capture('scope2:${account.store.partition}:${verified['scopeId']}');
    await capture(
      'directory2:${account.store.partition}:${account.directory.accountId}',
    );
    for (final member in current.members) {
      await capture(
        'directory2:${account.store.partition}:${member['accountId']}',
      );
      await capture(
        'scopedAuthority2:${account.store.partition}:$scope:${member['accountId']}',
      );
    }
    Future<void> guard() async {
      void identity() {
        if (!account.directory.isCurrent() ||
            generation != _authorityGeneration ||
            lifecycle != _BlobLifecycleEpoch.shared?.generation) {
          throw const CryptoAuthorityPending(
            'crypto_history_authority_changed',
          );
        }
      }

      identity();
      for (final pin in pins.entries) {
        if (await account.store.secure.read(pin.key) != pin.value) {
          throw const CryptoAuthorityPending(
            'crypto_history_authority_changed',
          );
        }
      }
      identity();
    }

    await guard();
    // Verification and pin capture are separated by asynchronous work. Recheck
    // the root carrier against the captured final authority, then compare pins
    // again so a concurrent revocation/rotation cannot open a stale lease.
    final finalAuthority = referenceAnchorWire != null
        ? await historicalTargetAuthority(effectiveWire)
        : carrierAnchorWire == null
        ? await recordAuthority(effectiveRoot)
        : await historicalCarrierAuthority(
            effectiveWire,
            anchorWire: carrierAnchorWire,
          );
    await recordCodec.verifyWire(
      serverId: account.directory.session.profile.serverId,
      wire: effectiveWire,
      trustedSigningKey: finalAuthority.signingKey,
      currentEpoch: finalAuthority.currentEpoch,
      closedRecordProofHash: finalAuthority.closedRecordProofHash,
    );
    if (referenceAnchorWire != null) {
      final carrierAuthority = carrierAnchorWire == null
          ? await recordAuthority(verified)
          : await historicalCarrierAuthority(
              anchorWire,
              anchorWire: carrierAnchorWire,
            );
      await recordCodec.verifyWire(
        serverId: account.directory.session.profile.serverId,
        wire: anchorWire,
        trustedSigningKey: carrierAuthority.signingKey,
        currentEpoch: carrierAuthority.currentEpoch,
        closedRecordProofHash: carrierAuthority.closedRecordProofHash,
      );
      await requireHistoricalRecordAnchor(
        effectiveRoot,
        await recordCodec.digest(
          Map<String, dynamic>.from(
            (effectiveWire['authorization'] as Map)['recordProof'] as Map,
          ),
        ),
      );
    }
    final rootHash = await recordCodec.digest(
      Map<String, dynamic>.from(
        (effectiveWire['authorization'] as Map)['recordProof'] as Map,
      ),
    );
    final historicalRoot =
        (reference == null || referenceAnchorWire != null) &&
        (carrierAnchorWire != null && reference == null ||
            (await currentHead(effectiveRoot['scopeId'])).headHash !=
                    effectiveRoot['membershipHeadHash'] &&
                finalAuthority.closedRecordProofHash == rootHash ||
            await _observedRecordHash(
                  effectiveRoot['scopeId'],
                  effectiveRoot['domain'],
                  effectiveRoot,
                ) ==
                rootHash);
    await guard();
    return CryptoHistoryChain._(
      this,
      scope,
      domain,
      id,
      revision,
      hash,
      finalAuthority.historyBasis ?? 'currentEpoch',
      guard,
      historicalRoot,
      reference?['revision'] as int?,
      reference?['recordProofHash'] as String?,
      {
        'scopeId': (carrierAnchorWire ?? anchorWire)['scopeId'],
        'id': (carrierAnchorWire ?? anchorWire)['id'],
        'revision': (carrierAnchorWire ?? anchorWire)['revision'],
        'recordProofHash': await recordCodec.digest(
          Map<String, dynamic>.from(
            ((carrierAnchorWire ?? anchorWire)['authorization']
                    as Map)['recordProof']
                as Map,
          ),
        ),
      },
    );
  }

  /// Verifies only the exact independently anchored historical carrier.
  /// This never grants current write authority or promotes a foreign identity.
  Future<CryptoRecordAuthority> historicalTargetAuthority(
    Map<String, dynamic> wire,
  ) async {
    final recordCodec = CryptoRecordProofCodec(
      account.directory.reducer.crypto,
    );
    final proof = Map<String, dynamic>.from(
      (wire['authorization'] as Map)['recordProof'] as Map,
    );
    final body = Map<String, dynamic>.from(
      CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map,
    );
    recordCodec.validateUntrustedRecord(body);
    final hash = await recordCodec.digest(proof);
    final basis = await requireHistoricalRecordAnchor(body, hash);
    final head = await headAt(body['scopeId'], body['membershipHeadHash']);
    if (head.epoch != body['epoch'] ||
        head.accessRevision != body['accessRevision']) {
      throw const FormatException('record_membership_substitution');
    }
    final member = head.member(body['accountId']);
    if (member['role'] == 'viewer' ||
        body['domain'] == 'finance' && member['financeRole'] != 'write') {
      throw const FormatException('record_author_role');
    }
    final author = await directoryAt(
      scopeId: body['scopeId'],
      scopeHeadHash: head.headHash,
      accountId: body['accountId'],
      directoryHeadHash: member['directoryHeadHash'],
    );
    final key = cryptoBase64(
      author.activeDevice(body['deviceId'])['signingKeyBase64'],
      length: 32,
    );
    await recordCodec.verifyWire(
      serverId: account.directory.session.profile.serverId,
      wire: wire,
      trustedSigningKey: key,
      currentEpoch: false,
      closedRecordProofHash: hash,
    );
    return CryptoRecordAuthority(
      signingKey: key,
      currentEpoch: false,
      closedRecordProofHash: hash,
      historyBasis: basis,
    );
  }

  /// Retrieves a higher target only from signed closure or own observed
  /// checkpoint descriptors. Unsigned latest/cursors never choose authority.
  Future<Map<String, dynamic>?> referenceAnchorCandidate(
    Map<String, dynamic> reference,
  ) async {
    final scope = reference['scopeId'] as String,
        domain = reference['domain'] as String;
    final current = await currentHead(scope, online: true);
    var closures = await account.store.database.rows(
      'SELECT * FROM crypto_scope_closures WHERE partition=? AND scope_id=? AND domain=? AND candidate_head_hash=?',
      [account.store.partition, scope, domain, current.headHash],
    );
    if (closures.isEmpty) {
      await hydrateClosures(scope);
      closures = await account.store.database.rows(
        'SELECT * FROM crypto_scope_closures WHERE partition=? AND scope_id=? AND domain=? AND candidate_head_hash=?',
        [account.store.partition, scope, domain, current.headHash],
      );
    }
    final candidates = <Map<String, dynamic>>[];
    for (final closure in closures) {
      for (final descriptor in await _verifyClosure(closure, current)) {
        if (descriptor['id'] == reference['id'] &&
            descriptor['revision'] >= reference['revision']) {
          candidates.add({
            'revision': descriptor['revision'],
            'recordProofHash': descriptor['recordProofHash'],
          });
        }
      }
    }
    for (final observation
        in _observedScopes[scope] ?? const <Map<String, dynamic>>[]) {
      for (final checkpoint in observation['checkpoints'] as List) {
        if (checkpoint['domain'] != domain) continue;
        final rows = await account.store.database.rows(
          'SELECT * FROM crypto_domain_checkpoints WHERE partition=? AND scope_id=? AND domain=? AND head_hash=? AND sequence=? AND manifest_hash=? AND record_count=?',
          [
            account.store.partition,
            scope,
            domain,
            checkpoint['membershipHeadHash'],
            checkpoint['sequence'],
            checkpoint['manifestHash'],
            checkpoint['recordCount'],
          ],
        );
        for (final row in rows) {
          final proof = Map<String, dynamic>.from(
            jsonDecode(row['authorization'] as String) as Map,
          );
          if (!(checkpoint['proofHashes'] as List).contains(
            await cryptoSha256(CryptoJson.encode(proof)),
          ))
            continue;
          for (final descriptor in await account.store.database.rows(
            'SELECT revision,proof_hash FROM crypto_domain_inventory_rows WHERE partition=? AND snapshot_id=? AND record_id=? AND revision>=?',
            [
              account.store.partition,
              row['snapshot_id'],
              reference['id'],
              reference['revision'],
            ],
          )) {
            candidates.add({
              'revision': descriptor['revision'],
              'recordProofHash': descriptor['proof_hash'],
            });
          }
        }
      }
    }
    if (candidates.isEmpty) return null;
    candidates.sort(
      (a, b) => (b['revision'] as int).compareTo(a['revision'] as int),
    );
    final chosen = candidates.first;
    if (chosen['revision'] == reference['revision'] &&
        chosen['recordProofHash'] != reference['recordProofHash']) {
      throw const FormatException('crypto_history_reference_fork');
    }
    final response = await account.directory
        .call('crypto2.records.historyGet', {
          'scopeId': scope,
          'domain': domain,
          'accessRevision': current.accessRevision,
          'id': reference['id'],
          'revision': chosen['revision'],
          'recordProofHash': chosen['recordProofHash'],
        });
    final wire = Map<String, dynamic>.from(response['record'] as Map);
    final codec = CryptoRecordProofCodec(account.directory.reducer.crypto);
    final proof = Map<String, dynamic>.from(
      (wire['authorization'] as Map)['recordProof'] as Map,
    );
    final body = Map<String, dynamic>.from(
      CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map,
    );
    if (body['scopeId'] != scope ||
        body['domain'] != domain ||
        body['id'] != reference['id'] ||
        wire['revision'] != chosen['revision'] ||
        await codec.digest(proof) != chosen['recordProofHash']) {
      throw const FormatException('crypto_history_reference_anchor');
    }
    await historicalTargetAuthority(wire);
    return wire;
  }

  /// Historical embedded authority needs evidence that this exact carrier
  /// existed in an authenticated scope closure or own observed checkpoint.
  /// A currently valid signature by itself cannot prove an old issuer's timing.
  Future<String> requireHistoricalRecordAnchor(
    Map<String, dynamic> record,
    String recordProofHash,
  ) async {
    final current = await currentHead(record['scopeId']);
    final observed = await _observedRecordHash(
      record['scopeId'],
      record['domain'],
      record,
    );
    if (observed == recordProofHash) return 'verifiedCheckpoint';
    if (current.headHash == record['membershipHeadHash']) {
      throw const CryptoAuthorityPending(
        'scoped_export_historical_carrier_pending',
      );
    }
    final authority = await recordAuthority(record);
    if (authority.closedRecordProofHash == recordProofHash) {
      return authority.historyBasis ?? 'verifiedCheckpoint';
    }
    throw const CryptoAuthorityPending(
      'scoped_export_historical_carrier_pending',
    );
  }

  Future<String?> _observedRecordHash(
    String scope,
    String domain,
    Map record,
  ) async {
    for (final observation
        in (_observedScopes[scope] ?? const <Map<String, dynamic>>[])
            .reversed) {
      for (final checkpoint in observation['checkpoints'] as List) {
        if (checkpoint['domain'] != domain ||
            checkpoint['membershipHeadHash'] != record['membershipHeadHash'])
          continue;
        final rows = await account.store.database.rows(
          'SELECT * FROM crypto_domain_checkpoints WHERE partition=? AND scope_id=? AND domain=? AND head_hash=? AND sequence=? AND manifest_hash=? AND record_count=?',
          [
            account.store.partition,
            scope,
            domain,
            checkpoint['membershipHeadHash'],
            checkpoint['sequence'],
            checkpoint['manifestHash'],
            checkpoint['recordCount'],
          ],
        );
        for (final row in rows) {
          final proof = Map<String, dynamic>.from(
            jsonDecode(row['authorization'] as String) as Map,
          );
          if (!(checkpoint['proofHashes'] as List).contains(
            await cryptoSha256(CryptoJson.encode(proof)),
          ))
            continue;
          final exact = await account.store.database.rows(
            'SELECT proof_hash FROM crypto_domain_inventory_rows WHERE partition=? AND snapshot_id=? AND record_id=? AND revision=?',
            [
              account.store.partition,
              row['snapshot_id'],
              record['id'],
              record['expectedRevision'] + 1,
            ],
          );
          if (exact.length == 1) return exact.single['proof_hash'] as String;
        }
      }
    }
    return null;
  }

  Future<Map<String, dynamic>> _headWire(VerifiedScopeHead head) async {
    final rows = await account.store.database.rows(
      'SELECT authorization FROM crypto_scope_heads WHERE partition=? AND scope_id=? AND head_hash=?',
      [account.store.partition, head.scopeId, head.headHash],
    );
    if (rows.length != 1) {
      throw const CryptoAuthorityPending('scope_head_pending');
    }
    return _decode(rows.single['authorization']);
  }

  Future<VerifiedAccountDirectory> _grantAuthor(
    VerifiedScopeHead head,
    Map command, {
    bool scopedOnly = false,
  }) async {
    final proposal =
        CryptoJson.decode(cryptoBase64(head.authorization['commandBase64']))
            as Map;
    String reference;
    if (proposal['accountId'] == command['accountId']) {
      reference = head.body['authorDirectoryHeadHash'];
    } else {
      final matches = head.members
          .where((m) => m['accountId'] == command['accountId'])
          .toList();
      if (matches.length != 1) throw const FormatException('grant_author');
      reference = matches.single['directoryHeadHash'];
    }
    return directoryAt(
      scopeId: head.scopeId,
      scopeHeadHash: head.headHash,
      accountId: command['accountId'],
      directoryHeadHash: reference,
      allowUnverifiedContact: scopedOnly,
    );
  }

  Stream<Map<String, dynamic>> _grantGroups(
    VerifiedScopeHead head,
    String domain, {
    bool genesisOnly = false,
    CryptoMigrationDescriptorAdmission? descriptorAdmission,
  }) async* {
    final sources =
        (descriptorAdmission != null
                ? descriptorAdmission._chain
                : [
                    for (final h in _heads.values)
                      if (h.headHash != head.headHash) h,
                    head,
                  ])
            .where(
              (h) =>
                  h.scopeId == head.scopeId &&
                  h.epoch <= head.epoch &&
                  (descriptorAdmission != null ||
                      !genesisOnly ||
                      h.headHash == head.headHash) &&
                  h.commitment(domain) != null,
            )
            .toList()
          ..sort((a, b) => a.epoch.compareTo(b.epoch));
    for (final source in sources) {
      final page = await _scopeCall('crypto2.grants.list', {
        'scopeId': head.scopeId,
        'headHash': head.headHash,
        'domain': domain,
        'epoch': source.epoch,
      });
      final groups = page['grants'];
      if (groups is! List || groups.length != 1) {
        throw const CryptoAuthorityPending('scope_history_keys_pending');
      }
      yield Map<String, dynamic>.from(groups.single as Map);
    }
  }

  Future<void> hydrateExistingCandidateKeys(String scopeId) async {
    final candidate = await recoveryCandidateHead(scopeId);
    await _hydrateHeadKeys(candidate, candidateOnly: true);
    // Historical possession is not current write authority after rebind/revoke.
    await account.store.database.execute(
      'UPDATE crypto_scope_keys SET write_ready=0 WHERE partition=? AND scope_id=? AND scope_head_hash=?',
      [account.store.partition, scopeId, candidate.headHash],
    );
  }

  Future<void> hydrateScopeKeys(String scopeId) async {
    final head = await currentHead(scopeId, online: true);
    await _hydrateHeadKeys(head);
  }

  /// Normal receiving may discover a newly activated inherited membership
  /// before this device has its content keys. Admit only the current signed
  /// grant set, including historical source keys, through the ordinary full
  /// manifest/recipient/wrapper/commitment verifier. Candidate recovery remains
  /// separate, and possession alone never selects the current membership.
  Future<void> ensureScopeReadKeys(String scopeId, String domain) async {
    if (!const {'content', 'finance'}.contains(domain)) {
      throw const FormatException('scope_domain');
    }
    Future<VerifiedScopeHead> readableHead() async {
      final head = await currentHead(scopeId, online: true);
      final member = head.member(account.directory.accountId);
      if (!head.active ||
          domain == 'finance' && member['financeRole'] == 'none') {
        throw const CryptoAuthorityPending('scope_read_forbidden');
      }
      return head;
    }

    Future<bool> hasKeys(VerifiedScopeHead head) async {
      final rows = await account.store.database.rows(
        'SELECT epoch_id,key_id FROM crypto_scope_keys WHERE partition=? AND scope_id=? AND domain=?',
        [account.store.partition, scopeId, domain],
      );
      return [..._heads.values, head]
          .where(
            (source) =>
                source.scopeId == scopeId &&
                source.epoch <= head.epoch &&
                source.commitment(domain) != null,
          )
          .every(
            (source) => rows.any(
              (row) =>
                  row['epoch_id'] == source.headHash &&
                  row['key_id'] == (source.body['keyIds'] as Map)[domain],
            ),
          );
    }

    // Retained keys can use the caller's still-current bounded read operation.
    // New key admission below always rechecks independent fresh boundaries.
    final head = await withVerifiedOperation(readableHead);
    if (await hasKeys(head)) return;
    if (_readOnlyFrozen != null ||
        Zone.current[_deletedScopeEvidenceZone] != null) {
      throw const CryptoAuthorityPending('scope_key_pending');
    }
    void requireSameHead(VerifiedScopeHead current) {
      if (current.headHash != head.headHash ||
          current.epoch != head.epoch ||
          (current.body['keyIds'] as Map)[domain] !=
              (head.body['keyIds'] as Map)[domain]) {
        throw const CryptoAuthorityPending('crypto_scope_head_changed');
      }
    }

    await withVerifiedOperation(() async {
      final current = await readableHead();
      requireSameHead(current);
      await _hydrateHeadKeys(current, onlyDomain: domain);
    }, freshBoundary: true);
    await withVerifiedOperation(() async {
      final current = await readableHead();
      requireSameHead(current);
      if (!await hasKeys(current)) {
        throw const CryptoAuthorityPending('scope_key_pending');
      }
    }, freshBoundary: true);
  }

  /// Explicit recovery phase: encryption roots exist only until this future
  /// finishes. Persisted DEKs remain unconfirmed and cannot authorize writes.
  Future<CryptoKeyLease> candidateKey(
    VerifiedScopeHead head,
    String domain,
  ) async {
    final rows = await account.store.database.rows(
      'SELECT key_bytes FROM crypto_scope_keys WHERE partition=? AND scope_id=? AND domain=? AND epoch_id=? AND key_id=?',
      [
        account.store.partition,
        head.scopeId,
        domain,
        head.headHash,
        (head.body['keyIds'] as Map)[domain],
      ],
    );
    if (rows.length != 1) {
      throw const CryptoAuthorityPending('scope_key_recovery_required');
    }
    final raw = Uint8List.fromList(
      (rows.single['key_bytes'] as List).cast<int>(),
    );
    try {
      if (await codec.keyCommitment(raw) != head.commitment(domain)) {
        throw const FormatException('scope_key_commitment');
      }
      return CryptoKeyLease.owned(
        account.directory.reducer.crypto.sodium.secureCopy(raw),
      );
    } finally {
      raw.fillRange(0, raw.length, 0);
    }
  }

  VerifiedScopeHead verifiedCandidateAncestor(String hash) {
    final head = _heads[hash];
    if (head == null) {
      throw const CryptoAuthorityPending('scope_prefix_pending');
    }
    return head;
  }

  Future<VerifiedScopeHead> recoveryCandidateHead(String scopeId) async {
    await _ensureInvitationAnchor(scopeId);
    final wire = await _scopeCall('crypto2.scope.headGet', {
      'scopeId': scopeId,
      if (_readOnlyFrozen != null) 'headHash': _readOnlyFrozen!.headHash,
    });
    for (final member in (wire['payload']['members'] as List)) {
      await currentMemberDirectory(
        scopeId,
        wire['headHash'],
        member['accountId'],
      );
    }
    final result = await _verifyHead(
      scopeId,
      wire,
      online: true,
      historical: true,
    );
    _requireInvitationDescendant(result);
    return result;
  }

  Future<VerifiedScopeHead> pendingHead(String scopeId, String hash) async {
    await _ensureInvitationAnchor(scopeId);
    final wire = await _scopeCall('crypto2.scope.headGet', {
      'scopeId': scopeId,
      'headHash': hash,
    });
    final body = Map<String, dynamic>.from(wire['payload'] as Map);
    final previous = body['epoch'] == 1
        ? null
        : await recoveryCandidateHead(scopeId);
    if (previous != null && previous.headHash != body['previousHeadHash']) {
      throw const CryptoAuthorityPending('scope_candidate_expired');
    }
    final raw =
        CryptoJson.decode(cryptoBase64(wire['authorization']['commandBase64']))
            as Map;
    final author = await directoryAt(
      scopeId: scopeId,
      scopeHeadHash: hash,
      accountId: raw['accountId'],
      directoryHeadHash: body['authorDirectoryHeadHash'],
      online: true,
    );
    final pending = await codec.verifyProposal(
      accessPolicyVersion: _knownPolicyVersion(scopeId, previous),
      serverId: author.serverId,
      authorization: Map<String, dynamic>.from(wire['authorization'] as Map),
      previous: previous,
      authorDirectory: author,
      directoryAtHead: (id, h) => directoryAt(
        scopeId: scopeId,
        scopeHeadHash: hash,
        accountId: id,
        directoryHeadHash: h,
        online: true,
      ),
      checkIdentity: (id, fp) async {
        if (_hasScopedIdentityAnchor(scopeId)) return;
        if (id != account.directory.accountId) {
          await identities.requireVerified(id, fp);
        }
      },
    );
    _heads[pending.headHash] = pending;
    _requireInvitationDescendant(pending);
    if (pending.headHash != hash || wire['state'] != 'pending') {
      throw const CryptoAuthorityPending('scope_candidate_expired');
    }
    await account.store.database.execute(
      'INSERT INTO crypto_scope_heads VALUES(?,?,?,?,?,?,?,?,?) ON CONFLICT(partition,scope_id,head_hash) DO UPDATE SET authorization=excluded.authorization',
      [
        account.store.partition,
        scopeId,
        hash,
        pending.epoch,
        pending.epoch,
        pending.epoch.toString(),
        body['previousHeadHash'],
        CryptoJson.encode(body),
        CryptoJson.encode(wire),
      ],
    );
    return pending;
  }

  Future<String> hydrateCandidateKeys(
    String scopeId,
    String hash, {
    String? onlyDomain,
  }) async {
    final head = await pendingHead(scopeId, hash);
    final result = await _hydrateHeadKeys(
      head,
      pendingManifest: true,
      onlyDomain: onlyDomain,
    );
    if (result == null) {
      throw const CryptoAuthorityPending('scope_keys_pending');
    }
    return result;
  }

  Future<void> recoverScopeCandidateKeys(
    String scopeId,
    Uint8List externalFile,
  ) => _withScopeDescriptorVerification(
    scopeId,
    () => _recoverScopeCandidateKeys(scopeId, externalFile),
  );

  Future<void> _recoverScopeCandidateKeys(
    String scopeId,
    Uint8List externalFile,
  ) async {
    await _ensureInvitationAnchor(scopeId);
    final info = account.files.inspect(
      externalFile,
      serverId: account.directory.session.profile.serverId,
      accountId: account.directory.accountId,
    );
    final anchor = await account.store.anchor(account.directory.accountId);
    if (anchor?['fingerprint'] != info['fingerprint']) {
      throw const FormatException('recovery_identity');
    }
    final status = await account.status();
    final root = account.files.open(
      file: externalFile,
      encryptedRoot:
          CryptoJson.decode(cryptoBase64(status['keyringCiphertextBase64']))
              as Map<String, dynamic>,
      serverId: account.directory.session.profile.serverId,
      accountId: account.directory.accountId,
      expectedFingerprint: info['fingerprint'],
    );
    try {
      final wire = await _scopeCall('crypto2.scope.headGet', {
        'scopeId': scopeId,
        if (_readOnlyFrozen != null) 'headHash': _readOnlyFrozen!.headHash,
      });
      if (_readOnlyFrozen != null) {
        await _guardReadOnlyFrozen(_readOnlyFrozen!);
        if (scopeId != _readOnlyFrozen!.scopeId ||
            wire['headHash'] != _readOnlyFrozen!.headHash) {
          throw const FormatException('crypto_frozen_source_head');
        }
      }
      final head = await _verifyHead(
        scopeId,
        wire,
        online: true,
        historical: true,
        requireDescriptor: _readOnlyFrozen == null,
        descriptorRecoveryRoot: root,
      );
      _requireInvitationDescendant(head);
      if (_readOnlyFrozen != null) await _guardReadOnlyFrozen(_readOnlyFrozen!);
      await _hydrateHeadKeys(head, recoveryRoot: root);
    } finally {
      root.dispose();
    }
  }

  Future<String?> _hydrateHeadKeys(
    VerifiedScopeHead head, {
    RecoveredAccountRoot? recoveryRoot,
    bool pendingManifest = false,
    String? onlyDomain,
    Map<String, dynamic>? descriptorGenesisWire,
    void Function(Uint8List bytes)? receiveDescriptorKey,
    bool candidateOnly = false,
    CryptoMigrationDescriptorAdmission? descriptorAdmission,
  }) async {
    if (descriptorAdmission != null) {
      await descriptorAdmission.requireContext(
        this,
        head.scopeId,
        descriptorAdmission._genesis.headHash,
      );
      if (receiveDescriptorKey == null ||
          head.headHash != descriptorAdmission._carrier.headHash) {
        throw const FormatException('scope_descriptor_key_only');
      }
    }
    if (receiveDescriptorKey != null &&
        (descriptorGenesisWire == null ||
            onlyDomain != 'content' ||
            descriptorAdmission == null &&
                (head.epoch != 1 ||
                    head.body['previousHeadHash'] != cryptoZeroHash))) {
      throw const FormatException('scope_descriptor_key_only');
    }
    String? manifestTop;
    final scopeId = head.scopeId;
    for (final domain in ['content', 'finance']) {
      if (onlyDomain != null && domain != onlyDomain) continue;
      if (head.commitment(domain) == null) continue;
      if (domain == 'finance' &&
          head.member(account.directory.accountId)['financeRole'] == 'none') {
        continue;
      }
      final descriptors = <Map<String, dynamic>>[];
      final verified = <({String intentId, VerifiedScopeHead source})>[];
      final descriptorGroups = <String, Map<String, dynamic>>{};
      await for (final group in _grantGroups(
        head,
        domain,
        genesisOnly: receiveDescriptorKey != null,
        descriptorAdmission: descriptorAdmission,
      )) {
        final source = group['keySourceHeadHash'] == head.headHash
            ? head
            : descriptorAdmission != null
            ? descriptorAdmission._chain.singleWhere(
                (h) => h.headHash == group['keySourceHeadHash'],
              )
            : _heads[group['keySourceHeadHash']];
        if (source == null || source.scopeId != scopeId) {
          throw const FormatException('grant_key_source');
        }
        if (group['scopeId'] != scopeId ||
            group['headHash'] != head.headHash ||
            group['domain'] != domain ||
            group['epoch'] != source.epoch ||
            group['keyId'] != (source.body['keyIds'] as Map)[domain] ||
            group['generation'] is! int ||
            (group['generation'] as int) < 1) {
          throw const FormatException('grant_key_source');
        }
        final recipients = (group['recipients'] as List)
            .cast<Map<String, dynamic>>();
        final authorizations = Map<String, dynamic>.from(
          group['authorizations'] as Map,
        );
        final hashes = <String>[];
        String last = '';
        final seen = <String>{};
        for (final recipient in recipients) {
          final pair =
              '${recipient['recipientKind']}:${recipient['recipientId']}';
          if (pair.compareTo(last) <= 0 || !seen.add(pair)) {
            throw const FormatException('grant_recipient_order');
          }
          last = pair;
          final proof = Map<String, dynamic>.from(
            authorizations[recipient['authorizationId']] as Map,
          );
          final raw =
              CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
          final author = await _grantAuthor(
            head,
            raw,
            scopedOnly: receiveDescriptorKey != null,
          );
          final device = author.activeDevice(raw['deviceId']);
          final command = account.directory.reducer.crypto.verifyDomain(
            proof,
            cryptoBase64(device['signingKeyBase64'], length: 32),
            cryptoDirectoryDomain,
          );
          final payload = command['payload'] as Map;
          VerifiedScopeHead managerHead = head;
          if (head.body['previousHeadHash'] != cryptoZeroHash) {
            managerHead = descriptorAdmission != null
                ? descriptorAdmission._chain[descriptorAdmission._chain.length -
                      2]
                : _heads[head.body['previousHeadHash']]!;
          }
          final contentCard = head.body['contentKeyProposalProof'] == null
              ? null
              : CryptoJson.decode(
                      cryptoBase64(
                        head.body['contentKeyProposalProof']['commandBase64'],
                      ),
                    )
                    as Map;
          final newContentContributor =
              domain == 'content' &&
              source.headHash == head.headHash &&
              contentCard != null &&
              contentCard['accountId'] == command['accountId'] &&
              contentCard['deviceId'] == command['deviceId'];
          final financeCard = head.body['financeKeyProposalProof'] == null
              ? null
              : CryptoJson.decode(
                      cryptoBase64(
                        head.body['financeKeyProposalProof']['commandBase64'],
                      ),
                    )
                    as Map;
          final selectedFinanceContributor =
              source.headHash != head.headHash ||
              financeCard != null &&
                  financeCard['accountId'] == command['accountId'] &&
                  financeCard['deviceId'] == command['deviceId'];
          final grantAuthority = domain == 'finance'
              ? selectedFinanceContributor &&
                    head.member(command['accountId'])['financeRole'] !=
                        'none' &&
                    (managerHead.commitment('finance') == null ||
                        managerHead.member(
                              command['accountId'],
                            )['financeRole'] !=
                            'none')
              : source.headHash == head.headHash && contentCard != null
              ? newContentContributor
              : managerHead.member(command['accountId'])['manageKeys'] == true;
          if (!grantAuthority ||
              command['version'] != 2 ||
              command['operation'] != 'crypto2.grants.put' ||
              command['signer'] != 'device' ||
              command['serverId'] != author.serverId ||
              payload['scopeId'] != scopeId ||
              payload['headHash'] != head.headHash ||
              payload['accountId'] != account.directory.accountId ||
              payload['domain'] != domain ||
              payload['epoch'] != source.epoch ||
              payload['keyId'] != group['keyId'] ||
              payload['keySourceHeadHash'] != source.headHash ||
              payload['expectedGeneration'] is! int ||
              (payload['expectedGeneration'] as int) < 0 ||
              (payload['expectedGeneration'] as int) >= group['generation']) {
            throw const FormatException('grant_authorization');
          }
          final signedRecipients = payload['recipients'];
          if (signedRecipients is! List ||
              signedRecipients.isEmpty ||
              signedRecipients.length > 32 ||
              !signedRecipients.any(
                (r) =>
                    r['recipientKind'] == recipient['recipientKind'] &&
                    r['recipientId'] == recipient['recipientId'] &&
                    r['publicKeyBase64'] == recipient['publicKeyBase64'] &&
                    r['sealedEnvelopeBase64'] ==
                        recipient['sealedEnvelopeBase64'],
              )) {
            throw const FormatException('grant_recipient_substitution');
          }
          hashes.add(await cryptoSha256(CryptoJson.encode(proof)));
        }
        final ownDirectory = await directoryAt(
          scopeId: scopeId,
          scopeHeadHash: head.headHash,
          accountId: account.directory.accountId,
          directoryHeadHash: head.member(
            account.directory.accountId,
          )['directoryHeadHash'],
          allowUnverifiedContact: receiveDescriptorKey != null,
        );
        final expected = <String, String>{
          'recovery:${ownDirectory.snapshot['recoveryRootEpochId']}':
              ownDirectory.snapshot['rootEncryptionKeyBase64'],
        };
        for (final device in ownDirectory.devices.where(
          (d) =>
              d['revokedGeneration'] == null &&
              d['identityEpochId'] == ownDirectory.identityEpochId,
        )) {
          expected['device:${device['deviceId']}'] =
              device['encryptionKeyBase64'];
        }
        if (recipients.length != expected.length ||
            recipients.any(
              (r) =>
                  expected['${r['recipientKind']}:${r['recipientId']}'] !=
                  r['publicKeyBase64'],
            )) {
          throw const CryptoAuthorityPending('grant_recipients_pending');
        }
        descriptors.add({
          'accountId': account.directory.accountId,
          'epoch': source.epoch,
          'keyId': group['keyId'],
          'keySourceHeadHash': source.headHash,
          'generation': group['generation'],
          'recipientProofHashes': hashes,
        });
        final intentId = 'grant:${head.headHash}:${group['keyId']}';
        final groupBytes = Uint8List.fromList(utf8.encode(jsonEncode(group)));
        if (groupBytes.length > 2 * 1024 * 1024) {
          throw const FormatException('grant_group_size');
        }
        if (receiveDescriptorKey != null) {
          descriptorGroups[intentId] = group;
        } else {
          await account.store.database.execute(
            'INSERT INTO crypto_membership_intents VALUES(?,?,?,?,?,NULL) ON CONFLICT(partition,scope_id,intent_id) DO UPDATE SET payload=excluded.payload',
            [
              account.store.partition,
              scopeId,
              intentId,
              'verifiedGrantCandidate',
              groupBytes,
            ],
          );
        }
        verified.add((intentId: intentId, source: source));
      }
      final top = await _verifyGrantManifest(
        head,
        domain,
        descriptors,
        pendingManifest: pendingManifest,
        descriptorGenesisWire: descriptorGenesisWire,
      );
      if (manifestTop != null && manifestTop != top) {
        throw const CryptoAuthorityPending('scope_grants_changed');
      }
      manifestTop = top;
      final pair = recoveryRoot == null ? await account.encryptionKey() : null;
      final retainedPairs = <KeyPair>[];
      try {
        for (final grant in verified) {
          if (descriptorAdmission != null &&
              grant.source.headHash != descriptorAdmission._genesis.headHash) {
            // Other CONTENT descriptors still participate in the signed full
            // manifest, but no later key is opened by the baseline reader.
            continue;
          }
          if (candidateOnly &&
              recoveryRoot == null &&
              receiveDescriptorKey == null) {
            CryptoKeyLease? retained;
            try {
              retained = await candidateKey(grant.source, domain);
            } on CryptoAuthorityPending catch (error) {
              if (error.reason != 'scope_key_recovery_required') rethrow;
            }
            if (retained != null) {
              try {
                // Full signed grant/manifest verification precedes this exact
                // commitment check. Possession remains a read-only candidate.
                continue;
              } finally {
                retained.release();
              }
            }
          }
          final stored = receiveDescriptorKey != null
              ? const <Map<String, dynamic>>[]
              : await account.store.database.rows(
                  'SELECT payload FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND intent_id=?',
                  [account.store.partition, scopeId, grant.intentId],
                );
          final group =
              descriptorGroups[grant.intentId] ??
              jsonDecode(
                    utf8.decode((stored.single['payload'] as List).cast<int>()),
                  )
                  as Map<String, dynamic>;
          final recipients = (group['recipients'] as List)
              .cast<Map<String, dynamic>>();
          late Map<String, dynamic> own;
          late KeyPair recipientPair;
          if (recoveryRoot == null) {
            final current = recipients
                .where(
                  (r) =>
                      r['recipientKind'] == 'device' &&
                      r['recipientId'] == account.deviceId,
                )
                .toList();
            if (current.length == 1) {
              own = current.single;
              recipientPair = pair!;
            } else {
              Map<String, dynamic>? match;
              KeyPair? matchingKey;
              for (final r in recipients.where(
                (r) => r['recipientKind'] == 'device',
              )) {
                final local = await account.retainedEncryptionKey(
                  r['recipientId'],
                  r['publicKeyBase64'],
                );
                if (local != null) {
                  match = r;
                  matchingKey = local;
                  retainedPairs.add(local);
                  break;
                }
              }
              if (match == null || matchingKey == null) {
                throw const CryptoAuthorityPending(
                  'scope_key_recovery_required',
                );
              }
              own = match;
              recipientPair = matchingKey;
            }
          } else {
            own = recipients.singleWhere(
              (r) => r['recipientKind'] == 'recovery',
            );
            final roots = [
              recoveryRoot.encryption,
              ...recoveryRoot.historicalEncryption,
            ];
            final matching = roots
                .where(
                  (r) => base64Encode(r.publicKey) == own['publicKeyBase64'],
                )
                .toList();
            if (matching.length != 1) {
              throw const CryptoAuthorityPending(
                'recovery_historical_key_pending',
              );
            }
            recipientPair = matching.single;
          }
          final context = codec.wrapperContext(
            serverId: account.directory.session.profile.serverId,
            head: head,
            keySourceHead: grant.source,
            domain: domain,
            keyId: group['keyId'],
            recipient: {
              ...own,
              'recoveryRootEpochId': head.member(
                account.directory.accountId,
              )['recoveryRootEpochId'],
            },
          );
          final key = account.directory.reducer.crypto.openKey(
            sealed: own['sealedEnvelopeBase64'],
            recipient: recipientPair,
            context: context,
          );
          final bytes = key.extractBytes();
          try {
            if (await codec.keyCommitment(bytes) !=
                grant.source.commitment(domain)) {
              throw const FormatException('grant_key_commitment');
            }
            if (receiveDescriptorKey != null) {
              await descriptorAdmission?.requireContext(
                this,
                scopeId,
                grant.source.headHash,
              );
              receiveDescriptorKey(bytes);
              continue;
            }
            await account.store.database.execute(
              'INSERT INTO crypto_scope_keys VALUES(?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(partition,scope_id,domain,epoch_id,key_id) DO UPDATE SET grant=excluded.grant,recovery_wrapping_durable=excluded.recovery_wrapping_durable,write_ready=excluded.write_ready',
              [
                account.store.partition,
                scopeId,
                domain,
                grant.source.epoch,
                grant.source.headHash,
                group['keyId'],
                bytes,
                head.headHash,
                Uint8List.fromList(utf8.encode(jsonEncode(group))),
                recoveryRoot == null ? 1 : 0,
                !candidateOnly &&
                        head.active &&
                        recoveryRoot == null &&
                        grant.source.headHash == head.headHash
                    ? 1
                    : 0,
              ],
            );
          } finally {
            bytes.fillRange(0, bytes.length, 0);
            key.dispose();
          }
        }
      } finally {
        pair?.secretKey.dispose();
        for (final retained in retainedPairs) {
          retained.secretKey.dispose();
        }
      }
    }
    return manifestTop;
  }

  Future<String> _verifyGrantManifest(
    VerifiedScopeHead head,
    String domain,
    List<Map<String, dynamic>> ownDescriptors, {
    bool pendingManifest = false,
    Map<String, dynamic>? descriptorGenesisWire,
  }) async {
    final headWire = descriptorGenesisWire ?? await _headWire(head);
    final activation = headWire['activationAuthorization'] == null
        ? null
        : CryptoJson.decode(
                cryptoBase64(
                  headWire['activationAuthorization']['commandBase64'],
                ),
              )
              as Map;
    if (!pendingManifest && activation == null) {
      throw const CryptoAuthorityPending('scope_activation_pending');
    }
    final expected = activation == null
        ? null
        : (activation['payload'] as Map)['grantManifestHash'];
    final manifest = await _scopeCall('crypto2.grants.manifest', {
      'scopeId': head.scopeId,
      'headHash': head.headHash,
    });
    final roots = Map<String, dynamic>.from(manifest['domains'] as Map);
    if (roots.length != 2 ||
        await cryptoSha256(CryptoJson.encode(roots)) !=
            manifest['grantManifestHash'] ||
        expected != null && manifest['grantManifestHash'] != expected) {
      throw const FormatException('grant_manifest_substitution');
    }
    final financeProof = activation == null
        ? headWire['financeGrantManifestProof']
        : (activation['payload'] as Map)['financeGrantManifestProof'];
    if (!pendingManifest && head.commitment('finance') != null) {
      if (financeProof is! Map) {
        throw const FormatException('finance_manifest_required');
      }
      final body =
          CryptoJson.decode(cryptoBase64(financeProof['commandBase64'])) as Map;
      if (body['financeManifestHash'] != roots['finance']) {
        throw const FormatException('finance_manifest_root_substitution');
      }
    }
    if (!pendingManifest && head.body['contentKeyProposalProof'] != null) {
      final proof =
          (activation!['payload'] as Map)['contentGrantManifestProof'];
      if (proof is! Map ||
          (CryptoJson.decode(cryptoBase64(proof['commandBase64']))
                  as Map)['contentManifestHash'] !=
              roots['content']) {
        throw const FormatException('content_manifest_root_substitution');
      }
    }
    final sink = Sha256().newHashSink();
    var seenBytes = 0;
    String? afterAccount;
    int? afterEpoch;
    final own = <int, Map<String, dynamic>>{};
    String lastAccount = '';
    var lastEpoch = 0;
    while (true) {
      final page = await _scopeCall('crypto2.grants.manifest', {
        'scopeId': head.scopeId,
        'headHash': head.headHash,
        'domain': domain,
        if (afterAccount != null) 'afterAccountId': afterAccount,
        if (afterEpoch != null) 'afterEpoch': afterEpoch,
        'limit': 50,
      });
      final rows = page['descriptors'];
      if (rows is! List || rows.length > 50) {
        throw const FormatException('grant_manifest_shape');
      }
      for (final raw in rows) {
        final descriptor = Map<String, dynamic>.from(raw as Map);
        final id = descriptor['accountId'] as String,
            epoch = descriptor['epoch'] as int;
        if (id.compareTo(lastAccount) < 0 ||
            id == lastAccount && epoch <= lastEpoch) {
          throw const FormatException('grant_manifest_order');
        }
        final bytes = CryptoJson.encode(descriptor);
        seenBytes += bytes.length + 1;
        if (seenBytes > 64 * 1024 * 1024) {
          throw const CryptoAuthorityPending(
            'grant_manifest_inventory_pending',
          );
        }
        sink.add(bytes);
        sink.add([10]);
        lastAccount = id;
        lastEpoch = epoch;
        if (id == account.directory.accountId) own[epoch] = descriptor;
      }
      if (page['hasMore'] != true) break;
      if (rows.isEmpty ||
          page['nextAccountId'] != lastAccount ||
          page['nextEpoch'] != lastEpoch) {
        throw const FormatException('grant_manifest_cursor');
      }
      afterAccount = lastAccount;
      afterEpoch = lastEpoch;
    }
    sink.close();
    final actual = (await sink.hash()).bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    if (actual != roots[domain] ||
        own.length != ownDescriptors.length ||
        ownDescriptors.any(
          (d) =>
              base64Encode(CryptoJson.encode(d)) !=
              base64Encode(CryptoJson.encode(own[d['epoch']])),
        )) {
      throw const FormatException('grant_manifest_mismatch');
    }
    return manifest['grantManifestHash'] as String;
  }

  Future<CryptoKeyLease> getScopeKey(
    String scopeId,
    String domain,
    int epoch,
  ) async {
    await currentHead(scopeId);
    final sources = _heads.values
        .where((h) => h.scopeId == scopeId && h.epoch == epoch)
        .toList();
    if (sources.length != 1) {
      throw const CryptoAuthorityPending('scope_key_provenance_pending');
    }
    final source = sources.single;
    final rows = await account.store.database.rows(
      'SELECT * FROM crypto_scope_keys WHERE partition=? AND scope_id=? AND domain=? AND epoch=? AND epoch_id=? AND key_id=?',
      [
        account.store.partition,
        scopeId,
        domain,
        epoch,
        source.headHash,
        (source.body['keyIds'] as Map)[domain],
      ],
    );
    if (rows.length != 1) {
      throw const CryptoAuthorityPending('scope_key_pending');
    }
    final bytes = Uint8List.fromList(
      (rows.single['key_bytes'] as List).cast<int>(),
    );
    try {
      if (await codec.keyCommitment(bytes) !=
          sources.single.commitment(domain)) {
        throw const FormatException('scope_key_commitment');
      }
      return CryptoKeyLease.owned(
        account.directory.reducer.crypto.sodium.secureCopy(bytes),
      );
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  Future<CryptoKeyLease> recordKey(Map<String, dynamic> record) =>
      getScopeKey(record['scopeId'], record['domain'], record['epoch']);
  Future<CryptoReadContext> readContext(String scopeId, String domain) async {
    final head = await currentHead(scopeId, online: true);
    final member = head.member(account.directory.accountId);
    if (domain == 'finance' && member['financeRole'] == 'none') {
      throw const CryptoAuthorityPending('scope_read_forbidden');
    }
    return CryptoReadContext(
      epoch: head.epoch,
      accessRevision: head.accessRevision,
      headHash: head.headHash,
    );
  }

  Future<CryptoWriteContext> writeContext(
    String scopeId,
    String domain, {
    bool online = false,
  }) async {
    Future<VerifiedScopeHead> writableHead({required bool online}) async {
      if (_readOnlyFrozen != null ||
          Zone.current[_deletedScopeEvidenceZone] != null) {
        throw const CryptoAuthorityPending('crypto_frozen_source_read_only');
      }
      final head = await currentHead(scopeId, online: online);
      final member = head.member(account.directory.accountId);
      if (member['role'] == 'viewer' ||
          domain == 'finance' && member['financeRole'] != 'write') {
        throw const CryptoAuthorityPending('scope_write_forbidden');
      }
      final local = await account.directory.cachedVerifiedDirectory();
      if (!account.directory.isCurrent()) {
        throw const CryptoAuthorityPending('crypto_stale_identity');
      }
      if (member['deviceSnapshotHash'] != local.deviceSnapshotHash) {
        throw const CryptoAuthorityPending('scope_rotation_required');
      }
      return head;
    }

    Future<List<Map<String, Object?>>> readyKeys(
      VerifiedScopeHead head,
    ) => account.store.database.rows(
      'SELECT * FROM crypto_scope_keys WHERE partition=? AND scope_id=? AND domain=? AND epoch=? AND epoch_id=? AND key_id=? AND recovery_wrapping_durable=1 AND write_ready=1',
      [
        account.store.partition,
        scopeId,
        domain,
        head.epoch,
        head.headHash,
        (head.body['keyIds'] as Map)[domain],
      ],
    );

    Future<CryptoWriteContext> admittedContext(
      VerifiedScopeHead head,
      List<Map<String, Object?>> rows,
    ) async {
      if (rows.length != 1) {
        throw const CryptoAuthorityPending('scope_keys_pending');
      }
      return CryptoWriteContext(
        headHash: head.headHash,
        epoch: head.epoch,
        accessRevision: head.accessRevision,
        contentContract: domain == 'finance' ? 3 : 6,
        keyId: rows.single['key_id'] as String,
        key: await getScopeKey(scopeId, domain, head.epoch),
      );
    }

    final head = await writableHead(online: online);
    final rows = await readyKeys(head);
    if (rows.isNotEmpty) return admittedContext(head, rows);

    void requireSameHead(VerifiedScopeHead current) {
      if (!current.active ||
          current.headHash != head.headHash ||
          current.epoch != head.epoch ||
          (current.body['keyIds'] as Map)[domain] !=
              (head.body['keyIds'] as Map)[domain]) {
        throw const CryptoAuthorityPending('crypto_scope_head_changed');
      }
    }

    // Migration/recovery candidates are intentionally read-only. The first
    // write may admit the current device's genuine active grants through the
    // normal signed manifest, recipient, wrapper and commitment checks once.
    await withVerifiedOperation(() async {
      final current = await writableHead(online: true);
      requireSameHead(current);
      await _hydrateHeadKeys(current, onlyDomain: domain);
    }, freshBoundary: true);
    // online:true can reuse an operation memo. A separate fresh boundary is
    // required after hydration before the exact ready-key query authorizes use.
    return withVerifiedOperation(() async {
      final current = await writableHead(online: true);
      requireSameHead(current);
      return admittedContext(current, await readyKeys(current));
    }, freshBoundary: true);
  }

  Future<VerifiedAccountDirectory> currentMemberDirectory(
    String scopeId,
    String scopeHeadHash,
    String accountId,
  ) async {
    final operation = _operation,
        key = '$scopeId:$scopeHeadHash:$accountId',
        cached = operation?.directories['$scopeId:$scopeHeadHash:$accountId'];
    if (cached != null && await _operationPinsValid(operation!)) {
      await _requireCurrentMemberIdentity(scopeId, scopeHeadHash, cached);
      if (identical(_operation, operation) &&
          await _operationPinsValid(operation))
        return cached;
    }
    final status = await _scopeCall('crypto2.directory.status', {
      'scopeId': scopeId,
      if (scopeHeadHash != cryptoZeroHash) 'headHash': scopeHeadHash,
      'accountId': accountId,
    });
    final anchor = await account.store.anchor(accountId);
    if (status['generation'] is! int ||
        (anchor != null &&
            (status['generation'] as int) < (anchor['generation'] as int))) {
      throw const FormatException('directory_known_rollback');
    }
    final state = await directoryAt(
      scopeId: scopeId,
      scopeHeadHash: scopeHeadHash,
      accountId: accountId,
      directoryHeadHash: status['headHash'],
      online: true,
    );
    if (state.generation != status['generation'] ||
        state.snapshotHash != status['snapshotHash'] ||
        state.deviceSnapshotHash != status['deviceSnapshotHash']) {
      throw const FormatException('directory_snapshot_substitution');
    }
    if (await _hasCommittedMigrationIdentity(scopeId, scopeHeadHash)) {
      await _requireCurrentMemberIdentity(scopeId, scopeHeadHash, state);
    }
    if (operation != null &&
        operation.active &&
        ((await account.store.anchor(accountId))?['trustState'] == 'verified' ||
            await _hasCommittedMigrationIdentity(scopeId, scopeHeadHash))) {
      operation.directories[key] = state;
      await _rememberOperationDirectory(operation, state);
    }
    return state;
  }

  Future<void> beforeDelivery(Map<String, dynamic> signedCommand) =>
      withVerifiedOperation(
        () => _beforeDelivery(signedCommand),
        freshBoundary: true,
      );
  Future<void> _beforeDelivery(Map<String, dynamic> signedCommand) async {
    if (_readOnlyFrozen != null ||
        Zone.current[_deletedScopeEvidenceZone] != null)
      throw const CryptoAuthorityPending('crypto_frozen_source_read_only');
    final c =
        CryptoJson.decode(cryptoBase64(signedCommand['commandBase64'])) as Map;
    if (c['version'] != 2 ||
        c['accountId'] != account.directory.accountId ||
        c['deviceId'] != account.deviceId ||
        c['serverId'] != account.directory.session.profile.serverId ||
        c['signer'] != 'device') {
      throw const FormatException('crypto_delivery_identity');
    }
    if (CryptoBusinessProjectRelocation.deliveryOperations.contains(
      c['operation'],
    )) {
      await CryptoBusinessProjectRelocation.verifyDelivery(
        this,
        Map<String, dynamic>.from(c),
      );
      return;
    }
    if (CryptoScopedExports.deliveryOperations.contains(c['operation'])) {
      await CryptoScopedExports.verifyDelivery(this, c);
      return;
    }
    if (CryptoBusinessModeration.deliveryOperations.contains(c['operation'])) {
      await CryptoBusinessModeration.verifyDelivery(
        this,
        Map<String, dynamic>.from(c),
      );
      return;
    }
    if (CryptoBusinessLifecycle.deliveryOperations.contains(c['operation'])) {
      await CryptoBusinessLifecycle.verifyDelivery(
        this,
        Map<String, dynamic>.from(c),
      );
      return;
    }
    if (CryptoBusinessInlineDeletion.operations.contains(c['operation'])) {
      await CryptoBusinessInlineDeletion.verifyDelivery(
        this,
        Map<String, dynamic>.from(c),
      );
      return;
    }
    if (c['operation'] == CryptoBusinessDeletion.deliveryOperation) {
      await CryptoBusinessDeletion.verifyDelivery(
        this,
        Map<String, dynamic>.from(c),
      );
      return;
    }
    if (c['operation'] == 'crypto2.scope.financePolicy.propose') {
      final own = await account.directory.requireFresh();
      own.activeDevice(account.deviceId);
      final payload = c['payload'] as Map;
      final head = await currentHead(payload['scopeId'], online: true);
      if (head.member(own.accountId)['manageKeys'] != true ||
          payload['membershipHeadHash'] != head.headHash ||
          payload['expectedAccessRevision'] != head.accessRevision ||
          payload['authorDirectoryHeadHash'] != own.headHash) {
        throw const CryptoAuthorityPending(
          'crypto_finance_policy_authority_changed',
        );
      }
      for (final member in head.members) {
        final directory = await currentMemberDirectory(
          head.scopeId,
          head.headHash,
          member['accountId'],
        );
        if (directory.deviceSnapshotHash != member['deviceSnapshotHash']) {
          throw const CryptoAuthorityPending('scope_rotation_required');
        }
      }
      return;
    }
    final lifecycle = _BlobLifecycleEpoch.shared;
    final payload = c['payload'] as Map;
    final windowKey =
        '${payload['scopeId']}:${payload['domain']}:${payload['id']}';
    if (c['operation'] == 'crypto2.blob.chunk' &&
        account.directory.isCurrent() &&
        lifecycle != null &&
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      final window = _blobWindows[windowKey];
      if (window != null &&
          window.lifecycle == lifecycle.generation &&
          window.timer.elapsed < const Duration(seconds: 5) &&
          window.bytes < 2 * 1024 * 1024) {
        final own = await account.directory.cachedVerifiedDirectory();
        final scopePin = await account.store.secure.read(
          'scope2:${account.store.partition}:${payload['scopeId']}',
        );
        var same =
            own.deviceSnapshotHash == window.ownSnapshot &&
            scopePin == window.scopePin;
        for (final m in window.members.entries) {
          final pin = await account.store.anchor(m.key);
          same = same && pin?['deviceSnapshotHash'] == m.value;
        }
        for (final key in [
          'scopeId',
          'id',
          'domain',
          'epoch',
          'accessRevision',
          'membershipHeadHash',
        ]) {
          same = same && payload[key] == window.common[key];
        }
        final staged = await account.store.database.rows(
          'SELECT cipher FROM crypto_document_chunks WHERE partition=? AND id=? AND offset=?',
          [account.store.partition, payload['id'], payload['offset']],
        );
        final job = await account.store.database.rows(
          'SELECT descriptor,source_hash FROM crypto_document_jobs WHERE partition=? AND id=? AND state=?',
          [account.store.partition, payload['id'], 'staged'],
        );
        final source = await account.store.database.rows(
          'SELECT o.signed_body FROM crypto_command_keys k JOIN crypto_outbox o ON o.partition=k.partition AND o.request_id=k.request_id WHERE k.partition=? AND k.action_key=?',
          [account.store.partition, 'blob:${payload['id']}:begin'],
        );
        final chunkSize = staged.length == 1
            ? (staged.single['cipher'] as List).length
            : 0;
        if (permitsImmutableBlobChunk(
          elapsed: window.timer.elapsed,
          usedBytes: window.bytes,
          chunkBytes: chunkSize,
          foreground:
              WidgetsBinding.instance.lifecycleState ==
              AppLifecycleState.resumed,
          lifecycleMatches: window.lifecycle == lifecycle.generation,
          identityCurrent: account.directory.isCurrent(),
          ownSnapshotMatches: same,
          scopePinMatches:
              window.scopePin != null && scopePin == window.scopePin,
          allMembersPinned: same,
          manifestMatches:
              job.length == 1 &&
              await cryptoSha256(
                    utf8.encode(
                      '${job.single['descriptor']}:${job.single['source_hash']}',
                    ),
                  ) ==
                  window.manifestHash,
          sourceProofMatches:
              source.length == 1 &&
              await cryptoSha256(
                    utf8.encode(source.single['signed_body'] as String),
                  ) ==
                  window.sourceProofHash,
          stagedChunkMatches:
              staged.length == 1 &&
              base64Encode((staged.single['cipher'] as List).cast<int>()) ==
                  payload['dataBase64'],
        )) {
          window.bytes += chunkSize;
          return;
        }
      }
      _blobWindows.remove(windowKey);
    }
    await account.directory.requireFresh();
    if (const {
      'crypto2.reminders.cancel',
      'crypto2.inbox.read',
      'crypto2.inbox.preferences.set',
    }.contains(c['operation'])) {
      return;
    }
    if (c['operation'] == 'crypto2.reminders.put') {
      final head = await currentHead(payload['scopeId'], online: true),
          member = head.member(account.directory.accountId);
      final finance = [
        'financeEntry',
        'personalFinanceEntry',
      ].contains(payload['targetType']);
      if (finance && member['financeRole'] == 'none') {
        throw const CryptoAuthorityPending('scope_write_forbidden');
      }
      for (final m in head.members) {
        final current = await currentMemberDirectory(
          head.scopeId,
          head.headHash,
          m['accountId'],
        );
        if (current.deviceSnapshotHash != m['deviceSnapshotHash']) {
          throw const CryptoAuthorityPending('scope_rotation_required');
        }
      }
      final targets = await account.store.database.rows(
        "SELECT r.wire FROM crypto_business_records b JOIN crypto_received r ON r.partition=b.partition AND r.scope_id=b.scope_id AND r.domain=b.domain AND r.record_id=b.id AND r.revision=b.crypto_revision WHERE b.partition=? AND b.scope_id=? AND b.domain=? AND b.id=? AND b.type=? AND b.deleted=0 AND r.verdict='verified'",
        [
          account.store.partition,
          head.scopeId,
          finance ? 'finance' : 'content',
          payload['targetId'],
          payload['targetType'],
        ],
      );
      if (targets.length != 1) {
        throw const CryptoAuthorityPending('reminder_target_pending');
      }
      final wire = jsonDecode(targets.single['wire'] as String) as Map,
          record =
              CryptoJson.decode(
                    cryptoBase64(
                      wire['authorization']['recordProof']['commandBase64'],
                    ),
                  )
                  as Map<String, dynamic>;
      await recordAuthority(record);
      if (payload['targetIdentity'] is! Map ||
          base64Encode(CryptoJson.encode(payload['targetIdentity'])) !=
              base64Encode(CryptoJson.encode(record['metadata']['identity']))) {
        throw const FormatException('reminder_target_identity');
      }
      if (record['metadata']['reminderState']?['closed'] != false) {
        throw const CryptoAuthorityPending('reminder_target_unavailable');
      }
      return;
    }
    if (const {
      'crypto2.migration.blob.begin',
      'crypto2.migration.blob.chunk',
      'crypto2.migration.blob.complete',
    }.contains(c['operation'])) {
      final payload = c['payload'] as Map;
      if (payload['captureVersion'] != 3 ||
          !const {
            'typedWitness',
            'canonicalPayload',
            'auditWitness',
            'ideaAsset',
          }.contains(payload['purpose']) ||
          payload['purpose'] == 'auditWitness' &&
              payload['domain'] != 'finance' ||
          payload['purpose'] == 'ideaAsset' && payload['domain'] != 'content' ||
          !const {'content', 'finance'}.contains(payload['domain']) ||
          !const [
            'migrationId',
            'captureId',
            'bindingId',
            'scopeId',
            'id',
          ].every((key) => isCryptoCanonicalUuid(payload[key])) ||
          payload['sourceInventoryRoot'] is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(payload['sourceInventoryRoot'])) {
        throw const FormatException('crypto_migration_witness_context');
      }
      final candidate = await migrationCandidate(
        scopeId: payload['scopeId'],
        migrationId: payload['migrationId'],
        captureId: payload['captureId'],
        headHash: payload['membershipHeadHash'],
      );
      final head = candidate.head;
      final member = head.member(account.directory.accountId);
      if (payload['membershipHeadHash'] != head.headHash ||
          payload['epoch'] != head.epoch ||
          payload['accessRevision'] != head.accessRevision ||
          payload['domain'] == 'finance' && member['financeRole'] == 'none') {
        throw const CryptoAuthorityPending(
          'crypto_migration_witness_authority',
        );
      }
      for (final member in head.members) {
        final directory = await currentMemberDirectory(
          head.scopeId,
          head.headHash,
          member['accountId'],
        );
        if (directory.deviceSnapshotHash != member['deviceSnapshotHash']) {
          throw const CryptoAuthorityPending('scope_rotation_required');
        }
      }
      return;
    }
    const migrationOperations = {
      'crypto2.migration.generation.prepare',
      'crypto2.migration.generation.financeDraft',
      'crypto2.migration.generation.draft',
      'crypto2.migration.generation.seal',
      'crypto2.migration.generation.approve',
      'crypto2.migration.generation.finish',
      'crypto2.migration.capture.prepare',
      'crypto2.migration.capture.bind',
      'crypto2.migration.capture.seal',
      'crypto2.migration.capture.fence',
      'crypto2.migration.legacyFinanceEnable',
      'crypto2.migration.legacy.certify',
      'crypto2.migration.legacy.anchor',
      'crypto2.migration.legacy.reserveReplacement',
      'crypto2.migration.audit.stage',
      'crypto2.migration.verify3',
      'crypto2.migration.activation.stage',
      'crypto2.migration.commit3',
      'crypto2.migration.structure.source',
      'crypto2.migration.structure.sourceAnchor',
      'crypto2.migration.structure.context',
      'crypto2.migration.structure.contextApprove',
      'crypto2.migration.domains.prepare',
      'crypto2.migration.domains.contribute',
      'crypto2.migration.domains.anchorContribution',
      'crypto2.migration.domains.certify',
      'crypto2.migration.domains.anchor',
      'crypto2.migration.invitations.stage',
      'crypto2.migration.invitations.certify',
      'crypto2.migration.invitations.anchor',
      'crypto2.migration.notifications.stage',
      'crypto2.migration.notifications.certify',
      'crypto2.migration.notifications.anchor',
      'crypto2.migration.prepare',
      'crypto2.migration.fence',
      'crypto2.migration.abort',
      'crypto2.migration.archiveBegin',
      'crypto2.migration.archiveChunk',
      'crypto2.migration.archiveComplete',
      'crypto2.migration.recordsStage',
      'crypto2.legacy.reserveReplacement',
      'crypto2.scope.create',
      'crypto2.scope.ensurePersonal',
      'crypto2.migration.verify',
      'crypto2.migration.commit',
    };
    if (migrationOperations.contains(c['operation'])) return;
    if ([
      'crypto2.blob.begin',
      'crypto2.blob.chunk',
      'crypto2.blob.complete',
      'crypto2.blob.abort',
      'crypto2.table.acquire',
      'crypto2.table.renew',
      'crypto2.table.release',
      'crypto2.domain.checkpoint',
    ].contains(c['operation'])) {
      final payload = c['payload'] as Map;
      final head = await currentHead(payload['scopeId'], online: true);
      if (payload['membershipHeadHash'] != head.headHash ||
          payload['epoch'] != head.epoch ||
          payload['accessRevision'] != head.accessRevision) {
        throw const CryptoAuthorityPending('scope_reauthorization_required');
      }
      final member = head.member(account.directory.accountId);
      final checkpoint = c['operation'] == 'crypto2.domain.checkpoint';
      if ((!checkpoint && member['role'] == 'viewer') ||
          payload['domain'] == 'finance' &&
              (checkpoint
                  ? member['financeRole'] == 'none'
                  : member['financeRole'] != 'write')) {
        throw const CryptoAuthorityPending('scope_write_forbidden');
      }
      for (final member in head.members) {
        final current = await currentMemberDirectory(
          head.scopeId,
          head.headHash,
          member['accountId'],
        );
        if (current.deviceSnapshotHash != member['deviceSnapshotHash']) {
          throw const CryptoAuthorityPending('scope_rotation_required');
        }
      }
      if ([
            'crypto2.blob.begin',
            'crypto2.blob.chunk',
          ].contains(c['operation']) &&
          lifecycle != null) {
        final staged = await account.store.database.rows(
          'SELECT descriptor,source_hash FROM crypto_document_jobs WHERE partition=? AND id=? AND state=?',
          [account.store.partition, payload['id'], 'staged'],
        );
        if (staged.length == 1) {
          final descriptor =
              jsonDecode(staged.single['descriptor'] as String) as Map;
          if ((c['operation'] == 'crypto2.blob.begin' &&
                  descriptor['manifestBase64'] == payload['manifestBase64'] &&
                  descriptor['cipherSha256'] == payload['sha256'] &&
                  descriptor['cipherSize'] == payload['size']) ||
              (c['operation'] == 'crypto2.blob.chunk' &&
                  descriptor['scopeId'] == payload['scopeId'] &&
                  descriptor['domain'] == payload['domain'] &&
                  descriptor['membershipHeadHash'] ==
                      payload['membershipHeadHash'] &&
                  descriptor['epoch'] == payload['epoch'] &&
                  descriptor['accessRevision'] == payload['accessRevision'])) {
            final own = await account.directory.cachedVerifiedDirectory(),
                members = <String, String>{};
            var allPinned = true;
            for (final member in head.members) {
              final pin = await account.store.anchor(member['accountId']);
              if (pin == null ||
                  pin['trustState'] != 'verified' ||
                  pin['deviceSnapshotHash'] != member['deviceSnapshotHash']) {
                allPinned = false;
                break;
              }
              members[member['accountId']] = pin['deviceSnapshotHash'];
            }
            final scopePin = await account.store.secure.read(
              'scope2:${account.store.partition}:${head.scopeId}',
            );
            final source = await account.store.database.rows(
              'SELECT o.signed_body FROM crypto_command_keys k JOIN crypto_outbox o ON o.partition=k.partition AND o.request_id=k.request_id WHERE k.partition=? AND k.action_key=?',
              [account.store.partition, 'blob:${payload['id']}:begin'],
            );
            if (allPinned &&
                members.length == head.members.length &&
                scopePin != null &&
                source.length == 1) {
              _blobWindows[windowKey] = _BlobAuthorityWindow(
                Map<String, dynamic>.from(payload),
                own.deviceSnapshotHash,
                scopePin,
                members,
                lifecycle.generation,
                await cryptoSha256(
                  utf8.encode(
                    '${staged.single['descriptor']}:${staged.single['source_hash']}',
                  ),
                ),
                await cryptoSha256(
                  utf8.encode(source.single['signed_body'] as String),
                ),
              );
            }
          }
        }
      } else if (c['operation'] == 'crypto2.blob.complete' ||
          c['operation'] == 'crypto2.blob.abort')
        _blobWindows.remove(windowKey);
      return;
    }

    if (c['operation'] != 'crypto2.records.batch') {
      throw const CryptoAuthorityPending(
        'crypto_delivery_operation_unsupported',
      );
    }
    if (((c['payload'] as Map)['exportBindings'] as List?)?.isNotEmpty ==
        true) {
      await CryptoScopedExports.verifyBatchDelivery(this, c);
    }
    for (final proof in (c['payload'] as Map)['records'] as List) {
      final record =
          CryptoJson.decode(cryptoBase64(proof['commandBase64']))
              as Map<String, dynamic>;
      final head = await currentHead(record['scopeId'], online: true);
      if (record['membershipHeadHash'] != head.headHash) {
        throw const CryptoAuthorityPending('scope_reauthorization_required');
      }
      for (final member in head.members) {
        final current = await currentMemberDirectory(
          head.scopeId,
          head.headHash,
          member['accountId'],
        );
        if (current.deviceSnapshotHash != member['deviceSnapshotHash']) {
          throw const CryptoAuthorityPending('scope_rotation_required');
        }
        if (member['accountId'] != account.directory.accountId) {
          await requireExistingScopeMemberIdentity(head, current);
        }
      }
    }
  }
}
