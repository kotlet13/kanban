import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/e2ee/crypto_project_relocation_graph.dart';

String id(int n) =>
    '00000000-0000-4000-a000-${n.toRadixString(16).padLeft(12, '0')}';
String wire(int n) =>
    '00000000-0000-8000-a000-${n.toRadixString(16).padLeft(12, '0')}';
CryptoRelocationRecord row(
  int n,
  String type,
  Map<String, dynamic> raw, {
  bool deleted = false,
  int logical = 9,
}) => CryptoRelocationRecord(
  id: id(n),
  wireId: wire(n),
  type: type,
  revision: 3,
  logicalRevision: logical,
  proofHash: n.toRadixString(16).padLeft(64, '0'),
  deleted: deleted,
  raw: raw,
);

void main() {
  test(
    'large finite graph preserves source revisions and unknown payloads',
    () async {
      final project = row(1, 'project', {'title': 'One'});
      final source = <CryptoRelocationRecord>[
        project,
        for (var n = 2; n <= 53; n++)
          row(n, 'task', {
            'projectId': id(1),
            'future': {'x': 1.25},
          }),
        row(100, 'task', {'projectId': id(99)}),
      ];
      final result = CryptoProjectRelocationGraph.select(
        projectId: id(1),
        inventory: source,
        paymentHistory: [],
      );
      expect(result.canApply, true);
      expect(result.records.length, 53);
      expect(result.records.last.logicalRevision, 9);
      expect(result.records[1].raw!['future'], {'x': 1.25});
      expect(result.records.any((r) => r.id == id(100)), false);
      final vector =
          jsonDecode(
                File(
                  'server/tests/fixtures/e2ee-project-relocation-v2.json',
                ).readAsStringSync(),
              )
              as Map;
      expect(await result.root, vector['root']);
      final reversed = CryptoProjectRelocationGraph.select(
        projectId: id(1),
        inventory: source.reversed.toList(),
        paymentHistory: [],
      );
      expect(await result.root, await reversed.root);
      // The commitment does not expose/guess low-entropy plaintext values.
      final changedPayload = CryptoProjectRelocationGraph.select(
        projectId: id(1),
        inventory: [
          project,
          ...source
              .skip(1)
              .map(
                (r) => row(int.parse(r.id.split('-').last, radix: 16), r.type, {
                  ...r.raw!,
                  'title': 'Another name',
                }),
              ),
        ],
        paymentHistory: [],
      );
      expect(await changedPayload.root, await result.root);
    },
  );

  test(
    'exclusive task costs follow account and recurrence, shared ones block',
    () {
      final source = [
        row(1, 'project', {}),
        row(2, 'task', {'projectId': id(1)}),
        row(3, 'financeEntry', {
          'taskId': id(2),
          'ledgerAccountId': id(4),
          'recurrenceRuleId': id(5),
        }),
        row(4, 'financeAccount', {'name': 'Account'}),
        row(5, 'financeRecurrenceRule', {'ledgerAccountId': id(4)}),
        row(6, 'financeEntry', {'ledgerAccountId': id(4)}),
      ];
      final result = CryptoProjectRelocationGraph.select(
        projectId: id(1),
        inventory: source,
        paymentHistory: [],
      );
      expect(
        result.records.map((r) => r.id),
        containsAll([id(3), id(4), id(5)]),
      );
      expect(result.records.any((r) => r.id == id(6)), false);
      expect(
        result.blockers,
        contains(
          equals({'code': 'project_finance_account_shared', 'recordId': id(6)}),
        ),
      );
    },
  );

  test(
    'external transfer and shared person never follow graph automatically',
    () {
      final result = CryptoProjectRelocationGraph.select(
        projectId: id(1),
        inventory: [
          row(1, 'project', {}),
          row(2, 'task', {'projectId': id(1), 'assigneePersonId': id(8)}),
          row(3, 'financeEntry', {'taskId': id(2), 'ledgerAccountId': id(4)}),
          row(4, 'financeAccount', {}),
          row(5, 'financeTransfer', {
            'fromAccountId': id(4),
            'toAccountId': id(9),
          }),
          row(6, 'task', {'projectId': id(99), 'assigneePersonId': id(8)}),
          row(8, 'householdPerson', {}),
        ],
        paymentHistory: [],
      );
      expect(
        result.blockers.map((b) => b['code']),
        containsAll(['project_person_shared', 'project_transfer_cross_scope']),
      );
      expect(result.records.any((r) => r.id == id(5) || r.id == id(6)), false);
    },
  );

  test('cancelled and tombstoned payment history remains a blocker', () {
    final result = CryptoProjectRelocationGraph.select(
      projectId: id(1),
      inventory: [
        row(1, 'project', {}),
        row(2, 'task', {'projectId': id(1)}),
        row(3, 'financeEntry', {'taskId': id(2)}),
      ],
      paymentHistory: [
        row(20, 'paymentEvent', {
          'sourceEntryId': id(3),
          'sourceState': 'cancelled',
        }, deleted: true),
      ],
    );
    expect(result.blockers, [
      {'code': 'project_linked_payment_dependency', 'recordId': id(20)},
    ]);
  });

  test('duplicate inventory and capacity failure precede any staging', () {
    final project = row(1, 'project', {});
    expect(
      () => CryptoProjectRelocationGraph.select(
        projectId: id(1),
        inventory: [project, project],
        paymentHistory: [],
      ),
      throwsFormatException,
    );
    expect(
      () => CryptoProjectRelocationGraph.select(
        projectId: id(1),
        inventory: [
          project,
          row(2, 'task', {'projectId': id(1)}),
        ],
        paymentHistory: [],
        maximumRecords: 1,
      ),
      throwsFormatException,
    );
  });
}
