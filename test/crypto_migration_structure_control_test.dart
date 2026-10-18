import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/e2ee/crypto_finance_topology.dart';
import 'package:kanban/organizer/data/e2ee/crypto_migration_structure_control.dart';
import 'package:kanban/organizer/data/e2ee/crypto_migration_cold_controls.dart';
import 'package:kanban/organizer/data/e2ee/crypto_migration_structure_context.dart';

void main() {
  test(
    'scoped parent facts reject unrelated identity, finance and policy expansion',
    () {
      final owner = {
        'accountId': '11111111-1111-4111-8111-111111111111',
        'role': 'owner',
        'leader': false,
      };
      final member = {
        'accountId': '22222222-2222-4222-8222-222222222222',
        'role': 'member',
        'leader': false,
      };
      final parent = {
        'kind': 'organization',
        'accessPolicyVersion': 2,
        'ownArchived': false,
        'members': [owner],
      };
      CryptoMigrationStructureContexts.facts('parentAccess', parent);
      for (final invalid in [
        {...parent, 'parentScopeId': '33333333-3333-4333-8333-333333333333'},
        {
          ...parent,
          'financePolicy': {'enabled': true},
        },
        {
          ...parent,
          'members': [owner, member],
        },
        {...parent, 'accessPolicyVersion': 1},
        {
          ...parent,
          'members': [owner, owner],
        },
      ]) {
        expect(
          () => CryptoMigrationStructureContexts.facts('parentAccess', invalid),
          throwsFormatException,
        );
      }
      CryptoMigrationStructureContexts.facts('parentAccess', {
        ...parent,
        'accessPolicyVersion': 1,
        'members': [],
      });
      CryptoMigrationStructureContexts.facts('parentAccess', {
        ...parent,
        'accessPolicyVersion': 3,
        'members': [owner, member],
      });
    },
  );
  test(
    'scope context binds own metadata/lifecycle without exposing grant history',
    () async {
      final facts = <String, dynamic>{
        'descriptor': {
          'kind': 'organization',
          'accessPolicyVersion': 1,
          'ownArchived': false,
          'parentScopeToken': null,
          'ownerAccountId': '11111111-1111-4111-8111-111111111111',
        },
        'members': [
          {
            'accountId': '11111111-1111-4111-8111-111111111111',
            'role': 'owner',
            'leader': false,
          },
        ],
        'financePolicy': {
          'enabled': true,
          'revision': 4,
          'requiredContractVersion': 3,
          'policyHash':
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          'grantCount': 0,
        },
        'financeTopology': await CryptoFinanceTopology.create(
          serverId: '33333333-3333-4333-8333-333333333333',
          scopeId: '44444444-4444-4444-8444-444444444444',
          childTokens: [],
        ),
        'scopeMetadataProofHash': '1' * 64,
        'lifecycleHash': '2' * 64,
      };
      CryptoMigrationStructureContexts.facts('scopeContext', facts);
      for (final invalid in [
        {...facts}..remove('financeTopology'),
        {...facts}..remove('scopeMetadataProofHash'),
        {...facts}..remove('lifecycleHash'),
        {
          ...facts,
          'financePolicy': {
            'enabled': true,
            'revision': 4,
            'requiredContractVersion': 3,
            'policyHash':
                'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            'grantCount': 0,
            'grants': [],
          },
        },
        {
          ...facts,
          'financePolicy': {
            'enabled': true,
            'revision': -1,
            'requiredContractVersion': 3,
            'policyHash':
                'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            'grantCount': 0,
          },
        },
        {
          ...facts,
          'financePolicy': {
            'enabled': true,
            'revision': 4,
            'requiredContractVersion': 0,
            'policyHash':
                'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            'grantCount': 0,
          },
        },
      ]) {
        expect(
          () => CryptoMigrationStructureContexts.facts('scopeContext', invalid),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'complete structure set matches independent Python framing including empty',
    () async {
      final v =
          jsonDecode(
                File(
                  'server/tests/fixtures/e2ee-structure-set-v3.json',
                ).readAsStringSync(),
              )
              as Map;
      final common = Map<String, dynamic>.from(v['common'] as Map);
      final sections = (v['sections'] as List)
          .map((s) => Map<String, dynamic>.from(s as Map))
          .toList();
      expect(
        await CryptoMigrationStructureControl.aggregate(common, sections),
        {'kind': 'structure', 'count': 3, 'root': v['root']},
      );
      expect(await CryptoMigrationStructureControl.aggregate(common, []), {
        'kind': 'structure',
        'count': 0,
        'root': v['emptyRoot'],
      });
      for (final invalid in [
        sections.reversed,
        [sections[0], sections[0]],
        [
          {...sections[0], 'sourceBindingCount': -1},
        ],
      ]) {
        await expectLater(
          CryptoMigrationStructureControl.aggregate(common, invalid),
          throwsFormatException,
        );
      }
      expect(
        (await CryptoMigrationStructureControl.aggregate({
          ...common,
          'sourceInventoryRoot': '1' * 64,
        }, sections))['root'],
        isNot(v['root']),
      );
    },
  );
  test(
    'private typed source keeps exact null/false and rejects malformed cells',
    () {
      expect(
        CryptoMigrationColdEvidence.cells({
          'flag': {
            'type': 'integer',
            'valueBase64': base64Encode(utf8.encode('0')),
          },
          'none': {'type': 'null', 'valueBase64': null},
        }),
        {'flag': '0', 'none': null},
      );
      expect(
        () => CryptoMigrationColdEvidence.compareColumns(
          {'sound': true},
          {'sound': '0'},
          {'sound': 'sound'},
        ),
        throwsFormatException,
      );
      expect(
        () => CryptoMigrationColdEvidence.integer('01'),
        throwsFormatException,
      );
      expect(
        () => CryptoMigrationColdEvidence.cells({
          'x': {'valueBase64': 'AA=='},
        }),
        throwsFormatException,
      );
    },
  );
  test(
    'structure cards bind exact sorted nonempty context without changing source framing',
    () async {
      final v =
          jsonDecode(
                File(
                  'server/tests/fixtures/e2ee-structure-set-v3.json',
                ).readAsStringSync(),
              )
              as Map;
      final c = v['contextVector'] as Map;
      final header = Map<String, dynamic>.from(c['header'] as Map);
      final section = Map<String, dynamic>.from(c['section'] as Map);
      final hashes = List<String>.from(c['contextProofHashes'] as List);
      expect(
        await CryptoMigrationStructureControl.structureHash(header, section),
        c['absentHash'],
      );
      expect(
        await CryptoMigrationStructureControl.structureHash(
          header,
          section,
          contextProofHashes: hashes,
        ),
        c['boundHash'],
      );
      expect(
        await CryptoMigrationStructureControl.structureHash(
          header,
          section,
          contextProofHashes: ['3' * 64],
        ),
        isNot(c['boundHash']),
      );
      for (final invalid in <List<String>>[
        [],
        hashes.reversed.toList(),
        [hashes[0], hashes[0]],
      ]) {
        await expectLater(
          CryptoMigrationStructureControl.structureHash(
            header,
            section,
            contextProofHashes: invalid,
          ),
          throwsFormatException,
        );
      }
    },
  );
}
