import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart' show Sha256;

import 'account_directory_v2.dart' show cryptoSha256;
import 'crypto_business_router.dart';
import 'crypto_capture_archive.dart';
import 'crypto_json.dart';
import 'crypto_migration_cold_business.dart';
import 'crypto_migration_cold_controls.dart';
import 'crypto_migration_notification_codec.dart';
import 'crypto_migration_structure_context.dart';
import 'crypto_migration_scope_baseline.dart';
import 'crypto_migration_topology.dart';
import 'crypto_record_address.dart';
import 'crypto_sync_repository.dart';

/// Produced only by the independent FILE/source comparison below. This token
/// does not carry a signing key or authorize full component cutover.
class VerifiedCryptoMigrationStructureSource {
  VerifiedCryptoMigrationStructureSource._(Map<String, dynamic> value)
    : value = _freeze(value) as Map<String, dynamic>;
  final Map<String, dynamic> value;
  static Object? _freeze(Object? value) => value is Map
      ? Map<String, dynamic>.unmodifiable({
          for (final e in value.entries) e.key as String: _freeze(e.value),
        })
      : value is List
      ? List<Object?>.unmodifiable(value.map(_freeze))
      : value;
}

/// A scoped attestation plus exact decrypted own metadata, for the isolated
/// canonical reader's type dispatch only. This is no active scope/WRITE anchor.
class VerifiedCryptoMigrationScopedDescriptor {
  VerifiedCryptoMigrationScopedDescriptor._(
    Map<String, dynamic> descriptor,
    this.sourceProofHash,
  ) : descriptor = Map<String, dynamic>.unmodifiable(descriptor);
  final Map<String, dynamic> descriptor;
  final String sourceProofHash;
}

/// Structural comparison uses the complete private FILE source and already
/// verified staged records. No SQL equality flag or unsigned catalog is trusted.
class CryptoMigrationStructureControl implements CryptoMigrationColdControl {
  CryptoMigrationStructureControl(
    this.runtime,
    this.archive, {
    required this.recoveryFile,
  }) : evidence = CryptoMigrationColdEvidence(runtime, archive);
  final CryptoBusinessSession runtime;
  final VerifiedCryptoCaptureArchive archive;
  final Uint8List recoveryFile;
  final CryptoMigrationColdEvidence evidence;
  static const tables = {
    'familyhub_scopes',
    'familyhub_members',
    'familyhub_organization_leaders',
    'familyhub_scope_revocations',
    'familyhub_finance_policy',
    'familyhub_finance_grants',
    'familyhub_personal_scopes',
    'familyhub_record_relocations',
  };
  final _sections = <String, Map<String, dynamic>>{};
  final _contextProofs = <String, List<String>>{};
  final _scopedDescriptors =
      <String, VerifiedCryptoMigrationScopedDescriptor>{};
  bool _prepared = false;
  bool _sourcesIndexed = false;

  Future<void> _indexSources() async {
    if (_sourcesIndexed) return;
    await runtime.db.execute(
      'CREATE TABLE IF NOT EXISTS cold_structure_sources('
      'binding_id TEXT PRIMARY KEY,scope_id TEXT,source_table TEXT,typed_row TEXT,binding TEXT)',
    );
    String? after;
    while (true) {
      final rows = await runtime.db.rows(
        'SELECT * FROM crypto_capture_sources WHERE partition=? AND capture_id=?'
        '${after == null ? '' : ' AND binding_id>?'} ORDER BY binding_id LIMIT 20',
        [
          runtime.partition,
          archive.capture.captureId,
          if (after != null) after,
        ],
      );
      if (rows.isEmpty) break;
      for (final row in rows) {
        after = row['binding_id'] as String;
        final context = jsonDecode(row['context'] as String) as Map;
        if (!tables.contains(context['sourceTable'])) continue;
        final typed = Map<String, dynamic>.from(
          jsonDecode(row['typed_row'] as String) as Map,
        );
        final cells = CryptoMigrationColdEvidence.cells(typed);
        final scope = context['sourceTable'] == 'familyhub_scopes'
            ? cells['id']
            : cells['scope_id'];
        if (!isCryptoCanonicalUuid(scope)) {
          throw const FormatException('crypto_structure_scope');
        }
        await runtime.db.execute(
          'INSERT OR IGNORE INTO cold_structure_sources VALUES(?,?,?,?,?)',
          [
            after,
            scope,
            context['sourceTable'],
            row['typed_row'],
            row['binding'],
          ],
        );
        final saved = await runtime.db.rows(
          'SELECT scope_id,source_table,typed_row,binding FROM cold_structure_sources WHERE binding_id=?',
          [after],
        );
        if (saved.length != 1 ||
            saved.single['scope_id'] != scope ||
            saved.single['source_table'] != context['sourceTable'] ||
            saved.single['typed_row'] != row['typed_row'] ||
            saved.single['binding'] != row['binding']) {
          throw const FormatException('crypto_structure_source_index_changed');
        }
      }
    }
    await evidence.indexRecords();
    _sourcesIndexed = true;
  }

  Future<void> _prepare() async {
    if (_prepared) return;
    await _indexSources();
    String? lastScope;
    while (true) {
      final scopes = await runtime.db.rows(
        'SELECT DISTINCT scope_id FROM (SELECT scope_id FROM cold_structure_sources '
        "UNION SELECT scope_id FROM cold_control_records WHERE domain='finance')"
        '${lastScope == null ? '' : ' WHERE scope_id>?'} ORDER BY scope_id LIMIT 20',
        [if (lastScope != null) lastScope],
      );
      if (scopes.isEmpty) break;
      for (final s in scopes) {
        lastScope = s['scope_id'] as String;
        _sections[lastScope] = await _scope(lastScope);
      }
    }
    for (final selection in archive.capture.receiptSelections) {
      if (selection['domain'] == 'content' &&
          !_sections.containsKey(selection['scopeId'])) {
        final scope = selection['scopeId'] as String;
        _sections[scope] = await _scope(scope);
      }
    }
    _prepared = true;
  }

  Future<List<Map<String, String?>>> _rows(String scope, String table) async {
    final result = <Map<String, String?>>[];
    String? after;
    while (true) {
      final page = await runtime.db.rows(
        'SELECT binding_id,typed_row FROM cold_structure_sources WHERE scope_id=? AND source_table=?'
        '${after == null ? '' : ' AND binding_id>?'} ORDER BY binding_id LIMIT 20',
        [scope, table, if (after != null) after],
      );
      if (page.isEmpty) break;
      for (final row in page) {
        after = row['binding_id'] as String;
        result.add(
          CryptoMigrationColdEvidence.cells(
            Map<String, dynamic>.from(
              jsonDecode(row['typed_row'] as String) as Map,
            ),
          ),
        );
      }
    }
    return result;
  }

  /// Independent owner content source/control, before any full component
  /// verify3. Monetary controls and child portions cannot create a reciprocal dependency.
  Future<VerifiedCryptoMigrationStructureSource> contentSource(
    String scope,
  ) async {
    await _indexSources();
    final section = await _scope(scope);
    final raw = (await _rows(scope, 'familyhub_scopes')).single;
    final direct = await _rows(scope, 'familyhub_members');
    final leaders = await _rows(scope, 'familyhub_organization_leaders');
    final owner = direct.singleWhere(
      (m) => m['active'] == '1' && m['role'] == 'owner',
    );
    if (owner['account_id'] != evidence.common['accountId']) {
      throw const CryptoAuthorityPending(
        'crypto_structure_source_owner_pending',
      );
    }
    final parentId = raw['parent_scope_id'] ?? raw['organization_id'];
    final members =
        [
          for (final m in direct.where((m) => m['active'] == '1'))
            {
              'accountId': m['account_id'],
              'role': m['role'],
              'leader': leaders.any((l) => l['account_id'] == m['account_id']),
            },
        ]..sort(
          (a, b) =>
              (a['accountId'] as String).compareTo(b['accountId'] as String),
        );
    final policies = await _rows(scope, 'familyhub_finance_policy');
    final grants = [
      for (final row in await _rows(scope, 'familyhub_finance_grants'))
        {'accountId': row['account_id'], 'grant': row['access_level']},
    ]..sort((a, b) => a['accountId']!.compareTo(b['accountId']!));
    final metadata = await runtime.db.rows(
      "SELECT id FROM cold_control_records WHERE scope_id=? AND domain='content' AND type='scopeMetadata' AND proof_hash=?",
      [scope, section['scopeMetadataProofHash']],
    );
    if (metadata.length != 1) {
      throw const FormatException('crypto_structure_metadata_proof');
    }
    final own = await evidence.own();
    return VerifiedCryptoMigrationStructureSource._({
      'common': evidence.common,
      'section': section,
      'scopeMetadataWireId': metadata.single['id'],
      'sourceDeviceSnapshotHash': own.deviceSnapshotHash,
      'sourceIdentityEpochId': own.identityEpochId,
      if (_contextProofs[scope]?.isNotEmpty == true)
        'contextProofHashes': _contextProofs[scope],
      'descriptor': {
        'kind': raw['kind'],
        'accessPolicyVersion': CryptoMigrationColdEvidence.integer(
          raw['access_policy_version'],
        ),
        'ownArchived': raw['archived'] == '1',
        'parentScopeToken': parentId == null
            ? null
            : await cryptoSha256([
                ...utf8.encode('JivieParentLifecycleScope/v2\n'),
                ...CryptoJson.encode({
                  'version': 2,
                  'serverId': evidence.common['serverId'],
                  'scopeId': scope,
                  'parentScopeId': parentId,
                }),
              ]),
        'ownerAccountId': owner['account_id'],
      },
      'members': members,
      if (const ['household', 'organization'].contains(raw['kind']))
        'financeTopology': await CryptoMigrationTopology.load(
          runtime.db,
          runtime.partition,
          archive.capture.captureId,
          scope,
          evidence.common['serverId'] as String,
        ),
      'financePolicy': {
        'enabled': policies.isNotEmpty && policies.single['enabled'] == '1',
        'revision': CryptoMigrationColdEvidence.integer(
          policies.isEmpty ? '0' : policies.single['revision'],
        ),
        'requiredContractVersion': CryptoMigrationColdEvidence.integer(
          policies.isEmpty ? '1' : policies.single['required_contract_version'],
        ),
        'grants': grants,
      },
    });
  }

  Future<Map<String, dynamic>> _scope(String scope) async {
    final scopes = await _rows(scope, 'familyhub_scopes');
    if (scopes.length != 1) {
      if (scopes.isNotEmpty) {
        throw const FormatException('crypto_structure_scope_source');
      }
      return _scopedScope(scope);
    }
    final raw = scopes.single;
    final parentId = raw['parent_scope_id'] ?? raw['organization_id'];
    Map<String, String?>? parent;
    if (parentId != null) {
      final parents = await _rows(parentId, 'familyhub_scopes');
      if (parents.length > 1) {
        throw const FormatException('crypto_structure_parent_source');
      }
      if (parents.isNotEmpty) parent = parents.single;
    }
    final records = await runtime.db.rows(
      'SELECT proof_hash,body FROM cold_control_records WHERE scope_id=? AND domain=? AND type=?',
      [scope, 'content', 'scopeMetadata'],
    );
    final metadata = records;
    if (metadata.length != 1) {
      throw const CryptoAuthorityPending('crypto_structure_metadata_pending');
    }
    final record = Map<String, dynamic>.from(
      jsonDecode(metadata.single['body'] as String) as Map,
    );
    // The isolated FILE database intentionally has no live scope anchor.
    // Its exact already-verified staged metadata proof supplies the frozen
    // read coordinate, without creating future/live authority.
    final head = await runtime.access.withReadOnlyFrozenScope(
      scopeId: scope,
      candidateHeadHash: record['membershipHeadHash'],
      recoveryFile: recoveryFile,
      body: () async {
        final candidate = await runtime.access.recoveryCandidateHead(scope);
        if (candidate.headHash != record['membershipHeadHash']) {
          throw const FormatException('crypto_structure_metadata_head');
        }
        return candidate;
      },
    );
    if (head.scopeId != scope ||
        record['deleted'] != false ||
        !head.member(record['accountId'])['manageKeys']) {
      throw const FormatException('crypto_structure_metadata_authority');
    }
    final contexts = parentId != null && parent == null
        ? await runtime.access.withReadOnlyFrozenScope(
            scopeId: scope,
            candidateHeadHash: head.headHash,
            recoveryFile: recoveryFile,
            body: () => CryptoMigrationStructureContexts(
              runtime,
              archive,
            ).load(scope, head.headHash),
          )
        : <VerifiedCryptoStructureContext>[];
    final parentCard = contexts
        .where((c) => c.purpose == 'parentAccess')
        .toList();
    if (parentId != null && parent == null && parentCard.length != 1 ||
        contexts.length != parentCard.length) {
      throw const CryptoAuthorityPending(
        'crypto_structure_parent_source_pending',
      );
    }
    final parentFacts = parentCard.isEmpty ? null : parentCard.single.facts;
    final policy =
        parentFacts?['accessPolicyVersion'] ??
        CryptoMigrationColdEvidence.integer(
          parent?['access_policy_version'] ?? raw['access_policy_version'],
        );
    if (![1, 2, 3].contains(policy) || raw['deleted_at'] != null) {
      throw const FormatException('crypto_structure_policy');
    }
    final projected = await runtime.wireRecord(scope, 'content', record['id']);
    if (projected == null ||
        projected['crypto_revision'] != record['expectedRevision'] + 1) {
      throw const CryptoAuthorityPending('crypto_structure_metadata_pending');
    }
    final payload =
        (jsonDecode(projected['projection'] as String) as Map)['payload']
            as Map;
    final parentToken = parentId == null
        ? null
        : await cryptoSha256([
            ...utf8.encode('JivieParentLifecycleScope/v2\n'),
            ...CryptoJson.encode({
              'version': 2,
              'serverId': evidence.common['serverId'],
              'scopeId': scope,
              'parentScopeId': parentId,
            }),
          ]);
    if (parentCard.isNotEmpty &&
        parentCard.single.card['parentScopeToken'] != parentToken) {
      throw const FormatException('crypto_structure_parent_token');
    }
    if (payload['kind'] != raw['kind'] ||
        payload['accessPolicyVersion'] !=
            CryptoMigrationColdEvidence.integer(raw['access_policy_version']) ||
        payload['parentScopeToken'] != parentToken ||
        payload['name'] != raw['name'] ||
        payload['address'] != raw['address'] ||
        payload['archived'] != (raw['archived'] == '1') ||
        payload['legacyMetadataRevision'] !=
            CryptoMigrationColdEvidence.integer(raw['metadata_revision'])) {
      throw const FormatException('crypto_structure_metadata_source');
    }
    final direct = await _rows(scope, 'familyhub_members');
    final baseline = await CryptoMigrationScopeBaseline.fromRows(
      scopeId: scope,
      accountId: evidence.common['accountId'] as String,
      scopes: scopes,
      policies: await _rows(scope, 'familyhub_finance_policy'),
      members: direct,
      leaders: await _rows(scope, 'familyhub_organization_leaders'),
      grants: await _rows(scope, 'familyhub_finance_grants'),
    );
    if (const ['household', 'organization'].contains(raw['kind'])) {
      final topology = await CryptoMigrationTopology.load(
        runtime.db,
        runtime.partition,
        archive.capture.captureId,
        scope,
        evidence.common['serverId'] as String,
      );
      if (!CryptoMigrationColdEvidence.same(
        payload['financeTopology'],
        topology,
      )) {
        throw const FormatException('crypto_structure_metadata_topology');
      }
    } else if (payload.containsKey('financeTopology')) {
      throw const FormatException('crypto_structure_metadata_topology');
    }
    if (!CryptoMigrationColdEvidence.same(
          payload['financePolicy'],
          baseline['financePolicy'],
        ) ||
        (raw['kind'] == 'organization'
            ? !CryptoMigrationColdEvidence.same(
                payload['leaderAccountIds'],
                baseline['leaderAccountIds'],
              )
            : payload.containsKey('leaderAccountIds'))) {
      throw const FormatException('crypto_structure_metadata_baseline');
    }
    final ownMembers = <String, Map<String, String?>>{};
    for (final m in direct) {
      if (!isCryptoCanonicalUuid(m['account_id']) ||
          !['0', '1'].contains(m['active']) ||
          !['owner', 'member', 'viewer'].contains(m['role'])) {
        throw const FormatException('crypto_structure_member');
      }
      if (m['active'] == '1') ownMembers[m['account_id']!] = m;
    }
    final expected = <String, String>{
      for (final m in ownMembers.entries) m.key: m.value['role']!,
    };
    final parentMembers = parentFacts != null
        ? [
            for (final m in parentFacts['members'] as List)
              <String, String?>{
                'account_id': m['accountId'],
                'role': m['role'],
                'active': '1',
              },
          ]
        : parentId == null
        ? <Map<String, String?>>[]
        : await _rows(parentId, 'familyhub_members');
    final leaders = parentFacts != null
        ? [
            for (final m in (parentFacts['members'] as List).where(
              (m) => m['leader'] == true,
            ))
              <String, String?>{'account_id': m['accountId']},
          ]
        : parentId == null
        ? <Map<String, String?>>[]
        : await _rows(parentId, 'familyhub_organization_leaders');
    if ((parent != null || parentFacts != null) && raw['kind'] == 'project') {
      for (final m in parentMembers.where((m) => m['active'] == '1')) {
        final id = m['account_id']!, role = m['role']!;
        if (policy == 3) {
          expected.putIfAbsent(id, () => role == 'owner' ? 'member' : role);
          if (role != 'viewer' && expected[id] == 'viewer') {
            expected[id] = 'member';
          }
        } else if (policy == 2 &&
            (parentFacts?['kind'] ?? parent?['kind']) == 'organization' &&
            (role == 'owner' || leaders.any((l) => l['account_id'] == id))) {
          expected.putIfAbsent(id, () => 'viewer');
        }
      }
    }
    final actual = {for (final m in head.members) m['accountId'] as String: m};
    if (!CryptoMigrationColdEvidence.same(
      expected.keys.toList()..sort(),
      actual.keys.toList()..sort(),
    )) {
      throw const CryptoAuthorityPending(
        'crypto_structure_complete_roster_pending',
      );
    }
    final owners = ownMembers.values
        .where((m) => m['role'] == 'owner')
        .toList();
    if (owners.length != 1 || owners.single['user_id'] != raw['owner_id']) {
      throw const FormatException('crypto_structure_owner_identity');
    }
    final finance = await _rows(scope, 'familyhub_finance_policy'),
        grants = await _rows(scope, 'familyhub_finance_grants');
    if (finance.length > 1) {
      throw const FormatException('crypto_structure_finance_policy');
    }
    final grantMap = <String, String>{};
    for (final grant in grants) {
      if (!isCryptoCanonicalUuid(grant['account_id']) ||
          !['none', 'read', 'write'].contains(grant['access_level'])) {
        throw const FormatException('crypto_structure_finance_grant');
      }
      grantMap[grant['account_id']!] = grant['access_level']!;
    }
    final archived =
        raw['archived'] == '1' ||
        parent?['archived'] == '1' ||
        parentFacts?['ownArchived'] == true;
    for (final entry in actual.entries) {
      final role = expected[entry.key], m = entry.value;
      if (m['role'] != role ||
          m['manageKeys'] !=
              (role == 'owner' || policy == 3 && role == 'member')) {
        throw const FormatException('crypto_structure_roster');
      }
      if (finance.isNotEmpty) {
        var access = grantMap[entry.key] ?? 'none';
        final leader =
            (raw['kind'] == 'organization' &&
            policy == 2 &&
            (role == 'owner' ||
                (await _rows(
                  scope,
                  'familyhub_organization_leaders',
                )).any((l) => l['account_id'] == entry.key)));
        if (access == 'none' &&
            (policy == 3 && raw['kind'] != 'personal' ||
                policy == 2 &&
                    (raw['kind'] == 'project' &&
                            raw['organization_id'] != null ||
                        leader))) {
          access = 'read';
        }
        if (policy == 3 && raw['kind'] != 'personal') {
          access = role == 'viewer' ? 'read' : 'write';
        }
        if ((role == 'viewer' || archived) && access == 'write') {
          access = 'read';
        }
        if (finance.single['enabled'] != '1') access = 'none';
        if (m['financeRole'] != access) {
          throw const FormatException('crypto_structure_finance_role');
        }
      }
    }
    final personals = await _rows(scope, 'familyhub_personal_scopes');
    if (raw['kind'] == 'personal' &&
        (personals.length != 1 ||
            personals.single['account_id'] != owners.single['account_id'])) {
      throw const FormatException('crypto_structure_personal');
    }
    final lifecycle = await runtime.access.withReadOnlyFrozenScope<String>(
      scopeId: scope,
      candidateHeadHash: head.headHash,
      recoveryFile: recoveryFile,
      body: () => runtime.access.verifiedLifecycleHash(scope),
    );
    final header = {
      'version': 3,
      'serverId': evidence.common['serverId'],
      'migrationId': archive.capture.migrationId,
      'captureId': archive.capture.captureId,
      'sourceInventoryRoot': archive.sourceInventoryRoot,
      'scopeId': scope,
    };
    final sink = Sha256().newHashSink()
      ..add(utf8.encode('JivieMigrationStructureSources/v3\n'))
      ..add(CryptoJson.encode(header))
      ..add([10]);
    var count = 0;
    String? after;
    while (true) {
      final rows = await runtime.db.rows(
        'SELECT binding_id,binding FROM cold_structure_sources WHERE scope_id=?'
        '${after == null ? '' : ' AND binding_id>?'} ORDER BY binding_id LIMIT 20',
        [scope, if (after != null) after],
      );
      if (rows.isEmpty) break;
      for (final row in rows) {
        after = row['binding_id'] as String;
        final b = jsonDecode(row['binding'] as String) as Map;
        sink.add(
          CryptoJson.encode({
            'bindingId': b['bindingId'],
            'sourceCommitment': b['sourceCommitment'],
          }),
        );
        sink.add([10]);
        count++;
      }
    }
    sink.close();
    final sourceRoot = (await sink.hash()).bytes
        .map((v) => v.toRadixString(16).padLeft(2, '0'))
        .join();
    final section = <String, dynamic>{
      'version': 3,
      'scopeId': scope,
      'membershipHeadHash': head.headHash,
      'scopeMetadataProofHash': metadata.single['proof_hash'],
      'lifecycleHash': lifecycle,
      'sourceBindingCount': count,
      'sourceCommitmentRoot': sourceRoot,
    };
    final contextHashes = contexts.map((c) => c.hash).toList()..sort();
    _contextProofs[scope] = contextHashes;
    section['structureHash'] = await structureHash(
      header,
      section,
      contextProofHashes: contextHashes.isEmpty ? null : contextHashes,
    );
    return section;
  }

  final _targets = <String, Map<String, dynamic>>{};
  bool _targetsLoaded = false;
  Future<Map<String, dynamic>> _target(String scope) async {
    if (!_targetsLoaded) {
      String? after;
      while (true) {
        final page = await runtime.account.directory.call(
          'crypto2.migration.structure.targets',
          {
            for (final k in ['migrationId', 'captureId', 'sourceInventoryRoot'])
              k: evidence.common[k],
            if (after != null) 'afterScopeId': after,
            'limit': 20,
          },
        );
        if (page['targets'] is! List ||
            (page['targets'] as List).length > 20 ||
            page['hasMore'] is! bool) {
          throw const FormatException('crypto_structure_target_page');
        }
        for (final item in page['targets'] as List) {
          if (item is! Map ||
              !isCryptoCanonicalUuid(item['scopeId']) ||
              after != null && after.compareTo(item['scopeId']) >= 0) {
            throw const FormatException('crypto_structure_target_order');
          }
          after = item['scopeId'];
          _targets[after!] = Map<String, dynamic>.from(item);
        }
        if (page['hasMore'] == false) break;
        if (after == null || page['nextAfterScopeId'] != after) {
          throw const FormatException('crypto_structure_target_page');
        }
      }
      _targetsLoaded = true;
    }
    final value = _targets[scope];
    if (value == null) {
      throw const CryptoAuthorityPending('crypto_structure_metadata_pending');
    }
    return value;
  }

  /// Bootstrap type dispatch before a nonowner's monetary canonical projection.
  /// Caller may install this exact capability only in its isolated FILE reader.
  Future<VerifiedCryptoMigrationScopedDescriptor> prepareScopedDescriptor(
    String scope,
  ) async {
    await _scopedScope(scope);
    return _scopedDescriptors[scope]!;
  }

  /// A selected finance contributor does not receive the owner's private ACL
  /// archive. Its own FILE-pinned countersignature fixes the minimal source
  /// attestation and exact candidate head. Its monetary rows remain independently
  /// compared by the normal canonical cold controls.
  Future<Map<String, dynamic>> _scopedScope(String scope) async {
    final target = await _target(scope);
    final headHash = target['membershipHeadHash'] as String;
    return runtime.access.withReadOnlyFrozenScope(
      scopeId: scope,
      candidateHeadHash: headHash,
      recoveryFile: recoveryFile,
      body: () async {
        final head = await runtime.access.recoveryCandidateHead(scope);
        if (head.headHash != headHash) {
          throw const FormatException('crypto_structure_context_head');
        }
        await runtime.access.recoverScopeCandidateKeys(scope, recoveryFile);
        final contexts = await CryptoMigrationStructureContexts(
          runtime,
          archive,
        ).load(scope, headHash);
        final own = contexts.where((c) => c.purpose == 'scopeContext').toList();
        final parents = contexts
            .where((c) => c.purpose == 'parentAccess')
            .toList();
        if (own.length != 1 ||
            contexts.length != own.length + parents.length ||
            parents.length > 1) {
          throw const CryptoAuthorityPending(
            'crypto_structure_scope_context_pending',
          );
        }
        final facts = own.single.facts,
            descriptor = own.single.facts['descriptor'] as Map;
        if ((descriptor['parentScopeToken'] != null) != parents.isNotEmpty ||
            own.single.card['parentScopeToken'] !=
                descriptor['parentScopeToken'] ||
            parents.isNotEmpty &&
                parents.single.card['parentScopeToken'] !=
                    descriptor['parentScopeToken'] ||
            facts['scopeMetadataProofHash'] !=
                target['scopeMetadataProofHash'] ||
            facts['lifecycleHash'] != target['lifecycleHash']) {
          throw const FormatException('crypto_structure_context_target');
        }
        final proof = Map<String, dynamic>.from(target['recordProof'] as Map);
        if (await runtime.codec.digest(proof) !=
            target['scopeMetadataProofHash']) {
          throw const FormatException('crypto_structure_metadata_proof');
        }
        final recordBody = CryptoMigrationStructureContexts.body(proof);
        runtime.codec.validateUntrustedRecord(recordBody);
        final member = head.member(recordBody['accountId']);
        if (recordBody['scopeId'] != scope ||
            recordBody['membershipHeadHash'] != headHash ||
            recordBody['id'] != target['scopeMetadataWireId'] ||
            recordBody['type'] != 'scopeMetadata' ||
            recordBody['domain'] != 'content' ||
            recordBody['expectedRevision'] != 0 ||
            recordBody['deleted'] != false ||
            member['manageKeys'] != true) {
          throw const FormatException('crypto_structure_metadata_authority');
        }
        final author = await runtime.access.directoryAt(
          scopeId: scope,
          scopeHeadHash: headHash,
          accountId: recordBody['accountId'],
          directoryHeadHash: member['directoryHeadHash'],
          online: true,
          allowUnverifiedContact: true,
        );
        if (author.deviceSnapshotHash != member['deviceSnapshotHash'] ||
            author.snapshot['rootSigningKeyBase64'] !=
                member['rootSigningKeyBase64'] ||
            author.snapshot['rootEncryptionKeyBase64'] !=
                member['rootEncryptionKeyBase64']) {
          throw const FormatException('crypto_structure_metadata_authority');
        }
        final record = await runtime.codec.verifyWire(
          serverId: evidence.common['serverId'],
          wire: {
            ...recordBody,
            'revision': 1,
            'sequence': 1,
            'authorization': {
              'recordProof': proof,
              'batchCommitment': target['batchCommitment'],
            },
          },
          trustedSigningKey: cryptoBase64(
            author.activeDevice(recordBody['deviceId'])['signingKeyBase64'],
            length: 32,
          ),
          currentEpoch: true,
        );
        final key = await runtime.access.getScopeKey(
          scope,
          'content',
          head.epoch,
        );
        Map payload;
        try {
          final bytes = runtime.codec.openVerified(record, key.key);
          if (bytes == null) {
            throw const FormatException('crypto_structure_metadata_payload');
          }
          final envelope = CryptoJson.decode(bytes);
          if (envelope is! Map ||
              envelope.length != 3 ||
              envelope['format'] != 2 ||
              !CryptoMigrationColdEvidence.same(
                envelope['identity'],
                recordBody['metadata']['identity'],
              ) ||
              envelope['payload'] is! Map) {
            throw const FormatException('crypto_structure_metadata_payload');
          }
          payload = envelope['payload'] as Map;
        } finally {
          key.release();
        }
        for (final k in ['kind', 'accessPolicyVersion', 'parentScopeToken']) {
          if (payload[k] != descriptor[k]) {
            throw const FormatException('crypto_structure_metadata_context');
          }
        }
        if (payload['archived'] != descriptor['ownArchived']) {
          throw const FormatException('crypto_structure_metadata_context');
        }
        final parent = parents.isEmpty ? null : parents.single.facts;
        final policy =
            parent?['accessPolicyVersion'] ?? descriptor['accessPolicyVersion'];
        final expected = <String, String>{
          for (final m in facts['members'] as List)
            m['accountId'] as String: m['role'] as String,
        };
        if (parent != null && descriptor['kind'] == 'project') {
          for (final m in parent['members'] as List) {
            final id = m['accountId'] as String, role = m['role'] as String;
            if (policy == 3) {
              expected.putIfAbsent(id, () => role == 'owner' ? 'member' : role);
              if (role != 'viewer' && expected[id] == 'viewer') {
                expected[id] = 'member';
              }
            } else if (policy == 2) {
              expected.putIfAbsent(id, () => 'viewer');
            }
          }
        }
        final actual = {
          for (final m in head.members) m['accountId'] as String: m,
        };
        if (!CryptoMigrationColdEvidence.same(
          expected.keys.toList()..sort(),
          actual.keys.toList()..sort(),
        )) {
          throw const FormatException('crypto_structure_context_roster');
        }
        for (final entry in actual.entries) {
          final role = expected[entry.key];
          if (entry.value['role'] != role ||
              entry.value['manageKeys'] !=
                  (role == 'owner' || policy == 3 && role == 'member')) {
            throw const FormatException('crypto_structure_context_roster');
          }
        }
        final ownMember = head.member(evidence.common['accountId']);
        final finance = facts['financePolicy'] as Map?;
        if (finance == null) {
          throw const FormatException(
            'crypto_structure_finance_baseline_pending',
          );
        }
        final minimalFinance = finance;
        if (const ['household', 'organization'].contains(descriptor['kind'])) {
          if (!CryptoMigrationColdEvidence.same(
            payload['financeTopology'],
            facts['financeTopology'],
          )) {
            throw const FormatException('crypto_structure_metadata_topology');
          }
        } else if (payload.containsKey('financeTopology')) {
          throw const FormatException('crypto_structure_metadata_topology');
        }
        final effectiveLeaders = <String>[
          if (descriptor['kind'] == 'organization' && policy < 3)
            for (final member in facts['members'] as List)
              if ((member as Map)['leader'] == true &&
                  member['role'] != 'owner')
                member['accountId'] as String,
        ]..sort();
        if (!CryptoMigrationColdEvidence.same(
              payload['financePolicy'],
              minimalFinance,
            ) ||
            (descriptor['kind'] == 'organization'
                ? !CryptoMigrationColdEvidence.same(
                    payload['leaderAccountIds'],
                    effectiveLeaders,
                  )
                : payload.containsKey('leaderAccountIds'))) {
          throw const FormatException('crypto_structure_metadata_baseline');
        }
        final selectedFinance = archive.capture.receiptSelections.any(
          (selection) =>
              selection['scopeId'] == scope && selection['domain'] == 'finance',
        );
        if (selectedFinance &&
            (ownMember['financeRole'] == 'none' ||
                finance['enabled'] != true)) {
          throw const FormatException(
            'crypto_structure_context_finance_access',
          );
        }
        final lifecycle = await runtime.access.verifiedLifecycleHash(scope);
        if (lifecycle != facts['lifecycleHash']) {
          throw const FormatException('crypto_structure_context_lifecycle');
        }
        _scopedDescriptors[scope] = VerifiedCryptoMigrationScopedDescriptor._({
          'id': scope,
          'kind': descriptor['kind'],
          'accessPolicyVersion': descriptor['accessPolicyVersion'],
          'parentScopeToken': descriptor['parentScopeToken'],
          'financePolicy': minimalFinance,
          if (facts.containsKey('financeTopology'))
            'financeTopology': facts['financeTopology'],
          if (descriptor['kind'] == 'organization')
            'leaderAccountIds': effectiveLeaders,
        }, target['scopeMetadataProofHash']);
        final header = <String, dynamic>{
          for (final k in [
            'version',
            'serverId',
            'migrationId',
            'captureId',
            'sourceInventoryRoot',
          ])
            k: evidence.common[k],
          'scopeId': scope,
        };
        final root = await cryptoSha256([
          ...utf8.encode('JivieMigrationStructureSources/v3\n'),
          ...CryptoJson.encode(header),
          10,
        ]);
        final section = <String, dynamic>{
          'version': 3,
          'scopeId': scope,
          'membershipHeadHash': headHash,
          'scopeMetadataProofHash': target['scopeMetadataProofHash'],
          'lifecycleHash': lifecycle,
          'sourceBindingCount': 0,
          'sourceCommitmentRoot': root,
        };
        section['structureHash'] = await structureHash(
          header,
          section,
          contextProofHashes: contexts.map((c) => c.hash).toList()..sort(),
        );
        return section;
      },
    );
  }

  @override
  Future<String> verify(CryptoMigrationColdSource source) async {
    await _prepare();
    if (!tables.contains(source.context.sourceTable)) {
      throw const FormatException('crypto_structure_source');
    }
    final row = CryptoMigrationColdEvidence.cells(source.typedRow);
    final scope = source.context.sourceTable == 'familyhub_scopes'
        ? row['id']
        : row['scope_id'];
    final section = _sections[scope];
    if (section == null) {
      throw const CryptoAuthorityPending('crypto_structure_section_pending');
    }
    return cryptoSha256([
      ...utf8.encode('JivieMigrationStructureArtifact/v3\n'),
      ...CryptoJson.encode({
        ...evidence.common,
        'binding': source.binding.toJson(),
        'scopeId': scope,
        'structureHash': section['structureHash'],
      }),
    ]);
  }

  @override
  Future<Map<String, dynamic>> finish() async {
    await _prepare();
    return aggregate(
      evidence.common,
      (_sections.keys.toList()..sort()).map((s) => _sections[s]!),
    );
  }

  /// Absent context preserves the original framing. Nonempty context commits
  /// exact independently verified cards; the source binding root is unchanged.
  static Future<String> structureHash(
    Map<String, dynamic> header,
    Map<String, dynamic> section, {
    List<String>? contextProofHashes,
  }) async {
    CryptoMigrationNotificationCodec.fields(header, {
      'version',
      'serverId',
      'migrationId',
      'captureId',
      'sourceInventoryRoot',
      'scopeId',
    });
    if (header['version'] != 3) {
      throw const FormatException('crypto_structure_context');
    }
    for (final field in ['serverId', 'migrationId', 'captureId', 'scopeId']) {
      if (!isCryptoCanonicalUuid(header[field])) {
        throw const FormatException('crypto_structure_context');
      }
    }
    CryptoMigrationNotificationCodec.digest(header['sourceInventoryRoot']);
    if (contextProofHashes != null) {
      if (contextProofHashes.isEmpty || contextProofHashes.length > 100) {
        throw const FormatException('crypto_structure_context_proofs');
      }
      String? previous;
      for (final hash in contextProofHashes) {
        CryptoMigrationNotificationCodec.digest(hash);
        if (previous != null && previous.compareTo(hash) >= 0) {
          throw const FormatException('crypto_structure_context_proofs');
        }
        previous = hash;
      }
    }
    return cryptoSha256([
      ...utf8.encode('JivieMigrationStructure/v3\n'),
      ...CryptoJson.encode({
        ...header,
        if (contextProofHashes != null)
          'contextProofHashes': contextProofHashes,
      }),
      10,
      ...CryptoJson.encode(section),
    ]);
  }

  static Future<Map<String, dynamic>> aggregate(
    Map<String, dynamic> common,
    Iterable<Map<String, dynamic>> sections,
  ) async {
    CryptoMigrationNotificationCodec.context(common);
    final sink = Sha256().newHashSink()
      ..add(utf8.encode('JivieMigrationStructureSet/v3\n'))
      ..add(CryptoJson.encode(common))
      ..add([10]);
    var count = 0;
    String? previous;
    for (final s in sections) {
      CryptoMigrationNotificationCodec.fields(s, {
        'version',
        'scopeId',
        'membershipHeadHash',
        'scopeMetadataProofHash',
        'lifecycleHash',
        'sourceBindingCount',
        'sourceCommitmentRoot',
        'structureHash',
      });
      if (s['version'] != 3 ||
          !isCryptoCanonicalUuid(s['scopeId']) ||
          previous != null && previous.compareTo(s['scopeId']) >= 0) {
        throw const FormatException('crypto_structure_order');
      }
      CryptoMigrationNotificationCodec.count(s['sourceBindingCount']);
      for (final key in [
        'membershipHeadHash',
        'scopeMetadataProofHash',
        'lifecycleHash',
        'sourceCommitmentRoot',
        'structureHash',
      ]) {
        CryptoMigrationNotificationCodec.digest(s[key]);
      }
      count += s['sourceBindingCount'] as int;
      CryptoMigrationNotificationCodec.count(count);
      sink.add(CryptoJson.encode(s));
      sink.add([10]);
      previous = s['scopeId'];
    }
    sink.close();
    return {
      'kind': 'structure',
      'count': count,
      'root': (await sink.hash()).bytes
          .map((v) => v.toRadixString(16).padLeft(2, '0'))
          .join(),
    };
  }
}
