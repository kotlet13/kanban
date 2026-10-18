import 'crypto_business_json.dart';
import 'crypto_record_address.dart';

/// Mirrors the signed consent transition enforced by NotificationV2. A date
/// change is separate from closing/reopening/deleting the target or project.
class CryptoConsentGeneration {
  static Map<String, dynamic> transition({
    required Map<String, dynamic> state,
    required Map<String, dynamic>? previous,
    required String field,
    required bool wasDeleted,
    required bool deleted,
    required String Function() mint,
  }) {
    final next = Map<String, dynamic>.from(state);
    final old = previous?['consentGeneration'];
    if (old != null) {
      if (!isCryptoCanonicalUuid(old)) {
        throw const FormatException('crypto_scheduling_consent_generation');
      }
      next['consentGeneration'] =
          wasDeleted != deleted || previous![field] != next[field]
          ? mint()
          : old;
    }
    validate(next, previous, field, wasDeleted, deleted);
    return next;
  }

  /// Called only while preparing a new canonical migration proof, before its
  /// immutable signed request is stored. Accepted stages are never rewritten.
  static void mintCanonical(
    Map<String, dynamic> metadata,
    String Function() mint,
  ) {
    for (final key in const ['reminderState', 'projectState']) {
      final value = metadata[key];
      if (value is Map) {
        metadata[key] = {
          ...Map<String, dynamic>.from(value),
          'consentGeneration': mint(),
        };
      }
    }
  }

  static void validate(
    Map state,
    Map? previous,
    String field,
    bool wasDeleted,
    bool deleted,
  ) {
    final old = previous?['consentGeneration'],
        next = state['consentGeneration'];
    if (old != null && next == null ||
        next != null && !isCryptoCanonicalUuid(next) ||
        next != null &&
            deleted &&
            (state[field] != true ||
                field == 'closed' && state['dueAtEpoch'] != null)) {
      throw const FormatException('crypto_scheduling_consent_generation');
    }
    if (old == null) return;
    final changed = wasDeleted != deleted || previous![field] != state[field];
    if (changed == (old == next)) {
      throw const FormatException('crypto_scheduling_consent_generation');
    }
  }

  /// The encrypted business date remains intact. A null clear date is allowed
  /// on a generation-bearing record without any new or active consent.
  static bool matchesReminder(Map state, Map expected) {
    final shape = Map<String, dynamic>.from(state)
      ..remove('scheduleRevision')
      ..remove('consentGeneration');
    if (state['consentGeneration'] != null &&
        state['dueAtEpoch'] == null &&
        expected['closed'] == false) {
      shape['dueAtEpoch'] = expected['dueAtEpoch'];
    }
    return CryptoBusinessJson.canonical(shape) ==
        CryptoBusinessJson.canonical(expected);
  }

  /// The callback is the existing full target-use verifier, never a SQL or
  /// server active flag. Missing evidence propagates; only a completed lookup
  /// with no usable consent masks the public date. It issues no use or event.
  static Future<Map<String, dynamic>> disclosure(
    Map<String, dynamic> metadata,
    Future<Map<String, dynamic>?> Function(Map<String, dynamic>) verifiedUse,
  ) async {
    final state = metadata['reminderState'];
    if (state is! Map ||
        state['consentGeneration'] == null ||
        state['closed'] != false ||
        state['dueAtEpoch'] == null) {
      return metadata;
    }
    final use = await verifiedUse(metadata);
    final result = Map<String, dynamic>.from(metadata)..remove('schedulingUse');
    if (use != null) {
      result['schedulingUse'] = use;
    } else {
      result['reminderState'] = {...state, 'dueAtEpoch': null};
    }
    return result;
  }
}
