import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_addresses.dart';
import 'package:kanban/organizer/data/e2ee/crypto_project_root_projection.dart';
import 'package:kanban/organizer/data/e2ee/crypto_record_address.dart';

const partition = 'root-address-seam-synthetic';
const server = '00000000-0000-4000-a000-000000000001';
const scope = '00000000-0000-4000-a000-000000000002';
const other = '00000000-0000-4000-a000-000000000003';
const descriptor = <String, dynamic>{
  'kind': 'project',
  'accessPolicyVersion': 3,
};
CryptoRecordAddress address(String canonical) => CryptoRecordAddress.forType(
  serverId: server,
  scopeId: scope,
  type: 'project',
  canonicalId: canonical,
);
Future<void> seed(
  CollaborationDatabase db,
  String canonical, {
  bool mapping = true,
  bool legacy = false,
}) async {
  final value = address(canonical);
  if (mapping) {
    await CryptoBusinessAddresses(db, partition, server).install(value);
  }
  await db.execute(
    'INSERT INTO crypto_business_records VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)',
    [
      partition,
      scope,
      'content',
      value.wireId,
      'project',
      1,
      legacy ? 1 : 0,
      'a' * 64,
      0,
      '{}',
      jsonEncode({'id': canonical, 'type': 'project', 'deleted': false}),
      'ordinary',
      legacy ? 'legacy' : 'crypto',
    ],
  );
}

Future<List<Map<String, Object?>>> candidates(
  CollaborationDatabase db, {
  String accountPartition = partition,
}) => cryptoProjectRootCandidates(
  database: db,
  partition: accountPartition,
  serverId: server,
  scopeId: scope,
);
String? root(List<Map<String, Object?>> rows, {bool complete = false}) =>
    cryptoProjectRootProjection(
      scopeId: scope,
      descriptor: descriptor,
      projects: rows,
      completeVerifiedInventory: complete,
    );
void main() {
  test(
    'actual wire-address SQL reproduces null then bound canonical loader finds native root without network',
    () async {
      final db = CollaborationDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await seed(db, scope);
      final oldRows = await db.rows(
        "SELECT id,deleted,legacy_revision,revision_namespace FROM crypto_business_records WHERE partition=? AND scope_id=? AND domain='content' AND type='project'",
        [partition, scope],
      );
      expect(oldRows.single['id'], address(scope).wireId);
      expect(isCryptoWireRecordId(oldRows.single['id']), true);
      expect(isCryptoCanonicalUuid(oldRows.single['id']), false);
      expect(root(oldRows), isNull);
      await db.execute('PRAGMA query_only=ON');
      final resolved = await candidates(db);
      expect(resolved.single['wire_id'], address(scope).wireId);
      expect(resolved.single['id'], scope);
      expect(root(resolved), scope);
      expect(
        await candidates(db, accountPartition: 'foreign-partition'),
        isEmpty,
      );
    },
  );
  test(
    'canonical mapping rejects wrong derivation type domain source and projection identity',
    () async {
      final db = CollaborationDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await seed(db, scope);
      for (final change in <String, String>{
        'canonical_id': other,
        'type': 'task',
        'domain': 'finance',
        'source_kind': 'tables',
      }.entries) {
        await db.execute(
          'UPDATE crypto_business_addresses SET ${change.key}=? WHERE partition=?',
          [change.value, partition],
        );
        expect(root(await candidates(db)), isNull, reason: change.key);
        await db.execute(
          'UPDATE crypto_business_addresses SET canonical_id=?,type=?,domain=?,source_kind=? WHERE partition=?',
          [scope, 'project', 'content', 'records', partition],
        );
      }
      await db.execute(
        'UPDATE crypto_business_records SET projection=? WHERE partition=?',
        [
          jsonEncode({'id': other, 'type': 'project'}),
          partition,
        ],
      );
      expect(root(await candidates(db)), isNull);
    },
  );
  test(
    'unmapped active rows remain ambiguous and migrated canonical identity still requires complete inventory',
    () async {
      final db = CollaborationDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await seed(db, other, legacy: true);
      final migrated = await candidates(db);
      expect(migrated.single['id'], other);
      expect(root(migrated), isNull);
      expect(root(migrated, complete: true), other);
      await seed(db, scope, mapping: false);
      final ambiguous = await candidates(db);
      expect(ambiguous, hasLength(2));
      expect(ambiguous.where((row) => row['id'] == null), hasLength(1));
      expect(root(ambiguous, complete: true), isNull);
    },
  );
}
