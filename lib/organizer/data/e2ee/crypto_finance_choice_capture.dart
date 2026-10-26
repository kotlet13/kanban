import 'dart:convert';

import 'crypto_business_json.dart';
import 'crypto_capture_archive.dart';
import 'crypto_capture_v3.dart';
import 'crypto_finance_choice_selection_codec.dart';
import 'crypto_json.dart';
import 'crypto_migration_cold_business.dart';
import 'crypto_migration_record_source.dart';
import 'scope_crypto_codec.dart';

/// A closed transformation result, not ordinary record or issuer authority.
/// The caller must additionally refold its complete FILE source inventory and
/// bind this exact raw hash into the finalized companion/domain publication.
class VerifiedCapturedFinanceAccountChoices {
  VerifiedCapturedFinanceAccountChoices._(this.raw, this.rawHash, this.choices);
  final Map<String, dynamic> raw;
  final String rawHash;
  final List<Map<String, dynamic>> choices;
}

/// The Capture3 variant retains the same sanitized whole-selection meaning.
/// Its source checkpoint is the exact frozen capture root, not a fabricated
/// ordinary checkpoint or an export certificate issued before cutover.
class CryptoFinanceChoiceCapture {
  static const variant = CryptoFinanceChoiceSelectionCodec.variant;
  static const hashDomain = 'JivieFinanceAccountChoiceCapture/v3\n';

  static bool isSourceMaterializer(VerifiedScopeHead head, String accountId) {
    final eligible =
        head.members
            .where((m) => const {'read', 'write'}.contains(m['financeRole']))
            .toList()
          ..sort(
            (a, b) =>
                (a['accountId'] as String).compareTo(b['accountId'] as String),
          );
    final owner = eligible.where((m) => m['role'] == 'owner').firstOrNull;
    return (owner ?? eligible.firstOrNull)?['accountId'] == accountId;
  }

  /// Issuer side: the target coordinates are an intended destination, not a
  /// claim to target authority. The target manager must endorse their exact
  /// hash separately. No target archive or target business row is opened here.
  static Future<Map<String, dynamic>> deriveSourceSelection({
    required String serverId,
    required String sourceAccountId,
    required VerifiedCryptoCaptureArchive sourceArchive,
    required List<CryptoMigrationColdSource> sourceParentAccountRows,
    required VerifiedScopeHead exactSourceHead,
    required Map<String, dynamic> targetContext,
    required CryptoCaptureBinding childBinding,
    required String selectionSaltBase64,
    required Future<String> Function(String, String) reservedId,
  }) async {
    if (!isSourceMaterializer(exactSourceHead, sourceAccountId) ||
        exactSourceHead.epoch != 1 ||
        exactSourceHead.body['previousHeadHash'] != '0' * 64 ||
        exactSourceHead.body['accessIntentProof'] != null ||
        exactSourceHead.body['financePolicyIntentProof'] != null ||
        !const {
          'read',
          'write',
        }.contains(exactSourceHead.member(sourceAccountId)['financeRole']) ||
        !(sourceArchive.capture.scopeIds.contains(exactSourceHead.scopeId) ||
            sourceArchive.capture.receiptSelections.any(
              (s) =>
                  s['scopeId'] == exactSourceHead.scopeId &&
                  s['domain'] == 'finance',
            ))) {
      throw const FormatException('crypto_account_choices_capture_source');
    }
    final choices = <Map<String, dynamic>>[], seen = <String>{};
    for (final row in sourceParentAccountRows) {
      final c = row.context;
      if (c.serverId != serverId ||
          c.accountId != sourceAccountId ||
          c.scopeId != exactSourceHead.scopeId ||
          c.domain != 'finance' ||
          c.sourceTable != 'familyhub_finance_records' ||
          c.captureId != sourceArchive.capture.captureId ||
          c.migrationId != sourceArchive.capture.migrationId ||
          row.binding.scopeId != c.scopeId ||
          row.binding.domain != 'finance' ||
          !seen.add(row.binding.bindingId)) {
        throw const FormatException('crypto_account_choices_capture_source');
      }
      final source = await CryptoMigrationRecordSource.decode(
        table: c.sourceTable,
        domain: c.domain,
        row: row.typedRow,
        serverId: serverId,
        reservedId: reservedId,
      );
      if (source.deleted || source.type != 'financeAccount') continue;
      final raw = source.rawPayload!;
      choices.add({
        'accountId': source.canonicalId,
        'accountScopeId': source.scopeId,
        'archived': raw['archived'],
        'currency': raw['currency'],
        'name': raw['name'],
        'sourceRevision': source.legacyRevision,
      });
      if (choices.length > 5000) {
        throw const FormatException('crypto_account_choices_capture_capacity');
      }
    }
    choices.sort(
      (a, b) => (a['accountId'] as String).compareTo(b['accountId'] as String),
    );
    final selection = {
      'context': {
        'version': 3,
        'purpose': 'financeAccountChoice',
        'serverId': serverId,
        'source': {
          'migrationId': sourceArchive.capture.migrationId,
          'captureId': sourceArchive.capture.captureId,
          'accountId': sourceAccountId,
          'sourceInventoryRoot': sourceArchive.sourceInventoryRoot,
          'scopeId': exactSourceHead.scopeId,
          'membershipHeadHash': exactSourceHead.headHash,
        },
        'target': Map<String, dynamic>.from(targetContext),
        'childBinding': childBinding.toJson(),
      },
      'choices': CryptoFinanceChoiceSelectionCodec.choices(
        choices,
        exactSourceHead.scopeId,
      ),
      'selectionSaltBase64': selectionSaltBase64,
    };
    final raw = {
      'version': 2,
      'variant': variant,
      'capture3': selection,
      'selectionHash': await selectionHash(selection),
    };
    validate(raw);
    if (targetContext['migrationId'] != sourceArchive.capture.migrationId ||
        CryptoBusinessJson.encode(raw).length > 190000) {
      throw const FormatException('crypto_account_choices_capture_context');
    }
    return raw;
  }

  /// Target side: checks only its own exact frozen financial row and the
  /// sanitized disclosure. Source derivation authority comes from the issuer
  /// signature and exact manager endorsement, never an imported parent FILE.
  static Future<void> verifyTargetSelection(
    Map<String, dynamic> raw, {
    required CryptoMigrationColdSource childSource,
    required VerifiedCryptoCaptureArchive childArchive,
    required VerifiedScopeHead exactTargetHead,
    required Future<String> Function(String, String) reservedId,
  }) async {
    validate(raw);
    final selection = Map<String, dynamic>.from(raw['capture3'] as Map),
        context = Map<String, dynamic>.from(selection['context'] as Map),
        c = childSource.context;
    final target = {
      'migrationId': c.migrationId,
      'captureId': c.captureId,
      'accountId': c.accountId,
      'sourceInventoryRoot': childArchive.sourceInventoryRoot,
      'scopeId': c.scopeId,
      'membershipHeadHash': exactTargetHead.headHash,
    };
    if (exactTargetHead.scopeId != c.scopeId ||
        exactTargetHead.epoch != 1 ||
        exactTargetHead.body['previousHeadHash'] != '0' * 64 ||
        exactTargetHead.body['accessIntentProof'] != null ||
        exactTargetHead.body['financePolicyIntentProof'] != null ||
        childArchive.capture.captureId != c.captureId ||
        childArchive.capture.migrationId != c.migrationId ||
        c.domain != 'finance' ||
        !const {
          'read',
          'write',
        }.contains(exactTargetHead.member(c.accountId)['financeRole']) ||
        CryptoBusinessJson.canonical(target) !=
            CryptoBusinessJson.canonical(context['target']) ||
        CryptoBusinessJson.canonical(childSource.binding.toJson()) !=
            CryptoBusinessJson.canonical(context['childBinding']) ||
        context['serverId'] != c.serverId ||
        await selectionHash(selection) != raw['selectionHash']) {
      throw const FormatException('crypto_account_choices_capture_target');
    }
    final source = await CryptoMigrationRecordSource.decode(
      table: c.sourceTable,
      domain: c.domain,
      row: childSource.typedRow,
      serverId: c.serverId,
      reservedId: reservedId,
    );
    if (source.deleted ||
        !const {
          'financeEntry',
          'financeTransfer',
          'financeRecurrenceRule',
        }.contains(source.type) ||
        source.rawPayload?['accountScopeId'] != context['source']['scopeId']) {
      throw const FormatException('crypto_account_choices_capture_child');
    }
    final choices = CryptoFinanceChoiceSelectionCodec.choices(
      selection['choices'],
      context['source']['scopeId'],
    );
    for (final key in ['accountId', 'fromAccountId', 'toAccountId']) {
      final id = source.rawPayload?[key];
      if (id != null && !choices.any((a) => a['accountId'] == id)) {
        throw const FormatException('crypto_account_choices_capture_selected');
      }
    }
  }

  static Future<VerifiedCapturedFinanceAccountChoices> verifySourceSelection(
    Map<String, dynamic> raw, {
    required String serverId,
    required String sourceAccountId,
    required VerifiedCryptoCaptureArchive sourceArchive,
    required List<CryptoMigrationColdSource> sourceParentAccountRows,
    required VerifiedScopeHead exactSourceHead,
    required Future<String> Function(String, String) reservedId,
  }) async {
    validate(raw);
    final selection = raw['capture3'] as Map, c = selection['context'] as Map;
    final expected = await deriveSourceSelection(
      serverId: serverId,
      sourceAccountId: sourceAccountId,
      sourceArchive: sourceArchive,
      sourceParentAccountRows: sourceParentAccountRows,
      exactSourceHead: exactSourceHead,
      targetContext: Map<String, dynamic>.from(c['target'] as Map),
      childBinding: CryptoCaptureBinding.fromJson(
        Map<String, dynamic>.from(c['childBinding'] as Map),
      ),
      selectionSaltBase64: selection['selectionSaltBase64'],
      reservedId: reservedId,
    );
    final unsigned = Map<String, dynamic>.from(raw)
      ..remove('offerAuthorization')
      ..remove('delegationAuthorization')
      ..remove('certificateAuthorization');
    if (CryptoBusinessJson.canonical(expected) !=
        CryptoBusinessJson.canonical(unsigned)) {
      throw const FormatException('crypto_account_choices_capture_derivation');
    }
    return VerifiedCapturedFinanceAccountChoices._(
      Map.unmodifiable(Map<String, dynamic>.from(raw)),
      await CryptoBusinessJson.hash(raw),
      CryptoFinanceChoiceSelectionCodec.choices(
        selection['choices'],
        exactSourceHead.scopeId,
      ),
    );
  }

  static void validate(Map<String, dynamic> raw) {
    final proofs = const {
      'offerAuthorization',
      'delegationAuthorization',
      'certificateAuthorization',
    };
    final signed = proofs.any(raw.containsKey);
    CryptoFinanceChoiceSelectionCodec.closed(raw, {
      'version',
      'variant',
      'capture3',
      'selectionHash',
      if (signed) ...proofs,
    });
    if (raw['version'] != 2 ||
        raw['variant'] != variant ||
        raw['capture3'] is! Map) {
      throw const FormatException('crypto_account_choices_capture_shape');
    }
    final selection = raw['capture3'] as Map;
    CryptoFinanceChoiceSelectionCodec.closed(selection, {
      'context',
      'choices',
      'selectionSaltBase64',
    });
    final context = selection['context'];
    if (context is! Map) {
      throw const FormatException('crypto_account_choices_capture_shape');
    }
    CryptoFinanceChoiceSelectionCodec.closed(context, {
      'version',
      'purpose',
      'serverId',
      'source',
      'target',
      'childBinding',
    });
    if (context['version'] != 3 ||
        context['purpose'] != 'financeAccountChoice') {
      throw const FormatException('crypto_account_choices_capture_shape');
    }
    CryptoFinanceChoiceSelectionCodec.uuid(context['serverId']);
    for (final name in ['source', 'target']) {
      final value = context[name];
      if (value is! Map) {
        throw const FormatException('crypto_account_choices_capture_shape');
      }
      CryptoFinanceChoiceSelectionCodec.closed(value, {
        'migrationId',
        'captureId',
        'accountId',
        'sourceInventoryRoot',
        'scopeId',
        'membershipHeadHash',
      });
      for (final k in ['migrationId', 'captureId', 'accountId', 'scopeId']) {
        CryptoFinanceChoiceSelectionCodec.uuid(value[k]);
      }
      for (final k in ['sourceInventoryRoot', 'membershipHeadHash']) {
        CryptoFinanceChoiceSelectionCodec.hash(value[k]);
      }
    }
    final binding = CryptoCaptureBinding.fromJson(
      Map<String, dynamic>.from(context['childBinding'] as Map),
    );
    if (binding.scopeId != context['target']['scopeId'] ||
        binding.domain != 'finance') {
      throw const FormatException('crypto_account_choices_capture_binding');
    }
    CryptoFinanceChoiceSelectionCodec.choices(
      selection['choices'],
      context['source']['scopeId'],
    );
    final salt = cryptoBase64(selection['selectionSaltBase64'], length: 32);
    salt.fillRange(0, salt.length, 0);
    CryptoFinanceChoiceSelectionCodec.hash(raw['selectionHash']);
  }

  static Future<String> selectionHash(Map selection) async {
    final salt = cryptoBase64(selection['selectionSaltBase64'], length: 32);
    try {
      return await CryptoBusinessJson.hash({
        'domain': hashDomain,
        'context': selection['context'],
        'choices': selection['choices'],
        'selectionSaltBase64': base64Encode(salt),
      });
    } finally {
      salt.fillRange(0, salt.length, 0);
    }
  }
}
