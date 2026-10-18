import 'dart:convert';

import 'package:cryptography/dart.dart' show DartSha256;

import 'crypto_json.dart';

/// The canonical ID belongs to a source namespace. It must never be mistaken
/// for an already derived wire ID, even though both use UUID syntax.
class CryptoRecordAddress {
  CryptoRecordAddress({
    required this.serverId,
    required this.scopeId,
    required this.domain,
    required this.sourceKind,
    required this.canonicalId,
    required this.type,
  }) {
    if (!isCryptoCanonicalUuid(serverId) ||
        !isCryptoCanonicalUuid(scopeId) ||
        !isCryptoCanonicalUuid(canonicalId) ||
        cryptoRecordDomain(type) != domain ||
        cryptoRecordSourceKind(type) != sourceKind) {
      throw const FormatException('crypto_record_identity');
    }
  }
  factory CryptoRecordAddress.forType({
    required String serverId,
    required String scopeId,
    required String type,
    required String canonicalId,
    String? domain,
  }) => CryptoRecordAddress(
    serverId: serverId,
    scopeId: scopeId,
    type: type,
    canonicalId: canonicalId,
    domain: domain ?? cryptoRecordDomain(type),
    sourceKind: cryptoRecordSourceKind(type),
  );
  final String serverId, scopeId, domain, sourceKind, canonicalId, type;
  Map<String, dynamic> get identity => {
    'sourceKind': sourceKind,
    'canonicalId': canonicalId,
  };
  String get wireId {
    final bytes = const DartSha256()
        .hashSync([
          ...utf8.encode('JivieRecordAddress/v2\n'),
          ...CryptoJson.encode({
            'version': 2,
            'serverId': serverId,
            'scopeId': scopeId,
            'domain': domain,
            'sourceKind': sourceKind,
            'canonicalId': canonicalId,
          }),
        ])
        .bytes
        .take(16)
        .toList();
    bytes[6] = (bytes[6] & 0x0f) | 0x80;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final h = bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }
}

String cryptoWireRecordId(
  String serverId,
  String scopeId,
  String type,
  String canonicalId, {
  String? domain,
}) => CryptoRecordAddress.forType(
  serverId: serverId,
  scopeId: scopeId,
  type: type,
  canonicalId: canonicalId,
  domain: domain,
).wireId;

String cryptoRecordDomain(String type) => switch (type) {
  'financeAccount' ||
  'financeEntry' ||
  'financeTransfer' ||
  'personalFinanceEntry' ||
  'personalFinanceAccount' ||
  'financeRecurrenceRule' ||
  'financeAccountChoice' ||
  'paymentEvent' ||
  'paymentProjection' ||
  'cashMovement' ||
  'taskDerivationResolution' => 'finance',
  'idea' ||
  'garden' ||
  'project' ||
  'task' ||
  'shoppingList' ||
  'shoppingItem' ||
  'event' ||
  'householdPerson' ||
  'table' ||
  'attachment' ||
  'ideaAsset' ||
  'scopeMetadata' ||
  'taskDerivationIntent' => 'content',
  _ => throw const FormatException('crypto_record_identity_type'),
};

String cryptoRecordSourceKind(String type) => switch (type) {
  'idea' ||
  'garden' ||
  'project' ||
  'task' ||
  'shoppingList' ||
  'shoppingItem' ||
  'event' ||
  'householdPerson' => 'records',
  'financeAccount' ||
  'financeEntry' ||
  'financeTransfer' ||
  'personalFinanceEntry' ||
  'personalFinanceAccount' ||
  'financeRecurrenceRule' => 'finance_records',
  'table' => 'tables',
  'attachment' => 'attachments',
  'ideaAsset' => 'idea_assets',
  'paymentEvent' => 'payment_events',
  'paymentProjection' => 'payment_projections',
  'cashMovement' => 'payment_cash',
  'scopeMetadata' => 'scope_metadata',
  'taskDerivationIntent' => 'task_derivation_intents',
  'taskDerivationResolution' => 'task_derivation_resolutions',
  'financeAccountChoice' => 'finance_account_choices',
  _ => throw const FormatException('crypto_record_identity_type'),
};

CryptoRecordAddress cryptoRecordAddressFromMetadata(
  Map<String, dynamic> record,
) {
  final metadata = record['metadata'];
  final identity = metadata is Map ? metadata['identity'] : null;
  if (identity is! Map ||
      identity.length != 2 ||
      identity['sourceKind'] is! String ||
      identity['canonicalId'] is! String) {
    throw const FormatException('crypto_record_identity');
  }
  final address = CryptoRecordAddress(
    serverId: record['serverId'],
    scopeId: record['scopeId'],
    domain: record['domain'],
    sourceKind: identity['sourceKind'],
    canonicalId: identity['canonicalId'],
    type: record['type'],
  );
  if (address.wireId != record['id'])
    throw const FormatException('crypto_record_identity');
  return address;
}

/// Wire addresses use RFC9562 custom UUIDv8; scope/account/canonical validators
/// deliberately remain unchanged.
bool isCryptoWireRecordId(Object? value) =>
    value is String &&
    RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-8[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    ).hasMatch(value);

/// Matches the server's canonical scope/account/source UUID boundary.
bool isCryptoCanonicalUuid(Object? value) =>
    value is String &&
    RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    ).hasMatch(value);
