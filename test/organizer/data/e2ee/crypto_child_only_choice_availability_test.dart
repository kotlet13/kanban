import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_router.dart';
import 'package:kanban/organizer/data/e2ee/crypto_finance_account_choices.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';

const _scope = '11111111-1111-4111-a111-111111111111';
const _action = '22222222-2222-4222-a222-222222222222';
const _partition = 'child-only-availability';

class _UnusedAccount implements AccountCryptoV2Workflow {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('No account/parent request allowed');
}

class _UnusedAccess implements SessionCryptoAccess {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('No source authority can be inferred');
}

class _Runtime extends CryptoBusinessSession {
  _Runtime(CollaborationDatabase db)
    : super(_UnusedAccount(), _UnusedAccess(), db);
  final pulls = <(String, String)>[];
  @override
  String get p => _partition;
  @override
  Future<void> pullVerified(
    String scope,
    String domain, {
    bool attest = true,
  }) async {
    expect(scope, _scope);
    expect(domain, 'content');
    pulls.add((scope, domain));
  }
}

// Only the independently verified read result is controlled. The actual ensure
// method must return it before trying source-side derivation or parent discovery.
class _VerifiedRead extends CryptoFinanceAccountChoices {
  _VerifiedRead(super.context);
  @override
  Future<Map<String, dynamic>> read(String scope) async => {
    'fixture': 'verified-target-contained-selection',
  };
  @override
  Future<Map<String, dynamic>> prepare(
    String scope, {
    required String actionId,
  }) async => throw StateError('Must retain the prior verified read');
  @override
  Future<bool> materializeAvailable(
    String scope, {
    CryptoMigrationCandidate? candidate,
  }) async => throw StateError('Existing verified read comes first');
}

void main() {
  late CollaborationDatabase db;
  late _Runtime runtime;
  setUp(() async {
    db = CollaborationDatabase(NativeDatabase.memory());
    runtime = _Runtime(db);
    await db.execute('INSERT INTO accounts(partition,profile) VALUES(?,?)', [
      _partition,
      '{}',
    ]);
  });
  tearDown(() async => db.close());
  Future<void> scope({String kind = 'project', Object? parent}) async {
    await db.execute(
      'INSERT OR REPLACE INTO scopes(partition,id,data) VALUES(?,?,?)',
      [
        _partition,
        _scope,
        jsonEncode({
          ...SharedScope(
            id: _scope,
            name: 'Child-only project',
            kind: SharedScopeKind.project,
            role: SharedRole.member,
          ).toJson(),
          'kind': kind,
          'parentScopeId': parent,
        }),
      ],
    );
  }

  test(
    'actual prepare reports hidden parent availability after verified child read without parent access',
    () async {
      await scope();
      await expectLater(
        CryptoFinanceAccountChoices(runtime).prepare(_scope, actionId: _action),
        throwsA(
          isA<CryptoAuthorityPending>().having(
            (e) => e.reason,
            'reason',
            'crypto_account_choices_parent_unavailable',
          ),
        ),
      );
      expect(runtime.pulls, [(_scope, 'content')]);
      expect(await db.rows('SELECT 1 FROM crypto_export_drafts'), isEmpty);
      expect(await db.rows('SELECT 1 FROM crypto_outbox'), isEmpty);
    },
  );
  test(
    'existing verified target selection is read before source availability is considered',
    () async {
      await scope();
      expect(await _VerifiedRead(runtime).ensure(_scope), {
        'fixture': 'verified-target-contained-selection',
      });
      expect(runtime.pulls, isEmpty);
    },
  );
  for (final malformed in [
    ('organization', null),
    ('project', 'not-a-canonical-uuid'),
    ('project', 7),
  ]) {
    test(
      'malformed target $malformed is never optional source unavailability',
      () async {
        await scope(kind: malformed.$1, parent: malformed.$2);
        await expectLater(
          CryptoFinanceAccountChoices(
            runtime,
          ).prepare(_scope, actionId: _action),
          throwsA(isA<FormatException>()),
        );
        expect(runtime.pulls, [(_scope, 'content')]);
        expect(await db.rows('SELECT 1 FROM crypto_export_drafts'), isEmpty);
      },
    );
  }
}
