import 'dart:convert';

import '../../domain/linked_payment_models.dart';
import 'crypto_record_address.dart';

/// Captured legacy facts only. The caller retains the complete typed row and
/// must verify its blinded capture/source authority before projecting this DTO.
/// No current grant, issuer certificate or modern payment link is invented.
class CryptoMigrationPaymentSource {
  const CryptoMigrationPaymentSource({
    required this.scopeId,
    required this.canonicalId,
    required this.type,
    required this.legacyRevision,
    required this.rawPayload,
  });
  final String scopeId, canonicalId, type;
  final int legacyRevision;
  bool get deleted => false;
  final Map<String, dynamic> rawPayload;
}

/// Called only after the core has verified the migration certificate and exact
/// detached typed witness. A raw flag, SQL row or old device signature cannot
/// supply [origin]. Modern ordinary payment issuance retains its own validator.
Map<String, dynamic> validateCryptoMigrationPaymentBaseline({
  required Map<String, dynamic> origin,
  required Map<String, dynamic> record,
  required String recordProofHash,
  required Map<String, dynamic> raw,
}) {
  final type = record['type'];
  final table = switch (type) {
    'paymentEvent' => 'familyhub_payment_events',
    'paymentProjection' => 'familyhub_payment_projections',
    'cashMovement' => 'familyhub_payment_cash',
    _ => null,
  };
  if (table == null ||
      origin['captureVersion'] != 3 ||
      origin['sourceTable'] != table ||
      origin['type'] != type ||
      origin['scopeId'] != record['scopeId'] ||
      origin['domain'] != 'finance' ||
      record['domain'] != 'finance' ||
      origin['wireId'] != record['id'] ||
      origin['canonicalId'] != record['metadata']['identity']['canonicalId'] ||
      origin['sourceId'] != origin['canonicalId'] ||
      origin['sourceKind'] != cryptoRecordSourceKind(type as String) ||
      origin['recordProofHash'] != recordProofHash ||
      (origin['materializationRole'] ?? 'primary') != 'primary' ||
      record['expectedRevision'] != 0 ||
      record['deleted'] != false) {
    throw const FormatException('crypto_migration_payment_origin');
  }
  if (type == 'cashMovement') {
    PaymentCashMovement.fromJson(raw);
    if (raw['id'] != origin['canonicalId'] || origin['legacyRevision'] != 1) {
      throw const FormatException('crypto_migration_payment_coordinate');
    }
  } else {
    final event = PaymentEvent.fromJson(raw);
    if (event.eventId != origin['canonicalId'] ||
        event.revision != origin['legacyRevision'] ||
        type == 'paymentEvent' && event.sourceScopeId != record['scopeId']) {
      throw const FormatException('crypto_migration_payment_coordinate');
    }
    if (type == 'paymentProjection') PaymentProjection.fromJson(raw);
  }
  return raw;
}

CryptoMigrationPaymentSource decodeCryptoMigrationPaymentSource({
  required String table,
  required Map<String, dynamic> row,
}) {
  String text(String column) {
    final cell = row[column];
    if (cell is! Map ||
        cell.length != 2 ||
        cell['type'] is! String ||
        (cell['type'] as String).isEmpty ||
        (cell['type'] as String).length > 128 ||
        cell['valueBase64'] is! String) {
      throw const FormatException('crypto_migration_payment_cell');
    }
    final encoded = cell['valueBase64'] as String;
    final bytes = base64Decode(encoded);
    if (base64Encode(bytes) != encoded) {
      throw const FormatException('crypto_migration_payment_cell');
    }
    return utf8.decode(bytes);
  }

  String uuid(String column) {
    final value = text(column);
    if (!isCryptoCanonicalUuid(value)) {
      throw const FormatException('crypto_migration_payment_identity');
    }
    return value;
  }

  if (!const {
    'familyhub_payment_events',
    'familyhub_payment_projections',
    'familyhub_payment_cash',
  }.contains(table)) {
    throw const FormatException('crypto_migration_payment_table');
  }
  final scope = uuid('scope_id');
  final data = jsonDecode(text('data'));
  if (data is! Map<String, dynamic>) {
    throw const FormatException('crypto_migration_payment_data');
  }
  final raw = Map<String, dynamic>.from(data);
  late String id, type;
  late int revision;
  if (table == 'familyhub_payment_cash') {
    id = uuid('movement_id');
    type = 'cashMovement';
    revision = 1; // Immutable old cash facts have no revision column.
    PaymentCashMovement.fromJson(raw);
    if (raw['id'] != id || !isCryptoCanonicalUuid(raw['accountId'])) {
      throw const FormatException('crypto_migration_payment_coordinate');
    }
  } else {
    id = uuid('event_id');
    final event = PaymentEvent.fromJson(raw);
    if (event.eventId != id ||
        ![
          event.sourceScopeId,
          event.sourceEntryId,
          event.payerAccountId,
        ].every(isCryptoCanonicalUuid) ||
        event.reimbursements.any(
          (leg) =>
              !isCryptoCanonicalUuid(leg.legId) ||
              !isCryptoCanonicalUuid(leg.approvedByAccountId) ||
              leg.organizationAccountId != null &&
                  !isCryptoCanonicalUuid(leg.organizationAccountId) ||
              leg.organizationAccountScopeId != null &&
                  !isCryptoCanonicalUuid(leg.organizationAccountScopeId),
        )) {
      throw const FormatException('crypto_migration_payment_coordinate');
    }
    revision = event.revision;
    if (table == 'familyhub_payment_events') {
      type = 'paymentEvent';
      final number = text('revision');
      if (!RegExp(r'^[1-9][0-9]*$').hasMatch(number) ||
          int.tryParse(number) != revision ||
          event.sourceScopeId != scope ||
          event.sourceEntryId != uuid('entry_id') ||
          event.payerAccountId != uuid('payer_account_id')) {
        throw const FormatException('crypto_migration_payment_coordinate');
      }
    } else {
      type = 'paymentProjection';
      final projection = PaymentProjection.fromJson(raw);
      if (projection.event.sourceScopeId != uuid('source_scope_id') ||
          projection.event.payerAccountId != uuid('owner_account_id') ||
          projection.privateAccountId != null &&
              !isCryptoCanonicalUuid(projection.privateAccountId)) {
        throw const FormatException('crypto_migration_payment_coordinate');
      }
    }
  }
  // Validate with models, return the original map. Unknown top-level/nested
  // fields, fractional extensions and exact date strings survive unchanged.
  return CryptoMigrationPaymentSource(
    scopeId: scope,
    canonicalId: id,
    type: type,
    legacyRevision: revision,
    rawPayload: Map<String, dynamic>.unmodifiable(raw),
  );
}
