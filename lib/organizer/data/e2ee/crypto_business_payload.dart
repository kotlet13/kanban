import 'crypto_record_policy.dart';
import 'dart:convert';

import '../../domain/collaboration_models.dart';
import '../../domain/shared_finance_validation.dart';
import '../../domain/shared_payload_validation.dart';

/// Full authenticated JSON survives every edit. The UI's existing known model
/// is a separate validated projection; its serializer never becomes the archive.
abstract final class CryptoBusinessPayload {
  static Map<String, dynamic> projection(
    String domain,
    String type,
    Map<String, dynamic> raw, {
    bool personal = false,
  }) {
    raw = CryptoRecordPolicy.businessPayload(raw);
    if (domain == 'content') {
      final kind = SharedRecordType.values
          .where((t) => t.name == type)
          .firstOrNull;
      if (kind == null) {
        throw const FormatException('crypto_content_type_pending');
      }
      if (kind == SharedRecordType.idea || kind == SharedRecordType.garden) {
        final semantic = kind == SharedRecordType.idea ? _idea(raw) : raw;
        validateSharedPayload(
          kind,
          semantic,
          contractVersion: 6,
          personal: personal,
        );
        return _copy(semantic);
      }
      final keys = sharedPayloadKnownKeys(kind, raw, 6);
      final value = <String, dynamic>{
        for (final key in keys)
          if (raw.containsKey(key)) key: raw[key],
      };
      if (kind == SharedRecordType.project && value['phases'] is List) {
        value['phases'] = [
          for (final phase in value['phases'] as List)
            if (phase is Map)
              {
                for (final key in [
                  'id',
                  'title',
                  'milestone',
                  'startAt',
                  'endAt',
                ])
                  if (phase.containsKey(key)) key: phase[key],
              }
            else
              phase,
        ];
      }
      if (kind == SharedRecordType.task && value['timer'] is Map) {
        final timer = value['timer'] as Map;
        value['timer'] = {
          for (final key in ['elapsedSeconds', 'runningSince', 'runId'])
            if (timer.containsKey(key)) key: timer[key],
        };
      }
      validateSharedPayload(
        kind,
        value,
        contractVersion: 6,
        personal: personal,
      );
      return _copy(value);
    }
    if (domain == 'finance') {
      final kind = SharedFinanceRecordType.values
          .where((t) => t.name == type)
          .firstOrNull;
      if (kind == null) {
        throw const FormatException('crypto_finance_type_pending');
      }
      final keys = {
        ...sharedFinancePlanningKnownKeys(kind),
        if (kind == SharedFinanceRecordType.financeEntry) ...[
          'accountScopeId',
          'projectId',
        ],
      };
      final value = <String, dynamic>{
        for (final key in keys)
          if (raw.containsKey(key)) key: raw[key],
      };
      validateSharedFinancePayload(kind, value, contractVersion: 3);
      return _copy(value);
    }
    throw const FormatException('crypto_business_domain');
  }

  /// The encrypted payload retains future fields and validated transport
  /// descriptors. The strict existing board parser sees only its known schema.
  static Map<String, dynamic> _idea(Map<String, dynamic> raw) {
    Map<String, dynamic> known(Map value, List<String> keys) => {
      for (final key in keys)
        if (value.containsKey(key)) key: value[key],
    };
    final board = known(raw, [
      'version',
      'archived',
      'id',
      'title',
      'projectId',
      'width',
      'height',
      'elements',
      'revision',
      'createdAt',
      'updatedAt',
    ]);
    if (raw['version'] != 2) board.remove('archived');
    if (board['elements'] is List) {
      board['elements'] = [
        for (final value in board['elements'] as List)
          if (value is Map)
            <String, dynamic>{
              ...known(value, [
                'id',
                'kind',
                'fontSize',
                'x',
                'y',
                'width',
                'height',
                'rotation',
                'color',
                'strokeWidth',
                'text',
                'points',
                'parentImageId',
                'asset',
              ]),
              if (value['points'] is List)
                'points': [
                  for (final point in value['points'] as List)
                    if (point is Map) known(point, ['x', 'y']) else point,
                ],
              if (value['asset'] is Map)
                'asset': known(value['asset'] as Map, [
                  'sha256',
                  'mime',
                  'size',
                  'width',
                  'height',
                ]),
            }
          else
            value,
      ];
    }
    return board;
  }

  /// Lists of identified records merge by stable IDs. For arrays without IDs,
  /// preserve the exact raw array only when every known projected value is
  /// unchanged. A changed or reordered array has no inferred item identity.
  static Object? merge(Object? previous, Object? changed) {
    if (previous is Map && changed is Map) {
      return <String, dynamic>{
        for (final entry in previous.entries) entry.key as String: entry.value,
        for (final entry in changed.entries)
          entry.key as String: merge(previous[entry.key], entry.value),
      };
    }
    if (previous is List &&
        changed is List &&
        !changed.every((v) => v is Map && v['id'] is String) &&
        _unchangedProjection(previous, changed)) {
      return jsonDecode(jsonEncode(previous));
    }
    if (previous is List &&
        changed is List &&
        changed.every((v) => v is Map && v['id'] is String)) {
      final old = <String, Map>{
        for (final item in previous)
          if (item is Map && item['id'] is String) item['id'] as String: item,
      };
      return [
        for (final item in changed) merge(old[(item as Map)['id']], item),
      ];
    }
    return changed;
  }

  static bool _unchangedProjection(Object? raw, Object? projected) {
    if (raw is Map && projected is Map) {
      return projected.entries.every(
        (entry) =>
            raw.containsKey(entry.key) &&
            _unchangedProjection(raw[entry.key], entry.value),
      );
    }
    if (raw is List && projected is List) {
      if (raw.length != projected.length) return false;
      for (var i = 0; i < raw.length; i++) {
        if (!_unchangedProjection(raw[i], projected[i])) return false;
      }
      return true;
    }
    return raw == projected;
  }

  static Map<String, dynamic> _copy(Map<String, dynamic> value) =>
      jsonDecode(jsonEncode(value)) as Map<String, dynamic>;
}
