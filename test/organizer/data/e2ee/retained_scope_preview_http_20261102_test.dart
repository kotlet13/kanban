import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_repository.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_identity_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/data/e2ee/scope_crypto_manager.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:sodium/sodium.dart';

// Opt-in real HTTP on a NEW client clone only. All membership/record/directory
// verification is production code. No confirm, mutation RPC, receipt resume or
// business sync is available in this runner; the original client is never opened.
class _DiskStore implements AccountCryptoStore {
  _DiskStore(this.file);
  final File file;
  Future<void> tail = Future.value();
  Future<Map<String, dynamic>> all() async =>
      Map<String, dynamic>.from(jsonDecode(await file.readAsString()) as Map);
  @override
  Future<String?> read(String key) async {
    await tail;
    return (await all())['jivie_account_crypto_v1_$key'] as String?;
  }

  @override
  Future<void> write(String key, String value) {
    final next = tail.then((_) async {
      final rows = await all();
      rows['jivie_account_crypto_v1_$key'] = value;
      await file.writeAsString(jsonEncode(rows), flush: true);
    });
    tail = next;
    return next;
  }
}

const _reads = {
  'capabilities',
  'crypto2.authority.snapshot',
  'crypto2.account.status',
  'crypto2.account.directory',
  'crypto2.account.scopeObservations',
  'crypto2.scopes.catalog',
  'crypto2.scope.headGet',
  'crypto2.directory.status',
  'crypto2.directory.read',
  'crypto2.scope.lifecycle.baseline',
  'crypto2.scope.lifecycle.list',
  'crypto2.scope.recordPolicy.status',
  'crypto2.scope.recordPolicy.baseline',
  'crypto2.scope.closureGet',
  'crypto2.grants.list',
  'crypto2.grants.manifest',
  'crypto2.records.pull',
  'crypto2.records.historyGet',
  'crypto2.domain.inventory',
};

String _reason(Object error) => switch (error) {
  CryptoAuthorityPending() => error.reason,
  CryptoDirectoryException() => error.code,
  CollaborationException() => error.code,
  FormatException() when RegExp(r'^[a-z0-9_]+$').hasMatch(error.message) =>
    error.message,
  _ => error.runtimeType.toString(),
};

void main() {
  final path = Platform.environment['JIVIE_RETAINED_PREVIEW_HTTP_FIXTURE'];
  test(
    'real HTTP retained review reopens on a fresh access instance',
    () async {
      final fixtureFile = File(path!);
      final fixture = jsonDecode(await fixtureFile.readAsString()) as Map;
      expect(fixture['synthetic'], true);
      expect(fixture['purpose'], 'retained-preview-http-20261102');
      expect(fixture['serverUrl'], 'http://127.0.0.1:57901');
      expect(
        fixtureFile.parent.path.endsWith(
          'build/qa/password-flow-fix-20261102/retained-preview-http',
        ),
        true,
      );
      final root = fixtureFile.parent;
      final progress = File('${root.path}/result.json');
      final result = progress.existsSync()
          ? Map<String, dynamic>.from(
              jsonDecode(await progress.readAsString()) as Map,
            )
          : <String, dynamic>{};
      expect(result['passed'], isNot(true), reason: 'Never repeat passed work');
      final attempt = (result['attempts'] as int? ?? 0) + 1;
      expect(attempt, lessThanOrEqualTo(3));
      result['attempts'] = attempt;
      result['startedAt'] = DateTime.now().toUtc().toIso8601String();
      Future<void> save() =>
          progress.writeAsString(jsonEncode(result), flush: true);
      await save();
      final sessionData =
          jsonDecode(
                await File(
                  '${root.path}/owner-session-private.json',
                ).readAsString(),
              )
              as Map;
      final session = DeviceSession(
        AccountSession.fromJson(
          Map<String, dynamic>.from(sessionData['profile'] as Map),
        ),
        sessionData['token'] as String,
      );
      expect(Uri.parse(session.profile.serverUrl).host, '127.0.0.1');
      expect(Uri.parse(session.profile.serverUrl).port, 57901);
      final db = CollaborationDatabase(
        NativeDatabase(File('${root.path}/owner.sqlite')),
      );
      await db.rows('SELECT name FROM local_meta LIMIT 1');
      final operations = <String, int>{};
      final wire = HttpCollaborationTransport(
        onAttempt: (operation) {
          if (!_reads.contains(operation)) {
            throw StateError('preview_http_write_forbidden');
          }
          operations.update(operation, (v) => v + 1, ifAbsent: () => 1);
        },
      );
      final account = AccountCryptoV2Workflow(
        AccountDirectoryRepository(
          reducer: AccountDirectoryV2(CryptoCodec(await SodiumInit.init())),
          session: session,
          transport: wire,
          store: CryptoIdentityStore(
            db,
            _DiskStore(File('${root.path}/owner-keys-private.json')),
            session.profile.partition,
          ),
          isCurrent: () => true,
        ),
      );
      Future<String> rowsHash(String table) async => cryptoSha256(
        Uint8List.fromList(
          utf8.encode(
            jsonEncode(await db.rows('SELECT * FROM $table ORDER BY rowid')),
          ),
        ),
      );
      try {
        final scope = fixture['scopeId'] as String;
        final outboxBefore = await rowsHash('crypto_outbox');
        final identityBefore = await rowsHash('crypto_identity_secrets');
        final creator = ScopeCryptoManager(
          SessionCryptoAccess(account: account),
        );
        final review = await creator.reviewRotation(scope);
        // The original in-memory verifier is deliberately discarded here.
        final reopened = ScopeCryptoManager(
          SessionCryptoAccess(account: account),
        );
        final retained = (await reopened.pendingRotationReviews(
          scope,
        )).singleWhere((value) => value.id == review.id);
        await reopened.proposedMembers(
          retained,
        ); // same saved-page restore route
        final intentsBefore = await rowsHash('crypto_membership_intents');
        final reviewBefore = await rowsHash('crypto_scope_review_records');
        final keysBefore = await rowsHash('crypto_scope_keys');
        var count = 0, readable = 0, sawOriginalTask = false;
        String? after;
        while (true) {
          final page = await reopened.previewRotation(retained, afterId: after);
          try {
            if (page.isEmpty) break;
            for (final item in page) {
              count++;
              if (item.plaintext != null) {
                readable++;
                sawOriginalTask |= utf8
                    .decode(item.plaintext!)
                    .contains('Password flow task');
              }
            }
            after = page.last.id;
          } finally {
            for (final item in page) {
              item.dispose();
            }
          }
          expect(count, lessThanOrEqualTo(1000));
        }
        final expected = retained.domains.values.fold<int>(
          0,
          (n, domain) => n + (domain as Map)['count'] as int,
        );
        expect(count, expected);
        expect(sawOriginalTask, true);
        expect(await rowsHash('crypto_outbox'), outboxBefore);
        expect(await rowsHash('crypto_identity_secrets'), identityBefore);
        expect(await rowsHash('crypto_membership_intents'), intentsBefore);
        expect(await rowsHash('crypto_scope_review_records'), reviewBefore);
        expect(await rowsHash('crypto_scope_keys'), keysBefore);
        expect(
          (await reopened.pendingRotationReviews(
            scope,
          )).any((v) => v.id == review.id),
          true,
        );
        final source = Directory(fixture['sourceClone'] as String);
        for (final entry in (fixture['sourceHashes'] as Map).entries) {
          expect(
            await cryptoSha256(
              await File('${source.path}/${entry.key}').readAsBytes(),
            ),
            entry.value,
          );
        }
        result.addAll({
          'passed': true,
          'previewedRecords': count,
          'readableRecords': readable,
          'originalTaskVisible': true,
          'historyBasis': retained.historyBasis,
          'reviewStillPending': true,
          'heldCommandsUnchanged': true,
          'identityKeysUnchanged': true,
          'previewKeysAndReviewUnchanged': true,
          'sourceCloneUnchanged': true,
          'readOnlyHttp': true,
          'httpOperations': operations,
        });
        await save();
        debugPrint(
          'RETAINED_PREVIEW_HTTP PASS attempt=$attempt records=$count readonlyCalls=${operations.values.fold(0, (a, b) => a + b)}',
        );
      } catch (error, stack) {
        result.addAll({
          'error': _reason(error),
          'httpOperations': operations,
          'stack': stack.toString().split('\n').take(12).toList(),
        });
        await save();
        fail(
          'RETAINED_PREVIEW_HTTP FAILED attempt=$attempt reason=${_reason(error)}',
        );
      } finally {
        wire.close();
        await db.close();
      }
    },
    skip: path == null ? 'New private client clone required' : false,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
