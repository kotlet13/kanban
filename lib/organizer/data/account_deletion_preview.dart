import 'dart:convert';
import '../domain/collaboration_models.dart';
import '../domain/shared_payload_validation.dart';

/// Decode the complete policy-v1 review before presenting destructive controls.
Map<String, dynamic> decodeAccountDeletionPreview(
  Map<String, dynamic> wire,
  AccountSession profile,
) {
  Never invalid() => throw const CollaborationException('invalid_response');
  bool text(Object? v, {bool nullable = false}) =>
      (nullable && v == null) ||
      (v is String && v.length <= 5000 && !v.contains('\u0000'));
  List<Map<String, dynamic>> rows(String key) {
    final value = wire[key];
    if (value is! List ||
        value.length > 10000 ||
        value.any((v) => v is! Map<String, dynamic>)) {
      invalid();
    }
    return value.cast<Map<String, dynamic>>();
  }

  if (wire['serverId'] != profile.serverId ||
      wire['accountId'] != profile.accountId ||
      wire['policyVersion'] != 1 ||
      wire['canDelete'] is! bool ||
      wire['previewHash'] is! String ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch(wire['previewHash'] as String)) {
    invalid();
  }
  final impact = wire['impact'];
  if (impact is! Map<String, dynamic> ||
      impact.length > 100 ||
      impact.entries.any(
        (e) =>
            !RegExp(r'^[A-Za-z][A-Za-z0-9]{0,80}$').hasMatch(e.key) ||
            e.value is! int ||
            (e.value as int) < 0 ||
            (e.value as int) > 9000000000000,
      )) {
    invalid();
  }
  final blockers = rows('blockers');
  for (final b in blockers) {
    if (b['code'] is! String ||
        !RegExp(r'^[a-z_]{1,100}$').hasMatch(b['code'] as String) ||
        b['count'] is! int ||
        (b['count'] as int) < 1 ||
        (b['scopeId'] != null && !isSharedUuid(b['scopeId']))) {
      invalid();
    }
  }
  if (wire['canDelete'] == true && blockers.isNotEmpty) invalid();
  for (final s in rows('sharedScopes')) {
    if (!isSharedUuid(s['id']) ||
        !text(s['name']) ||
        !const ['household', 'project'].contains(s['kind']) ||
        !const ['owner', 'member', 'viewer'].contains(s['role'])) {
      invalid();
    }
  }
  final ownedIds = <String>{};
  for (final s in rows('ownedScopes')) {
    if (!isSharedUuid(s['id']) ||
        !ownedIds.add(s['id'] as String) ||
        !text(s['name']) ||
        !const ['household', 'project'].contains(s['kind']) ||
        s['canDeleteScope'] is! bool ||
        s['eligibleSuccessors'] is! List ||
        (s['eligibleSuccessors'] as List).length > 10000) {
      invalid();
    }
    final members = <String>{};
    for (final value in s['eligibleSuccessors'] as List) {
      if (value is! Map<String, dynamic> ||
          !isSharedUuid(value['accountId']) ||
          value['accountId'] == profile.accountId ||
          !members.add(value['accountId'] as String) ||
          !text(value['displayName'])) {
        invalid();
      }
    }
  }
  final resolutionIds = <String>{};
  for (final r in rows('resolutions')) {
    if (!isSharedUuid(r['scopeId']) ||
        !isSharedUuid(r['recordId']) ||
        !resolutionIds.add('${r['scopeId']}:${r['recordId']}') ||
        !const ['shoppingList', 'financeAccount'].contains(r['type']) ||
        r['action'] != 'preserveStructure' ||
        !text(r['name'], nullable: true)) {
      invalid();
    }
    if (r.containsKey('currency') || r.containsKey('openingBalanceMinor')) {
      if (r['type'] != 'financeAccount' ||
          !const ['EUR', 'USD', 'GBP', 'CHF'].contains(r['currency']) ||
          r['openingBalanceMinor'] is! int ||
          (r['openingBalanceMinor'] as int).abs() > 9000000000000) {
        invalid();
      }
    }
  }
  return jsonDecode(jsonEncode(wire)) as Map<String, dynamic>;
}
