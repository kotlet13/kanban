import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/e2ee/crypto_record_address.dart';
import 'package:kanban/organizer/data/e2ee/crypto_record_policy.dart';

const _server = '11111111-1111-4111-8111-111111111111';
const _scope = '22222222-2222-4222-8222-222222222222';
const _creator = '33333333-3333-4333-8333-333333333333';
const _assignee = '44444444-4444-4444-8444-444444444444';
const _id = '55555555-5555-4555-8555-555555555555';
final _key = Uint8List.fromList(List.generate(32, (i) => i));
String _wire(String type) => CryptoRecordAddress.forType(
  serverId: _server,
  scopeId: _scope,
  canonicalId: _id,
  type: type,
).wireId;
Future<Map<String, dynamic>> _policy(
  String type,
  Map<String, dynamic> payload, {
  String operation = 'edit',
}) => CryptoRecordPolicy.prepare(
  serverId: _server,
  scopeId: _scope,
  domain: 'content',
  wireId: _wire(type),
  type: type,
  creator: _creator,
  operation: operation,
  payload: payload,
);
Map<String, dynamic> _record(
  String type,
  Map<String, dynamic> policy, {
  bool deleted = false,
}) => {
  'serverId': _server,
  'scopeId': _scope,
  'domain': 'content',
  'id': _wire(type),
  'type': type,
  'deleted': deleted,
  'metadata': {'recordPolicy': policy},
};

void main() {
  test(
    'keyed commitments resist dictionary comparison and bind identity plus all future business fields',
    () async {
      final raw = CryptoRecordPolicy.attachSecret({
        'title': 'Milk',
        'quantity': '1',
        'isChecked': false,
        'future': {'nested': 1},
      }, _key);
      final a = await _policy('shoppingItem', raw);
      final anotherKey = CryptoRecordPolicy.attachSecret(
        raw,
        Uint8List.fromList(List.filled(32, 91)),
      );
      final b = await _policy('shoppingItem', anotherKey);
      expect(
        a['fieldCommitments']['content'],
        isNot(b['fieldCommitments']['content']),
      );
      expect(a.containsKey('keyBase64'), false);
      final changedFuture = await _policy('shoppingItem', {
        ...raw,
        'future': {'nested': 2},
      });
      expect(
        a['fieldCommitments']['content'],
        isNot(changedFuture['fieldCommitments']['content']),
      );
      final anotherIdentity = await CryptoRecordPolicy.commitments(
        serverId: _server,
        scopeId: '66666666-6666-4666-8666-666666666666',
        domain: 'content',
        wireId: _wire('shoppingItem'),
        type: 'shoppingItem',
        payload: raw,
      );
      expect(
        a['fieldCommitments']['content'],
        isNot(anotherIdentity['content']),
      );
    },
  );

  test(
    'shoppingCheck changes only checked group; forged ciphertext title cannot pass honest receiver',
    () async {
      final before = CryptoRecordPolicy.attachSecret({
        'title': 'Milk',
        'quantity': '1',
        'isChecked': false,
        'updatedAt': 'old',
      }, _key);
      final priorPolicy = await _policy('shoppingItem', before);
      final after = {...before, 'isChecked': true, 'updatedAt': 'new'};
      final policy = await _policy(
        'shoppingItem',
        after,
        operation: 'shoppingCheck',
      );
      expect(
        policy['fieldCommitments']['content'],
        priorPolicy['fieldCommitments']['content'],
      );
      expect(
        policy['fieldCommitments']['checked'],
        isNot(priorPolicy['fieldCommitments']['checked']),
      );
      await CryptoRecordPolicy.verifyPayload(
        record: _record('shoppingItem', policy),
        payload: after,
        previousPayload: before,
        previousPolicy: priorPolicy,
      );
      await expectLater(
        CryptoRecordPolicy.verifyPayload(
          record: _record('shoppingItem', policy),
          payload: {...after, 'title': 'Other product'},
          previousPayload: before,
          previousPolicy: priorPolicy,
        ),
        throwsFormatException,
      );
      final maliciousPolicy = await _policy('shoppingItem', {
        ...after,
        'quantity': '10',
      }, operation: 'shoppingCheck');
      await expectLater(
        CryptoRecordPolicy.verifyPayload(
          record: _record('shoppingItem', maliciousPolicy),
          payload: {...after, 'quantity': '10'},
          previousPayload: before,
          previousPolicy: priorPolicy,
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'task assignment commitment separate; business due dates remain protected while updatedAt is volatile',
    () async {
      final raw = CryptoRecordPolicy.attachSecret({
        'title': 'Task',
        'assigneeAccountIds': [_assignee],
        'dueAt': '2026-10-24',
        'updatedAt': 'old',
      }, _key);
      final a = await _policy('task', raw);
      final b = await _policy('task', {
        ...raw,
        'title': 'Edited',
        'updatedAt': 'new',
      });
      expect(
        a['fieldCommitments']['assignment'],
        b['fieldCommitments']['assignment'],
      );
      expect(
        a['fieldCommitments']['content'],
        isNot(b['fieldCommitments']['content']),
      );
      final c = await _policy('task', {
        ...raw,
        'assigneeAccountIds': [_creator],
      });
      expect(
        a['fieldCommitments']['content'],
        c['fieldCommitments']['content'],
      );
      expect(
        a['fieldCommitments']['assignment'],
        isNot(c['fieldCommitments']['assignment']),
      );
      final dueChanged = await _policy('task', {...raw, 'dueAt': '2026-10-25'});
      expect(
        a['fieldCommitments']['content'],
        isNot(dueChanged['fieldCommitments']['content']),
      );
      final timestamp = await _policy('task', {...raw, 'updatedAt': 'later'});
      expect(a['fieldCommitments'], timestamp['fieldCommitments']);
    },
  );

  test(
    'key rotation or author substitution cannot evade predecessor commitments',
    () async {
      final before = CryptoRecordPolicy.attachSecret({
        'title': 'Task',
        'assigneeAccountIds': [_assignee],
      }, _key);
      final prior = await _policy('task', before);
      final rotated = CryptoRecordPolicy.attachSecret(before, Uint8List(32));
      final newPolicy = await _policy('task', rotated);
      await expectLater(
        CryptoRecordPolicy.verifyPayload(
          record: _record('task', newPolicy),
          payload: rotated,
          previousPayload: before,
          previousPolicy: prior,
        ),
        throwsFormatException,
      );
      await expectLater(
        CryptoRecordPolicy.verifyPayload(
          record: _record('task', {...prior, 'createdByAccountId': _assignee}),
          payload: before,
          previousPayload: before,
          previousPolicy: prior,
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'deletion carries exact predecessor commitments and cannot substitute edited payload',
    () async {
      final raw = CryptoRecordPolicy.attachSecret({
        'title': 'Task',
        'assigneeAccountIds': [_assignee],
      }, _key);
      final prior = await _policy('task', raw);
      final deleted = {...prior, 'operation': 'delete'};
      await CryptoRecordPolicy.verifyPayload(
        record: _record('task', deleted, deleted: true),
        payload: null,
        previousPolicy: prior,
      );
      await expectLater(
        CryptoRecordPolicy.verifyPayload(
          record: _record('task', deleted, deleted: true),
          payload: raw,
          previousPolicy: prior,
        ),
        throwsFormatException,
      );
      await expectLater(
        CryptoRecordPolicy.verifyPayload(
          record: _record('task', {
            ...deleted,
            'fieldCommitments': {
              ...prior['fieldCommitments'],
              'content': '0' * 64,
            },
          }, deleted: true),
          payload: null,
          previousPolicy: prior,
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'accepted predecessor author and assignee rules never grant finance or self-assignment authority',
    () async {
      final raw = CryptoRecordPolicy.attachSecret({
        'title': 'Task',
        'assigneeAccountIds': [_assignee],
      }, _key);
      final prior = await _policy('task', raw);
      final next = await _policy('task', {...raw, 'title': 'Edited'});
      final record = {
        ..._record('task', next),
        'accountId': _assignee,
        'expectedRevision': 1,
      };
      CryptoRecordPolicy.requireAuthority(
        record: record,
        role: 'viewer',
        financeRole: 'none',
        previousPolicy: prior,
        previousAssignees: [_assignee],
      );
      expect(
        () => CryptoRecordPolicy.requireAuthority(
          record: record,
          role: 'member',
          financeRole: 'none',
          previousPolicy: prior,
          previousAssignees: [_creator],
        ),
        throwsFormatException,
      );
      final reassign = await _policy('task', {
        ...raw,
        'assigneeAccountIds': [_creator],
      });
      expect(
        () => CryptoRecordPolicy.requireAuthority(
          record: {
            ...record,
            'metadata': {'recordPolicy': reassign},
          },
          role: 'viewer',
          financeRole: 'none',
          previousPolicy: prior,
          previousAssignees: [_assignee],
        ),
        throwsFormatException,
      );
      expect(
        () => CryptoRecordPolicy.requireAuthority(
          record: {
            ...record,
            'deleted': true,
            'metadata': {
              'recordPolicy': {...prior, 'operation': 'delete'},
            },
          },
          role: 'viewer',
          financeRole: 'none',
          previousPolicy: prior,
          previousAssignees: [_assignee],
        ),
        throwsFormatException,
      );
      expect(
        () => CryptoRecordPolicy.requireAuthority(
          record: {...record, 'domain': 'finance'},
          role: 'owner',
          financeRole: 'read',
          previousPolicy: prior,
          previousAssignees: [_assignee],
        ),
        throwsFormatException,
      );
      final created = {
        ...record,
        'expectedRevision': 0,
        'metadata': {
          'recordPolicy': {
            ...next,
            'operation': 'create',
            'createdByAccountId': _assignee,
          },
        },
      };
      expect(
        () => CryptoRecordPolicy.requireAuthority(
          record: created,
          role: 'viewer',
          financeRole: 'none',
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'new existing record cannot masquerade as create for owner or creator',
    () async {
      final raw = CryptoRecordPolicy.attachSecret({'title': 'Title'}, _key);
      final prior = await _policy('shoppingList', raw);
      final forged = await _policy('shoppingList', raw, operation: 'create');
      final record = {
        ..._record('shoppingList', forged),
        'expectedRevision': 1,
        'accountId': _creator,
      };
      for (final role in ['owner', 'member']) {
        expect(
          () => CryptoRecordPolicy.requireAuthority(
            record: record,
            role: role,
            financeRole: 'none',
            previousPolicy: prior,
          ),
          throwsFormatException,
        );
      }
      await expectLater(
        CryptoRecordPolicy.verifyPayload(
          record: record,
          payload: raw,
          previousPayload: raw,
          previousPolicy: prior,
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'new creation operation remains valid only at initial revision',
    () async {
      final raw = CryptoRecordPolicy.attachSecret({'title': 'Initial'}, _key);
      final policy = await _policy('shoppingList', raw, operation: 'create');
      final record = {
        ..._record('shoppingList', policy),
        'expectedRevision': 0,
        'accountId': _creator,
      };
      CryptoRecordPolicy.requireAuthority(
        record: record,
        role: 'member',
        financeRole: 'none',
      );
      await CryptoRecordPolicy.verifyPayload(record: record, payload: raw);
    },
  );
  test(
    'inline and expanded transport representations have equal MACs but business cells and plaintext hashes remain bound',
    () async {
      final table = CryptoRecordPolicy.attachSecret({
        'title': 'Large table',
        'cells': {'A1': '12', 'cryptoBlob': 'business cell text'},
      }, _key);
      final inline = await _policy('table', table);
      final expanded = await _policy('table', {
        ...table,
        'cryptoPayloadBlob': {'id': 'ciphertext-object'},
        'cryptoBlob': {'id': 'legacy-table-object'},
      });
      expect(expanded['fieldCommitments'], inline['fieldCommitments']);
      final changed = await _policy('table', {
        ...table,
        'cells': {'A1': '12', 'cryptoBlob': 'changed business cell'},
      });
      expect(
        changed['fieldCommitments']['content'],
        isNot(inline['fieldCommitments']['content']),
      );
      final idea = CryptoRecordPolicy.attachSecret({
        'title': 'Idea',
        'elements': [
          {
            'asset': {'sha256': 'a' * 64},
          },
        ],
        'assets': [
          {
            'sha256': 'a' * 64,
            'mime': 'image/png',
            'size': 10,
            'width': 1,
            'height': 1,
          },
        ],
      }, _key);
      final semantic = await _policy('idea', idea);
      final technical = await _policy('idea', {
        ...idea,
        'cryptoPayloadBlob': {'id': 'payload'},
        'assets': [
          {
            'sha256': 'a' * 64,
            'mime': 'image/png',
            'size': 10,
            'width': 1,
            'height': 1,
            'cryptoBlob': {'id': 'encrypted-image'},
          },
        ],
      });
      expect(technical['fieldCommitments'], semantic['fieldCommitments']);
      final changedHash = await _policy('idea', {
        ...idea,
        'elements': [
          {
            'asset': {'sha256': 'b' * 64},
          },
        ],
      });
      expect(
        changedHash['fieldCommitments']['content'],
        isNot(semantic['fieldCommitments']['content']),
      );
    },
  );
  test(
    'explicit restore requires owner or immutable author and preserves predecessor key',
    () async {
      final priorRaw = CryptoRecordPolicy.attachSecret({
        'title': 'Deleted task',
        'assigneeAccountIds': [_assignee],
      }, _key);
      final prior = await _policy('task', priorRaw);
      final tombstone = {...prior, 'operation': 'delete'};
      final restored = {...priorRaw, 'title': 'Retained dirty draft'};
      final policy = await _policy('task', restored, operation: 'restore');
      final tag = {
        'version': 1,
        'tombstoneProofHash': 'a' * 64,
        'previousLiveProofHash': 'b' * 64,
      };
      final record = {
        ..._record('task', policy),
        'expectedRevision': 3,
        'previousRecordHash': 'a' * 64,
        'accountId': _creator,
        'metadata': {'recordPolicy': policy, 'recordRestore': tag},
      };
      CryptoRecordPolicy.requireAuthority(
        record: record,
        role: 'viewer',
        financeRole: 'none',
        previousPolicy: tombstone,
      );
      await CryptoRecordPolicy.verifyPayload(
        record: record,
        payload: restored,
        previousPayload: priorRaw,
        previousPolicy: tombstone,
      );
      expect(
        () => CryptoRecordPolicy.requireAuthority(
          record: {...record, 'accountId': _assignee},
          role: 'member',
          financeRole: 'write',
          previousPolicy: tombstone,
          previousAssignees: [_assignee],
        ),
        throwsFormatException,
      );
      await expectLater(
        CryptoRecordPolicy.verifyPayload(
          record: {
            ...record,
            'metadata': {'recordPolicy': policy},
          },
          payload: restored,
          previousPayload: priorRaw,
          previousPolicy: tombstone,
        ),
        throwsFormatException,
      );
      final changedKey = CryptoRecordPolicy.attachSecret(
        restored,
        Uint8List.fromList(List.filled(32, 99)),
      );
      await expectLater(
        CryptoRecordPolicy.verifyPayload(
          record: record,
          payload: changedKey,
          previousPayload: priorRaw,
          previousPolicy: tombstone,
        ),
        throwsFormatException,
      );
      expect(
        () => CryptoRecordPolicy.requireAuthority(
          record: {...record, 'domain': 'finance'},
          role: 'owner',
          financeRole: 'none',
          previousPolicy: tombstone,
        ),
        throwsFormatException,
      );
    },
  );
}
