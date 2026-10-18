import 'dart:convert';
import 'dart:typed_data';

import 'crypto_business_router.dart';
import 'crypto_account_archive.dart';
import 'crypto_capture_archive.dart';
import 'crypto_capture_keys.dart';
import 'crypto_migration_cold_business.dart';
import 'crypto_migration_cold_controls.dart';
import 'crypto_migration_structure_context.dart';
import 'crypto_migration_structure_producer.dart';
import 'crypto_sync_repository.dart';

class CryptoMigrationStructureReview {
  CryptoMigrationStructureReview({
    required this.scopeId,
    required this.purpose,
    required this.issuerFingerprint,
    required this.facts,
    required this.members,
    this.labels = const {},
  });
  final String scopeId, purpose, issuerFingerprint;
  final Map<String, dynamic> facts;
  final List<Map<String, dynamic>> members;
  final Map<String, String> labels;
}

typedef CryptoMigrationStructureReviewer =
    Future<bool> Function(CryptoMigrationStructureReview review);

/// Connects the existing source certificate/scoped consent controls to the
/// normal wizard. Source-only FILE checks never wait for another full verify3.
class CryptoMigrationStructureWorkflow {
  CryptoMigrationStructureWorkflow(this.runtime, this.business, {this.review});
  final CryptoBusinessSession runtime;
  final CryptoMigrationColdBusiness business;
  final CryptoMigrationStructureReviewer? review;

  Future<Map<String, String?>> _ownScopes(
    CryptoCaptureKeyDescriptor capture,
  ) async {
    final result = <String, String?>{};
    var after = '';
    while (true) {
      final rows = await runtime.db.rows(
        "SELECT binding_id,context,typed_row FROM crypto_capture_sources WHERE partition=? AND capture_id=? AND binding_id>? AND json_extract(context,'\$.sourceTable')='familyhub_scopes' ORDER BY binding_id LIMIT 1",
        [runtime.partition, capture.captureId, after],
      );
      if (rows.isEmpty) return result;
      final row = rows.single;
      after = row['binding_id'] as String;
      final context = jsonDecode(row['context'] as String) as Map;
      final cells = CryptoMigrationColdEvidence.cells(
        Map<String, dynamic>.from(jsonDecode(row['typed_row'] as String)),
      );
      if (context['scopeId'] != cells['id'] ||
          context['domain'] != 'content' ||
          result.containsKey(cells['id'])) {
        throw const FormatException('crypto_structure_workflow_source');
      }
      result[cells['id']!] =
          cells['parent_scope_id'] ?? cells['organization_id'];
    }
  }

  Future<void> run({
    required CryptoCaptureKeyDescriptor capture,
    required CryptoArchiveManifest manifest,
    required VerifiedCryptoCaptureArchive archive,
    required Uint8List recoveryFile,
  }) async {
    final producer = CryptoMigrationStructureProducer(runtime);
    final own = await _ownScopes(capture);
    final published = <String>{};
    // Roots and locally complete parent chains can publish independently.
    // Child-only portions wait for the already existing scoped parent card.
    for (final scope in own.keys) {
      if (own[scope] != null && !own.containsKey(own[scope])) continue;
      await _publish(scope, capture, manifest, recoveryFile, producer);
      published.add(scope);
    }
    final required = <String, Set<String>>{};
    for (final scope in own.keys) {
      if (own[scope] != null && !own.containsKey(own[scope])) {
        required.putIfAbsent(scope, () => <String>{}).add('parentAccess');
      }
    }
    for (final selection in capture.receiptSelections) {
      if (const ['content', 'finance'].contains(selection['domain']) &&
          !own.containsKey(selection['scopeId'])) {
        required
            .putIfAbsent(selection['scopeId']!, () => <String>{})
            .add('scopeContext');
      }
    }
    for (final entry in required.entries) {
      final candidate = await runtime.access.migrationCandidate(
        scopeId: entry.key,
        migrationId: capture.migrationId,
        captureId: capture.captureId,
      );
      final found = <String>{};
      String? after;
      while (true) {
        final page = await runtime.account.directory
            .call('crypto2.migration.structure.contexts', {
              'migrationId': capture.migrationId,
              'captureId': capture.captureId,
              'sourceInventoryRoot': archive.sourceInventoryRoot,
              'scopeId': entry.key,
              'membershipHeadHash': candidate.head.headHash,
              if (after != null) 'afterHash': after,
              'limit': 20,
            });
        if (page['contexts'] is! List ||
            (page['contexts'] as List).length > 20 ||
            page['hasMore'] is! bool) {
          throw const FormatException('crypto_structure_context_page');
        }
        for (final raw in page['contexts'] as List) {
          final item = Map<String, dynamic>.from(raw as Map);
          final hash = item['contextProofHash'];
          if (hash is! String || after != null && hash.compareTo(after) <= 0) {
            throw const FormatException('crypto_structure_context_cursor');
          }
          after = hash;
          final card = CryptoMigrationStructureContexts.body(
            Map<String, dynamic>.from(item['authorization'] as Map),
          );
          if (!entry.value.contains(card['purpose']) ||
              !found.add(card['purpose'])) {
            throw const FormatException('crypto_structure_context_purpose');
          }
          final issuer = await runtime.access.currentMemberDirectory(
            entry.key,
            candidate.head.headHash,
            card['accountId'],
          );
          await producer.approve(
            archive: archive,
            cardEvidence: item,
            issuer: issuer,
            review: (facts, members) async {
              final callback = review;
              if (callback == null) return false;
              final labels = <String, String>{};
              for (final row in await runtime.db.rows(
                'SELECT data FROM members WHERE partition=? AND scope_id=? LIMIT 100',
                [runtime.partition, entry.key],
              )) {
                final value = jsonDecode(row['data'] as String) as Map;
                final label = value['displayName'] ?? value['username'];
                if (value['accountId'] is String &&
                    label is String &&
                    label.trim().isNotEmpty) {
                  labels[value['accountId']] = label;
                }
              }
              return callback(
                CryptoMigrationStructureReview(
                  scopeId: entry.key,
                  purpose: card['purpose'],
                  issuerFingerprint: issuer.rootFingerprint,
                  labels: Map.unmodifiable(labels),
                  facts: Map.unmodifiable(facts),
                  members: List.unmodifiable(
                    members.map((m) => Map<String, dynamic>.unmodifiable(m)),
                  ),
                ),
              );
            },
          );
        }
        if (page['hasMore'] != true) break;
        if ((page['contexts'] as List).isEmpty ||
            page['nextAfterHash'] != after) {
          throw const FormatException('crypto_structure_context_cursor');
        }
      }
      if (!found.containsAll(entry.value)) {
        throw const CryptoAuthorityPending(
          'crypto_structure_context_contributors_pending',
        );
      }
    }
    for (final scope in own.keys.where((s) => !published.contains(s))) {
      await _publish(scope, capture, manifest, recoveryFile, producer);
    }
  }

  Future<void> _publish(
    String scope,
    CryptoCaptureKeyDescriptor capture,
    CryptoArchiveManifest manifest,
    Uint8List recoveryFile,
    CryptoMigrationStructureProducer producer,
  ) async {
    final source = await business.verifyStructureSource(
      capture: capture,
      manifest: manifest,
      externalFile: recoveryFile,
      scopeId: scope,
    );
    await producer.publishSource(source);
    final candidate = await runtime.access.migrationCandidate(
      scopeId: scope,
      migrationId: capture.migrationId,
      captureId: capture.captureId,
    );
    await producer.publishContext(
      source: source,
      purpose: 'scopeContext',
      targetScopeId: scope,
      targetMembershipHeadHash: candidate.head.headHash,
    );
    for (final child in await runtime.catalog()) {
      if (child['parentScopeId'] != scope ||
          child['headHash'] is! String ||
          child['cryptoOrigin'] == true ||
          const ['committed', 'retired'].contains(child['migrationState'])) {
        continue;
      }
      // A visible signed child candidate is a scoped routing prerequisite only;
      // it never creates an ordinary head, key or floor in the live session.
      final head = await runtime.access.withReadOnlyFrozenScope(
        scopeId: child['id'],
        candidateHeadHash: child['headHash'],
        recoveryFile: recoveryFile,
        body: () => runtime.access.recoveryCandidateHead(child['id']),
      );
      if (head.headHash != child['headHash']) {
        throw const FormatException('crypto_structure_context_target');
      }
      await producer.publishContext(
        source: source,
        purpose: 'parentAccess',
        targetScopeId: head.scopeId,
        targetMembershipHeadHash: head.headHash,
      );
    }
  }
}
