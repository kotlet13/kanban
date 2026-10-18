import 'dart:convert';

import 'package:cryptography/cryptography.dart' show Sha256;

import 'crypto_capture_v3.dart';
import 'crypto_inventory_json.dart';
import 'crypto_json.dart';
import 'crypto_record_address.dart';

/// One Capture3 cold-business comparison stream. All source commitments are
/// blinded and all artifact digests describe ciphertext or signed proofs.
/// Plaintext row/file comparisons happen inside the isolated verifier first.
/// This codec cannot itself attest that those comparisons took place.
abstract final class CryptoMigrationBusinessParityV3 {
  static Map<String, dynamic> scopedAudit(Object? value) {
    if (value is! Map) {
      throw const FormatException('crypto_migration_scoped_audit_section');
    }
    exact(value, {'audit'});
    final section = value['audit'];
    if (section is! Map) {
      throw const FormatException('crypto_migration_scoped_audit_section');
    }
    exact(section, {'kind', 'count', 'root'});
    if (section['kind'] != 'audit' ||
        !count(section['count']) ||
        !hash(section['root'])) {
      throw const FormatException('crypto_migration_scoped_audit_section');
    }
    return Map<String, dynamic>.from(section);
  }

  static const adapters = {
    'canonical',
    'canonicalFile',
    'structure',
    'notification',
    'invitation',
    'immutableReceipt',
    'auditHistory',
    'moderationDisclosure',
    'sourceContext',
  };

  /// Closed source classification shared with the server reconstruction.
  /// A current source never falls through to archive-context preservation.
  static String sourceAdapter(String table) => switch (table) {
    'familyhub_scopes' ||
    'familyhub_records' ||
    'familyhub_finance_records' ||
    'familyhub_tables' ||
    'familyhub_attachments' ||
    'familyhub_payment_events' ||
    'familyhub_payment_projections' ||
    'familyhub_payment_cash' => 'canonical',
    'familyhub_members' ||
    'familyhub_organization_leaders' ||
    'familyhub_scope_revocations' ||
    'familyhub_finance_policy' ||
    'familyhub_finance_grants' ||
    'familyhub_personal_scopes' ||
    'familyhub_record_relocations' => 'structure',
    'familyhub_reminders' ||
    'familyhub_inbox' ||
    'familyhub_inbox_preferences' ||
    'familyhub_inbox_state' ||
    'familyhub_deliveries' ||
    'familyhub_push_jobs' => 'notification',
    'familyhub_invitations' || 'familyhub_invitation_mail' => 'invitation',
    'familyhub_operations' ||
    'familyhub_finance_operations' ||
    'familyhub_document_requests' => 'immutableReceipt',
    'familyhub_finance_audit' => 'auditHistory',
    'familyhub_moderation_reports' ||
    'familyhub_idea_report_assets' => 'moderationDisclosure',
    // Associated SQL chunk copies survive in the private source archive; live
    // logical files additionally require their actual canonical file objects.
    'familyhub_attachment_chunks' => 'sourceContext',
    // Idea assets use their own physical adapter, never context-only coverage.
    'familyhub_idea_assets' => 'canonicalFile',
    _ => throw const FormatException('crypto_business_parity_adapter_pending'),
  };

  /// Hash only AFTER the outer stage signature, capture binding, source witness
  /// and exact business transformation have been independently verified.
  static Future<String> canonicalArtifact(
    Map<String, dynamic> signedSourceBinding,
  ) async {
    exact(signedSourceBinding, {
      'bindingId',
      'scopeId',
      'sourceKind',
      'canonicalId',
      'wireId',
      'domain',
      'type',
      'legacyRevision',
      'recordProofHash',
      'companionProofHashes',
      'witness',
      'objects',
    });
    return hex(
      (await Sha256().hash([
        ...utf8.encode('JivieMigrationCanonicalArtifact/v3\n'),
        ...CryptoInventoryJson.encode(signedSourceBinding),
      ])).bytes,
    );
  }

  /// The physical Idea file has no synthetic business record. Its caller first
  /// verifies this exact signed begin against the FILE source and file bytes.
  static Future<String> canonicalFileArtifact(
    Map<String, dynamic> signedBegin,
  ) async {
    exact(signedBegin, {'commandBase64', 'signatureBase64'});
    cryptoBase64(signedBegin['signatureBase64'], length: 64);
    final command =
        CryptoJson.decode(cryptoBase64(signedBegin['commandBase64'])) as Map;
    exact(command, {
      'version',
      'operation',
      'requestId',
      'serverId',
      'accountId',
      'deviceId',
      'signer',
      'payload',
    });
    final payload = command['payload'] as Map;
    exact(payload, {
      'captureVersion',
      'migrationId',
      'captureId',
      'sourceInventoryRoot',
      'bindingId',
      'scopeId',
      'domain',
      'epoch',
      'membershipHeadHash',
      'accessRevision',
      'id',
      'purpose',
      'size',
      'sha256',
      'manifestBase64',
    });
    if (command['version'] != 2 ||
        command['operation'] != 'crypto2.migration.blob.begin' ||
        command['signer'] != 'device' ||
        payload['captureVersion'] != 3 ||
        payload['purpose'] != 'ideaAsset' ||
        payload['domain'] != 'content') {
      throw const FormatException('crypto_business_parity_file');
    }
    return hex(
      (await Sha256().hash([
        ...utf8.encode('JivieMigrationCanonicalArtifact/v3\n'),
        ...CryptoInventoryJson.encode(signedBegin),
      ])).bytes,
    );
  }

  static const requiredSections = {
    'audit',
    'invitations',
    'notifications',
    'receipts',
    'structure',
  };
  static bool hash(Object? value) =>
      value is String && RegExp(r'^[a-f0-9]{64}$').hasMatch(value);
  static bool count(Object? value) =>
      value is int && value >= 0 && value <= 9007199254740991;
  static void exact(Map value, Set<String> keys) {
    if (value.length != keys.length ||
        value.keys.any((k) => !keys.contains(k))) {
      throw const FormatException('crypto_business_parity_shape');
    }
  }

  static String hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  /// Bindings come from the COMPLETE verified frozen capture, in binding-ID
  /// order. Their independently folded inventory must equal the signed seal.
  /// Each required adapter is closed; an unknown live source cannot be relabelled
  /// as context by this codec's caller. The final server verifier reconstructs
  /// the classification, artifact proofs and sections from its frozen source.
  static Future<Map<String, dynamic>> compute({
    required Map<String, dynamic> header,
    required Stream<Map<String, dynamic>> frames,
  }) async {
    exact(header, {
      'version',
      'serverId',
      'migrationId',
      'captureId',
      'componentId',
      'componentCommitment',
      'accountId',
      'sourceInventoryRoot',
      'sourceCount',
      'archiveManifestHash',
    });
    if (header['version'] != 3 ||
        ![
          'serverId',
          'migrationId',
          'captureId',
          'componentId',
          'accountId',
        ].every((k) => isCryptoCanonicalUuid(header[k])) ||
        ![
          'componentCommitment',
          'sourceInventoryRoot',
          'archiveManifestHash',
        ].every((k) => hash(header[k])) ||
        !count(header['sourceCount']) ||
        header['sourceCount'] > 10000000) {
      throw const FormatException('crypto_business_parity_context');
    }
    final sink = Sha256().newHashSink();
    sink.add(utf8.encode('JivieMigrationBusinessParity/v3\n'));
    void add(String tag, Map value) {
      final bytes = CryptoInventoryJson.encode({'tag': tag, 'value': value});
      if (bytes.length > 196608) {
        throw const FormatException('crypto_business_parity_frame');
      }
      sink.add(bytes);
      sink.add([10]);
    }

    add('header', header);
    final inventory = Sha256().newHashSink();
    inventory.add(utf8.encode('JivieCaptureInventory/v3\n'));
    inventory.add(
      CryptoInventoryJson.encode({
        'version': 3,
        for (final k in [
          'serverId',
          'captureId',
          'migrationId',
          'accountId',
          'sourceCount',
        ])
          k: header[k],
      }),
    );
    inventory.add([10]);
    var phase = 0,
        sourceRows = 0,
        primary = 0,
        companions = 0,
        contexts = 0,
        userFiles = 0,
        userBytes = 0,
        proofBlobs = 0;
    String? previous;
    final sections = <String>{};
    final adapterCounts = <String, int>{
      for (final adapter in adapters) adapter: 0,
    };
    await for (final frame in frames) {
      exact(frame, {'tag', 'value'});
      final tag = frame['tag'], value = frame['value'];
      if (value is! Map<String, dynamic>) {
        throw const FormatException('crypto_business_parity_shape');
      }
      late int nextPhase;
      late String key;
      if (tag == 'binding') {
        exact(value, {
          'binding',
          'adapter',
          'primaryRecordProofHash',
          'companionProofHashes',
          'artifactHash',
        });
        if (value['binding'] is! Map<String, dynamic>) {
          throw const FormatException('crypto_business_parity_binding');
        }
        final binding = CryptoCaptureBinding.fromJson(value['binding']);
        final adapter = value['adapter'],
            hashes = value['companionProofHashes'];
        if (!adapters.contains(adapter) ||
            !hash(value['artifactHash']) ||
            hashes is! List ||
            hashes.length > 31 ||
            (adapter == 'canonical'
                ? !hash(value['primaryRecordProofHash'])
                : value['primaryRecordProofHash'] != null ||
                      hashes.isNotEmpty)) {
          throw const FormatException('crypto_business_parity_adapter_pending');
        }
        String? last;
        for (final digest in hashes) {
          if (!hash(digest) ||
              digest == value['primaryRecordProofHash'] ||
              last != null && last.compareTo(digest) >= 0) {
            throw const FormatException('crypto_business_parity_companions');
          }
          last = digest;
        }
        sourceRows++;
        adapterCounts[adapter as String] = adapterCounts[adapter]! + 1;
        if (adapter == 'canonical') {
          primary++;
          companions += hashes.length;
        }
        if (const {
          'immutableReceipt',
          'moderationDisclosure',
          'sourceContext',
        }.contains(adapter)) {
          contexts++;
        }
        if (sourceRows > header['sourceCount']) {
          throw const FormatException('crypto_business_parity_coverage');
        }
        inventory.add(CryptoInventoryJson.encode(binding.toJson()));
        inventory.add([10]);
        nextPhase = 1;
        key = binding.bindingId;
      } else if (tag == 'file' || tag == 'proofBlob') {
        exact(value, {
          'bindingId',
          'id',
          'kind',
          'plainSize',
          'cipherSize',
          'cipherSha256',
          'manifestHash',
        });
        if (!isCryptoCanonicalUuid(value['bindingId']) ||
            !isCryptoCanonicalUuid(value['id']) ||
            (tag == 'file'
                ? !count(value['plainSize']) || value['plainSize'] > 20971520
                : value['plainSize'] != null) ||
            !count(value['cipherSize']) ||
            value['cipherSize'] < 1 ||
            value['cipherSize'] > 69206016 ||
            !hash(value['cipherSha256']) ||
            !hash(value['manifestHash']) ||
            (tag == 'file'
                ? !const {'attachment', 'ideaAsset'}.contains(value['kind'])
                : value['kind'] != 'typedWitness')) {
          throw const FormatException('crypto_business_parity_file');
        }
        if (tag == 'file') {
          userFiles++;
          userBytes += value['plainSize'] as int;
        } else {
          proofBlobs++;
        }
        nextPhase = tag == 'file' ? 2 : 3;
        key = '${value['bindingId']}/${value['kind']}/${value['id']}';
      } else if (tag == 'section') {
        exact(value, {'kind', 'count', 'root'});
        if (!requiredSections.contains(value['kind']) ||
            !count(value['count']) ||
            !hash(value['root']) ||
            !sections.add(value['kind'])) {
          throw const FormatException('crypto_business_parity_section');
        }
        nextPhase = 4;
        key = value['kind'];
      } else {
        throw const FormatException('crypto_business_parity_adapter_pending');
      }
      if (nextPhase < phase ||
          nextPhase == phase &&
              previous != null &&
              previous.compareTo(key) >= 0) {
        throw const FormatException('crypto_business_parity_order');
      }
      phase = nextPhase;
      previous = key;
      add(tag as String, value);
    }
    inventory.close();
    if (sourceRows != header['sourceCount'] ||
        hex((await inventory.hash()).bytes) != header['sourceInventoryRoot'] ||
        sections.length != requiredSections.length) {
      throw const FormatException('crypto_business_parity_coverage');
    }
    final footer = <String, dynamic>{
      'version': 3,
      'sourceRowCount': sourceRows,
      'primaryRecordProofCount': primary,
      'companionProofCount': companions,
      'archiveContextRowCount': contexts,
      'userFileCount': userFiles,
      'userFileBytes': userBytes,
      'witnessBlobCount': proofBlobs,
      'adapterCounts': adapterCounts,
    };
    add('footer', footer);
    sink.close();
    return {...footer, 'hash': hex((await sink.hash()).bytes)};
  }
}
