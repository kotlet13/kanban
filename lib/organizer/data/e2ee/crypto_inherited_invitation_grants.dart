import 'dart:typed_data';
import 'dart:convert';

import 'crypto_inherited_invitation_evidence.dart';
import 'crypto_json.dart';
import 'crypto_record_address.dart' show isCryptoCanonicalUuid;
import 'crypto_finance_topology.dart';
import 'crypto_business_router.dart';
import 'crypto_lifecycle_evidence.dart';
import 'crypto_sync_repository.dart';
import 'scope_crypto_manager.dart';
import 'session_crypto_access.dart';

/// UUIDs are values in canonical protocol JSON, never object property names.
/// This small codec keeps each automatic review bound to exactly one child.
class InheritedInvitationReviewJournal {
  static Map<String, String> decode(Object? value) {
    if (value == null) return {};
    if (value is! List || value.length > 1000) {
      throw const FormatException('crypto_inherited_invitation_review_journal');
    }
    final out = <String, String>{}, usedReviews = <String>{};
    String? previous;
    for (final entry in value) {
      if (entry is! Map ||
          entry.length != 2 ||
          !isCryptoCanonicalUuid(entry['scopeId']) ||
          !isCryptoCanonicalUuid(entry['reviewId']) ||
          previous != null &&
              (entry['scopeId'] as String).compareTo(previous) <= 0 ||
          !usedReviews.add(entry['reviewId'] as String)) {
        throw const FormatException(
          'crypto_inherited_invitation_review_journal',
        );
      }
      previous = entry['scopeId'] as String;
      out[previous] = entry['reviewId'] as String;
    }
    return out;
  }

  static List<Map<String, dynamic>> encode(Map<String, String> reviews) {
    final scopes = reviews.keys.toList()..sort();
    final value = [
      for (final scope in scopes)
        {'scopeId': scope, 'reviewId': reviews[scope]},
    ];
    decode(value);
    return value;
  }
}

/// Durable continuation of the same explicitly approved parent invitation.
/// Journal rows route work only; every child grant requires fresh signed parent
/// membership, invitation intent, policy and exact signed child relationship.
class CryptoInheritedInvitationGrants {
  CryptoInheritedInvitationGrants(this.access, {this.runtime});
  final SessionCryptoAccess access;
  final CryptoBusinessSession? runtime;
  CryptoBusinessSession get _runtime =>
      runtime ??
      CryptoBusinessSession(
        access.account,
        access,
        access.account.store.database,
      );
  static final _queues = <String, Future<void>>{};
  String get _partition => access.account.store.partition;

  Future<T> _serial<T>(String parent, Future<T> Function() body) async {
    final key = '$_partition:$parent';
    final task = (_queues[key] ?? Future<void>.value()).then((_) => body());
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

  Map<String, dynamic> _decode(Object value) => Map<String, dynamic>.from(
    CryptoJson.decode(Uint8List.fromList((value as List).cast<int>())) as Map,
  );

  Future<List<Map<String, dynamic>>> _catalog() async {
    final out = <Map<String, dynamic>>[];
    String? after;
    while (true) {
      final page = await access.account.directory.call(
        'crypto2.scopes.catalog',
        {'limit': 50, if (after != null) 'afterId': after},
      );
      final rows = page['scopes'];
      if (rows is! List ||
          rows.length > 50 ||
          out.length + rows.length > 1000) {
        throw const FormatException('crypto_scope_catalog');
      }
      String? previous = after;
      for (final value in rows) {
        if (value is! Map ||
            value['id'] is! String ||
            previous != null &&
                (value['id'] as String).compareTo(previous) <= 0) {
          throw const FormatException('crypto_scope_catalog_cursor');
        }
        previous = value['id'];
        out.add(Map<String, dynamic>.from(value));
      }
      if (page['hasMore'] != true) return out;
      if (previous == after || page['nextAfterId'] != previous) {
        throw const FormatException('crypto_scope_catalog_cursor');
      }
      after = previous;
    }
  }

  Future<List<String>> _children(String parentScopeId) async {
    final context = _runtime;
    if (!identical(context.access, access)) {
      throw const FormatException('crypto_inherited_invitation_context');
    }
    // This is the complete authenticated parent inventory, rather than the
    // unsigned catalog's suggested parent IDs or absence of rows.
    await context.pullVerified(parentScopeId, 'content');
    final read = await access.readContext(parentScopeId, 'content');
    if (!await context.hasReusableCheckpoint(parentScopeId, 'content', read)) {
      throw const CryptoAuthorityPending('crypto_inherited_invitation_pending');
    }
    final metadata = await context.record(
      parentScopeId,
      'content',
      await context.reservedRecordId(parentScopeId, 'scopeMetadata'),
      type: 'scopeMetadata',
    );
    if (metadata == null ||
        metadata['deleted'] == 1 ||
        metadata['raw_payload'] is! String) {
      throw const CryptoAuthorityPending('crypto_inherited_invitation_pending');
    }
    final raw = jsonDecode(metadata['raw_payload'] as String);
    if (raw is! Map || raw['financeTopology'] is! Map) {
      throw const CryptoAuthorityPending('crypto_inherited_invitation_pending');
    }
    final topology = Map<String, dynamic>.from(raw['financeTopology'] as Map);
    final server = access.account.directory.session.profile.serverId;
    await CryptoFinanceTopology.validate(
      topology,
      serverId: server,
      scopeId: parentScopeId,
    );
    final required = (topology['childTokens'] as List).cast<String>().toSet();
    final unresolved = {...required};
    final out = <String>[];
    for (final candidate in await _catalog()) {
      final id = candidate['id'] as String;
      if (id == parentScopeId) continue;
      final token = await CryptoFinanceTopology.childToken(
        server,
        parentScopeId,
        id,
      );
      final selected = required.contains(token);
      if (!selected && candidate['parentScopeId'] != parentScopeId) continue;
      if (candidate['headHash'] == null) {
        throw const CryptoAuthorityPending(
          'crypto_inherited_invitation_pending',
        );
      }
      final descriptor = await access.verifiedScopeDescriptor(id, online: true);
      final exactParent =
          descriptor['kind'] == 'project' &&
          descriptor['accessPolicyVersion'] == 3 &&
          descriptor['parentScopeToken'] ==
              await CryptoLifecycleEvidence(
                access,
              ).parentToken(id, parentScopeId);
      if (!exactParent) {
        if (selected) {
          throw const CryptoAuthorityPending(
            'crypto_inherited_invitation_parent',
          );
        }
        continue;
      }
      // A real child absent from the signed set indicates concurrent or
      // incomplete structure; it cannot silently vanish from the approval.
      if (!selected) {
        throw const CryptoAuthorityPending(
          'crypto_inherited_invitation_pending',
        );
      }
      unresolved.remove(token);
      out.add(id);
    }
    if (unresolved.isNotEmpty) {
      throw const CryptoAuthorityPending('crypto_inherited_invitation_pending');
    }
    return out..sort();
  }

  /// Complete verified graph for Send-time sealing; never a recipient consent.
  Future<List<String>> preauthorizationChildren(String parentScopeId) async {
    final descriptor = await access.verifiedScopeDescriptor(
      parentScopeId,
      online: true,
    );
    if (!const {'household', 'organization'}.contains(descriptor['kind']) ||
        descriptor['accessPolicyVersion'] != 3)
      return const [];
    return _children(parentScopeId);
  }

  Future<void> _write(
    String parent,
    String invitationId,
    Map<String, dynamic> payload, {
    bool complete = false,
  }) => access.account.store.database.execute(
    'INSERT INTO crypto_membership_intents VALUES(?,?,?,?,?,NULL) ON CONFLICT(partition,scope_id,intent_id) DO UPDATE SET state=excluded.state,payload=excluded.payload',
    [
      _partition,
      parent,
      'inherited:$invitationId',
      complete
          ? 'invitationInheritedGrantsComplete'
          : 'invitationInheritedGrants',
      CryptoJson.encode(payload),
    ],
  );

  Future<void> prepare({
    required String parentScopeId,
    required String invitationId,
    required String recipientAccountId,
    required String acceptanceProofHash,
    bool foregroundOnly = false,
  }) => _serial(parentScopeId, () async {
    if (!access.account.directory.isCurrent()) {
      throw const CryptoAuthorityPending('crypto_stale_identity');
    }
    final descriptor = await access.verifiedScopeDescriptor(
      parentScopeId,
      online: true,
    );
    // A child-only or separate-project invitation retains its original scope.
    if (!const {'household', 'organization'}.contains(descriptor['kind']) ||
        descriptor['accessPolicyVersion'] != 3) {
      return;
    }
    final rows = await access.account.store.database.rows(
      'SELECT payload FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND intent_id=?',
      [_partition, parentScopeId, 'inherited:$invitationId'],
    );
    if (rows.isNotEmpty) {
      final saved = _decode(rows.single['payload']!);
      if (saved['recipientAccountId'] != recipientAccountId ||
          saved['acceptanceProofHash'] != acceptanceProofHash ||
          saved['invitationId'] != invitationId) {
        throw const FormatException(
          'crypto_inherited_invitation_journal_changed',
        );
      }
      return;
    }
    final source = await access.currentHead(parentScopeId, online: true);
    if (source.member(access.account.directory.accountId)['manageKeys'] !=
        true) {
      throw const CryptoAuthorityPending('scope_management_required');
    }
    await _write(parentScopeId, invitationId, {
      'version': 1,
      if (foregroundOnly) 'foregroundOnly': true,
      'parentScopeId': parentScopeId,
      'invitationId': invitationId,
      'recipientAccountId': recipientAccountId,
      'acceptanceProofHash': acceptanceProofHash,
      'children': await _children(parentScopeId),
    });
  });

  Future<List<Map<String, dynamic>>> pending() async {
    final rows = await access.account.store.database.rows(
      "SELECT payload FROM crypto_membership_intents WHERE partition=? AND state='invitationInheritedGrants' ORDER BY scope_id,intent_id",
      [_partition],
    );
    return [for (final row in rows) _decode(row['payload']!)];
  }

  Future<void> finish(
    String parentScopeId,
    String invitationId, {
    bool verifiedHistoryOnly = false,
    Future<void> Function()? beforeDisclosure,
    Future<void> Function()? freshDisclosureBoundary,
  }) => _serial(parentScopeId, () async {
    final rows = await access.account.store.database.rows(
      "SELECT payload FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND intent_id=? AND state='invitationInheritedGrants'",
      [_partition, parentScopeId, 'inherited:$invitationId'],
    );
    if (rows.isEmpty) return;
    final payload = _decode(rows.single['payload']!);
    if (payload['version'] != 1 ||
        payload['parentScopeId'] != parentScopeId ||
        payload['invitationId'] != invitationId ||
        payload['children'] is! List) {
      throw const FormatException('crypto_inherited_invitation_journal');
    }
    Future<void> verifyParent() async {
      await beforeDisclosure?.call();
      await VerifiedInheritedInvitationAdmission.requireParent(
        access: access,
        parentScopeId: parentScopeId,
        invitationId: invitationId,
        acceptanceProofHash: payload['acceptanceProofHash'],
        recipientAccountId: payload['recipientAccountId'],
      );
    }

    await verifyParent();
    final children = (payload['children'] as List).cast<String>().toSet();
    final done = <String>{};
    final autoReviews = InheritedInvitationReviewJournal.decode(
      payload['automaticReviewIds'],
    );
    // A final fresh sweep includes children created while the parent grant was
    // being activated. Concurrent growth remains pending after this bound.
    for (var sweep = 0; sweep < 4; sweep++) {
      for (final child in children.toList()..sort()) {
        await beforeDisclosure?.call();
        if (done.contains(child)) continue;
        final evidence = await VerifiedInheritedInvitationAdmission.verify(
          access: access,
          parentScopeId: parentScopeId,
          childScopeId: child,
          invitationId: invitationId,
          acceptanceProofHash: payload['acceptanceProofHash'],
          recipientAccountId: payload['recipientAccountId'],
        );
        if (!evidence.alreadyAvailable) {
          final manager = ScopeCryptoManager(access);
          final pending = await manager.pendingRotationReviews(child);
          if (verifiedHistoryOnly && autoReviews[child] == null) {
            autoReviews[child] = access.account.directory.reducer.crypto
                .randomId();
            payload['automaticReviewIds'] =
                InheritedInvitationReviewJournal.encode(autoReviews);
            await _write(parentScopeId, invitationId, payload);
          }
          final matching = pending
              .where(
                (r) => verifiedHistoryOnly
                    ? r.id == autoReviews[child]
                    : r.sourceHeadHash == evidence.source.headHash,
              )
              .firstOrNull;
          if (verifiedHistoryOnly && matching == null) {
            final retained = await access.account.store.database.rows(
              'SELECT state FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND intent_id=?',
              [_partition, child, autoReviews[child]],
            );
            if (retained.isNotEmpty) {
              throw const CryptoAuthorityPending(
                'scope_review_confirmation_required',
              );
            }
          }
          final review =
              matching ??
              await manager.reviewRotation(
                child,
                inheritedInvitationAdmission: evidence,
                fixedReviewId: verifiedHistoryOnly ? autoReviews[child] : null,
              );
          if (verifiedHistoryOnly &&
              review.historyBasis != 'verifiedCheckpoint') {
            throw const CryptoAuthorityPending(
              'scope_review_confirmation_required',
            );
          }
          await manager.confirmRotation(
            review,
            beforeDisclosure: beforeDisclosure,
            freshDisclosureBoundary: freshDisclosureBoundary,
            acceptedCandidateHistory: !verifiedHistoryOnly,
            members: evidence.members,
            inheritedInvitationAdmission: evidence,
          );
        }
        if (verifiedHistoryOnly &&
            evidence.alreadyAvailable &&
            autoReviews[child] != null) {
          await ScopeCryptoManager(access).reconcileAppliedRotation(
            scopeId: child,
            reviewId: autoReviews[child]!,
            headHash: evidence.source.headHash,
            beforeDisclosure: beforeDisclosure,
          );
        }
        done.add(child);
      }
      final discovered = await _children(parentScopeId);
      final newChildren = discovered
          .where((id) => !children.contains(id))
          .toList();
      if (newChildren.isEmpty) {
        // Recheck every child after the sweep; an intervening authorized
        // change cannot be hidden by an earlier in-memory 'done' marker.
        for (final child in children) {
          final checked = await VerifiedInheritedInvitationAdmission.verify(
            access: access,
            parentScopeId: parentScopeId,
            childScopeId: child,
            invitationId: invitationId,
            acceptanceProofHash: payload['acceptanceProofHash'],
            recipientAccountId: payload['recipientAccountId'],
          );
          if (!checked.alreadyAvailable) {
            throw const CryptoAuthorityPending(
              'crypto_inherited_invitation_pending',
            );
          }
        }
        await verifyParent();
        await _write(parentScopeId, invitationId, {
          ...payload,
          'children': children.toList()..sort(),
        }, complete: true);
        return;
      }
      children.addAll(newChildren);
      await _write(parentScopeId, invitationId, {
        ...payload,
        'children': children.toList()..sort(),
      });
    }
    throw const CryptoAuthorityPending('crypto_inherited_invitation_pending');
  });

  Future<void> resumeAll() async {
    for (final row in await pending()) {
      if (row['foregroundOnly'] == true) continue;
      await finish(row['parentScopeId'], row['invitationId']);
    }
  }
}
