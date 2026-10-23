import 'crypto_finance_topology_creation.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:sodium/sodium.dart';
import 'package:cryptography/cryptography.dart' show Sha256;

import 'account_directory_v2.dart';
import 'crypto_json.dart';
import 'crypto_record_address.dart';
import 'crypto_record_proof_codec.dart';
import 'crypto_sync_repository.dart';
import 'scope_crypto_codec.dart';
import 'scope_key_contributions.dart';
import 'crypto_lifecycle_evidence.dart';
import 'session_crypto_access.dart';
import 'crypto_inherited_invitation_evidence.dart';
import 'crypto_preauthorized_invitation.dart';

class ScopeRotationReview {
  ScopeRotationReview(Map<String, dynamic> value)
    : value = Map.unmodifiable(value);
  final Map<String, dynamic> value;
  String get id => value['reviewId'];
  String get scopeId => value['scopeId'];
  String get sourceHeadHash => value['sourceHeadHash'];
  String get historyBasis => value['historyBasis'];
  Map get domains => value['domains'];
}

class ScopeRecoveryPreview {
  ScopeRecoveryPreview(this.id, this.plaintext);
  final String id;
  final Uint8List? plaintext;
  void dispose() => plaintext?.fillRange(0, plaintext!.length, 0);
}

class _PreparedMigrationGenerationDraft implements Exception {
  _PreparedMigrationGenerationDraft(this.value);
  final Map<String, dynamic> value;
}

/// Durable scope setup: independent identity checks precede per-device/recovery
/// envelopes; exact proposals, grants and activation survive accepted lost ACKs.
class ScopeCryptoManager {
  ScopeCryptoManager(this.access);
  static final _foregroundInvitationJournal = Object();

  /// Provenance only: exact signed permissions and foreground guards remain
  /// required at admission. Generic pending resumption skips these commands.
  static Future<T> foregroundInvitationOperation<T>(
    String invitationId,
    Future<T> Function() body, {
    required bool Function() isForegroundCurrent,
  }) => runZoned(
    body,
    zoneValues: {
      _foregroundInvitationJournal: (invitationId, isForegroundCurrent),
    },
  );
  void _foregroundDeliveryGuard() {
    final context = Zone.current[_foregroundInvitationJournal];
    if (context is (String, bool Function()) &&
        (!context.$2() || !access.account.directory.isCurrent())) {
      throw const CryptoAuthorityPending(
        'crypto_invitation_foreground_required',
      );
    }
  }

  final SessionCryptoAccess access;
  static final _queues = <String, Future<void>>{};
  Future<T> _exclusive<T>(String scopeId, Future<T> Function() body) async {
    final key = '${access.account.store.partition}:$scopeId';
    final previous = _queues[key] ?? Future<void>.value();
    final task = previous.then((_) => body());
    final marker = task.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    _queues[key] = marker;
    try {
      return await task;
    } finally {
      if (identical(_queues[key], marker)) _queues.remove(key);
    }
  }

  Future<Map<String, dynamic>> _mutate(
    String operation,
    String scopeId,
    Map<String, dynamic> payload, {
    String? actionKey,
    String? deliveryToken,
    String? fixedRequestId,
    Map<String, dynamic>? preparedAuthorization,
  }) async {
    final account = access.account;
    final crypto = account.directory.reducer.crypto;
    actionKey ??= await cryptoSha256(
      CryptoJson.encode({'operation': operation, 'payload': payload}),
    );
    final existing = await account.store.database.rows(
      'SELECT i.* FROM crypto_membership_action_keys a JOIN crypto_membership_intents i ON i.partition=a.partition AND i.scope_id=a.scope_id AND i.intent_id=a.request_id WHERE a.partition=? AND a.scope_id=? AND a.action_key=?',
      [account.store.partition, scopeId, actionKey],
    );
    if (existing.isNotEmpty) {
      final row = existing.single;
      final original =
          CryptoJson.decode(
                Uint8List.fromList((row['authorization'] as List).cast<int>()),
              )
              as Map<String, dynamic>;
      final prior =
          CryptoJson.decode(cryptoBase64(original['commandBase64'])) as Map;
      Map<String, dynamic> comparable(Map source) {
        final out = Map<String, dynamic>.from(source);
        if (operation == 'crypto2.scope.create' ||
            operation == 'crypto2.scope.ensurePersonal') {
          out.remove('originProof');
        }
        if (operation == 'crypto2.grants.put') {
          out['recipients'] = [
            for (final recipient in out['recipients'] as List)
              Map<String, dynamic>.from(recipient as Map)
                ..remove('sealedEnvelopeBase64'),
          ];
        }
        return out;
      }

      if (fixedRequestId != null && prior['requestId'] != fixedRequestId ||
          prior['operation'] != operation ||
          base64Encode(
                CryptoJson.encode(comparable(prior['payload'] as Map)),
              ) !=
              base64Encode(CryptoJson.encode(comparable(payload)))) {
        throw const CryptoAuthorityPending(
          'scope_setup_reauthorization_required',
        );
      }
      if (row['state'] == 'confirmed') {
        final saved =
            jsonDecode(utf8.decode((row['payload'] as List).cast<int>()))
                as Map;
        return {
          ...Map<String, dynamic>.from(
            (saved['receipt'] as Map)['response'] as Map,
          ),
          'authorization': original,
        };
      }
      return _send(scopeId, row['intent_id'] as String, original);
    }
    final requestId = fixedRequestId ?? crypto.randomId();
    final originDirectory =
        (operation == 'crypto2.scope.create' ||
            operation == 'crypto2.scope.ensurePersonal')
        ? await account.directory.requireFresh()
        : null;
    final lease = preparedAuthorization == null
        ? await account.signingKey()
        : null;
    late Map<String, dynamic> proof;
    try {
      if (preparedAuthorization != null) {
        final c =
            CryptoJson.decode(
                  cryptoBase64(preparedAuthorization['commandBase64']),
                )
                as Map;
        if (operation != 'crypto2.scope.headPut' ||
            c['version'] != 2 ||
            c['signer'] != 'device' ||
            c['operation'] != operation ||
            c['requestId'] != requestId ||
            c['serverId'] != account.directory.session.profile.serverId ||
            c['accountId'] != account.directory.accountId ||
            c['deviceId'] != account.deviceId ||
            base64Encode(CryptoJson.encode(c['payload'])) !=
                base64Encode(CryptoJson.encode(payload))) {
          throw const FormatException('crypto_immutable_generation_proposal');
        }
        final own = await account.directory.requireFresh();
        crypto.verifyDomain(
          preparedAuthorization,
          cryptoBase64(
            own.activeDevice(account.deviceId)['signingKeyBase64'],
            length: 32,
          ),
          cryptoDirectoryDomain,
        );
        proof = preparedAuthorization;
      } else {
        if (originDirectory != null) {
          final personal = operation == 'crypto2.scope.ensurePersonal';
          payload = {
            ...payload,
            'originProof': crypto.signDomain(
              {
                'version': 2,
                'operation': 'crypto2.scope.origin',
                'serverId': account.directory.session.profile.serverId,
                'scopeId': scopeId,
                'kind': personal ? 'personal' : payload['kind'],
                'accessPolicyVersion': personal ? 1 : 3,
                'parentScopeToken': payload['parentScopeId'] == null
                    ? null
                    : await CryptoLifecycleEvidence(
                        access,
                      ).parentToken(scopeId, payload['parentScopeId']),
                'requestId': requestId,
                'accountId': account.directory.accountId,
                'deviceId': account.deviceId,
                'authorDirectoryHeadHash': originDirectory.headHash,
              },
              lease!.key,
              'JivieE2EE/scopeOrigin/v2\n',
            ),
          };
        }
        proof = crypto.signDomain(
          {
            'version': 2,
            'operation': operation,
            'requestId': requestId,
            'serverId': account.directory.session.profile.serverId,
            'accountId': account.directory.accountId,
            'deviceId': account.deviceId,
            'signer': 'device',
            'payload': payload,
          },
          lease!.key,
          cryptoDirectoryDomain,
        );
      }
    } finally {
      lease?.release();
    }
    final command =
        CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
    await account.store.database.transaction(() async {
      await account.store.database.execute(
        'INSERT INTO crypto_membership_intents VALUES(?,?,?,?,?,?)',
        [
          account.store.partition,
          scopeId,
          command['requestId'],
          'pending',
          Uint8List.fromList(
            utf8.encode(
              jsonEncode({
                'operation': operation,
                'actionKey': actionKey,
                if (Zone.current[_foregroundInvitationJournal]
                    is (String, bool Function()))
                  'foregroundInvitationId':
                      (Zone.current[_foregroundInvitationJournal]
                              as (String, bool Function()))
                          .$1,
              }),
            ),
          ),
          CryptoJson.encode(proof),
        ],
      );
      if (deliveryToken != null) {
        await account.store.database.execute(
          'INSERT INTO crypto_invitation_deliveries VALUES(?,?,?)',
          [account.store.partition, command['requestId'], deliveryToken],
        );
      }
      await account.store.database.execute(
        'INSERT INTO crypto_membership_action_keys VALUES(?,?,?,?)',
        [account.store.partition, scopeId, actionKey, command['requestId']],
      );
    });
    return _send(scopeId, command['requestId'], proof);
  }

  Future<Map<String, dynamic>> _send(
    String scopeId,
    String requestId,
    Map<String, dynamic> proof, {
    bool receiptOnly = false,
  }) async {
    _foregroundDeliveryGuard();
    final account = access.account;
    final c = CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
    final hash = await cryptoSha256(cryptoBase64(proof['commandBase64']));
    Future<Map<String, dynamic>> lookup() => account.directory.call(
      'crypto2.receipt.get',
      {'requestId': requestId, 'requestHash': hash},
    );
    var receipt = await lookup();
    bool exact(Map<String, dynamic> r) =>
        r['requestId'] == requestId &&
        r['requestHash'] == hash &&
        r['status'] is int &&
        base64Encode(CryptoJson.encode(r['authorization'])) ==
            base64Encode(CryptoJson.encode(proof));
    if (!exact(receipt)) {
      if (receipt['outcome'] != 'unknown') {
        throw const FormatException('scope_receipt_substitution');
      }
      if (receiptOnly) {
        throw const CryptoAuthorityPending('scope_receipt_pending');
      }
      await account.directory.requireFresh();
      try {
        final delivery = await account.store.database.rows(
          'SELECT token FROM crypto_invitation_deliveries WHERE partition=? AND request_id=?',
          [account.store.partition, requestId],
        );
        _foregroundDeliveryGuard();
        await account.directory.call(c['operation'], {
          ...proof,
          if (delivery.isNotEmpty) 'deliveryToken': delivery.single['token'],
        });
      } catch (error, stack) {
        final after = await lookup();
        if (!exact(after)) Error.throwWithStackTrace(error, stack);
        receipt = after;
      }
      if (!exact(receipt)) receipt = await lookup();
    }
    if (!exact(receipt)) {
      throw const CryptoAuthorityPending('scope_receipt_pending');
    }
    if (receipt['status'] != 200) {
      await account.store.database.execute(
        "UPDATE crypto_membership_intents SET state='rejected',payload=? WHERE partition=? AND scope_id=? AND intent_id=?",
        [
          Uint8List.fromList(
            utf8.encode(
              jsonEncode({'operation': c['operation'], 'receipt': receipt}),
            ),
          ),
          account.store.partition,
          scopeId,
          requestId,
        ],
      );
      throw const CryptoAuthorityPending('scope_reauthorization_required');
    }
    await account.store.database.execute(
      "UPDATE crypto_membership_intents SET state='confirmed',payload=? WHERE partition=? AND scope_id=? AND intent_id=? AND state='pending'",
      [
        Uint8List.fromList(
          utf8.encode(
            jsonEncode({'operation': c['operation'], 'receipt': receipt}),
          ),
        ),
        account.store.partition,
        scopeId,
        requestId,
      ],
    );
    return {
      ...Map<String, dynamic>.from(receipt['response'] as Map),
      'authorization': proof,
    };
  }

  /// After a verified exact activation is already current, reconcile only its
  /// retained request receipt. Never replay an unknown activation or new keys.
  Future<void> reconcileAppliedRotation({
    required String scopeId,
    required String reviewId,
    required String headHash,
    Future<void> Function()? beforeDisclosure,
  }) => _exclusive(scopeId, () async {
    await beforeDisclosure?.call();
    final db = access.account.store.database,
        partition = access.account.store.partition;
    final publications = await db.rows(
      "SELECT payload FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND intent_id=? AND state='scopeRotationPublished'",
      [partition, scopeId, '$reviewId:published'],
    );
    if (publications.length != 1) {
      throw const CryptoAuthorityPending('scope_review_confirmation_required');
    }
    final publication =
        CryptoJson.decode(
              Uint8List.fromList(
                (publications.single['payload'] as List).cast<int>(),
              ),
            )
            as Map;
    if (publication['reviewId'] != reviewId ||
        publication['headHash'] != headHash) {
      throw const FormatException('scope_review_publication_changed');
    }
    final rows = await db.rows(
      "SELECT intent_id,state,authorization FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND state IN ('pending','confirmed') AND authorization IS NOT NULL",
      [partition, scopeId],
    );
    final matching = <Map<String, dynamic>>[];
    for (final row in rows) {
      final proof = Map<String, dynamic>.from(
        CryptoJson.decode(
              Uint8List.fromList((row['authorization'] as List).cast<int>()),
            )
            as Map,
      );
      final c = CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
      if (c['operation'] == 'crypto2.scope.activate' &&
          c['payload']['scopeId'] == scopeId &&
          c['payload']['headHash'] == headHash) {
        matching.add({...row, 'proof': proof});
      }
    }
    if (matching.length != 1) {
      throw const CryptoAuthorityPending('scope_receipt_pending');
    }
    await beforeDisclosure?.call();
    if (matching.single['state'] == 'pending') {
      await _send(
        scopeId,
        matching.single['intent_id'],
        matching.single['proof'],
        receiptOnly: true,
      );
    }
    await db.execute(
      "UPDATE crypto_membership_intents SET state='scopeRotationReviewComplete' WHERE partition=? AND scope_id=? AND intent_id=? AND state='scopeRotationReview'",
      [partition, scopeId, reviewId],
    );
  });

  Future<void> resume(String scopeId) => _exclusive(scopeId, () async {
    final rows = await access.account.store.database.rows(
      "SELECT intent_id,authorization,payload FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND state='pending' AND authorization IS NOT NULL ORDER BY rowid",
      [access.account.store.partition, scopeId],
    );
    for (final row in rows) {
      final metadata =
          jsonDecode(utf8.decode((row['payload'] as List).cast<int>())) as Map;
      if (metadata['foregroundInvitationId'] is String) continue;
      final proof =
          CryptoJson.decode(
                Uint8List.fromList((row['authorization'] as List).cast<int>()),
              )
              as Map<String, dynamic>;
      await _send(scopeId, row['intent_id'] as String, proof);
    }
  });

  Future<Map<String, dynamic>> createScope({
    required String id,
    required String kind,
    String? parentScopeId,
    int? expectedParentAccessRevision,
    List<Map<String, dynamic>>? expectedParentAccessBasis,
  }) => _exclusive(
    id,
    () => _mutate('crypto2.scope.create', id, {
      'id': id,
      'kind': kind,
      if (parentScopeId != null) 'parentScopeId': parentScopeId,
      if (expectedParentAccessRevision != null)
        'expectedParentAccessRevision': expectedParentAccessRevision,
      if (expectedParentAccessBasis != null)
        'expectedParentAccessBasis': expectedParentAccessBasis,
    }),
  );
  Future<Map<String, dynamic>> ensurePersonal(String id) => _exclusive(
    id,
    () => _mutate('crypto2.scope.ensurePersonal', id, {'id': id}),
  );

  /// Existing SQL members are discovery inputs only. Every root and device set
  /// is independently pinned and fully replayed before it enters the proposal.
  Future<VerifiedScopeHead> initializeEmptyScope({
    required String scopeId,
    required int accessRevision,
    required List<Map<String, dynamic>> members,
    String? migrationId,
    String? captureId,
    Map<String, dynamic>? parentTopologyBatch,
  }) => _initializeEmptyScope(
    scopeId: scopeId,
    accessRevision: accessRevision,
    members: members,
    migrationId: migrationId,
    captureId: captureId,
    parentTopologyBatch: parentTopologyBatch,
  );

  /// Builds and journals a fresh generation locally. No head/grant/activation
  /// RPC, scope floor or active key is published by this method.
  Future<Map<String, dynamic>> prepareMigrationGenerationDraft({
    required String generationId,
    required String scopeId,
    required int accessRevision,
    required List<Map<String, dynamic>> members,
  }) async {
    if (!isCryptoCanonicalUuid(generationId)) {
      throw const FormatException('crypto_migration_generation');
    }
    try {
      await _initializeEmptyScope(
        scopeId: scopeId,
        accessRevision: accessRevision,
        members: members,
        generationId: generationId,
        onDraft: (body, headHash) async {
          final account = access.account;
          final key = 'scopeGenerationProposal:$generationId:$scopeId';
          final old = await account.store.database.rows(
            "SELECT payload FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND intent_id=? AND state='scopeGenerationProposal'",
            [account.store.partition, scopeId, generationId],
          );
          Map<String, dynamic> proof;
          if (old.isNotEmpty) {
            proof = Map<String, dynamic>.from(
              CryptoJson.decode(
                    Uint8List.fromList(
                      (old.single['payload'] as List).cast<int>(),
                    ),
                  )
                  as Map,
            );
            final signed =
                CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
            if (base64Encode(CryptoJson.encode(signed['payload'])) !=
                base64Encode(CryptoJson.encode(body))) {
              throw const FormatException('crypto_immutable_generation_draft');
            }
          } else {
            final lease = await account.signingKey();
            try {
              proof = account.directory.reducer.crypto.signDomain(
                {
                  'version': 2,
                  'operation': 'crypto2.scope.headPut',
                  'requestId': account.directory.reducer.crypto.randomId(),
                  'serverId': account.directory.session.profile.serverId,
                  'accountId': account.directory.accountId,
                  'deviceId': account.deviceId,
                  'signer': 'device',
                  'payload': body,
                },
                lease.key,
                cryptoDirectoryDomain,
              );
            } finally {
              lease.release();
            }
            await account.store.database.execute(
              'INSERT INTO crypto_membership_intents VALUES(?,?,?,?,?,NULL)',
              [
                account.store.partition,
                scopeId,
                generationId,
                'scopeGenerationProposal',
                CryptoJson.encode(proof),
              ],
            );
          }
          throw _PreparedMigrationGenerationDraft({
            'generationId': generationId,
            'scopeId': scopeId,
            'headHash': headHash,
            'authorization': proof,
            'actionKey': key,
          });
        },
      );
    } on _PreparedMigrationGenerationDraft catch (draft) {
      return draft.value;
    }
    throw const FormatException('crypto_migration_generation_draft_published');
  }

  Future<VerifiedScopeHead> publishMigrationGenerationDraft({
    required String generationId,
    required String migrationId,
    required String scopeId,
    String? captureId,
  }) async {
    final rows = await access.account.store.database.rows(
      "SELECT payload FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND intent_id=? AND state='scopeGenerationProposal'",
      [access.account.store.partition, scopeId, generationId],
    );
    if (rows.length != 1) {
      throw const CryptoAuthorityPending(
        'crypto_migration_generation_local_draft_missing',
      );
    }
    final proof = Map<String, dynamic>.from(
      CryptoJson.decode(
            Uint8List.fromList((rows.single['payload'] as List).cast<int>()),
          )
          as Map,
    );
    final command =
        CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
    final body = Map<String, dynamic>.from(command['payload'] as Map);
    return _initializeEmptyScope(
      scopeId: scopeId,
      accessRevision: body['accessRevision'],
      members: (body['members'] as List)
          .map((m) => Map<String, dynamic>.from(m as Map))
          .toList(),
      generationId: generationId,
      migrationId: migrationId,
      captureId: captureId,
      preparedAuthorization: proof,
    );
  }

  Future<VerifiedScopeHead> _initializeEmptyScope({
    required String scopeId,
    required int accessRevision,
    required List<Map<String, dynamic>> members,
    String? migrationId,
    String? captureId,
    Map<String, dynamic>? parentTopologyBatch,
    String? generationId,
    Map<String, dynamic>? preparedAuthorization,
    Future<Never> Function(Map<String, dynamic>, String)? onDraft,
  }) => _exclusive(scopeId, () async {
    final draftState = generationId == null
        ? 'scopeSetupDraft'
        : 'scopeGenerationDraft:$generationId';
    final account = access.account;
    final crypto = account.directory.reducer.crypto;
    final author = await account.directory.requireFresh();
    final existing = <Map<String, dynamic>>[];
    String? afterId;
    while (existing.isEmpty) {
      final page = await account.directory.call('crypto2.scopes.catalog', {
        if (afterId != null) 'afterId': afterId,
        'limit': 50,
      });
      final scopes = (page['scopes'] as List).cast<Map<String, dynamic>>();
      existing.addAll(scopes.where((scope) => scope['id'] == scopeId));
      if (existing.isNotEmpty || page['hasMore'] != true) break;
      final next = page['nextAfterId'];
      if (next is! String ||
          scopes.isEmpty ||
          afterId != null && next.compareTo(afterId) <= 0) {
        throw const FormatException('scope_catalog_cursor');
      }
      afterId = next;
    }
    if (existing.isEmpty) {
      throw const CryptoAuthorityPending('scope_discovery_pending');
    }
    final local = await account.store.database.rows(
      "SELECT intent_id,payload FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND state=? ORDER BY rowid DESC LIMIT 1",
      [account.store.partition, scopeId, draftState],
    );
    late Map<String, dynamic> body;
    late String headHash;
    if (local.isNotEmpty) {
      final draft =
          jsonDecode(utf8.decode((local.single['payload'] as List).cast<int>()))
              as Map;
      body = Map<String, dynamic>.from(draft['body'] as Map);
      headHash = draft['headHash'];
      if (body['accessRevision'] != accessRevision) {
        throw const CryptoAuthorityPending(
          'scope_setup_reauthorization_required',
        );
      }
    } else {
      // Legacy migration stages its exact signed lifecycle baseline before a
      // key/head draft is created, including already fenced migration sources.
      if ((onDraft == null ||
              generationId != null && existing.single['headHash'] == null) &&
          existing.single['cryptoOrigin'] != true) {
        await _mutate('crypto2.scope.prepare', scopeId, {
          'scopeId': scopeId,
          'expectedAccessRevision': accessRevision,
        });
      }
      final inheritedPreauthorizations = await access
          .preauthorizationsForNewScope(
            scopeId: scopeId,
            parentScopeId:
                generationId == null && existing.single['cryptoOrigin'] == true
                ? existing.single['parentScopeId'] as String?
                : null,
          );
      final normalized = <Map<String, dynamic>>[];
      for (final member in members) {
        final inheritedMarker = inheritedPreauthorizations.where((entry) =>
          entry['accountId'] == member['accountId']).firstOrNull;
        VerifiedAccountDirectory? retainedInheritedDirectory;
        if (inheritedMarker != null) {
          final parent = await access.currentHead(
            inheritedMarker['invitationScopeId'] as String, online: true);
          final parentMember = parent.member(member['accountId'] as String);
          final role = parentMember['role'] == 'viewer' ? 'viewer' : 'member';
          if (member['role'] != role || member['manageKeys'] != (role == 'member') ||
              role == 'viewer' && member['financeRole'] == 'write') {
            throw const FormatException('crypto_invitation_new_child_rights');
          }
          retainedInheritedDirectory = await access.directoryAt(
            scopeId: parent.scopeId, scopeHeadHash: parent.headHash,
            accountId: member['accountId'] as String,
            directoryHeadHash: parentMember['directoryHeadHash'] as String,
            online: true);
        }
        final directory = retainedInheritedDirectory ?? (member['accountId'] == author.accountId
            ? author
            : await access.currentMemberDirectory(
                scopeId,
                generationId == null
                    ? cryptoZeroHash
                    : (existing.single['headHash'] ?? cryptoZeroHash),
                member['accountId'],
              ));
        if (directory.accountId != author.accountId) {
          await access.identities.requireVerified(
            directory.accountId,
            access.identities.fingerprint(directory),
          );
        }
        normalized.add({
          'accountId': directory.accountId,
          'rootSigningKeyBase64': directory.snapshot['rootSigningKeyBase64'],
          'rootEncryptionKeyBase64':
              directory.snapshot['rootEncryptionKeyBase64'],
          'recoveryRootEpochId': directory.snapshot['recoveryRootEpochId'],
          'identityEpochId': directory.identityEpochId,
          'directoryHeadHash': directory.headHash,
          'deviceSnapshotHash': directory.deviceSnapshotHash,
          'role': member['role'],
          'financeRole': member['financeRole'],
          'manageKeys': member['manageKeys'] ?? member['role'] == 'owner',
        });
      }
      normalized.sort(
        (a, b) => (a['accountId'] as String).compareTo(b['accountId']),
      );
      final mine = normalized.singleWhere(
        (m) => m['accountId'] == author.accountId,
      );
      if (mine['role'] != 'owner') {
        throw const CryptoAuthorityPending('scope_owner_required');
      }
      final hasFinance = normalized.any((m) => m['financeRole'] != 'none');
      final intent = crypto.randomId();
      final commitments = <String, dynamic>{'content': null, 'finance': null};
      final ids = <String, dynamic>{'content': null, 'finance': null};
      final keys = <String, SecureKey>{};
      try {
        for (final domain in [
          'content',
          if (hasFinance && mine['financeRole'] != 'none') 'finance',
        ]) {
          final key = crypto.sodium.secureRandom(32);
          keys[domain] = key;
          ids[domain] = crypto.randomId();
          final raw = key.extractBytes();
          try {
            commitments[domain] = await access.codec.keyCommitment(raw);
          } finally {
            raw.fillRange(0, raw.length, 0);
          }
        }
        body = {
          'scopeId': scopeId,
          'epoch': 1,
          'initialLifecycleHash': await access.initialLifecycleHash(scopeId),
          'previousLifecycleHash': null,
          'financePolicyIntentProof': null,
          'accessIntentProof': null,
          'previousHeadHash': cryptoZeroHash,
          'accessRevision': accessRevision,
          'expectedAccessRevision': existing.single['expectedAccessRevision'],
          'accessBasis': existing.single['accessBasis'],
          'authorDirectoryHeadHash': author.headHash,
          'members': normalized,
          'membershipIntents': <Map<String, dynamic>>[],
          if (inheritedPreauthorizations.isNotEmpty)
            'invitationPreauthorizations': inheritedPreauthorizations,
          'closures': {'content': null, 'finance': null},
          'keyIds': ids,
          'keyCommitments': commitments,
        };
        await _signOwnFinanceKey(body, author);
        if (mine['financeRole'] != 'none' || !hasFinance) {
          access.codec.validateBody(body);
        }
        headHash = await access.codec.headHash(body);
        final lease = await account.signingKey();
        try {
          await account.store.database.transaction(() async {
            for (final item in keys.entries) {
              final context = {
                'version': 2,
                'purpose': 'pendingScopeKey',
                'scopeId': scopeId,
                'domain': item.key,
                'keyId': ids[item.key],
                'intentId': intent,
                'serverId': author.serverId,
                'accountId': author.accountId,
                'recipientKind': 'recovery',
                'recipientId': author.snapshot['recoveryRootEpochId'],
                'recipientPublicKeyBase64':
                    author.snapshot['rootEncryptionKeyBase64'],
              };
              final sealed = crypto.sealKey(
                key: item.value,
                recipientPublicKey: cryptoBase64(
                  author.snapshot['rootEncryptionKeyBase64'],
                  length: 32,
                ),
                context: context,
              );
              final recovery = crypto.signDomain(
                {
                  'version': 2,
                  'operation': 'crypto2.localScopeKeyIntent',
                  'serverId': author.serverId,
                  'accountId': author.accountId,
                  'deviceId': account.deviceId,
                  'context': context,
                  'sealedEnvelopeBase64': sealed,
                },
                lease.key,
                'JivieE2EE/localKeyIntent/v2\n',
              );
              final raw = item.value.extractBytes();
              try {
                await account.store.database.execute(
                  'INSERT INTO crypto_scope_keys VALUES(?,?,?,?,?,?,?,?,?,?,?)',
                  [
                    account.store.partition,
                    scopeId,
                    item.key,
                    1,
                    headHash,
                    ids[item.key],
                    raw,
                    headHash,
                    CryptoJson.encode(recovery),
                    0,
                    0,
                  ],
                );
              } finally {
                raw.fillRange(0, raw.length, 0);
              }
            }
            await account.store.database.execute(
              'INSERT INTO crypto_membership_intents VALUES(?,?,?,?,?,NULL)',
              [
                account.store.partition,
                scopeId,
                intent,
                draftState,
                Uint8List.fromList(
                  utf8.encode(jsonEncode({'body': body, 'headHash': headHash})),
                ),
              ],
            );
          });
        } finally {
          lease.release();
        }
      } finally {
        for (final key in keys.values) {
          key.dispose();
        }
      }
    }
    if ((body['members'] as List).any((m) => m['financeRole'] != 'none') &&
        (body['keyCommitments'] as Map)['finance'] == null) {
      final draftRows = await account.store.database.rows(
        "SELECT intent_id FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND state=? ORDER BY rowid DESC LIMIT 1",
        [account.store.partition, scopeId, draftState],
      );
      final draftId = draftRows.single['intent_id'] as String;
      final resolved = await _obtainFinanceContribution(
        scopeId,
        body,
        draftId,
        headHash,
        generationId: generationId,
      );
      body = resolved.body;
      headHash = resolved.headHash;
      await account.store.database.execute(
        "UPDATE crypto_membership_intents SET payload=? WHERE partition=? AND scope_id=? AND intent_id=?",
        [
          Uint8List.fromList(
            utf8.encode(jsonEncode({'body': body, 'headHash': headHash})),
          ),
          account.store.partition,
          scopeId,
          draftId,
        ],
      );
    }
    if (onDraft != null) return onDraft(body, headHash);
    // The prepare operation is an explicit stage, never a legacy content send.
    if (existing.single['headHash'] == headHash && migrationId != null) {
      final candidate = await access.migrationCandidate(
        scopeId: scopeId,
        migrationId: migrationId,
        captureId: captureId,
        headHash: headHash,
      );
      await access.hydrateMigrationCandidateKeys(candidate);
      return candidate.head;
    }
    if (existing.single['headHash'] == headHash &&
        existing.single['cryptoState'] == 'active') {
      final active = await access.currentHead(scopeId, online: true);
      await access.hydrateScopeKeys(scopeId);
      return active;
    }
    final preparedCommand = preparedAuthorization == null
        ? null
        : CryptoJson.decode(
                cryptoBase64(preparedAuthorization['commandBase64']),
              )
              as Map;
    final result = await _mutate(
      'crypto2.scope.headPut',
      scopeId,
      body,
      actionKey: generationId == null
          ? null
          : 'scopeGenerationProposal:$generationId:$scopeId',
      fixedRequestId: preparedCommand?['requestId'],
      preparedAuthorization: preparedAuthorization,
    );
    if (result['headHash'] != headHash) {
      throw const FormatException('scope_head_ack');
    }
    final wire = await account.directory.call('crypto2.scope.headGet', {
      'scopeId': scopeId,
      'headHash': headHash,
    });
    final proposal = Map<String, dynamic>.from(wire['authorization'] as Map);
    final proposalAuthor = body['authorDirectoryHeadHash'] == author.headHash
        ? author
        : await access.directoryAt(
            scopeId: scopeId,
            scopeHeadHash: headHash,
            accountId: author.accountId,
            directoryHeadHash: body['authorDirectoryHeadHash'],
            online: true,
          );
    if (!author.includesAnchor(
          proposalAuthor.generation,
          proposalAuthor.headHash,
        ) ||
        proposalAuthor.deviceSnapshotHash != author.deviceSnapshotHash) {
      throw const CryptoAuthorityPending(
        'crypto_migration_generation_authority_changed',
      );
    }
    final pending = await access.codec.verifyProposal(
      serverId: author.serverId,
      authorization: proposal,
      previous: null,
      authorDirectory: proposalAuthor,
      directoryAtHead: (id, hash) => access.directoryAt(
        scopeId: scopeId,
        scopeHeadHash: headHash,
        accountId: id,
        directoryHeadHash: hash,
        online: true,
      ),
      checkIdentity: (id, fp) async {
        if (id != author.accountId) {
          await access.identities.requireVerified(id, fp);
        }
      },
    );
    return _grantAndActivate(
      pending: pending,
      author: author,
      migrationId: migrationId,
      captureId: captureId,
      parentTopologyBatch: parentTopologyBatch,
    );
  });

  /// Review a complete encrypted inventory before changing an existing scope.
  /// Emergency recovery deliberately labels this as an accepted candidate,
  /// because a file proves identity rather than when old records were signed.
  Future<ScopeRotationReview> reviewRotation(
    String scopeId, {
    Uint8List? recoveryFile,
    bool financeOnly = false,
    VerifiedInheritedInvitationAdmission? inheritedInvitationAdmission,
    VerifiedPreauthorizedInvitationAdmission? preauthorizedInvitationAdmission,
    String? fixedReviewId,
  }) => _exclusive(scopeId, () async {
    final account = access.account, crypto = account.directory.reducer.crypto;
    await account.directory.requireFresh();
    final source = await access.recoveryCandidateHead(scopeId);
    if (fixedReviewId != null) {
      final retained = await account.store.database.rows(
        "SELECT payload FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND intent_id=? AND state='scopeRotationReview'",
        [account.store.partition, scopeId, fixedReviewId],
      );
      if (retained.isNotEmpty) {
        final value = Map<String, dynamic>.from(
          CryptoJson.decode(
                Uint8List.fromList(
                  (retained.single['payload'] as List).cast<int>(),
                ),
              )
              as Map,
        );
        if (value['sourceHeadHash'] != source.headHash ||
            preauthorizedInvitationAdmission == null) {
          throw const CryptoAuthorityPending(
            'scope_review_confirmation_required',
          );
        }
        await preauthorizedInvitationAdmission.revalidate(source);
        return ScopeRotationReview(value);
      }
    }
    await inheritedInvitationAdmission?.revalidate(
      access: access,
      source: source,
    );
    await preauthorizedInvitationAdmission?.revalidate(source);
    final transportAccessRevision = preauthorizedInvitationAdmission != null
        ? (await _catalogScope(scopeId))['expectedAccessRevision'] as int
        : inheritedInvitationAdmission == null
        ? source.accessRevision
        : inheritedInvitationAdmission.liveAccess['expectedAccessRevision']
              as int;
    if ((!financeOnly &&
            source.member(account.directory.accountId)['manageKeys'] != true) ||
        (financeOnly &&
            source.member(account.directory.accountId)['financeRole'] ==
                'none')) {
      throw const CryptoAuthorityPending('scope_management_forbidden');
    }
    if (recoveryFile != null) {
      await access.recoverScopeCandidateKeys(scopeId, recoveryFile);
    } else {
      await access.hydrateExistingCandidateKeys(scopeId);
    }
    final id = fixedReviewId ?? crypto.randomId();
    final domains = <String, dynamic>{};
    var emergency = false;
    for (final member in source.members) {
      final current = await access.currentMemberDirectory(
        scopeId,
        source.headHash,
        member['accountId'],
      );
      emergency |= current.deviceSnapshotHash != member['deviceSnapshotHash'];
    }
    final records = CryptoRecordProofCodec(crypto);
    for (final domain in ['content', 'finance']) {
      if (financeOnly && domain != 'finance') continue;
      if (source.commitment(domain) == null) continue;
      if (domain == 'finance' &&
          source.member(account.directory.accountId)['financeRole'] == 'none') {
        continue;
      }
      var cursor = 0, sequence = -1;
      while (true) {
        await inheritedInvitationAdmission?.revalidate(
          access: access,
          source: source,
        );
        final page = await account.directory.call('crypto2.records.pull', {
          'scopeId': scopeId,
          'domain': domain,
          'accessRevision': transportAccessRevision,
          'cursor': cursor,
          'limit': 20,
        });
        if (page['scopeSequence'] is! int ||
            page['records'] is! List ||
            page['hasMore'] is! bool ||
            page['cursor'] is! int ||
            page['cursor'] < cursor ||
            page['accessRevision'] != transportAccessRevision ||
            page['epoch'] != source.epoch ||
            sequence >= 0 && page['scopeSequence'] != sequence) {
          throw const CryptoAuthorityPending('scope_review_changed');
        }
        sequence = page['scopeSequence'];
        for (final value in page['records'] as List) {
          final wire = Map<String, dynamic>.from(value as Map);
          final proof = Map<String, dynamic>.from(
            wire['authorization']['recordProof'] as Map,
          );
          final r =
              CryptoJson.decode(cryptoBase64(proof['commandBase64']))
                  as Map<String, dynamic>;
          final recordHead = access.verifiedCandidateAncestor(
            r['membershipHeadHash'],
          );
          late Map<String, dynamic> decoded;
          if ((r['metadata'] as Map).containsKey('migrationOrigin')) {
            if (r['scopeId'] != scopeId ||
                r['domain'] != domain ||
                recordHead.scopeId != scopeId) {
              throw const FormatException('scope_review_migration_context');
            }
            final authority = await access.recordAuthority(r),
                proofHash = await records.digest(proof),
                origin = authority.migrationOrigin;
            if (authority.historyBasis != 'migrationCapturedSource' ||
                authority.closedRecordProofHash != proofHash ||
                origin == null ||
                origin['captureVersion'] != 3 ||
                origin['recordProofHash'] != proofHash) {
              throw const FormatException('scope_review_migration_authority');
            }
            decoded = await records.verifyWire(
              serverId: account.directory.session.profile.serverId,
              wire: wire,
              trustedSigningKey: authority.signingKey,
              currentEpoch: authority.currentEpoch,
              closedRecordProofHash: authority.closedRecordProofHash,
            );
          } else {
            final member = recordHead.member(r['accountId']);
            if (member['role'] == 'viewer' ||
                domain == 'finance' && member['financeRole'] != 'write') {
              throw const FormatException('scope_review_author');
            }
            final directory = await access.directoryAt(
              scopeId: scopeId,
              scopeHeadHash: source.headHash,
              accountId: r['accountId'],
              directoryHeadHash: member['directoryHeadHash'],
            );
            final device = directory.activeDevice(r['deviceId']);
            decoded = await records.verifyWire(
              serverId: directory.serverId,
              wire: wire,
              trustedSigningKey: cryptoBase64(
                device['signingKeyBase64'],
                length: 32,
              ),
              currentEpoch: true,
            );
          }
          final key = await access.candidateKey(recordHead, domain);
          try {
            final plaintext = records.openVerified(decoded, key.key);
            plaintext?.fillRange(0, plaintext.length, 0);
          } finally {
            key.release();
          }
          final descriptor = {
            'id': wire['id'],
            'revision': wire['revision'],
            'recordProofHash': await records.digest(proof),
            'sequence': wire['sequence'],
            'recordEpoch': wire['epoch'],
          };
          if (descriptor['sequence'] is! int ||
              descriptor['sequence'] > sequence) {
            throw const FormatException('scope_review_sequence');
          }
          await account.store.database.execute(
            'INSERT INTO crypto_scope_review_records VALUES(?,?,?,?,?,?,?)',
            [
              account.store.partition,
              scopeId,
              id,
              domain,
              wire['id'],
              jsonEncode(wire),
              CryptoJson.encode(descriptor),
            ],
          );
        }
        final next = page['cursor'] as int;
        if (page['hasMore'] != true) break;
        if (next <= cursor) throw const FormatException('scope_review_cursor');
        cursor = next;
      }
      final sink = Sha256().newHashSink();
      var count = 0;
      String? after;
      while (true) {
        final rows = await account.store.database.rows(
          'SELECT record_id,descriptor FROM crypto_scope_review_records WHERE partition=? AND scope_id=? AND review_id=? AND domain=? AND record_id>? ORDER BY record_id LIMIT 100',
          [account.store.partition, scopeId, id, domain, after ?? ''],
        );
        if (rows.isEmpty) break;
        for (final row in rows) {
          sink.add((row['descriptor'] as List).cast<int>());
          sink.add([10]);
          count++;
        }
        after = rows.last['record_id'] as String;
      }
      sink.close();
      domains[domain] = {
        'sequence': sequence,
        'count': count,
        'manifestHash': (await sink.hash()).bytes
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join(),
      };
    }
    final value = {
      'reviewId': id,
      'scopeId': scopeId,
      'sourceHeadHash': source.headHash,
      'previousLifecycleHash': (await CryptoLifecycleEvidence(access)
          .forRecoveryReview(
            scopeId,
            sourceHeadHash: source.headHash,
            financeOnly: financeOnly,
          ))['headHash'],
      'domains': domains,
      'historyBasis': emergency
          ? 'reviewedRecoveryBaseline'
          : 'verifiedCheckpoint',
    };
    await account.store.database.execute(
      'INSERT INTO crypto_membership_intents VALUES(?,?,?,?,?,NULL)',
      [
        account.store.partition,
        scopeId,
        id,
        'scopeRotationReview',
        CryptoJson.encode(value),
      ],
    );
    return ScopeRotationReview(value);
  });

  Future<List<ScopeRecoveryPreview>> previewRotation(
    ScopeRotationReview review, {
    String? afterId,
    int limit = 20,
  }) async {
    if (limit < 1 || limit > 50) {
      throw const FormatException('scope_review_limit');
    }
    final rows = await access.account.store.database.rows(
      'SELECT * FROM crypto_scope_review_records WHERE partition=? AND scope_id=? AND review_id=? AND record_id>? ORDER BY record_id LIMIT ?',
      [
        access.account.store.partition,
        review.scopeId,
        review.id,
        afterId ?? '',
        limit,
      ],
    );
    final result = <ScopeRecoveryPreview>[];
    try {
      for (final row in rows) {
        final wire = jsonDecode(row['wire'] as String) as Map<String, dynamic>;
        final r =
            CryptoJson.decode(
                  cryptoBase64(
                    wire['authorization']['recordProof']['commandBase64'],
                  ),
                )
                as Map<String, dynamic>;
        final head = access.verifiedCandidateAncestor(r['membershipHeadHash']);
        final lease = await access.candidateKey(head, row['domain'] as String);
        try {
          result.add(
            ScopeRecoveryPreview(
              row['record_id'] as String,
              CryptoRecordProofCodec(
                access.account.directory.reducer.crypto,
              ).openVerified(r, lease.key),
            ),
          );
        } finally {
          lease.release();
        }
      }
      return result;
    } catch (_) {
      for (final item in result) {
        item.dispose();
      }
      rethrow;
    }
  }

  Future<VerifiedScopeHead> confirmRotation(
    ScopeRotationReview review, {
    Future<void> Function()? beforeDisclosure,
    Future<void> Function()? freshDisclosureBoundary,
    required bool acceptedCandidateHistory,
    List<Map<String, dynamic>>? members,
    List<Map<String, dynamic>> membershipIntents = const [],
    Future<VerifiedAccountDirectory> Function(String accountId)?
    joiningDirectory,
    Map<String, dynamic>? ownerAcceptanceProof,
    Map<String, dynamic>? financePolicyIntentProof,
    Map<String, dynamic>? accessIntentProof,
    VerifiedInheritedInvitationAdmission? inheritedInvitationAdmission,
    VerifiedPreauthorizedInvitationAdmission? preauthorizedInvitationAdmission,
    Future<Map<String, dynamic>> Function(
      List<Map<String, dynamic>> members,
      VerifiedAccountDirectory author,
    )?
    accessConsentBuilder,
  }) => _exclusive(review.scopeId, () async {
    await beforeDisclosure?.call();
    final account = access.account, crypto = account.directory.reducer.crypto;
    final author = await account.directory.requireFresh();
    final source = await access.recoveryCandidateHead(review.scopeId);
    if (preauthorizedInvitationAdmission != null) {
      if (review.historyBasis != 'verifiedCheckpoint' ||
          inheritedInvitationAdmission != null ||
          accessIntentProof != null ||
          accessConsentBuilder != null ||
          joiningDirectory != null ||
          membershipIntents.length != 1 ||
          base64Encode(CryptoJson.encode(membershipIntents.single)) !=
              base64Encode(
                CryptoJson.encode(preauthorizedInvitationAdmission.intent),
              )) {
        throw const CryptoAuthorityPending(
          'crypto_invitation_preauthorization_review',
        );
      }
      await preauthorizedInvitationAdmission.revalidate(source);
    }
    if (source.headHash != review.sourceHeadHash ||
        review.historyBasis == 'reviewedRecoveryBaseline' &&
            !acceptedCandidateHistory) {
      throw const CryptoAuthorityPending('scope_review_confirmation_required');
    }
    final rows = await account.store.database.rows(
      "SELECT payload FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND intent_id=? AND state='scopeRotationReview'",
      [account.store.partition, review.scopeId, review.id],
    );
    if (rows.length != 1 ||
        base64Encode((rows.single['payload'] as List).cast<int>()) !=
            base64Encode(CryptoJson.encode(review.value))) {
      throw const FormatException('scope_review_not_local');
    }
    final catalog = await _catalogScope(review.scopeId);
    // New transitions follow the existing server membership admission limit.
    // The historical codec still accepts previously signed larger heads.
    if ((members ?? source.members).length > 100) {
      throw const FormatException('scope_members_limit');
    }
    if (inheritedInvitationAdmission != null) {
      if (membershipIntents.isNotEmpty ||
          accessIntentProof != null ||
          accessConsentBuilder != null ||
          joiningDirectory != null) {
        throw const FormatException('scope_inherited_admission_ambiguous');
      }
      await inheritedInvitationAdmission.revalidate(
        access: access,
        source: source,
        proposedMembers: members ?? source.members,
      );
    }
    final normalized = <Map<String, dynamic>>[];
    final memberDirectories = <String, VerifiedAccountDirectory>{};
    for (final member in members ?? source.members) {
      final isJoining = !source.members.any(
        (m) => m['accountId'] == member['accountId'],
      );
      if (isJoining &&
          inheritedInvitationAdmission == null &&
          preauthorizedInvitationAdmission == null &&
          accessIntentProof == null &&
          accessConsentBuilder == null &&
          (joiningDirectory == null ||
              !membershipIntents.any(
                (i) => i['accountId'] == member['accountId'],
              ))) {
        throw const CryptoAuthorityPending('invitation_acceptance_required');
      }
      final directory =
          preauthorizedInvitationAdmission != null &&
              member['accountId'] ==
                  preauthorizedInvitationAdmission.recipientAccountId
          ? preauthorizedInvitationAdmission.directory
          : inheritedInvitationAdmission != null &&
                member['accountId'] ==
                    inheritedInvitationAdmission.recipientAccountId
          ? inheritedInvitationAdmission.recipientDirectory
          : isJoining && joiningDirectory != null
          ? await joiningDirectory(member['accountId'])
          : await access.currentMemberDirectory(
              review.scopeId,
              source.headHash,
              member['accountId'],
            );
      if (directory.accountId != author.accountId) {
        await access.requireExistingScopeMemberIdentity(source, directory);
      }
      memberDirectories[directory.accountId] = directory;
      normalized.add({
        ...member,
        'rootSigningKeyBase64': directory.snapshot['rootSigningKeyBase64'],
        'rootEncryptionKeyBase64':
            directory.snapshot['rootEncryptionKeyBase64'],
        'recoveryRootEpochId': directory.snapshot['recoveryRootEpochId'],
        'identityEpochId': directory.identityEpochId,
        'directoryHeadHash': directory.headHash,
        'deviceSnapshotHash': directory.deviceSnapshotHash,
      });
    }
    normalized.sort(
      (a, b) => (a['accountId'] as String).compareTo(b['accountId']),
    );
    if (accessConsentBuilder != null) {
      if (accessIntentProof != null) {
        throw const FormatException('scope_access_consent_ambiguous');
      }
      accessIntentProof = await accessConsentBuilder(normalized, author);
    }
    final accessConsent = accessIntentProof == null
        ? null
        : Map<String, dynamic>.from(
            CryptoJson.decode(cryptoBase64(accessIntentProof!['commandBase64']))
                as Map,
          );
    final expectedAccessRevision =
        accessConsent?['expectedAccessRevision'] ??
        catalog['expectedAccessRevision'];
    final accessBasis = accessConsent?['accessBasis'] ?? catalog['accessBasis'];
    final resultingAccessRevision = accessConsent?['resultingAccessRevision'];
    if (accessConsent != null &&
        (expectedAccessRevision != catalog['expectedAccessRevision'] ||
            base64Encode(CryptoJson.encode(accessBasis)) !=
                base64Encode(CryptoJson.encode(catalog['accessBasis'])))) {
      throw const CryptoAuthorityPending('crypto_access_base_changed');
    }
    if (accessConsent != null) {
      await access.codec.verifyAccessIntent(
        body: {
          'scopeId': review.scopeId,
          'expectedAccessRevision': expectedAccessRevision,
          'accessRevision': resultingAccessRevision,
          'accessBasis': accessBasis,
          'authorDirectoryHeadHash': author.headHash,
          'members': normalized,
          'accessIntentProof': accessIntentProof,
        },
        previous: source,
        authorDirectory: author,
        proposalCommand: {
          'serverId': author.serverId,
          'accountId': author.accountId,
          'deviceId': account.deviceId,
        },
      );
    }
    if (!normalized.any((m) => m['accountId'] == author.accountId)) {
      return ScopeKeyContributions(this).prepareDeparture(
        review,
        source,
        author,
        normalized,
        catalog,
        membershipIntents: membershipIntents,
        financePolicyIntentProof: financePolicyIntentProof,
        accessIntentProof: accessIntentProof,
      );
    }
    final drafts = await account.store.database.rows(
      "SELECT payload FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND state='scopeRotationDraft' AND json_extract(CAST(payload AS TEXT),'\$.reviewId')=?",
      [account.store.partition, review.scopeId, review.id],
    );
    if (drafts.length > 1) throw const FormatException('scope_rotation_fork');
    if (drafts.isNotEmpty) {
      final draft =
          CryptoJson.decode(
                Uint8List.fromList(
                  (drafts.single['payload'] as List).cast<int>(),
                ),
              )
              as Map;
      final body = Map<String, dynamic>.from(draft['body'] as Map);
      var sameMembers =
          base64Encode(CryptoJson.encode(body['members'])) ==
          base64Encode(CryptoJson.encode(normalized));
      if (!sameMembers && inheritedInvitationAdmission != null) {
        sameMembers = await _sameInheritedDraftMembers(
          source: source,
          admission: inheritedInvitationAdmission,
          recorded: (body['members'] as List).cast<Map<String, dynamic>>(),
          normalized: normalized,
          directories: memberDirectories,
        );
      }
      if (!sameMembers ||
          base64Encode(CryptoJson.encode(body['financePolicyIntentProof'])) !=
              base64Encode(CryptoJson.encode(financePolicyIntentProof)) ||
          base64Encode(CryptoJson.encode(body['accessIntentProof'])) !=
              base64Encode(CryptoJson.encode(accessIntentProof)) ||
          body['expectedAccessRevision'] != expectedAccessRevision ||
          base64Encode(CryptoJson.encode(body['accessBasis'])) !=
              base64Encode(CryptoJson.encode(accessBasis))) {
        throw const CryptoAuthorityPending(
          'scope_rotation_reauthorization_required',
        );
      }
      final originalAuthor = await access.directoryAt(
        scopeId: review.scopeId,
        scopeHeadHash: source.headHash,
        accountId: author.accountId,
        directoryHeadHash: body['authorDirectoryHeadHash'],
      );
      return await _publishRotation(
        review,
        body,
        draft['headHash'],
        source,
        originalAuthor,
        ownerAcceptanceProof,
        inheritedInvitationAdmission: inheritedInvitationAdmission,
        beforeDisclosure: beforeDisclosure,
        freshDisclosureBoundary: freshDisclosureBoundary,
      );
    }
    final commitments = <String, dynamic>{'content': null, 'finance': null},
        ids = <String, dynamic>{'content': null, 'finance': null};
    final rawKeys = <String, SecureKey>{};
    try {
      for (final domain in ['content', 'finance']) {
        if (domain == 'finance' &&
            (!normalized.any((m) => m['financeRole'] != 'none') ||
                normalized.singleWhere(
                      (m) => m['accountId'] == author.accountId,
                    )['financeRole'] ==
                    'none')) {
          continue;
        }
        final key = crypto.sodium.secureRandom(32);
        rawKeys[domain] = key;
        ids[domain] = crypto.randomId();
        final raw = key.extractBytes();
        try {
          commitments[domain] = await access.codec.keyCommitment(raw);
        } finally {
          raw.fillRange(0, raw.length, 0);
        }
      }
      final body = {
        'scopeId': review.scopeId,
        'epoch': source.epoch + 1,
        'initialLifecycleHash': source.body['initialLifecycleHash'],
        'previousLifecycleHash': review.value['previousLifecycleHash'],
        'financePolicyIntentProof': financePolicyIntentProof,
        'accessIntentProof': accessIntentProof,
        'previousHeadHash': source.headHash,
        'accessRevision':
            resultingAccessRevision ??
            (catalog['expectedAccessRevision'] as int) +
                (_sameRoster(
                      normalized,
                      (catalog['members'] as List).cast<Map<String, dynamic>>(),
                    )
                    ? 0
                    : 1),
        'expectedAccessRevision': expectedAccessRevision,
        'accessBasis': accessBasis,
        'authorDirectoryHeadHash': author.headHash,
        'members': normalized,
        'membershipIntents': membershipIntents,
        if (source.invitationPreauthorizations.isNotEmpty ||
            preauthorizedInvitationAdmission != null)
          'invitationPreauthorizations':
              ([
                for (final condition in source.invitationPreauthorizations)
                  if (normalized.any(
                        (m) => m['accountId'] == condition['accountId'],
                      ) &&
                      (preauthorizedInvitationAdmission == null ||
                          condition['accountId'] !=
                              preauthorizedInvitationAdmission
                                  .recipientAccountId))
                    condition,
                if (preauthorizedInvitationAdmission != null)
                  preauthorizedInvitationAdmission.condition,
              ]..sort(
                (a, b) => (a['accountId'] as String).compareTo(
                  b['accountId'] as String,
                ),
              )),
        'closures': {
          for (final domain in ['content', 'finance'])
            domain: review.domains[domain]?['manifestHash'],
        },
        'keyIds': ids,
        'keyCommitments': commitments,
      };
      await _signOwnFinanceKey(body, author);
      if (normalized.singleWhere(
                (m) => m['accountId'] == author.accountId,
              )['financeRole'] !=
              'none' ||
          !normalized.any((m) => m['financeRole'] != 'none')) {
        access.codec.validateBody(body);
      }
      final headHash = await access.codec.headHash(body);
      // Before network publication every new key has a durable recovery box.
      final lease = await account.signingKey();
      try {
        await account.store.database.transaction(() async {
          for (final entry in rawKeys.entries) {
            final context = {
              'version': 2,
              'purpose': 'pendingScopeKey',
              'scopeId': review.scopeId,
              'domain': entry.key,
              'keyId': ids[entry.key],
              'intentId': review.id,
              'serverId': author.serverId,
              'accountId': author.accountId,
              'recipientKind': 'recovery',
              'recipientId': author.snapshot['recoveryRootEpochId'],
              'recipientPublicKeyBase64':
                  author.snapshot['rootEncryptionKeyBase64'],
            };
            final sealed = crypto.sealKey(
              key: entry.value,
              recipientPublicKey: cryptoBase64(
                author.snapshot['rootEncryptionKeyBase64'],
                length: 32,
              ),
              context: context,
            );
            final proof = crypto.signDomain(
              {
                'version': 2,
                'operation': 'crypto2.localScopeKeyIntent',
                'serverId': author.serverId,
                'accountId': author.accountId,
                'deviceId': account.deviceId,
                'context': context,
                'sealedEnvelopeBase64': sealed,
              },
              lease.key,
              'JivieE2EE/localKeyIntent/v2\n',
            );
            final raw = entry.value.extractBytes();
            try {
              await account.store.database.execute(
                'INSERT INTO crypto_scope_keys VALUES(?,?,?,?,?,?,?,?,?,?,?)',
                [
                  account.store.partition,
                  review.scopeId,
                  entry.key,
                  source.epoch + 1,
                  headHash,
                  ids[entry.key],
                  raw,
                  headHash,
                  CryptoJson.encode(proof),
                  0,
                  0,
                ],
              );
            } finally {
              raw.fillRange(0, raw.length, 0);
            }
          }
          await account.store.database.execute(
            'INSERT INTO crypto_membership_intents VALUES(?,?,?,?,?,NULL)',
            [
              account.store.partition,
              review.scopeId,
              crypto.randomId(),
              'scopeRotationDraft',
              CryptoJson.encode({
                'reviewId': review.id,
                'body': body,
                'headHash': headHash,
              }),
            ],
          );
        });
      } finally {
        lease.release();
      }
      return await _publishRotation(
        review,
        body,
        headHash,
        source,
        author,
        ownerAcceptanceProof,
        inheritedInvitationAdmission: inheritedInvitationAdmission,
        beforeDisclosure: beforeDisclosure,
        freshDisclosureBoundary: freshDisclosureBoundary,
      );
    } finally {
      for (final key in rawKeys.values) {
        key.dispose();
      }
    }
  });

  /// A retained inherited grant keeps its exact proposal and keys. Ordinary
  /// account observations may advance a directory without changing its devices.
  /// Reverify the recorded prefix and its ancestry; no other roster field moves.
  Future<bool> _sameInheritedDraftMembers({
    required VerifiedScopeHead source,
    required VerifiedInheritedInvitationAdmission admission,
    required List<Map<String, dynamic>> recorded,
    required List<Map<String, dynamic>> normalized,
    required Map<String, VerifiedAccountDirectory> directories,
  }) async {
    if (recorded.length != normalized.length) return false;
    for (var i = 0; i < recorded.length; i++) {
      final old = recorded[i], current = normalized[i];
      final oldFields = Map<String, dynamic>.from(old)
        ..remove('directoryHeadHash');
      final currentFields = Map<String, dynamic>.from(current)
        ..remove('directoryHeadHash');
      if (base64Encode(CryptoJson.encode(oldFields)) !=
          base64Encode(CryptoJson.encode(currentFields))) {
        return false;
      }
      if (old['directoryHeadHash'] == current['directoryHeadHash']) continue;
      final directory = directories[old['accountId']];
      if (directory == null) return false;
      // The current directory was fully replayed under its secure pin above.
      // Historical replay must reconnect to it, including for a recipient whose
      // joining authority is the verified parent rather than the old child.
      final context =
          source.members.any(
            (member) => member['accountId'] == directory.accountId,
          )
          ? source
          : admission.parent;
      final prefix = await access.directoryAt(
        scopeId: context.scopeId,
        scopeHeadHash: context.headHash,
        accountId: directory.accountId,
        directoryHeadHash: old['directoryHeadHash'],
        online: true,
      );
      if (!directory.includesAnchor(prefix.generation, prefix.headHash) ||
          prefix.rootFingerprint != directory.rootFingerprint ||
          prefix.identityEpochId != directory.identityEpochId ||
          prefix.snapshot['recoveryRootEpochId'] !=
              directory.snapshot['recoveryRootEpochId'] ||
          prefix.deviceSnapshotHash != directory.deviceSnapshotHash) {
        return false;
      }
    }
    return true;
  }

  Future<VerifiedScopeHead> _publishRotation(
    ScopeRotationReview review,
    Map<String, dynamic> body,
    String headHash,
    VerifiedScopeHead source,
    VerifiedAccountDirectory author,
    Map<String, dynamic>? ownerAcceptanceProof, {
    VerifiedInheritedInvitationAdmission? inheritedInvitationAdmission,
    Future<void> Function()? beforeDisclosure,
    Future<void> Function()? freshDisclosureBoundary,
  }) async {
    final account = access.account;
    Future<void> validateInherited() async {
      await beforeDisclosure?.call();
      await inheritedInvitationAdmission?.revalidate(
        access: access,
        source: source,
        proposedMembers: (body['members'] as List).cast<Map<String, dynamic>>(),
      );
    }

    await validateInherited();
    if ((body['members'] as List).any((m) => m['financeRole'] != 'none') &&
        body['keyCommitments']['finance'] == null) {
      final resolved = await _obtainFinanceContribution(
        review.scopeId,
        body,
        review.id,
        headHash,
      );
      body = resolved.body;
      headHash = resolved.headHash;
      await account.store.database.execute(
        "UPDATE crypto_membership_intents SET payload=? WHERE partition=? AND scope_id=? AND state='scopeRotationDraft' AND json_extract(CAST(payload AS TEXT),'\$.reviewId')=?",
        [
          CryptoJson.encode({
            'reviewId': review.id,
            'body': body,
            'headHash': headHash,
          }),
          account.store.partition,
          review.scopeId,
          review.id,
        ],
      );
    }
    // One exact publication belongs to this local reviewed action, including
    // the contributor path where the departing manager has no future DEK.
    final publication = CryptoJson.encode({
      'reviewId': review.id,
      'body': body,
      'headHash': headHash,
    });
    final publicationId = '${review.id}:published';
    final published = await account.store.database.rows(
      "SELECT payload FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND intent_id=? AND state='scopeRotationPublished'",
      [account.store.partition, review.scopeId, publicationId],
    );
    if (published.isEmpty) {
      await account.store.database.execute(
        'INSERT INTO crypto_membership_intents VALUES(?,?,?,?,?,NULL)',
        [
          account.store.partition,
          review.scopeId,
          publicationId,
          'scopeRotationPublished',
          publication,
        ],
      );
    } else if (base64Encode(
          (published.single['payload'] as List).cast<int>(),
        ) !=
        base64Encode(publication)) {
      throw const FormatException('scope_review_publication_changed');
    }
    await validateInherited();
    await _mutate('crypto2.scope.headPut', review.scopeId, body);
    final proposalWire = await account.directory.call('crypto2.scope.headGet', {
      'scopeId': review.scopeId,
      'headHash': headHash,
    });
    final pending = await access.withRecoveryCandidatePolicy(
      scopeId: review.scopeId,
      sourceHeadHash: source.headHash,
      body: (policy) => access.codec.verifyProposal(
        serverId: author.serverId,
        authorization: Map<String, dynamic>.from(
          proposalWire['authorization'] as Map,
        ),
        accessPolicyVersion: policy.accessPolicyVersion,
        previous: source,
        authorDirectory: author,
        directoryAtHead: (id, hash) => access.directoryAt(
          scopeId: review.scopeId,
          scopeHeadHash: headHash,
          accountId: id,
          directoryHeadHash: hash,
          online: true,
        ),
        checkIdentity: (id, fp) async {
          if (id != author.accountId) {
            final member =
                (body['members'] as List).singleWhere(
                      (m) => m['accountId'] == id,
                    )
                    as Map;
            final directory = await access.directoryAt(
              scopeId: source.scopeId,
              scopeHeadHash: headHash,
              accountId: id,
              directoryHeadHash: member['directoryHeadHash'],
              online: true,
            );
            if (access.identities.fingerprint(directory) != fp) {
              throw const FormatException('scope_identity_substitution');
            }
            await access.requireExistingScopeMemberIdentity(source, directory);
          }
        },
      ),
    );
    for (final domain in ['content', 'finance']) {
      final inventory = review.domains[domain];
      if (inventory == null ||
          domain == 'finance' &&
              source.member(author.accountId)['financeRole'] == 'none') {
        continue;
      }
      await validateInherited();
      await _mutate('crypto2.scope.closeDomain', review.scopeId, {
        'scopeId': review.scopeId,
        'candidateHeadHash': headHash,
        'domain': domain,
        'epoch': source.epoch,
        'membershipHeadHash': source.headHash,
        'authorDirectoryHeadHash': author.headHash,
        'expectedSequence': inventory['sequence'],
        'recordCount': inventory['count'],
        'manifestHash': inventory['manifestHash'],
        'historyBasis': review.historyBasis,
        if (domain == 'content')
          'closingLifecycleHash': pending.body['previousLifecycleHash'],
      });
    }
    await freshDisclosureBoundary?.call();
    final active = await _grantAndActivate(
      pending: pending,
      author: author,
      previous: source,
      ownerAcceptanceProof: ownerAcceptanceProof,
      beforeDisclosure: validateInherited,
    );
    if (body['accessIntentProof'] != null) return active;
    if (active.members.any((m) => m['accountId'] == author.accountId)) {
      await access.hydrateClosures(review.scopeId);
    }
    await account.store.database.execute(
      "UPDATE crypto_membership_intents SET state='scopeRotationReviewComplete' WHERE partition=? AND scope_id=? AND intent_id=? AND state='scopeRotationReview'",
      [account.store.partition, review.scopeId, review.id],
    );
    return active;
  }

  /// Local resume candidates are evidence, never permission to skip the explicit
  /// review confirmation or the online authority checks in confirmRotation.
  Future<List<ScopeRotationReview>> pendingRotationReviews(
    String scopeId,
  ) async {
    final rows = await access.account.store.database.rows(
      "SELECT payload FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND state='scopeRotationReview' ORDER BY rowid DESC",
      [access.account.store.partition, scopeId],
    );
    return [
      for (final row in rows)
        ScopeRotationReview(
          CryptoJson.decode(
                Uint8List.fromList((row['payload'] as List).cast<int>()),
              )
              as Map<String, dynamic>,
        ),
    ];
  }

  Future<List<Map<String, dynamic>>?> proposedMembers(
    ScopeRotationReview review,
  ) async {
    final rows = await access.account.store.database.rows(
      "SELECT intent_id,state,payload FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND (state='scopeSuccessorDraft' OR state='scopeRotationDraft') ORDER BY rowid DESC",
      [access.account.store.partition, review.scopeId],
    );
    for (final row in rows) {
      final p =
          CryptoJson.decode(
                Uint8List.fromList((row['payload'] as List).cast<int>()),
              )
              as Map;
      if (row['state'] == 'scopeSuccessorDraft' &&
              row['intent_id'] == '${review.id}:successor' ||
          p['reviewId'] == review.id) {
        return (p['body']?['members'] ?? p['members'] as List)
            .cast<Map<String, dynamic>>();
      }
    }
    return null;
  }

  Future<void> cancelRotation(
    ScopeRotationReview review,
  ) => _exclusive(review.scopeId, () async {
    final rows = await access.account.store.database.rows(
      "SELECT intent_id,payload FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND state='scopeRotationDraft' AND json_extract(CAST(payload AS TEXT),'\$.reviewId')=?",
      [access.account.store.partition, review.scopeId, review.id],
    );
    for (final row in rows) {
      final draft =
          CryptoJson.decode(
                Uint8List.fromList((row['payload'] as List).cast<int>()),
              )
              as Map;
      await _mutate('crypto2.scope.cancel', review.scopeId, {
        'scopeId': review.scopeId,
        'headHash': draft['headHash'],
      });
      await access.account.store.database.execute(
        "UPDATE crypto_membership_intents SET state='scopeRotationCancelled' WHERE partition=? AND scope_id=? AND intent_id=?",
        [access.account.store.partition, review.scopeId, row['intent_id']],
      );
    }
    final successor = await access.account.store.database.rows(
      "SELECT intent_id FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND intent_id=? AND state='scopeSuccessorDraft'",
      [
        access.account.store.partition,
        review.scopeId,
        '${review.id}:successor',
      ],
    );
    if (successor.isNotEmpty) {
      await _mutate('crypto2.scope.keyDraft.cancel', review.scopeId, {
        'scopeId': review.scopeId,
        'draftId': review.id,
      });
      await access.account.store.database.execute(
        "UPDATE crypto_membership_intents SET state='scopeRotationCancelled' WHERE partition=? AND scope_id=? AND intent_id=?",
        [
          access.account.store.partition,
          review.scopeId,
          '${review.id}:successor',
        ],
      );
    }
    await access.account.store.database.execute(
      "UPDATE crypto_membership_intents SET state='scopeRotationReviewCancelled' WHERE partition=? AND scope_id=? AND intent_id=? AND state='scopeRotationReview'",
      [access.account.store.partition, review.scopeId, review.id],
    );
    // Old draft keys/raw records remain evidence. A fresh explicit review makes
    // fresh IDs and DEKs; cancelled candidates never regain write authority.
  });

  bool _sameRoster(List<Map<String, dynamic>> a, List<Map<String, dynamic>> b) {
    List<Map<String, dynamic>> minimal(List<Map<String, dynamic>> input) =>
        input
            .map(
              (m) => {
                for (final field in ['accountId', 'role']) field: m[field],
              },
            )
            .toList()
          ..sort(
            (x, y) => (x['accountId'] as String).compareTo(y['accountId']),
          );
    return base64Encode(CryptoJson.encode(minimal(a))) ==
        base64Encode(CryptoJson.encode(minimal(b)));
  }

  Future<Map<String, dynamic>> _catalogScope(String scopeId) async {
    String? after;
    while (true) {
      final page = await access.account.directory.call(
        'crypto2.scopes.catalog',
        {'limit': 50, if (after != null) 'afterId': after},
      );
      for (final scope in page['scopes'] as List) {
        if (scope['id'] == scopeId) {
          return Map<String, dynamic>.from(scope as Map);
        }
      }
      if (page['hasMore'] != true) {
        throw const CryptoAuthorityPending('scope_discovery_pending');
      }
      final next = page['nextAfterId'];
      if (next is! String || after != null && next.compareTo(after) <= 0) {
        throw const FormatException('scope_catalog_cursor');
      }
      after = next;
    }
  }

  Future<List<Map<String, dynamic>>> financeDrafts(String scopeId) async {
    final result = <Map<String, dynamic>>[];
    String? after;
    while (true) {
      final page = await access.account.directory.call(
        'crypto2.scope.financeDraft.list',
        {'scopeId': scopeId, 'limit': 20, if (after != null) 'afterId': after},
      );
      if (page['drafts'] is! List || page['hasMore'] is! bool) {
        throw const FormatException('finance_draft_shape');
      }
      result.addAll((page['drafts'] as List).cast<Map<String, dynamic>>());
      if (page['hasMore'] != true) break;
      final next = page['nextAfterId'];
      if (next is! String || after != null && next.compareTo(after) <= 0) {
        throw const FormatException('finance_draft_cursor');
      }
      after = next;
    }
    return result;
  }

  Future<Map<String, dynamic>> contributeFinanceDraft(
    String scopeId,
    String draftId, {
    ScopeRotationReview? reviewedInventory,
  }) => _exclusive(scopeId, () async {
    final account = access.account, crypto = account.directory.reducer.crypto;
    final own = await account.directory.requireFresh();
    final draft = await account.directory.call(
      'crypto2.scope.financeDraft.get',
      {'scopeId': scopeId, 'draftId': draftId},
    );
    final core = Map<String, dynamic>.from(draft['core'] as Map);
    final previous = core['epoch'] == 1
        ? null
        : await access.recoveryCandidateHead(scopeId);
    if (previous != null && previous.headHash != core['previousHeadHash']) {
      throw const CryptoAuthorityPending('finance_draft_changed');
    }
    final ownerRaw =
        CryptoJson.decode(cryptoBase64(draft['authorization']['commandBase64']))
            as Map;
    final owner = await access.currentMemberDirectory(
      scopeId,
      previous?.headHash ?? cryptoZeroHash,
      ownerRaw['accountId'],
    );
    if (owner.headHash != core['authorDirectoryHeadHash']) {
      // Keyring-only appends may move the current head; the exact signed
      // ancestor remains authorized only with the same device snapshot.
      final exact = await access.directoryAt(
        scopeId: scopeId,
        scopeHeadHash: previous?.headHash ?? cryptoZeroHash,
        accountId: owner.accountId,
        directoryHeadHash: core['authorDirectoryHeadHash'],
      );
      if (exact.deviceSnapshotHash != owner.deviceSnapshotHash) {
        throw const CryptoAuthorityPending('finance_draft_changed');
      }
    }
    final actor = owner.activeDevice(ownerRaw['deviceId']);
    final signed = crypto.verifyDomain(
      Map<String, dynamic>.from(draft['authorization'] as Map),
      cryptoBase64(actor['signingKeyBase64'], length: 32),
      cryptoDirectoryDomain,
    );
    if (signed['version'] != 2 ||
        signed['operation'] != 'crypto2.scope.financeDraft.put' ||
        signed['signer'] != 'device' ||
        signed['serverId'] != own.serverId ||
        signed['payload']['scopeId'] != scopeId ||
        signed['payload']['draftId'] != draftId ||
        base64Encode(CryptoJson.encode(signed['payload']['core'])) !=
            base64Encode(CryptoJson.encode(core))) {
      throw const FormatException('finance_draft_signature');
    }
    final ownerRole =
        previous?.member(owner.accountId) ??
        (core['members'] as List).singleWhere(
          (m) => m['accountId'] == owner.accountId,
        );
    if (ownerRole['manageKeys'] != true) {
      throw const FormatException('finance_draft_manager');
    }
    final mine = (core['members'] as List).singleWhere(
      (m) => m['accountId'] == own.accountId,
    );
    if (mine['financeRole'] == 'none' ||
        mine['deviceSnapshotHash'] != own.deviceSnapshotHash ||
        previous != null &&
            previous.member(own.accountId)['financeRole'] == 'none') {
      throw const CryptoAuthorityPending('finance_contribution_forbidden');
    }
    final prior = await account.store.database.rows(
      "SELECT payload FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND intent_id=? AND state='financeContributionDraft'",
      [account.store.partition, scopeId, draftId],
    );
    late Map<String, dynamic> body;
    late String hash;
    if (prior.isNotEmpty) {
      final saved =
          CryptoJson.decode(
                Uint8List.fromList(
                  (prior.single['payload'] as List).cast<int>(),
                ),
              )
              as Map;
      body = Map<String, dynamic>.from(saved['body'] as Map);
      hash = saved['headHash'];
    } else {
      if (previous?.commitment('finance') != null &&
          (reviewedInventory == null ||
              reviewedInventory.scopeId != scopeId ||
              reviewedInventory.sourceHeadHash != previous!.headHash ||
              reviewedInventory.domains['finance'] == null)) {
        throw const CryptoAuthorityPending('finance_inventory_review_required');
      }
      final copied =
          CryptoJson.decode(CryptoJson.encode(core)) as Map<String, dynamic>;
      final key = crypto.sodium.secureRandom(32);
      try {
        copied['keyIds']['finance'] = crypto.randomId();
        final raw = key.extractBytes();
        try {
          copied['keyCommitments']['finance'] = await access.codec
              .keyCommitment(raw);
        } finally {
          raw.fillRange(0, raw.length, 0);
        }
        copied['closures']['finance'] =
            reviewedInventory?.domains['finance']?['manifestHash'];
        await _signOwnFinanceKey(copied, own);
        access.codec.validateBody(copied);
        body = copied;
        hash = await access.codec.headHash(body);
        final context = {
          'version': 2,
          'purpose': 'pendingScopeKey',
          'scopeId': scopeId,
          'domain': 'finance',
          'keyId': body['keyIds']['finance'],
          'intentId': draftId,
          'serverId': own.serverId,
          'accountId': own.accountId,
          'recipientKind': 'recovery',
          'recipientId': own.snapshot['recoveryRootEpochId'],
          'recipientPublicKeyBase64': own.snapshot['rootEncryptionKeyBase64'],
        };
        final sealed = crypto.sealKey(
          key: key,
          recipientPublicKey: cryptoBase64(
            own.snapshot['rootEncryptionKeyBase64'],
            length: 32,
          ),
          context: context,
        );
        final lease = await account.signingKey();
        try {
          final proof = crypto.signDomain(
            {
              'version': 2,
              'operation': 'crypto2.localScopeKeyIntent',
              'serverId': own.serverId,
              'accountId': own.accountId,
              'deviceId': account.deviceId,
              'context': context,
              'sealedEnvelopeBase64': sealed,
            },
            lease.key,
            'JivieE2EE/localKeyIntent/v2\n',
          );
          await account.store.database.transaction(() async {
            final raw = key.extractBytes();
            try {
              await account.store.database.execute(
                'INSERT INTO crypto_scope_keys VALUES(?,?,?,?,?,?,?,?,?,?,?)',
                [
                  account.store.partition,
                  scopeId,
                  'finance',
                  body['epoch'],
                  hash,
                  body['keyIds']['finance'],
                  raw,
                  hash,
                  CryptoJson.encode(proof),
                  0,
                  0,
                ],
              );
            } finally {
              raw.fillRange(0, raw.length, 0);
            }
            await account.store.database.execute(
              'INSERT INTO crypto_membership_intents VALUES(?,?,?,?,?,NULL)',
              [
                account.store.partition,
                scopeId,
                draftId,
                'financeContributionDraft',
                CryptoJson.encode({
                  'body': body,
                  'headHash': hash,
                  'reviewId': reviewedInventory?.id,
                }),
              ],
            );
          });
        } finally {
          lease.release();
        }
      } finally {
        key.dispose();
      }
    }
    // Immutable request and local root envelope exist before publication.
    final result =
        await _mutate('crypto2.scope.financeDraft.contribute', scopeId, {
          'scopeId': scopeId,
          'draftId': draftId,
          'keyId': body['keyIds']['finance'],
          'keyCommitment': body['keyCommitments']['finance'],
          'financeClosureHash': body['closures']['finance'],
          'financeKeyProposalProof': body['financeKeyProposalProof'],
        });
    if (base64Encode(CryptoJson.encode(result['core'])) !=
            base64Encode(
              CryptoJson.encode(
                {...body}
                  ..remove('financeKeyProposalProof')
                  ..remove('contentKeyProposalProof'),
              ),
            ) ||
        base64Encode(CryptoJson.encode(result['financeKeyProposalProof'])) !=
            base64Encode(CryptoJson.encode(body['financeKeyProposalProof']))) {
      throw const FormatException('finance_contribution_ack');
    }
    return {'headHash': hash, 'draftId': draftId, 'scopeId': scopeId};
  });

  Future<void> publishFinanceGrants(
    String scopeId,
    String draftId,
  ) => _exclusive(scopeId, () async {
    final account = access.account;
    final author = await account.directory.requireFresh();
    final rows = await account.store.database.rows(
      "SELECT payload FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND intent_id=? AND state='financeContributionDraft'",
      [account.store.partition, scopeId, draftId],
    );
    if (rows.length != 1) {
      throw const CryptoAuthorityPending(
        'finance_contribution_device_required',
      );
    }
    final saved =
        CryptoJson.decode(
              Uint8List.fromList((rows.single['payload'] as List).cast<int>()),
            )
            as Map;
    final body = Map<String, dynamic>.from(saved['body'] as Map),
        hash = saved['headHash'] as String;
    final previous = body['epoch'] == 1
        ? null
        : await access.recoveryCandidateHead(scopeId);
    final wire = await account.directory.call('crypto2.scope.headGet', {
      'scopeId': scopeId,
      'headHash': hash,
    });
    final outer =
        CryptoJson.decode(cryptoBase64(wire['authorization']['commandBase64']))
            as Map;
    final owner = await access.directoryAt(
      scopeId: scopeId,
      scopeHeadHash: hash,
      accountId: outer['accountId'],
      directoryHeadHash: body['authorDirectoryHeadHash'],
      online: true,
    );
    final pending = await access.codec.verifyProposal(
      serverId: author.serverId,
      authorization: Map<String, dynamic>.from(wire['authorization'] as Map),
      previous: previous,
      accessPolicyVersion: await access.verifiedCandidatePolicyVersion(
        scopeId,
        wire,
      ),
      authorDirectory: owner,
      directoryAtHead: (id, h) => access.directoryAt(
        scopeId: scopeId,
        scopeHeadHash: hash,
        accountId: id,
        directoryHeadHash: h,
        online: true,
      ),
      checkIdentity: (id, fp) async {
        if (id != author.accountId) {
          await access.identities.requireVerified(id, fp);
        }
      },
    );
    if (pending.headHash != hash ||
        base64Encode(CryptoJson.encode(pending.body)) !=
            base64Encode(CryptoJson.encode(body))) {
      throw const FormatException('finance_contribution_head');
    }
    if (previous?.commitment('finance') != null) {
      final reviews = await account.store.database.rows(
        "SELECT payload FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND intent_id=? AND state='scopeRotationReview'",
        [account.store.partition, scopeId, saved['reviewId']],
      );
      if (reviews.length != 1) {
        throw const CryptoAuthorityPending('finance_inventory_review_required');
      }
      final review = ScopeRotationReview(
        CryptoJson.decode(
              Uint8List.fromList(
                (reviews.single['payload'] as List).cast<int>(),
              ),
            )
            as Map<String, dynamic>,
      );
      final inventory = review.domains['finance'];
      await _mutate('crypto2.scope.closeDomain', scopeId, {
        'scopeId': scopeId,
        'candidateHeadHash': hash,
        'domain': 'finance',
        'epoch': previous!.epoch,
        'membershipHeadHash': previous.headHash,
        'authorDirectoryHeadHash': author.headHash,
        'expectedSequence': inventory['sequence'],
        'recordCount': inventory['count'],
        'manifestHash': inventory['manifestHash'],
        'historyBasis': review.historyBasis,
      });
    }
    await _grantAndActivate(
      pending: pending,
      author: author,
      previous: previous,
      financeContributionOnly: true,
    );
  });

  Future<Map<String, dynamic>> invitationCommand(
    String operation,
    String scopeId,
    Map<String, dynamic> payload, {
    required String actionKey,
    String? deliveryToken,
  }) {
    if (!{
      'crypto2.invitations.create',
      'crypto2.invitations.resend',
      'crypto2.invitations.revoke',
      'crypto2.invitations.accept',
      'crypto2.invitations.publishPreauthorization',
    }.contains(operation)) {
      throw const FormatException('invitation_operation');
    }
    return _mutate(
      operation,
      scopeId,
      payload,
      actionKey: actionKey,
      deliveryToken: deliveryToken,
    );
  }

  Future<T> serialize<T>(String scopeId, Future<T> Function() body) =>
      _exclusive(scopeId, body);

  /// Only the closed component coordinator may use these lifecycle commands.
  /// The shared durable sender reconciles the original exact receipt first.
  Future<Map<String, dynamic>> accessCommand(
    String operation,
    String scopeId,
    Map<String, dynamic> payload, {
    required String actionKey,
    String? prepareRequestId,
  }) {
    if (!const {
      'crypto2.access.prepare',
      'crypto2.access.activate',
      'crypto2.access.cancel',
    }.contains(operation)) {
      throw const FormatException('scope_access_operation');
    }
    if (prepareRequestId != null && operation != 'crypto2.access.prepare') {
      throw const FormatException('scope_access_prepare_nonce');
    }
    return _mutate(
      operation,
      scopeId,
      payload,
      actionKey: actionKey,
      fixedRequestId: prepareRequestId,
    );
  }

  /// A member's request/cancel does not authorize a membership head or keys.
  Future<Map<String, dynamic>> leaveCommand(
    String operation,
    String scopeId,
    Map<String, dynamic> payload, {
    required String actionKey,
    required String requestId,
  }) {
    if (!const {
      'crypto2.access.leaveRequest',
      'crypto2.access.leaveCancel',
    }.contains(operation)) {
      throw const FormatException('scope_leave_operation');
    }
    return _mutate(
      operation,
      scopeId,
      payload,
      actionKey: actionKey,
      fixedRequestId: requestId,
    );
  }

  Future<Map<String, dynamic>> keyCommand(
    String operation,
    String scopeId,
    Map<String, dynamic> payload, {
    String? actionKey,
  }) {
    if (!{
      'crypto2.scope.keyDraft.put',
      'crypto2.scope.keyDraft.offer',
      'crypto2.scope.keyDraft.sign',
      'crypto2.scope.keyDraft.cancel',
      'crypto2.scope.contentManifest.put',
      'crypto2.scope.ownerAcceptance.put',
    }.contains(operation)) {
      throw const FormatException('scope_key_operation');
    }
    return _mutate(operation, scopeId, payload, actionKey: actionKey);
  }

  Future<VerifiedScopeHead> publishReviewedCandidate(
    ScopeRotationReview review,
    Map<String, dynamic> body,
    VerifiedScopeHead source,
    VerifiedAccountDirectory author,
  ) async => _publishRotation(
    review,
    body,
    await access.codec.headHash(body),
    source,
    author,
    null,
  );
  Future<void> publishFinanceDomainGrants(
    VerifiedScopeHead pending,
    VerifiedScopeHead source,
    VerifiedAccountDirectory author,
  ) async {
    await _grantAndActivate(
      pending: pending,
      previous: source,
      author: author,
      financeContributionOnly: true,
    );
  }

  Future<void> publishNewContentGrants(
    VerifiedScopeHead pending,
    VerifiedScopeHead? source,
    VerifiedAccountDirectory author,
  ) async {
    await _grantAndActivate(
      pending: pending,
      previous: source,
      author: author,
      contentContributionOnly: true,
    );
  }

  Future<Map<String, dynamic>> financeCommand(
    String operation,
    String scopeId,
    Map<String, dynamic> payload, {
    String? actionKey,
  }) {
    if (!{
      'crypto2.scope.financeDraft.put',
      'crypto2.scope.financeDraft.contribute',
      'crypto2.scope.financeManifest.put',
      'crypto2.scope.closeDomain',
    }.contains(operation)) {
      throw const FormatException('finance_operation');
    }
    return _mutate(operation, scopeId, payload, actionKey: actionKey);
  }

  Future<({Map<String, dynamic> body, String headHash})>
  _obtainFinanceContribution(
    String scopeId,
    Map<String, dynamic> partial,
    String draftId,
    String provisionalHash, {
    String? generationId,
  }) async {
    final account = access.account;
    final core = Map<String, dynamic>.from(partial)
      ..remove('financeKeyProposalProof')
      ..remove('contentKeyProposalProof');
    if (generationId != null) {
      await _mutate('crypto2.migration.generation.financeDraft', scopeId, {
        'generationId': generationId,
        'scopeId': scopeId,
        'draftId': draftId,
        'core': core,
      }, actionKey: 'generationFinanceDraft:$generationId:$scopeId');
    }
    await _mutate('crypto2.scope.financeDraft.put', scopeId, {
      'scopeId': scopeId,
      'draftId': draftId,
      'core': core,
    });
    final response = await account.directory.call(
      'crypto2.scope.financeDraft.get',
      {'scopeId': scopeId, 'draftId': draftId},
    );
    final contribution = response['contribution'];
    if (contribution is! Map) {
      throw const CryptoAuthorityPending('finance_key_contribution_required');
    }
    final completed = Map<String, dynamic>.from(contribution['core'] as Map);
    final comparable = Map<String, dynamic>.from(
      CryptoJson.decode(CryptoJson.encode(completed)) as Map,
    );
    comparable['keyIds']['finance'] = core['keyIds']['finance'];
    comparable['keyCommitments']['finance'] = core['keyCommitments']['finance'];
    comparable['closures']['finance'] = core['closures']['finance'];
    if (base64Encode(CryptoJson.encode(comparable)) !=
        base64Encode(CryptoJson.encode(core))) {
      throw const FormatException('finance_draft_substitution');
    }
    completed['contentKeyProposalProof'] = null;
    completed['financeKeyProposalProof'] =
        contribution['financeKeyProposalProof'];
    access.codec.validateBody(completed);
    final hash = await access.codec.headHash(completed);
    final previous = completed['epoch'] == 1
        ? null
        : access.verifiedCandidateAncestor(completed['previousHeadHash']);
    await access.codec.verifyFinanceKeyProposal(
      body: completed,
      previous: previous,
      directoryAtHead: (id, h) => access.directoryAt(
        scopeId: scopeId,
        scopeHeadHash: previous?.headHash ?? cryptoZeroHash,
        accountId: id,
        directoryHeadHash: h,
      ),
    );
    await account.store.database.execute(
      'UPDATE crypto_scope_keys SET epoch_id=?,scope_head_hash=? WHERE partition=? AND scope_id=? AND epoch_id=? AND domain=?',
      [
        hash,
        hash,
        account.store.partition,
        scopeId,
        provisionalHash,
        'content',
      ],
    );
    return (body: completed, headHash: hash);
  }

  Future<void> _signOwnFinanceKey(
    Map<String, dynamic> body,
    VerifiedAccountDirectory author,
  ) async {
    body['financeKeyProposalProof'] = null;
    body['contentKeyProposalProof'] = null;
    if ((body['keyCommitments'] as Map)['finance'] == null) return;
    if ((body['members'] as List).singleWhere(
          (m) => m['accountId'] == author.accountId,
        )['financeRole'] ==
        'none') {
      throw const CryptoAuthorityPending('finance_key_contribution_required');
    }
    final lease = await access.account.signingKey();
    try {
      body['financeKeyProposalProof'] = access.account.directory.reducer.crypto
          .signDomain(
            {
              'version': 2,
              'operation': 'crypto2.scope.financeKeyProposal',
              'serverId': author.serverId,
              'scopeId': body['scopeId'],
              'epoch': body['epoch'],
              'previousHeadHash': body['previousHeadHash'],
              'proposalContextHash': await access.codec.financeCoreHash(body),
              'keyId': body['keyIds']['finance'],
              'keyCommitment': body['keyCommitments']['finance'],
              'accountId': author.accountId,
              'deviceId': access.account.deviceId,
              'authorDirectoryHeadHash': author.headHash,
            },
            lease.key,
            'JivieE2EE/financeKeyProposal/v2\n',
          );
    } finally {
      lease.release();
    }
  }

  Future<VerifiedScopeHead> _grantAndActivate({
    required VerifiedScopeHead pending,
    required VerifiedAccountDirectory author,
    VerifiedScopeHead? previous,
    Map<String, dynamic>? ownerAcceptanceProof,
    bool financeContributionOnly = false,
    bool contentContributionOnly = false,
    String? migrationId,
    String? captureId,
    Map<String, dynamic>? parentTopologyBatch,
    Future<void> Function()? beforeDisclosure,
  }) async {
    final account = access.account, crypto = account.directory.reducer.crypto;
    await beforeDisclosure?.call();
    final scopeId = pending.scopeId, headHash = pending.headHash;
    final actor = pending.members
        .where((m) => m['accountId'] == author.accountId)
        .firstOrNull;
    final sources = <VerifiedScopeHead>[pending];
    var ancestor = previous;
    while (ancestor != null) {
      sources.insert(0, ancestor);
      if (ancestor.epoch == 1) break;
      ancestor = access.verifiedCandidateAncestor(
        ancestor.body['previousHeadHash'],
      );
    }
    final domainDescriptors = <String, List<Map<String, dynamic>>>{
      'content': [],
      'finance': [],
    };
    for (final domain in ['content', 'finance']) {
      if (financeContributionOnly && domain != 'finance' ||
          contentContributionOnly && domain != 'content' ||
          domain == 'finance' &&
              (actor == null || actor['financeRole'] == 'none')) {
        continue;
      }
      for (final source in sources) {
        if (contentContributionOnly && source.headHash != pending.headHash ||
            actor == null && source.headHash == pending.headHash) {
          continue;
        }
        if (source.commitment(domain) == null) continue;
        final rows = await account.store.database.rows(
          'SELECT key_bytes FROM crypto_scope_keys WHERE partition=? AND scope_id=? AND domain=? AND epoch_id=?',
          [account.store.partition, scopeId, domain, source.headHash],
        );
        if (rows.length != 1) {
          throw const CryptoAuthorityPending('scope_key_recovery_required');
        }
        final raw = Uint8List.fromList(
          (rows.single['key_bytes'] as List).cast<int>(),
        );
        if (await access.codec.keyCommitment(raw) !=
            source.commitment(domain)) {
          throw const FormatException('scope_key_commitment');
        }
        final key = crypto.sodium.secureCopy(raw);
        raw.fillRange(0, raw.length, 0);
        try {
          for (final member in pending.members) {
            if (domain == 'finance' && member['financeRole'] == 'none') {
              continue;
            }
            final directory = member['accountId'] == author.accountId
                ? author
                : await access.directoryAt(
                    scopeId: scopeId,
                    scopeHeadHash: headHash,
                    accountId: member['accountId'],
                    directoryHeadHash: member['directoryHeadHash'],
                    online: true,
                  );
            final recipients = <Map<String, dynamic>>[
              {
                'recipientKind': 'recovery',
                'recipientId': member['recoveryRootEpochId'],
                'publicKeyBase64': member['rootEncryptionKeyBase64'],
              },
            ];
            for (final device in directory.devices.where(
              (d) =>
                  d['revokedGeneration'] == null &&
                  d['identityEpochId'] == directory.identityEpochId,
            )) {
              recipients.add({
                'recipientKind': 'device',
                'recipientId': device['deviceId'],
                'publicKeyBase64': device['encryptionKeyBase64'],
              });
            }
            recipients.sort((a, b) {
              final kind = (a['recipientKind'] as String).compareTo(
                b['recipientKind'],
              );
              return kind != 0
                  ? kind
                  : (a['recipientId'] as String).compareTo(b['recipientId']);
            });
            var generation = 0;
            final proofHashes = <String>[];
            for (var offset = 0; offset < recipients.length; offset += 32) {
              await beforeDisclosure?.call();
              final chunk = recipients
                  .skip(offset)
                  .take(32)
                  .map(
                    (r) => {
                      ...r,
                      'sealedEnvelopeBase64': crypto.sealKey(
                        key: key,
                        recipientPublicKey: cryptoBase64(
                          r['publicKeyBase64'],
                          length: 32,
                        ),
                        context: access.codec.wrapperContext(
                          serverId: author.serverId,
                          head: pending,
                          keySourceHead: source,
                          domain: domain,
                          keyId: (source.body['keyIds'] as Map)[domain],
                          recipient: {
                            ...r,
                            'recoveryRootEpochId':
                                member['recoveryRootEpochId'],
                          },
                        ),
                      ),
                    },
                  )
                  .toList();
              await beforeDisclosure?.call();
              final ack = await _mutate(
                'crypto2.grants.put',
                scopeId,
                {
                  'scopeId': scopeId,
                  'headHash': headHash,
                  'keySourceHeadHash': source.headHash,
                  'accountId': member['accountId'],
                  'domain': domain,
                  'epoch': source.epoch,
                  'keyId': (source.body['keyIds'] as Map)[domain],
                  'expectedGeneration': generation,
                  'recipients': chunk,
                },
                actionKey:
                    'grant:$headHash:${source.epoch}:$domain:${member['accountId']}:$offset',
              );
              final proofHash = await cryptoSha256(
                CryptoJson.encode(ack['authorization']),
              );
              proofHashes.addAll(List.filled(chunk.length, proofHash));
              generation = ack['generation'] as int;
            }
            domainDescriptors[domain]!.add({
              'accountId': member['accountId'],
              'epoch': source.epoch,
              'keyId': (source.body['keyIds'] as Map)[domain],
              'keySourceHeadHash': source.headHash,
              'generation': generation,
              'recipientProofHashes': proofHashes,
            });
          }
        } finally {
          key.dispose();
        }
      }
      domainDescriptors[domain]!.sort((a, b) {
        final c = (a['accountId'] as String).compareTo(b['accountId']);
        return c != 0 ? c : (a['epoch'] as int).compareTo(b['epoch']);
      });
    }
    final manifest = await account.directory.call('crypto2.grants.manifest', {
      'scopeId': scopeId,
      'headHash': headHash,
    });
    final roots = <String, dynamic>{};
    for (final domain in ['content', 'finance']) {
      final sink = Sha256().newHashSink();
      for (final descriptor in domainDescriptors[domain]!) {
        sink.add(CryptoJson.encode(descriptor));
        sink.add([10]);
      }
      sink.close();
      roots[domain] = (await sink.hash()).bytes
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
    }
    Map<String, dynamic>? contentProof;
    if (contentContributionOnly) {
      await access.hydrateCandidateKeys(
        scopeId,
        headHash,
        onlyDomain: 'content',
      );
      final current = await account.directory.call('crypto2.grants.manifest', {
        'scopeId': scopeId,
        'headHash': headHash,
      });
      final lease = await account.signingKey();
      try {
        contentProof = crypto.signDomain(
          {
            'version': 2,
            'operation': 'crypto2.scope.contentGrantManifest',
            'serverId': author.serverId,
            'scopeId': scopeId,
            'headHash': headHash,
            'contentManifestHash': current['domains']['content'],
            'accountId': author.accountId,
            'deviceId': account.deviceId,
            'authorDirectoryHeadHash': author.headHash,
          },
          lease.key,
          'JivieE2EE/contentGrantManifest/v2\n',
        );
      } finally {
        lease.release();
      }
      await _mutate('crypto2.scope.contentManifest.put', scopeId, {
        'scopeId': scopeId,
        'headHash': headHash,
        'contentGrantManifestProof': contentProof,
      });
      return pending;
    }
    if (actor == null) {
      final wire = await account.directory.call('crypto2.scope.headGet', {
        'scopeId': scopeId,
        'headHash': headHash,
      });
      if (wire['contentGrantManifestProof'] is! Map) {
        throw const CryptoAuthorityPending(
          'scope_successor_key_contribution_required',
        );
      }
      contentProof = Map<String, dynamic>.from(
        wire['contentGrantManifestProof'] as Map,
      );
      roots['content'] = await access.codec.verifyContentGrantManifest(
        head: pending,
        proof: contentProof,
        directoryAtHead: (id, h) => access.directoryAt(
          scopeId: scopeId,
          scopeHeadHash: headHash,
          accountId: id,
          directoryHeadHash: h,
          online: true,
        ),
      );
    }
    Map<String, dynamic>? financeProof;
    if (pending.commitment('finance') != null &&
        actor != null &&
        actor['financeRole'] != 'none') {
      final lease = await account.signingKey();
      try {
        financeProof = crypto.signDomain(
          {
            'version': 2,
            'operation': 'crypto2.scope.financeGrantManifest',
            'serverId': author.serverId,
            'scopeId': scopeId,
            'headHash': headHash,
            'financeManifestHash': roots['finance'],
            'accountId': author.accountId,
            'deviceId': account.deviceId,
            'authorDirectoryHeadHash': author.headHash,
          },
          lease.key,
          'JivieE2EE/financeGrantManifest/v2\n',
        );
      } finally {
        lease.release();
      }
    }
    if (pending.commitment('finance') != null &&
        (actor == null || actor['financeRole'] == 'none')) {
      final wire = await account.directory.call('crypto2.scope.headGet', {
        'scopeId': scopeId,
        'headHash': headHash,
      });
      if (wire['financeGrantManifestProof'] is! Map) {
        throw const CryptoAuthorityPending('finance_key_contribution_required');
      }
      financeProof = Map<String, dynamic>.from(
        wire['financeGrantManifestProof'] as Map,
      );
      roots['finance'] = await access.codec.verifyFinanceGrantManifest(
        head: pending,
        previous: previous,
        proof: financeProof,
        directoryAtHead: (id, h) => access.directoryAt(
          scopeId: scopeId,
          scopeHeadHash: headHash,
          accountId: id,
          directoryHeadHash: h,
          online: true,
        ),
      );
    }
    if (financeContributionOnly) {
      if (financeProof == null ||
          manifest['domains']['finance'] != roots['finance']) {
        throw const FormatException('finance_manifest_substitution');
      }
      await _mutate('crypto2.scope.financeManifest.put', scopeId, {
        'scopeId': scopeId,
        'headHash': headHash,
        'financeGrantManifestProof': financeProof,
      });
      return pending;
    }
    final expectedManifest = await cryptoSha256(CryptoJson.encode(roots));
    if (manifest['grantManifestHash'] != expectedManifest ||
        base64Encode(CryptoJson.encode(manifest['domains'])) !=
            base64Encode(CryptoJson.encode(roots))) {
      throw const FormatException('scope_grant_manifest_ack');
    }
    // All envelope bytes were generated and receipted above; activation binds
    // their immutable proof manifest and does not publish plaintext records.
    if (ownerAcceptanceProof == null &&
        previous != null &&
        previous.members.singleWhere(
              (m) => m['role'] == 'owner',
            )['accountId'] !=
            pending.members.singleWhere(
              (m) => m['role'] == 'owner',
            )['accountId']) {
      final wire = await account.directory.call('crypto2.scope.headGet', {
        'scopeId': scopeId,
        'headHash': headHash,
      });
      if (wire['ownerAcceptanceProof'] is Map) {
        ownerAcceptanceProof = Map<String, dynamic>.from(
          wire['ownerAcceptanceProof'] as Map,
        );
      }
    }
    if (previous != null &&
        previous.members.singleWhere(
              (m) => m['role'] == 'owner',
            )['accountId'] !=
            pending.members.singleWhere(
              (m) => m['role'] == 'owner',
            )['accountId'] &&
        ownerAcceptanceProof == null) {
      throw const CryptoAuthorityPending('scope_owner_acceptance_required');
    }
    final activationPayload = <String, dynamic>{
      'scopeId': scopeId,
      'headHash': headHash,
      'grantManifestHash': expectedManifest,
      'authorDirectoryHeadHash': author.headHash,
      if (contentProof != null) 'contentGrantManifestProof': contentProof,
      if (financeProof != null) 'financeGrantManifestProof': financeProof,
      if (ownerAcceptanceProof != null)
        'ownerAcceptanceProof': ownerAcceptanceProof,
    };
    if (pending.body['accessIntentProof'] != null) {
      final consent =
          CryptoJson.decode(
                cryptoBase64(
                  pending.body['accessIntentProof']['commandBase64'],
                ),
              )
              as Map;
      activationPayload.addAll({
        'accessIntentHash': consent['intentHash'],
        'affectedCount': consent['affectedCount'],
        'affectedHash': consent['affectedHash'],
      });
      final intentId = 'accessActivation:$headHash';
      final saved = await account.store.database.rows(
        "SELECT authorization FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND intent_id=? AND state='scopeAccessActivation'",
        [account.store.partition, scopeId, intentId],
      );
      late Map<String, dynamic> nested;
      if (saved.isNotEmpty) {
        nested = Map<String, dynamic>.from(
          CryptoJson.decode(
                Uint8List.fromList(
                  (saved.single['authorization'] as List).cast<int>(),
                ),
              )
              as Map,
        );
        final old =
            CryptoJson.decode(cryptoBase64(nested['commandBase64'])) as Map;
        if (old['operation'] != 'crypto2.scope.activate' ||
            base64Encode(CryptoJson.encode(old['payload'])) !=
                base64Encode(CryptoJson.encode(activationPayload))) {
          throw const FormatException('scope_access_activation_immutable');
        }
      } else {
        final lease = await account.signingKey();
        try {
          nested = crypto.signDomain(
            {
              'version': 2,
              'operation': 'crypto2.scope.activate',
              'requestId': crypto.randomId(),
              'serverId': author.serverId,
              'accountId': author.accountId,
              'deviceId': account.deviceId,
              'signer': 'device',
              'payload': activationPayload,
            },
            lease.key,
            cryptoDirectoryDomain,
          );
        } finally {
          lease.release();
        }
        await account.store.database.execute(
          'INSERT INTO crypto_membership_intents VALUES(?,?,?,?,?,?)',
          [
            account.store.partition,
            scopeId,
            intentId,
            'scopeAccessActivation',
            CryptoJson.encode(activationPayload),
            CryptoJson.encode(nested),
          ],
        );
      }
      await _mutate('crypto2.access.approve', scopeId, {
        'intentHash': consent['intentHash'],
        'scopeId': scopeId,
        'activationProof': nested,
      });
      // Only the component coordinator may atomically install this head. No
      // current-head/key/floor projection follows an individual approval.
      return pending;
    }
    Map<String, dynamic> deliveryPayload = activationPayload;
    if (parentTopologyBatch != null) {
      if (previous != null ||
          pending.epoch != 1 ||
          migrationId != null ||
          pending.body['accessIntentProof'] != null) {
        throw const FormatException('crypto_topology_activation_context');
      }
      final hash = await CryptoFinanceTopologyCreation.hash(
        parentTopologyBatch,
      );
      final intentId = 'scopeTopologyActivation:$headHash';
      final stored = await account.store.database.rows(
        'SELECT authorization FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND intent_id=?',
        [account.store.partition, scopeId, intentId],
      );
      late Map<String, dynamic> inner;
      if (stored.isNotEmpty) {
        inner = Map<String, dynamic>.from(
          CryptoJson.decode(
                Uint8List.fromList(
                  (stored.single['authorization'] as List).cast<int>(),
                ),
              )
              as Map,
        );
        final command =
            CryptoJson.decode(cryptoBase64(inner['commandBase64'])) as Map;
        final p = command['payload'] as Map;
        if (command['operation'] != 'crypto2.scope.activate' ||
            p['scopeId'] != scopeId ||
            p['headHash'] != headHash ||
            p['parentTopologyBatchHash'] != hash) {
          throw const FormatException('crypto_topology_activation_immutable');
        }
      } else {
        final lease = await account.signingKey();
        try {
          inner = crypto.signDomain(
            {
              'version': 2,
              'operation': 'crypto2.scope.activate',
              'requestId': crypto.randomId(),
              'serverId': author.serverId,
              'accountId': author.accountId,
              'deviceId': account.deviceId,
              'signer': 'device',
              'payload': {
                ...activationPayload,
                'parentTopologyBatchHash': hash,
              },
            },
            lease.key,
            cryptoDirectoryDomain,
          );
        } finally {
          lease.release();
        }
        await account.store.database.execute(
          'INSERT INTO crypto_membership_intents VALUES(?,?,?,?,?,?)',
          [
            account.store.partition,
            scopeId,
            intentId,
            'scopeTopologyActivation',
            CryptoJson.encode({
              'headHash': headHash,
              'parentTopologyBatchHash': hash,
            }),
            CryptoJson.encode(inner),
          ],
        );
      }
      deliveryPayload = {
        'scopeId': scopeId,
        'headHash': headHash,
        'activationProof': inner,
        'parentTopologyBatch': parentTopologyBatch,
      };
    }
    await beforeDisclosure?.call();
    final activationAck = await _mutate(
      'crypto2.scope.activate',
      scopeId,
      deliveryPayload,
      actionKey: parentTopologyBatch == null
          ? null
          : 'scopeTopologyActivate:$headHash',
    );
    if (actor == null) {
      return access.codec.verifyActivation(
        pending: pending,
        previous: previous,
        authorization: Map<String, dynamic>.from(
          activationAck['authorization'] as Map,
        ),
        authorDirectory: author,
        grantManifestHash: expectedManifest,
        directoryAtHead: (id, h) => access.directoryAt(
          scopeId: scopeId,
          scopeHeadHash: headHash,
          accountId: id,
          directoryHeadHash: h,
        ),
      );
    }
    if (migrationId != null) {
      if (previous != null || pending.epoch != 1) {
        throw const FormatException('crypto_migration_candidate_genesis');
      }
      final candidate = await access.migrationCandidate(
        scopeId: scopeId,
        migrationId: migrationId,
        captureId: captureId,
        headHash: headHash,
      );
      await access.hydrateMigrationCandidateKeys(candidate);
      return candidate.head;
    }
    final active = await access.currentHead(scopeId, online: true);
    await access.hydrateScopeKeys(scopeId);
    for (final domain in ['content', 'finance']) {
      if (active.commitment(domain) == null) continue;
      await account.store.database.execute(
        "INSERT INTO crypto_scope_state(partition,scope_id,domain,state,epoch,access_revision,floor) VALUES(?,?,?,'active',?,?,?) ON CONFLICT(partition,scope_id,domain) DO UPDATE SET state='active',epoch=MAX(crypto_scope_state.epoch,excluded.epoch),access_revision=excluded.access_revision,floor=MAX(crypto_scope_state.floor,excluded.floor)",
        [
          account.store.partition,
          scopeId,
          domain,
          active.epoch,
          active.accessRevision,
          active.epoch,
        ],
      );
    }
    return active;
  }
}
