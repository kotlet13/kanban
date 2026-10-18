import 'package:cryptography/cryptography.dart' show Sha256;
import 'dart:typed_data';
import 'dart:convert';

import '../../domain/shared_payload_validation.dart';
import 'crypto_business_router.dart';
import 'account_directory_v2.dart' show cryptoSha256;
import 'crypto_json.dart';
import 'crypto_lifecycle_evidence.dart';
import 'session_crypto_access.dart';
import 'crypto_scoped_authority.dart';
import 'crypto_sync_repository.dart';

/// Resumable archive actions over the existing UI gateway. Child cards attest
/// only the exact inherited archive effect, never private child content.
class CryptoBusinessLifecycle {
  CryptoBusinessLifecycle(this.context);
  final CryptoBusinessSession context;
  bool supports(String operation) => operation == 'scopes.archive';
  String get partition => context.partition;

  static const deliveryOperations = {
    'crypto2.scope.lifecycle.prepare',
    'crypto2.scope.lifecycle.observation.put',
    'crypto2.scope.archive',
    'crypto2.scope.lifecycle.cancel',
    'crypto2.scope.lifecycle.delegate',
  };

  static Future<void> verifyDelivery(
    SessionCryptoAccess access,
    Map<String, dynamic> command,
  ) async {
    final operation = command['operation'];
    if (!deliveryOperations.contains(operation)) {
      throw const FormatException('crypto_lifecycle_operation');
    }
    final account = access.account;
    final own = await account.directory.requireFresh();
    own.activeDevice(account.deviceId);
    if (operation == 'crypto2.scope.lifecycle.cancel') return;
    final payload = command['payload'] as Map;
    final scope = payload['scopeId'] as String;
    Map intent = payload;
    if (operation == 'crypto2.scope.archive' ||
        operation == 'crypto2.scope.lifecycle.observation.put') {
      final rows = await account.store.database.rows(
        "SELECT payload FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND intent_id=? AND state='lifecycleWorkflow'",
        [
          account.store.partition,
          scope,
          'lifecycleAction:${payload['parentActionId']}',
        ],
      );
      if (rows.length != 1) {
        throw const CryptoAuthorityPending('crypto_lifecycle_intent_missing');
      }
      intent =
          CryptoJson.decode(
                Uint8List.fromList(
                  (rows.single['payload'] as List).cast<int>(),
                ),
              )
              as Map;
      final staged = await account.store.database.rows(
        'SELECT o.signed_body FROM crypto_command_keys k JOIN crypto_outbox o ON o.partition=k.partition AND o.request_id=k.request_id WHERE k.partition=? AND k.action_key=?',
        [
          account.store.partition,
          'lifecycle:${payload['parentActionId']}:prepare',
        ],
      );
      if (staged.length != 1) {
        throw const CryptoAuthorityPending('crypto_lifecycle_intent_missing');
      }
      final proof = Map<String, dynamic>.from(
        jsonDecode(staged.single['signed_body'] as String) as Map,
      );
      final expectedHash = await CryptoLifecycleEvidence(
        access,
      ).proofHash(proof);
      if (operation == 'crypto2.scope.archive' &&
          payload['intentProofHash'] != expectedHash) {
        throw const FormatException('crypto_lifecycle_intent_binding');
      }
      if (operation == 'crypto2.scope.lifecycle.observation.put') {
        final card =
            CryptoJson.decode(
                  cryptoBase64(
                    (payload['observation'] as Map)['commandBase64'],
                  ),
                )
                as Map;
        if (card['parentIntentProofHash'] != expectedHash ||
            card['accountId'] != own.accountId ||
            card['deviceId'] != account.deviceId ||
            card['parentDeviceSnapshotHash'] != own.deviceSnapshotHash ||
            card['parentScopeToken'] !=
                await CryptoLifecycleEvidence(
                  access,
                ).parentToken(card['scopeId'], scope) ||
            card['archived'] != intent['archived']) {
          throw const FormatException('crypto_lifecycle_observation_binding');
        }
        final device = own.activeDevice(account.deviceId);
        account.directory.reducer.crypto.verifyDomain(
          Map<String, dynamic>.from(payload['observation'] as Map),
          cryptoBase64(device['signingKeyBase64']),
          CryptoLifecycleEvidence.inheritedDomain,
        );
        if (card['delegationProofHash'] == null) {
          final child = await access.currentHead(card['scopeId'], online: true);
          if (child.headHash != card['membershipHeadHash'] ||
              child.member(own.accountId)['manageKeys'] != true) {
            throw const CryptoAuthorityPending('scope_management_forbidden');
          }
        }
        // A delegated card makes only the parent's exact archive decision.
        // The child consumer/server validates its delegation and prior chain;
        // the parent is deliberately not given child read or key authority.
      }
    }
    final head = await access.currentHead(scope, online: true);
    if (head.headHash != intent['membershipHeadHash'] ||
        head.accessRevision != intent['expectedAccessRevision'] ||
        head.member(own.accountId)['manageKeys'] != true) {
      throw const CryptoAuthorityPending('scope_management_forbidden');
    }
    for (final member in head.members) {
      final current = await access.currentMemberDirectory(
        scope,
        head.headHash,
        member['accountId'],
      );
      if (current.deviceSnapshotHash != member['deviceSnapshotHash']) {
        throw const CryptoAuthorityPending('scope_rotation_required');
      }
    }
    if (operation == 'crypto2.scope.lifecycle.delegate') {
      await CryptoScopedAuthority(access).current(
        scopeId: scope,
        scopeHeadHash: head.headHash,
        accountId: payload['parentAccountId'],
        signingPublicKey: payload['parentRootSigningKeyBase64'],
        encryptionPublicKey: payload['parentRootEncryptionKeyBase64'],
        identityEpochId: payload['parentIdentityEpochId'],
        deviceSnapshotHash: payload['parentDeviceSnapshotHash'],
      );
      final parent = await access.directoryAt(
        scopeId: scope,
        scopeHeadHash: head.headHash,
        accountId: payload['parentAccountId'],
        directoryHeadHash: payload['parentDirectoryHeadHash'],
        online: true,
        allowUnverifiedContact: true,
      );
      await access.identities.requireVerified(
        parent.accountId,
        access.identities.fingerprint(parent),
      );
    }
  }

  Future<Map<String, dynamic>> _send(
    String key,
    String operation,
    Map<String, dynamic> payload,
  ) async {
    final request = await context.queue.enqueueCommand(
      actionKey: key,
      operation: operation,
      payload: payload,
    );
    await context.queue.resumeUnresolved(requestIds: {request});
    return context.queue.commandResult(request);
  }

  Future<List<Map<String, dynamic>>> pendingApprovals(String scopeId) async {
    final out = <Map<String, dynamic>>[];
    String? after;
    while (true) {
      final page = await context.account.directory.call(
        'crypto2.scope.lifecycle.pendingDelegations',
        {'scopeId': scopeId, 'limit': 20, if (after != null) 'afterId': after},
      );
      if (page['requests'] is! List || (page['requests'] as List).length > 20) {
        throw const FormatException('crypto_lifecycle_approvals');
      }
      for (final raw in page['requests'] as List) {
        final request = Map<String, dynamic>.from(raw as Map);
        final directory = await context.access.directoryAt(
          scopeId: scopeId,
          scopeHeadHash: request['membershipHeadHash'],
          accountId: request['parentAccountId'],
          directoryHeadHash: request['parentDirectoryHeadHash'],
          online: true,
          allowUnverifiedContact: true,
        );
        if (directory.snapshot['rootSigningKeyBase64'] !=
                request['parentRootSigningKeyBase64'] ||
            directory.snapshot['rootEncryptionKeyBase64'] !=
                request['parentRootEncryptionKeyBase64'] ||
            directory.identityEpochId != request['parentIdentityEpochId'] ||
            directory.deviceSnapshotHash !=
                request['parentDeviceSnapshotHash']) {
          throw const CryptoAuthorityPending('scoped_authority_changed');
        }
        out.add({
          ...request,
          'safetyCode': await context.access.identities.safetyCode(directory),
        });
      }
      if (page['hasMore'] == false) break;
      final next = page['nextAfterId'];
      if (page['hasMore'] != true || next is! String || next == after) {
        throw const FormatException('crypto_lifecycle_approval_cursor');
      }
      after = next;
    }
    return out;
  }

  /// The UI first compares an unknown identity through the existing contact-card
  /// flow. An existing independent pin is reused without another comparison.
  Future<void> approveParent(
    String scopeId,
    String parentActionId, {
    String? expectedRequestHash,
  }) async {
    final request = (await pendingApprovals(scopeId)).singleWhere(
      (r) => r['parentActionId'] == parentActionId,
      orElse: () =>
          throw const CryptoAuthorityPending('crypto_lifecycle_action_expired'),
    );
    if (expectedRequestHash != null &&
        expectedRequestHash != await cryptoSha256(CryptoJson.encode(request))) {
      throw const CryptoAuthorityPending('crypto_lifecycle_review_changed');
    }
    final directory = await context.access.directoryAt(
      scopeId: scopeId,
      scopeHeadHash: request['membershipHeadHash'],
      accountId: request['parentAccountId'],
      directoryHeadHash: request['parentDirectoryHeadHash'],
      online: true,
      allowUnverifiedContact: true,
    );
    await context.access.identities.requireVerified(
      directory.accountId,
      context.access.identities.fingerprint(directory),
    );
    final author = await context.account.directory.requireFresh();
    final intentId = 'lifecycleDelegation:$parentActionId';
    final rows = await context.database.rows(
      'SELECT payload FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND intent_id=?',
      [partition, scopeId, intentId],
    );
    late Map<String, dynamic> payload;
    if (rows.isEmpty) {
      payload = {
        'scopeId': scopeId,
        'delegationId': context.account.directory.reducer.crypto.randomId(),
        'membershipHeadHash': request['membershipHeadHash'],
        'expectedAccessRevision': request['expectedAccessRevision'],
        'authorDirectoryHeadHash': author.headHash,
        for (final field in [
          'parentScopeToken',
          'parentAccountId',
          'parentDirectoryHeadHash',
          'parentRootSigningKeyBase64',
          'parentRootEncryptionKeyBase64',
          'parentIdentityEpochId',
          'parentDeviceSnapshotHash',
        ])
          field: request[field],
        'effect': 'inheritedArchived',
      };
      await context.database.execute(
        "INSERT INTO crypto_membership_intents(partition,scope_id,intent_id,state,payload) VALUES(?,?,?,'lifecycleWorkflow',?)",
        [partition, scopeId, intentId, CryptoJson.encode(payload)],
      );
    } else {
      payload = Map<String, dynamic>.from(
        CryptoJson.decode(
              Uint8List.fromList((rows.single['payload'] as List).cast<int>()),
            )
            as Map,
      );
    }
    await _send(
      'lifecycle:delegate:$scopeId:$parentActionId',
      'crypto2.scope.lifecycle.delegate',
      payload,
    );
  }

  Future<Map<String, dynamic>> dispatch(
    String operation,
    Map<String, Object?> params,
  ) async {
    if (!supports(operation) ||
        !isSharedUuid(params['scopeId']) ||
        !isSharedUuid(params['requestId']) ||
        params['archived'] is! bool) {
      throw const FormatException('crypto_lifecycle_request');
    }
    final scope = params['scopeId'] as String;
    final id = params['requestId'] as String;
    final intentId = 'lifecycleAction:$id';
    final saved = await context.database.rows(
      'SELECT payload FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND intent_id=?',
      [partition, scope, intentId],
    );
    late Map<String, dynamic> intent;
    if (saved.isEmpty) {
      final head = await context.access.currentHead(scope, online: true);
      if (head.member(context.account.directory.accountId)['manageKeys'] !=
          true) {
        throw const CryptoAuthorityPending('scope_management_forbidden');
      }
      final lifecycle = await CryptoLifecycleEvidence(
        context.access,
      ).current(scope);
      final directory = await context.account.directory.requireFresh();
      intent = {
        'scopeId': scope,
        'parentActionId': id,
        'expectedLifecycleRevision': lifecycle['revision'],
        'previousLifecycleHash': lifecycle['headHash'],
        'membershipHeadHash': head.headHash,
        'expectedAccessRevision': head.accessRevision,
        'authorDirectoryHeadHash': directory.headHash,
        'archived': params['archived'],
      };
      await context.database.execute(
        "INSERT INTO crypto_membership_intents(partition,scope_id,intent_id,state,payload) VALUES(?,?,?,'lifecycleWorkflow',?)",
        [partition, scope, intentId, CryptoJson.encode(intent)],
      );
    } else {
      intent = Map<String, dynamic>.from(
        CryptoJson.decode(
              Uint8List.fromList((saved.single['payload'] as List).cast<int>()),
            )
            as Map,
      );
      if (intent['archived'] != params['archived']) {
        throw const FormatException('crypto_lifecycle_immutable_intent');
      }
    }
    final key = 'lifecycle:$id';
    final prepared = await _send(
      '$key:prepare',
      'crypto2.scope.lifecycle.prepare',
      intent,
    );
    final digest = Sha256().newHashSink();
    var after = '', count = 0;
    while (true) {
      final page = await context.account.directory.call(
        'crypto2.scope.lifecycle.children',
        {'scopeId': scope, 'parentActionId': id, 'afterId': after, 'limit': 20},
      );
      if (page['children'] is! List || (page['children'] as List).length > 20) {
        throw const FormatException('crypto_lifecycle_children');
      }
      for (final raw in page['children'] as List) {
        final child = raw as Map;
        final childId = child['scopeId'];
        if (childId is! String || childId.compareTo(after) <= 0) {
          throw const FormatException('crypto_lifecycle_child_order');
        }
        if (child['pendingReason'] != null) {
          throw CryptoAuthorityPending(child['pendingReason'] as String);
        }
        final cardId = '$key:child:$childId';
        final stored = await context.database.rows(
          'SELECT authorization FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND intent_id=?',
          [partition, scope, cardId],
        );
        late Map<String, dynamic> proof;
        if (stored.isNotEmpty) {
          proof = Map<String, dynamic>.from(
            CryptoJson.decode(
                  Uint8List.fromList(
                    (stored.single['authorization'] as List).cast<int>(),
                  ),
                )
                as Map,
          );
        } else {
          final directory = await context.account.directory.requireFresh();
          final old = child['lifecycle'] as Map;
          String? delegation;
          for (final rawGrant in child['delegations'] as List) {
            final grant = rawGrant as Map;
            final authorization = grant['authorization'] as Map;
            final command =
                CryptoJson.decode(cryptoBase64(authorization['commandBase64']))
                    as Map;
            final payload = command['payload'] as Map;
            if (payload['scopeId'] == childId &&
                payload['membershipHeadHash'] == child['membershipHeadHash'] &&
                payload['parentScopeToken'] ==
                    await CryptoLifecycleEvidence(
                      context.access,
                    ).parentToken(childId, scope) &&
                payload['parentAccountId'] == directory.accountId &&
                payload['parentDeviceSnapshotHash'] ==
                    directory.deviceSnapshotHash &&
                payload['parentRootSigningKeyBase64'] ==
                    directory.snapshot['rootSigningKeyBase64'] &&
                payload['parentRootEncryptionKeyBase64'] ==
                    directory.snapshot['rootEncryptionKeyBase64'] &&
                payload['parentIdentityEpochId'] == directory.identityEpochId &&
                payload['effect'] == 'inheritedArchived' &&
                await CryptoLifecycleEvidence(
                      context.access,
                    ).proofHash(Map<String, dynamic>.from(authorization)) ==
                    grant['proofHash']) {
              delegation = grant['proofHash'];
              break;
            }
          }
          if (delegation == null) {
            // Direct management uses authenticated child authority. A parent
            // without child access instead needs the child's explicit grant.
            final head = await context.access.currentHead(
              childId,
              online: true,
            );
            if (head.member(directory.accountId)['manageKeys'] != true) {
              throw const CryptoAuthorityPending(
                'crypto_lifecycle_child_approval_pending',
              );
            }
            final verified = await CryptoLifecycleEvidence(
              context.access,
            ).current(childId);
            if (verified['headHash'] != old['headHash'] ||
                verified['revision'] != old['revision']) {
              throw const CryptoAuthorityPending('crypto_lifecycle_conflict');
            }
          }
          final card = <String, dynamic>{
            'version': 2,
            'serverId': directory.serverId,
            'accountId': directory.accountId,
            'deviceId': context.account.deviceId,
            'authorDirectoryHeadHash': directory.headHash,
            'parentActionId': id,
            'parentScopeToken': await CryptoLifecycleEvidence(
              context.access,
            ).parentToken(childId, scope),
            'parentMembershipHeadHash': intent['membershipHeadHash'],
            'parentExpectedLifecycleRevision':
                intent['expectedLifecycleRevision'],
            'parentPreviousLifecycleHash': intent['previousLifecycleHash'],
            'parentIntentProofHash': prepared['intentProofHash'],
            'parentDeviceSnapshotHash': directory.deviceSnapshotHash,
            'archived': intent['archived'],
            'scopeId': childId,
            'membershipHeadHash': child['membershipHeadHash'],
            'expectedLifecycleRevision': old['revision'],
            'previousLifecycleHash': old['headHash'],
            'delegationProofHash': delegation,
          };
          final lease = await context.account.signingKey();
          try {
            proof = context.account.directory.reducer.crypto.signDomain(
              card,
              lease.key,
              CryptoLifecycleEvidence.inheritedDomain,
            );
          } finally {
            lease.release();
          }
          await context.database.execute(
            "INSERT INTO crypto_membership_intents(partition,scope_id,intent_id,state,payload,authorization) VALUES(?,?,?,'lifecycleWorkflow',?,?)",
            [
              partition,
              scope,
              cardId,
              CryptoJson.encode(card),
              CryptoJson.encode(proof),
            ],
          );
        }
        final staged = await _send(
          cardId,
          'crypto2.scope.lifecycle.observation.put',
          {'scopeId': scope, 'parentActionId': id, 'observation': proof},
        );
        digest.add([
          ...CryptoJson.encode({
            'scopeId': childId,
            'observationProofHash': staged['observationProofHash'],
          }),
          10,
        ]);
        count++;
        after = childId;
      }
      if (page['hasMore'] == false) break;
      if (page['hasMore'] != true ||
          page['nextAfterId'] != after ||
          (page['children'] as List).isEmpty) {
        throw const FormatException('crypto_lifecycle_child_cursor');
      }
    }
    digest.close();
    final childrenHash = (await digest.hash()).bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    await _send('$key:commit', 'crypto2.scope.archive', {
      'scopeId': scope,
      'parentActionId': id,
      'intentProofHash': prepared['intentProofHash'],
      'childCount': count,
      'childrenHash': childrenHash,
    });
    final current = await CryptoLifecycleEvidence(
      context.access,
    ).current(scope);
    final scopes = await context.scopes();
    final result = (scopes['scopes'] as List).cast<Map>().singleWhere(
      (row) => row['id'] == scope,
    );
    return {
      'scope': {
        ...result,
        'archived':
            current['ownArchived'] == true ||
            current['inheritedArchived'] == true,
      },
    };
  }
}
