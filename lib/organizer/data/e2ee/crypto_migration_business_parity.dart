import 'dart:convert';

import 'package:cryptography/cryptography.dart' show Sha256;

import 'crypto_inventory_json.dart';
import 'crypto_record_address.dart';

/// One tagged streaming commitment to an actual isolated business restoration.
/// Producers must compare decrypted source/projection/file bytes first. This
/// codec authenticates that result; it never turns a server descriptor into
/// evidence that plaintext semantics or physical file bytes were verified.
abstract final class CryptoMigrationBusinessParity {
  static const sourceTables = {
    'familyhub_scopes',
    'familyhub_records',
    'familyhub_finance_records',
    'familyhub_tables',
    'familyhub_attachments',
    'familyhub_payment_events',
    'familyhub_payment_projections',
    'familyhub_payment_cash',
  };
  // These rows additionally require the immutable receipt index. Active
  // reminders, inbox/settings, audits, assets and structural state are NEVER
  // silently accepted as context while their dedicated adapters are missing.
  static const archiveContextTables = {
    'familyhub_operations',
    'familyhub_finance_operations',
    'familyhub_document_requests',
  };

  static bool _hash(Object? value) =>
      value is String && RegExp(r'^[a-f0-9]{64}$').hasMatch(value);
  static void _exact(Map value, Set<String> keys) {
    if (value.length != keys.length ||
        value.keys.any((k) => !keys.contains(k))) {
      throw const FormatException('crypto_business_parity_shape');
    }
  }

  /// Frames: domain {scopeId,domain,membershipHeadHash}; source exact signed
  /// source binding; context {table,rowCursor,rowHash}; file {kind,id,size,sha256}.
  /// Sections sort scope/domain. Within each section: sources table/id, contexts
  /// table/cursor, files kind/id. A section or source can occur only once.
  static Future<Map<String, dynamic>> compute({
    required Map<String, dynamic> header,
    required Stream<Map<String, dynamic>> frames,
  }) async {
    _exact(header, {
      'version',
      'serverId',
      'migrationId',
      'componentId',
      'componentHash',
      'accountId',
      'inventoryHash',
    });
    if (header['version'] != 2 ||
        ![
          'serverId',
          'migrationId',
          'componentId',
          'accountId',
        ].every((k) => isCryptoCanonicalUuid(header[k])) ||
        !['componentHash', 'inventoryHash'].every((k) => _hash(header[k]))) {
      throw const FormatException('crypto_business_parity_context');
    }
    final sink = Sha256().newHashSink();
    sink.add(utf8.encode('JivieMigrationBusinessParity/v2\n'));
    void add(String tag, Map<String, dynamic> value) {
      final bytes = CryptoInventoryJson.encode({'tag': tag, 'value': value});
      if (bytes.length > 196608)
        throw const FormatException('crypto_business_parity_frame');
      sink.add([...bytes, 10]);
    }

    add('header', header);
    String? section, scope, domain, previousKey;
    var sectionCount = 0,
        phase = 0,
        sources = 0,
        companions = 0,
        contexts = 0,
        files = 0,
        fileBytes = 0;
    await for (final frame in frames) {
      _exact(frame, {'tag', 'value'});
      final tag = frame['tag'], raw = frame['value'];
      if (raw is! Map<String, dynamic>)
        throw const FormatException('crypto_business_parity_shape');
      if (tag == 'domain') {
        _exact(raw, {'scopeId', 'domain', 'membershipHeadHash'});
        final nextScope = raw['scopeId'], nextDomain = raw['domain'];
        if (!['content', 'finance', 'private'].contains(nextDomain) ||
            (nextScope == null
                ? nextDomain != 'private'
                : !isCryptoCanonicalUuid(nextScope)) ||
            (nextDomain == 'private'
                ? raw['membershipHeadHash'] != null
                : !_hash(raw['membershipHeadHash']))) {
          throw const FormatException('crypto_business_parity_context');
        }
        final next = '${nextScope ?? ''}/$nextDomain';
        if (section != null && section.compareTo(next) >= 0 ||
            ++sectionCount > 3000) {
          throw const FormatException('crypto_business_parity_order');
        }
        section = next;
        scope = nextScope;
        domain = nextDomain;
        previousKey = null;
        phase = 0;
      } else {
        if (section == null)
          throw const FormatException('crypto_business_parity_context');
        late String key;
        late int nextPhase;
        if (tag == 'source') {
          _exact(raw, {
            'sourceTable',
            'scopeId',
            'sourceId',
            'sourceKind',
            'canonicalId',
            'wireId',
            'domain',
            'type',
            'legacyRevision',
            'sourceRowHash',
            'recordProofHash',
            'companionProofHashes',
          });
          final hashes = raw['companionProofHashes'];
          if (!sourceTables.contains(raw['sourceTable']) ||
              raw['scopeId'] != scope ||
              raw['domain'] != domain ||
              !isCryptoCanonicalUuid(raw['sourceId']) ||
              !isCryptoCanonicalUuid(raw['canonicalId']) ||
              !isCryptoWireRecordId(raw['wireId']) ||
              !_hash(raw['sourceRowHash']) ||
              !_hash(raw['recordProofHash']) ||
              raw['legacyRevision'] is! int ||
              raw['legacyRevision'] < 0 ||
              hashes is! List ||
              hashes.length > 31) {
            throw const FormatException('crypto_business_parity_source');
          }
          String? last;
          for (final hash in hashes) {
            if (!_hash(hash) ||
                hash == raw['recordProofHash'] ||
                last != null && last.compareTo(hash) >= 0) {
              throw const FormatException('crypto_business_parity_companions');
            }
            last = hash;
          }
          sources++;
          companions += hashes.length;
          nextPhase = 1;
          key = '${raw['sourceTable']}/${raw['sourceId']}';
        } else if (tag == 'context') {
          _exact(raw, {'table', 'rowCursor', 'rowHash'});
          if (!archiveContextTables.contains(raw['table']) ||
              raw['rowCursor'] is! int ||
              raw['rowCursor'] < 0 ||
              !_hash(raw['rowHash'])) {
            throw const FormatException(
              'crypto_business_parity_adapter_pending',
            );
          }
          contexts++;
          nextPhase = 2;
          key =
              '${raw['table']}/${raw['rowCursor'].toString().padLeft(20, '0')}';
        } else if (tag == 'file') {
          _exact(raw, {'kind', 'id', 'size', 'sha256'});
          if (domain != 'content' ||
              scope == null ||
              !['attachment', 'ideaAsset'].contains(raw['kind']) ||
              raw['id'] is! String ||
              raw['size'] is! int ||
              raw['size'] < 0 ||
              !_hash(raw['sha256'])) {
            throw const FormatException('crypto_business_parity_file');
          }
          files++;
          fileBytes += raw['size'] as int;
          nextPhase = 3;
          key = '${raw['kind']}/${raw['id']}';
        } else {
          throw const FormatException('crypto_business_parity_adapter_pending');
        }
        if (nextPhase < phase ||
            nextPhase == phase &&
                previousKey != null &&
                previousKey.compareTo(key) >= 0) {
          throw const FormatException('crypto_business_parity_order');
        }
        phase = nextPhase;
        previousKey = key;
      }
      if (sources + companions + contexts + files > 10000000)
        throw const FormatException('crypto_business_parity_size');
      add(tag as String, raw);
    }
    final footer = <String, dynamic>{
      'version': 2,
      'domainCount': sectionCount,
      'sourceRowCount': sources,
      'companionProofCount': companions,
      'archiveOnlyRowCount': contexts,
      'fileCount': files,
      'fileBytes': fileBytes,
    };
    add('footer', footer);
    sink.close();
    return {
      ...footer,
      'manifestHash': (await sink.hash()).bytes
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(),
    };
  }
}
