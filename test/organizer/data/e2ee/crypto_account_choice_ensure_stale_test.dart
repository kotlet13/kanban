import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_repository.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_router.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_finance_account_choices.dart';
import 'package:kanban/organizer/data/e2ee/crypto_record_proof_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/data/e2ee/scope_crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';

const _scope = '11111111-1111-4111-a111-111111111111';
const _oldAction = '22222222-2222-4222-a222-222222222222';
const _partition = 'ensure-stale-selection';
const _publication = CryptoAuthorityPending(
  'crypto_account_choices_publication_required',
);
const _current = <String, dynamic>{
  'accounts': [
    {'id': 'new-parent-account', 'name': 'New account', 'currency': 'EUR'},
  ],
  'accountScopeId': 'parent-scope',
  'accountSequence': 2,
};

class _Own implements VerifiedAccountDirectory {
  @override
  String get accountId => 'own-account';
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('No other directory proof used at orchestration seam');
}

class _Directory implements AccountDirectoryRepository {
  @override
  Future<VerifiedAccountDirectory> requireFresh() async => _Own();
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('No transport at orchestration seam');
}

class _Account implements AccountCryptoV2Workflow {
  @override
  final directory = _Directory();
  @override
  String get deviceId => 'own-device';
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('No signing at orchestration seam');
}

class _Head implements VerifiedScopeHead {
  _Head({required this.manageKeys, required this.financeRole});
  final bool manageKeys;
  final String financeRole;
  @override
  Map<String, dynamic> member(String account) {
    expect(account, 'own-account');
    return {'manageKeys': manageKeys, 'financeRole': financeRole};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('No other scope proof used at orchestration seam');
}

class _Access implements SessionCryptoAccess {
  _Access(this.head);
  final _Head head;
  @override
  Future<VerifiedScopeHead> currentHead(
    String scope, {
    bool online = false,
  }) async {
    expect(scope, _scope);
    expect(online, isTrue);
    return head;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('No key admission at orchestration seam');
}

class _Ids implements CryptoCodec {
  var count = 0;
  @override
  String randomId() =>
      '33333333-3333-4333-a333-${(++count).toString().padLeft(12, '0')}';
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('No cryptography replaced by ensure orchestration');
}

class _Runtime extends CryptoBusinessSession {
  _Runtime(CollaborationDatabase db, _Head head)
    : super(_Account(), _Access(head), db);
  final ids = _Ids();
  @override
  String get p => _partition;
  @override
  CryptoRecordProofCodec get codec => CryptoRecordProofCodec(ids);
  @override
  Future<String> reservedRecordId(String scope, String namespace) async {
    expect(scope, _scope);
    expect(namespace, startsWith('accountChoiceSelection:approve:'));
    return '44444444-4444-4444-a444-444444444444';
  }
}

/// Only independently verified operations' outcomes are controlled. The real
/// ensure orchestration, action choice, role gates and SQL selection are used.
/// Cryptographic acceptance is covered separately by the real HTTP regression.
class _Choices extends CryptoFinanceAccountChoices {
  _Choices(super.context, {required this.readOutcomes});
  final List<Object> readOutcomes;
  final prepared = <String>[];
  final finished = <String>[];
  final approved = <String>[];
  Object? discoveryError, prepareError, finishError;
  bool available = true;
  int reads = 0, discoveries = 0;

  @override
  Future<Map<String, dynamic>> read(String scope) async {
    expect(scope, _scope);
    final result = readOutcomes[reads++];
    if (result is Map<String, dynamic>) return result;
    throw result;
  }

  @override
  Future<bool> materializeAvailable(
    String scope, {
    CryptoMigrationCandidate? candidate,
  }) async {
    expect(scope, _scope);
    discoveries++;
    if (discoveryError != null) throw discoveryError!;
    return available;
  }

  @override
  Future<Map<String, dynamic>> prepare(
    String scope, {
    required String actionId,
  }) async {
    expect(scope, _scope);
    prepared.add(actionId);
    if (prepareError != null) throw prepareError!;
    return {
      'offerAuthorization': {'fixture': 'fresh-verified-selection'},
    };
  }

  @override
  Future<Map<String, dynamic>> approve(
    String scope,
    Map<String, dynamic> offerProof, {
    required String actionId,
    required String recipientAccountId,
    required String recipientDeviceId,
    CryptoMigrationCandidate? candidate,
  }) async {
    expect(scope, _scope);
    expect(recipientAccountId, 'own-account');
    expect(recipientDeviceId, 'own-device');
    approved.add(actionId);
    return {};
  }

  @override
  Future<Map<String, dynamic>> finish(
    String scope,
    String selectionActionId,
  ) async {
    expect(scope, _scope);
    finished.add(selectionActionId);
    if (finishError != null) throw finishError!;
    return {};
  }
}

void main() {
  late CollaborationDatabase db;
  late _Runtime runtime;
  late List<Map<String, dynamic>> oldDrafts, oldOutbox, oldSelections;
  setUp(() async {
    db = CollaborationDatabase(NativeDatabase.memory());
    runtime = _Runtime(db, _Head(manageKeys: true, financeRole: 'write'));
    await db.execute('INSERT INTO accounts(partition,profile) VALUES(?,?)', [
      _partition,
      '{}',
    ]);
    await db.execute(
      'CREATE TABLE IF NOT EXISTS crypto_export_drafts(partition TEXT NOT NULL,scope_id TEXT NOT NULL,action_id TEXT NOT NULL,payload TEXT NOT NULL,PRIMARY KEY(partition,scope_id,action_id))',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS crypto_account_choice_selections(partition TEXT NOT NULL,action_id TEXT NOT NULL,scope_id TEXT NOT NULL,selection TEXT NOT NULL,PRIMARY KEY(partition,action_id))',
    );
    await db.execute(
      'INSERT INTO crypto_account_choice_selections VALUES(?,?,?,?)',
      [
        _partition,
        _oldAction,
        _scope,
        jsonEncode({'choices': <Object>[], 'sourceSequence': 1}),
      ],
    );
    // Retain distinct original propose/delegate/certify request bodies. These
    // are opaque journal sentinels, not cryptographically accepted fixtures.
    for (final operation in ['propose', 'delegate', 'certify']) {
      final payload = jsonEncode({
        'requestId': 'old-$operation',
        'payload': {'originalSelection': 'empty', 'operation': operation},
      });
      await db.execute('INSERT INTO crypto_export_drafts VALUES(?,?,?,?)', [
        _partition,
        _scope,
        operation == 'propose' ? _oldAction : 'old-$operation-action',
        payload,
      ]);
      await db.execute(
        'INSERT INTO crypto_outbox(partition,request_id,operation,signed_body,request_hash,state) VALUES(?,?,?,?,?,?)',
        [
          _partition,
          'old-$operation',
          'crypto2.exports.$operation',
          payload,
          'original-$operation-hash',
          'applied',
        ],
      );
    }
    oldDrafts = await db.rows(
      'SELECT * FROM crypto_export_drafts ORDER BY action_id',
    );
    oldOutbox = await db.rows('SELECT * FROM crypto_outbox ORDER BY sequence');
    oldSelections = await db.rows(
      'SELECT * FROM crypto_account_choice_selections',
    );
  });
  tearDown(() async {
    expect(
      await db.rows('SELECT * FROM crypto_export_drafts ORDER BY action_id'),
      oldDrafts,
    );
    expect(
      await db.rows('SELECT * FROM crypto_outbox ORDER BY sequence'),
      oldOutbox,
    );
    expect(
      await db.rows('SELECT * FROM crypto_account_choice_selections'),
      oldSelections,
    );
    await db.close();
  });

  test(
    'post-materialization stale empty selection derives new account generation',
    () async {
      final choices = _Choices(
        runtime,
        readOutcomes: [
          _publication,
          const CollaborationApiException(
            'crypto_account_choices_source_set_changed',
          ),
          _current,
        ],
      );
      expect(await choices.ensure(_scope), _current);
      expect(choices.reads, 3);
      expect(choices.discoveries, 1);
      expect(choices.prepared, hasLength(1));
      expect(choices.prepared.single, isNot(_oldAction));
      expect(choices.finished, choices.prepared);
      expect(choices.approved, hasLength(1));
    },
  );

  test('post-materialization head change derives a new generation', () async {
    final choices = _Choices(
      runtime,
      readOutcomes: [
        _publication,
        const CryptoAuthorityPending('crypto_account_choices_head_changed'),
        _current,
      ],
    );
    expect(await choices.ensure(_scope), _current);
    expect(choices.prepared, hasLength(1));
    expect(choices.prepared.single, isNot(_oldAction));
    expect(choices.discoveries, 1);
  });

  test(
    'authority, identity, pins, malformed proof and permission failures propagate unchanged',
    () async {
      for (final failure in <Object>[
        const CryptoAuthorityPending('scoped_export_recipient_changed'),
        const CryptoDirectoryException('directory_stale_identity'),
        const CryptoDirectoryException('directory_root_changed'),
        const FormatException('crypto_signature'),
        const FormatException('crypto_account_choices_shape'),
        const CollaborationApiException('permission_denied'),
      ]) {
        final choices = _Choices(
          runtime,
          readOutcomes: [_publication, failure],
        );
        await expectLater(choices.ensure(_scope), throwsA(same(failure)));
        expect(choices.prepared, isEmpty);
        expect(choices.finished, isEmpty);
        expect(choices.approved, isEmpty);
        expect(choices.discoveries, 1);
        expect(choices.reads, 2);
      }
    },
  );

  test('discovery stale error is not broadened into read recovery', () async {
    const failure = CollaborationApiException(
      'crypto_account_choices_checkpoint_changed',
    );
    final choices = _Choices(runtime, readOutcomes: [_publication])
      ..discoveryError = failure;
    await expectLater(choices.ensure(_scope), throwsA(same(failure)));
    expect(choices.prepared, isEmpty);
    expect(choices.reads, 1);
  });

  test(
    'fresh discovered selection returns before creating a generation',
    () async {
      final choices = _Choices(runtime, readOutcomes: [_publication, _current]);
      expect(await choices.ensure(_scope), _current);
      expect(choices.prepared, isEmpty);
      expect(choices.approved, isEmpty);
      expect(runtime.ids.count, 0);
    },
  );

  test(
    'absent publication preserves the initial stale decision and resumable action',
    () async {
      for (final initial in <Object>[
        _publication,
        const CollaborationApiException(
          'crypto_account_choices_source_set_changed',
        ),
      ]) {
        final choices = _Choices(
          runtime,
          readOutcomes: [initial, _publication, _current],
        );
        expect(await choices.ensure(_scope), _current);
        expect(choices.prepared, hasLength(1));
        expect(choices.prepared.single == _oldAction, initial == _publication);
      }
    },
  );

  test('stale regeneration retains the two-attempt bound', () async {
    const failure = CollaborationApiException(
      'crypto_account_choices_source_set_changed',
    );
    final choices = _Choices(runtime, readOutcomes: [_publication, failure])
      ..prepareError = failure;
    await expectLater(choices.ensure(_scope), throwsA(same(failure)));
    expect(choices.prepared, hasLength(2));
    expect(choices.prepared.toSet(), hasLength(2));
    expect(choices.prepared, isNot(contains(_oldAction)));
    expect(choices.discoveries, 1);
    expect(choices.reads, 2);
  });

  test(
    'source writer without management preserves manual approval boundary',
    () async {
      runtime = _Runtime(db, _Head(manageKeys: false, financeRole: 'write'));
      const manual = CryptoAuthorityPending(
        'crypto_account_choices_approval_pending',
      );
      final choices = _Choices(
        runtime,
        readOutcomes: [
          _publication,
          const CollaborationApiException(
            'crypto_account_choices_source_set_changed',
          ),
        ],
      )..finishError = manual;
      await expectLater(choices.ensure(_scope), throwsA(same(manual)));
      expect(choices.prepared, hasLength(1));
      expect(choices.approved, isEmpty);
      expect(choices.finished, choices.prepared);
    },
  );

  test(
    'manager without source write never materializes or auto-approves',
    () async {
      runtime = _Runtime(db, _Head(manageKeys: true, financeRole: 'read'));
      const denied = CollaborationApiException('permission_denied');
      final choices = _Choices(runtime, readOutcomes: [_publication])
        ..prepareError = denied;
      await expectLater(choices.ensure(_scope), throwsA(same(denied)));
      expect(choices.discoveries, 0);
      expect(choices.prepared, [_oldAction]);
      expect(choices.approved, isEmpty);
      expect(choices.finished, isEmpty);
    },
  );
}
