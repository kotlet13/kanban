import 'dart:convert';
import 'organizer_models.dart' show maxMoneyMinor;

enum PaymentProjectionState {
  pending,
  sourceConfirmed,
  complete,
  blocked,
  sourceRemoved,
}

class PaymentSpaceRef {
  const PaymentSpaceRef(this.id, {this.partition});
  final String id;
  final String? partition;
  bool get isLocal => partition == null;
  String get key => isLocal ? 'local:$id' : 'remote:$partition:$id';
  Map<String, Object?> toJson() => {'id': id, 'partition': partition};
  factory PaymentSpaceRef.fromJson(Map<String, dynamic> j) => _space(j);
}

class PaymentSourceRef {
  const PaymentSourceRef({
    required this.space,
    required this.entryId,
    required this.expectedRevision,
  });
  final PaymentSpaceRef space;
  final String entryId;
  final int expectedRevision;
  Map<String, Object?> toJson() => {
    'space': space.toJson(),
    'entryId': entryId,
    'expectedRevision': expectedRevision,
  };
  factory PaymentSourceRef.fromJson(Map<String, dynamic> j) {
    if (j['entryId'] is! String ||
        !_uuid(j['entryId'] as String) ||
        j['expectedRevision'] is! int ||
        (j['expectedRevision'] as int) < 0) {
      throw const FormatException('Invalid payment source');
    }
    return PaymentSourceRef(
      space: PaymentSpaceRef.fromJson(
        Map<String, dynamic>.from(j['space'] as Map),
      ),
      entryId: j['entryId'] as String,
      expectedRevision: j['expectedRevision'] as int,
    );
  }
}

class PaymentReimbursement {
  const PaymentReimbursement({
    required this.legId,
    required this.amountMinor,
    required this.paidAt,
    required this.approvedByAccountId,
    this.organizationAccountId,
    this.organizationAccountScopeId,
  });
  final String legId, approvedByAccountId;
  final String? organizationAccountId;
  final String? organizationAccountScopeId;
  final int amountMinor;
  final DateTime paidAt;
  Map<String, Object?> toJson({bool projection = false}) => {
    'legId': legId,
    'amountMinor': amountMinor,
    'paidAt': paidAt.toUtc().toIso8601String(),
    'approvedByAccountId': approvedByAccountId,
    if (!projection) 'organizationAccountId': organizationAccountId,
    if (!projection) 'organizationAccountScopeId': organizationAccountScopeId,
  };
  factory PaymentReimbursement.fromJson(Map<String, dynamic> j) {
    _date(j['paidAt'] as String);
    return PaymentReimbursement(
      legId: j['legId'] as String,
      amountMinor: _money(j['amountMinor']),
      paidAt: DateTime.parse(j['paidAt'] as String),
      approvedByAccountId: j['approvedByAccountId'] as String,
      organizationAccountId: j['organizationAccountId'] as String?,
      organizationAccountScopeId: j['organizationAccountScopeId'] as String?,
    );
  }
}

class PaymentEvent {
  PaymentEvent({
    required this.eventId,
    required this.sourceScopeId,
    required this.sourceEntryId,
    required this.sourceRevision,
    required this.payerAccountId,
    required this.amountMinor,
    required this.currency,
    required this.paidAt,
    required this.expectReimbursement,
    required this.revision,
    this.sourcePartition,
    Iterable<PaymentReimbursement> reimbursements = const [],
  }) : reimbursements = List.unmodifiable(reimbursements);
  final String eventId, sourceScopeId, sourceEntryId, payerAccountId, currency;
  final String? sourcePartition;
  final int sourceRevision, amountMinor, revision;
  final DateTime paidAt;
  final bool expectReimbursement;
  final List<PaymentReimbursement> reimbursements;
  BigInt get reimbursedTotal => reimbursements.fold(
    BigInt.zero,
    (sum, leg) => sum + BigInt.from(leg.amountMinor),
  );
  int get reimbursedMinor => reimbursedTotal.toInt();
  int get receivableMinor =>
      expectReimbursement ? amountMinor - reimbursedMinor : 0;
  int get cashBurdenMinor => amountMinor - reimbursedMinor;
  Map<String, Object?> toJson() => {
    'eventId': eventId,
    'sourceScopeId': sourceScopeId,
    'sourceEntryId': sourceEntryId,
    'sourceRevision': sourceRevision,
    'payerAccountId': payerAccountId,
    'amountMinor': amountMinor,
    'currency': currency,
    'paidAt': paidAt.toUtc().toIso8601String(),
    'expectReimbursement': expectReimbursement,
    'revision': revision,
    if (sourcePartition != null) 'sourcePartition': sourcePartition,
    'reimbursements': [for (final leg in reimbursements) leg.toJson()],
  };
  factory PaymentEvent.fromJson(Map<String, dynamic> j) {
    _date(j['paidAt'] as String);
    final event = PaymentEvent(
      eventId: j['eventId'] as String,
      sourceScopeId: j['sourceScopeId'] as String,
      sourceEntryId: j['sourceEntryId'] as String,
      sourceRevision: j['sourceRevision'] as int,
      payerAccountId: j['payerAccountId'] as String,
      amountMinor: _money(j['amountMinor']),
      currency: j['currency'] as String,
      paidAt: DateTime.parse(j['paidAt'] as String),
      expectReimbursement: j['expectReimbursement'] as bool,
      revision: j['revision'] as int,
      sourcePartition: j['sourcePartition'] as String?,
      reimbursements: (j['reimbursements'] as List).map(
        (l) =>
            PaymentReimbursement.fromJson(Map<String, dynamic>.from(l as Map)),
      ),
    );
    if (event.reimbursedTotal > BigInt.from(event.amountMinor) ||
        !_uuid(event.eventId) ||
        !_uuid(event.sourceScopeId) ||
        !_uuid(event.sourceEntryId) ||
        !_uuid(event.payerAccountId) ||
        event.reimbursements.length > 500 ||
        event.sourceRevision < 0 ||
        event.revision < 1 ||
        !const ['EUR', 'USD', 'GBP', 'CHF'].contains(event.currency) ||
        (!event.expectReimbursement && event.reimbursements.isNotEmpty) ||
        event.reimbursements.map((l) => l.legId).toSet().length !=
            event.reimbursements.length) {
      throw const FormatException('Invalid reimbursement history');
    }
    for (final leg in event.reimbursements) {
      _date(leg.paidAt.toUtc().toIso8601String());
      if (!_uuid(leg.legId) ||
          !_uuid(leg.approvedByAccountId) ||
          leg.paidAt.isBefore(event.paidAt)) {
        throw const FormatException('Invalid payment reimbursement');
      }
    }
    return event;
  }
}

class PaymentProjection {
  const PaymentProjection({
    required this.event,
    required this.state,
    this.privateAccountId,
  });
  final PaymentEvent event;
  final PaymentProjectionState state;
  final String? privateAccountId;
  String get eventId => event.eventId;
  int get cashBurdenMinor => event.cashBurdenMinor;
  int get receivableMinor =>
      state == PaymentProjectionState.sourceRemoved ? 0 : event.receivableMinor;
  Map<String, Object?> toJson() => {
    ...event.toJson(),
    'paymentRevision': event.revision,
    'reimbursements': [
      for (final leg in event.reimbursements) leg.toJson(projection: true),
    ],
    'state': state.name,
    if (privateAccountId != null) 'privateAccountId': privateAccountId,
  };
  factory PaymentProjection.fromJson(Map<String, dynamic> j) {
    final event = PaymentEvent.fromJson(j);
    if (j['paymentRevision'] != event.revision ||
        (j['privateAccountId'] != null &&
            (j['privateAccountId'] is! String ||
                !_uuid(j['privateAccountId'] as String)))) {
      throw const FormatException('Invalid payment projection');
    }
    return PaymentProjection(
      event: event,
      state: PaymentProjectionState.values.byName(j['state'] as String),
      privateAccountId: j['privateAccountId'] as String?,
    );
  }
}

class PaymentCashMovement {
  const PaymentCashMovement({
    required this.id,
    required this.accountId,
    required this.amountMinor,
    required this.currency,
    required this.paidAt,
  });
  final String id, accountId, currency;
  final int amountMinor;
  final DateTime paidAt;
  Map<String, Object?> toJson() => {
    'id': id,
    'accountId': accountId,
    'amountMinor': amountMinor,
    'currency': currency,
    'paidAt': paidAt.toUtc().toIso8601String(),
  };
  factory PaymentCashMovement.fromJson(Map<String, dynamic> j) {
    final amount = j['amountMinor'];
    if (amount is! int || amount == 0 || amount.abs() > maxMoneyMinor) {
      throw const FormatException('Invalid cash movement');
    }
    if (!_uuid(j['id'] as String) ||
        !_uuid(j['accountId'] as String) ||
        !const ['EUR', 'USD', 'GBP', 'CHF'].contains(j['currency'])) {
      throw const FormatException('Invalid cash movement identity');
    }
    _date(j['paidAt'] as String);
    return PaymentCashMovement(
      id: j['id'] as String,
      accountId: j['accountId'] as String,
      amountMinor: amount,
      currency: j['currency'] as String,
      paidAt: DateTime.parse(j['paidAt'] as String),
    );
  }
}

class PaymentSnapshot {
  PaymentSnapshot({
    Iterable<PaymentEvent> events = const [],
    Iterable<PaymentProjection> projections = const [],
    this.pendingCount = 0,
    Iterable<PaymentCashMovement> cashMovements = const [],
    this.fresh = false,
  }) : events = List.unmodifiable(events),
       cashMovements = List.unmodifiable(cashMovements),
       projections = List.unmodifiable(projections);
  final List<PaymentEvent> events;
  final List<PaymentProjection> projections;
  final List<PaymentCashMovement> cashMovements;

  /// True only for the last complete, authorized fetch or atomic local transaction.
  final bool fresh;
  final int pendingCount;
  bool get complete =>
      pendingCount == 0 &&
      projections.every(
        (p) => const {
          PaymentProjectionState.complete,
          PaymentProjectionState.sourceRemoved,
        }.contains(p.state),
      );
  Map<String, BigInt> get cashBurdenByCurrency =>
      _sum((p) => p.cashBurdenMinor);
  Map<String, BigInt> get receivableByCurrency =>
      _sum((p) => p.receivableMinor);
  Map<String, BigInt> _sum(int Function(PaymentProjection) value) {
    final totals = <String, BigInt>{};
    final seen = <String>{};
    for (final p in projections.where(
      (p) => p.state != PaymentProjectionState.blocked,
    )) {
      final key =
          '${p.event.sourcePartition ?? 'local'}:${p.event.sourceScopeId}:${p.eventId}';
      if (seen.add(key)) {
        totals.update(
          p.event.currency,
          (v) => v + BigInt.from(value(p)),
          ifAbsent: () => BigInt.from(value(p)),
        );
      }
    }
    return Map.unmodifiable(totals);
  }
}

int _money(Object? value) {
  if (value is! int || value <= 0 || value > maxMoneyMinor) {
    throw const FormatException('Invalid payment amount');
  }
  return value;
}

/// Portable backup validates sidecar rows before any transaction or activation.
void validateLinkedPaymentsBackup(Map<String, dynamic> j) {
  if (j.keys.any(
    (k) => !const [
      'events',
      'projections',
      'intents',
      'cashMovements',
    ].contains(k),
  )) {
    throw const FormatException('Unknown linked payment section');
  }
  for (final table in ['events', 'projections', 'intents', 'cashMovements']) {
    final rows = j[table] ?? (table == 'cashMovements' ? const [] : null);
    if (rows is! List || rows.length > 50000) {
      throw const FormatException('Invalid linked payments backup');
    }
    final keys = <String>{};
    for (final raw in rows) {
      final row = Map<String, dynamic>.from(raw as Map);
      if (row['data'] is! String ||
          !keys.add(
            '${row['space_key'] ?? ''}:${row['event_id'] ?? row['movement_id'] ?? row['id']}',
          )) {
        throw const FormatException('Invalid linked payment row');
      }
      final decoded = jsonDecode(row['data'] as String);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Invalid linked payment payload');
      }
      if (table == 'cashMovements') {
        final movement = PaymentCashMovement.fromJson(decoded);
        if (movement.id != row['movement_id'] ||
            row['space_key'] is! String ||
            !(row['space_key'] as String).startsWith(
              RegExp(r'(local:|remote:)'),
            )) {
          throw const FormatException('Invalid cash movement row');
        }
      } else if (table != 'intents') {
        if (row['space_key'] is! String ||
            !(row['space_key'] as String).startsWith(
              RegExp(r'(local:|remote:)'),
            )) {
          throw const FormatException('Invalid linked payment space');
        }
        final event = table == 'events'
            ? PaymentEvent.fromJson(decoded)
            : PaymentProjection.fromJson(decoded).event;
        if (event.eventId != row['event_id'] ||
            !_uuid(event.sourceScopeId) ||
            !_uuid(event.eventId) ||
            !_uuid(event.sourceEntryId) ||
            !_uuid(event.payerAccountId)) {
          throw const FormatException('Invalid linked payment identity');
        }
      } else {
        if (row['id'] is! String ||
            !_uuid(row['id'] as String) ||
            row['state'] is! String ||
            decoded['source'] is! Map) {
          throw const FormatException('Invalid payment intent');
        }
        final source = PaymentSourceRef.fromJson(
          Map<String, dynamic>.from(decoded['source'] as Map),
        );
        if (!const {
              'pending',
              'complete',
              'local_only',
              'waiting_source_publication',
              'quarantine',
            }.contains(row['state']) ||
            decoded['sourceSpaceKey'] != source.space.key) {
          throw const FormatException('Invalid payment intent source');
        }
        for (final key in ['personal', 'household']) {
          if (decoded[key] != null) {
            final target = PaymentSpaceRef.fromJson(
              Map<String, dynamic>.from(decoded[key] as Map),
            );
            if (decoded['${key}SpaceKey'] != target.key) {
              throw const FormatException('Invalid payment intent target');
            }
          }
        }
        for (final key in [
          'personalAccountId',
          'organizationAccountId',
          'deviceId',
        ]) {
          if (decoded[key] != null &&
              (decoded[key] is! String || !_uuid(decoded[key] as String))) {
            throw const FormatException('Invalid payment intent identity');
          }
        }
        if (decoded['organizationAccountScope'] != null) {
          PaymentSpaceRef.fromJson(
            Map<String, dynamic>.from(
              decoded['organizationAccountScope'] as Map,
            ),
          );
        }
        if (decoded['localEvent'] != null) {
          final event = PaymentEvent.fromJson(
            Map<String, dynamic>.from(decoded['localEvent'] as Map),
          );
          if (event.sourceScopeId != source.space.id ||
              event.sourceEntryId != source.entryId) {
            throw const FormatException('Invalid local payment intent');
          }
        }
        if (decoded['params'] is Map) {
          final params = Map<String, dynamic>.from(decoded['params'] as Map);
          _validatePaymentIntentParams(decoded['operation'] as String, params);
          if (params['requestId'] != row['id'] ||
              params['scopeId'] != source.space.id ||
              (params['entryId'] != null &&
                  params['entryId'] != source.entryId)) {
            throw const FormatException('Invalid payment intent request');
          }
        }
        for (final refund in (decoded['refunds'] as List? ?? const [])) {
          _validatePaymentIntentParams(
            'finance3.paymentReimburse',
            Map<String, dynamic>.from(refund as Map),
          );
        }
        for (final entry
            in (decoded['refundRequests'] as Map? ?? const {}).entries) {
          if (entry.key is! String ||
              entry.value is! String ||
              !_uuid(entry.key as String) ||
              !_uuid(entry.value as String)) {
            throw const FormatException('Invalid deferred refund request');
          }
        }
      }
    }
  }
}

void _validatePaymentIntentParams(
  String operation,
  Map<String, dynamic> params,
) {
  final required = switch (operation) {
    'finance3.paymentCommit' => {
      'scopeId',
      'entryId',
      'expectedEntryRevision',
      'eventId',
      'paidAt',
      'expectReimbursement',
      'requestId',
    },
    'finance3.paymentReimburse' => {
      'scopeId',
      'eventId',
      'expectedRevision',
      'legId',
      'amountMinor',
      'paidAt',
      'organizationAccountId',
      'requestId',
    },
    'finance3.paymentProject' => {
      'scopeId',
      'eventId',
      'expectedRevision',
      'requestId',
    },
    _ => throw const FormatException('Invalid payment operation'),
  };
  final optional = operation == 'finance3.paymentReimburse'
      ? {'organizationAccountScopeId'}
      : {'personalTarget', 'householdScopeId'};
  if (!params.keys.toSet().containsAll(required) ||
      params.keys.any(
        (key) => !required.contains(key) && !optional.contains(key),
      )) {
    throw const FormatException('Invalid payment parameters');
  }
  for (final key in [
    'scopeId',
    'entryId',
    'eventId',
    'legId',
    'requestId',
    'organizationAccountId',
    'organizationAccountScopeId',
    'householdScopeId',
  ]) {
    if (params[key] != null &&
        (params[key] is! String || !_uuid(params[key] as String))) {
      throw const FormatException('Invalid payment parameter identity');
    }
  }
  final revision =
      params['expectedEntryRevision'] ?? params['expectedRevision'];
  if (revision is! int || revision < 1) {
    throw const FormatException('Invalid payment revision');
  }
  if (params['paidAt'] != null) _date(params['paidAt'] as String);
  if (operation == 'finance3.paymentCommit' &&
      params['expectReimbursement'] is! bool) {
    throw const FormatException('Invalid reimbursement choice');
  }
  if (operation == 'finance3.paymentReimburse') _money(params['amountMinor']);
  if (params['personalTarget'] != null) {
    final target = Map<String, dynamic>.from(params['personalTarget'] as Map);
    if (target.length != 2 ||
        !_uuid(target['scopeId'] as String) ||
        !_uuid(target['accountId'] as String)) {
      throw const FormatException('Invalid private payment target');
    }
  }
}

bool _uuid(String value) => RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
).hasMatch(value);

PaymentSpaceRef _space(Map<String, dynamic> j) {
  final id = j['id'] as String, partition = j['partition'] as String?;
  if ((id != 'local' && !_uuid(id)) ||
      (partition != null && (partition.isEmpty || partition.length > 5000))) {
    throw const FormatException('Invalid payment space');
  }
  return PaymentSpaceRef(id, partition: partition);
}

void _date(String value) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})T').firstMatch(value);
  final parsed = DateTime.tryParse(value);
  if (match == null || parsed == null) {
    throw const FormatException('Invalid payment date');
  }
  final year = int.parse(match[1]!),
      month = int.parse(match[2]!),
      day = int.parse(match[3]!);
  final civil = DateTime.utc(year, month, day);
  if (civil.year != year || civil.month != month || civil.day != day) {
    throw const FormatException('Invalid payment calendar date');
  }
}

/// Immutable receipts cannot move a known refund history backwards.
bool shouldReplacePaymentEvent(PaymentEvent old, PaymentEvent incoming) {
  if (incoming.revision < old.revision) return false;
  final previous = old.toJson(), next = incoming.toJson();
  previous.remove('sourcePartition');
  next.remove('sourcePartition');
  if (incoming.revision == old.revision &&
      jsonEncode(previous) != jsonEncode(next)) {
    throw const FormatException('Conflicting payment revision');
  }
  return incoming.revision > old.revision ||
      (old.sourcePartition == null && incoming.sourcePartition != null);
}

bool paymentFinancialFactsMatch(
  Map<String, dynamic> previous,
  Map<String, Object?> incoming,
) {
  for (final key in {...previous.keys, ...incoming.keys}) {
    if (const {
      'title',
      'notes',
      'category',
      'plannedAt',
      'updatedAt',
      'revision',
      'createdByAccountId',
      'updatedByAccountId',
    }.contains(key)) {
      continue;
    }
    final old = previous[key], next = incoming[key];
    if (const {'paidAt', 'occurredAt', 'createdAt'}.contains(key) &&
        old is String &&
        next is String) {
      if (DateTime.parse(old) != DateTime.parse(next)) return false;
    } else if (jsonEncode(old) != jsonEncode(next)) {
      return false;
    }
  }
  return true;
}
