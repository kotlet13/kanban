import 'dart:convert';

import '../collaboration_database.dart';
import 'crypto_migration_cold_controls.dart';
import 'crypto_record_address.dart';
import 'crypto_migration_topology.dart';
import 'crypto_finance_policy_actions.dart' show CryptoFinancePolicySnapshot;

/// Preparatory join over a complete own Capture3 source set. This loader adds
/// no trust: cold StructureControl independently compares the same joined facts
/// with FILE-authenticated sources before they can enter a cutover certificate.
class CryptoMigrationScopeBaseline {
  CryptoMigrationScopeBaseline({
    required this.database,
    required this.partition,
    required this.captureId,
    required this.accountId,
  });
  final CollaborationDatabase database;
  final String partition, captureId, accountId;

  Future<Map<String, dynamic>> load(String scopeId) async {
    if (!isCryptoCanonicalUuid(scopeId) ||
        !isCryptoCanonicalUuid(accountId) ||
        !isCryptoCanonicalUuid(captureId)) {
      throw const FormatException('crypto_structure_baseline_context');
    }
    final scopes = <Map<String, String?>>[];
    final policies = <Map<String, String?>>[];
    final members = <Map<String, String?>>[];
    final leaders = <Map<String, String?>>[];
    final grants = <Map<String, String?>>[];
    final seen = <String>{};
    String? serverId;
    String? after;
    do {
      final rows = await database.rows(
        'SELECT binding_id,context,typed_row FROM crypto_capture_sources WHERE partition=? AND capture_id=?'
        '${after == null ? '' : ' AND binding_id>?'} ORDER BY binding_id LIMIT 20',
        [partition, captureId, if (after != null) after],
      );
      if (rows.isEmpty) break;
      for (final row in rows) {
        final id = row['binding_id'] as String;
        if (after != null && id.compareTo(after) <= 0) {
          throw const FormatException('crypto_structure_baseline_cursor');
        }
        after = id;
        final context = jsonDecode(row['context'] as String) as Map;
        final table = context['sourceTable'];
        serverId ??= context['serverId'] as String;
        if (!const {
          'familyhub_scopes',
          'familyhub_finance_policy',
          'familyhub_members',
          'familyhub_organization_leaders',
          'familyhub_finance_grants',
        }.contains(table)) {
          continue;
        }
        final cells = CryptoMigrationColdEvidence.cells(
          Map<String, dynamic>.from(
            jsonDecode(row['typed_row'] as String) as Map,
          ),
        );
        final actualScope = table == 'familyhub_scopes'
            ? cells['id']
            : cells['scope_id'];
        if (actualScope != scopeId) continue;
        if (context['scopeId'] != scopeId ||
            context['domain'] != 'content' ||
            !seen.add('$table:${context['sourceId']}')) {
          throw const FormatException('crypto_structure_baseline_sources');
        }
        switch (table) {
          case 'familyhub_scopes':
            scopes.add(cells);
          case 'familyhub_finance_policy':
            policies.add(cells);
          case 'familyhub_members':
            members.add(cells);
          case 'familyhub_organization_leaders':
            leaders.add(cells);
          case 'familyhub_finance_grants':
            grants.add(cells);
        }
      }
    } while (true);
    final baseline = await fromRows(
      scopeId: scopeId,
      accountId: accountId,
      scopes: scopes,
      policies: policies,
      members: members,
      leaders: leaders,
      grants: grants,
    );
    if (scopes.length == 1 &&
        const ['household', 'organization'].contains(scopes.single['kind'])) {
      baseline['financeTopology'] = await CryptoMigrationTopology.load(
        database,
        partition,
        captureId,
        scopeId,
        serverId!,
      );
    }
    return baseline;
  }

  /// Shared closed join; independent callers supply their own verified rows.
  static Future<Map<String, dynamic>> fromRows({
    required String scopeId,
    required String accountId,
    required List<Map<String, String?>> scopes,
    required List<Map<String, String?>> policies,
    required List<Map<String, String?>> members,
    required List<Map<String, String?>> leaders,
    required List<Map<String, String?>> grants,
  }) async {
    if (scopes.length != 1 ||
        scopes.single['id'] != scopeId ||
        policies.length > 1) {
      throw const FormatException('crypto_structure_baseline_scope');
    }
    final raw = scopes.single;
    final policyVersion = CryptoMigrationColdEvidence.integer(
      raw['access_policy_version'],
    );
    if (!const [1, 2, 3].contains(policyVersion)) {
      throw const FormatException('crypto_structure_baseline_policy');
    }
    final active = <String, Map<String, String?>>{};
    final all = <String>{};
    for (final member in members) {
      final id = member['account_id'];
      if (member['scope_id'] != scopeId ||
          !isCryptoCanonicalUuid(id) ||
          !all.add(id!) ||
          !const ['0', '1'].contains(member['active']) ||
          !const ['owner', 'member', 'viewer'].contains(member['role'])) {
        throw const FormatException('crypto_structure_baseline_member');
      }
      if (member['active'] == '1') active[id] = member;
    }
    final owners = active.values.where((m) => m['role'] == 'owner').toList();
    if (owners.length != 1 || owners.single['account_id'] != accountId) {
      throw const FormatException('crypto_structure_baseline_owner');
    }
    final effectiveLeaders = <String>[];
    final unique = <String>{};
    for (final leader in leaders) {
      final id = leader['account_id'];
      if (leader['scope_id'] != scopeId ||
          !isCryptoCanonicalUuid(id) ||
          !unique.add(id!)) {
        throw const FormatException('crypto_structure_baseline_leader');
      }
      if (raw['kind'] == 'organization' &&
          policyVersion < 3 &&
          active[id] != null &&
          active[id]!['role'] != 'owner') {
        effectiveLeaders.add(id);
      }
    }
    effectiveLeaders.sort();
    final finance = policies.isEmpty
        ? <String, dynamic>{
            'enabled': false,
            'revision': 0,
            'requiredContractVersion': 1,
          }
        : financePolicy(policies.single, scopeId);
    final rawGrants = <Map<String, dynamic>>[];
    for (final row in grants) {
      if (row['scope_id'] != scopeId) {
        throw const FormatException('crypto_structure_baseline_grant');
      }
      rawGrants.add({
        'accountId': row['account_id'],
        'grant': row['access_level'],
      });
    }
    rawGrants.sort(
      (a, b) => (a['accountId'] as String).compareTo(b['accountId'] as String),
    );
    final snapshot = CryptoFinancePolicySnapshot(
      enabled: finance['enabled'] as bool,
      revision: finance['revision'] as int,
      requiredContractVersion: finance['requiredContractVersion'] as int,
      grants: rawGrants,
    );
    return {
      'financePolicy': {
        ...finance,
        'policyHash': await snapshot.hash(),
        'grantCount': rawGrants.length,
      },
      if (raw['kind'] == 'organization') 'leaderAccountIds': effectiveLeaders,
    };
  }

  static Map<String, dynamic> financePolicy(
    Map<String, String?> row,
    String scopeId,
  ) {
    if (row['scope_id'] != scopeId ||
        !const ['0', '1'].contains(row['enabled'])) {
      throw const FormatException('crypto_structure_baseline_finance');
    }
    final revision = CryptoMigrationColdEvidence.integer(row['revision']);
    final contract = CryptoMigrationColdEvidence.integer(
      row['required_contract_version'],
    );
    if (revision < 0 ||
        revision > 9007199254740991 ||
        contract < 1 ||
        contract > 3) {
      throw const FormatException('crypto_structure_baseline_finance');
    }
    return {
      'enabled': row['enabled'] == '1',
      'revision': revision,
      'requiredContractVersion': contract,
    };
  }
}
