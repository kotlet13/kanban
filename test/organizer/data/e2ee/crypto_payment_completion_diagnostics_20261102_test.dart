import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_repository.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_payments.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_router.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_domain_checkpoint_publisher.dart';
import 'package:kanban/organizer/data/e2ee/crypto_domain_checkpoint.dart';
import 'package:kanban/organizer/data/e2ee/crypto_identity_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_store.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:kanban/organizer/domain/payment_completion_diagnostics.dart';
import 'package:sodium/sodium.dart';

const _scope = '10000000-0000-4000-8000-000000000001';

class _Database extends CollaborationDatabase {
  _Database() : super(NativeDatabase.memory());
  bool failDiagnosticSample = false;
  @override
  Future<List<Map<String, dynamic>>> rows(
    String sql, [
    List<Object?> args = const [],
  ]) {
    if (failDiagnosticSample && sql.contains('SELECT r.verdict,r.error')) {
      throw StateError('synthetic_optional_sample_failure');
    }
    return super.rows(sql, args);
  }
}

class _Reader implements CryptoDomainCheckpointReader {
  Future<void> Function()? beforeResult;
  @override
  Future<String?> reconcile(
    String scope,
    String domain,
    CryptoReadContext context, {
    List<Map<String, dynamic>>? observedAnchors,
  }) async {
    await beforeResult?.call();
    return 'synthetic-snapshot';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Secure implements AccountCryptoStore {
  @override
  Future<String?> read(String key) async => null;
  @override
  Future<void> write(String key, String value) async {}
}

class _DirectoryState implements VerifiedAccountDirectory {
  @override
  String get headHash => 'b' * 64;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Directory extends AccountDirectoryRepository {
  _Directory({
    required super.reducer,
    required super.session,
    required super.transport,
    required super.store,
  }) : super(isCurrent: () => true);
  @override
  Future<VerifiedAccountDirectory> cachedVerifiedDirectory() async =>
      _DirectoryState();
}

class _Access extends SessionCryptoAccess {
  _Access({required super.account});
  bool denied = false;
  static final read = CryptoReadContext(
    epoch: 1,
    accessRevision: 0,
    headHash: 'a' * 64,
  );
  @override
  Future<CryptoReadContext> readContext(String scopeId, String domain) async =>
      read;
  @override
  Future<void> ensureScopeReadKeys(String scopeId, String domain) async {
    if (denied) throw const CollaborationException('permission_revoked');
  }
}

class _Wire implements CollaborationTransport {
  int reads = 0;
  List<Map<String, dynamic>> descriptors = [];
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    if (operation != 'crypto2.domain.inventory') throw StateError(operation);
    reads++;
    return {
      'scopeId': params['scopeId'],
      'domain': params['domain'],
      'epoch': 1,
      'membershipHeadHash': _Access.read.headHash,
      'scopeSequence': 1,
      'descriptors': descriptors,
      'hasMore': false,
    };
  }

  @override
  void close() {}
}

// Only key acquisition and transport delivery are seams. The actual runtime
// pull, publisher, scope-state SQL, diagnostic capture and payment snapshot run.
class _Queue implements CryptoSyncRepository {
  int pulls = 0, commands = 0;
  bool pending = true;
  @override
  Future<void> pull({
    required String scopeId,
    required String domain,
    required int accessRevision,
  }) async {
    pulls++;
  }

  @override
  Future<String> enqueueCommand({
    required String actionKey,
    required String operation,
    required Map<String, dynamic> payload,
    String? requestId,
  }) async {
    commands++;
    return 'synthetic-command';
  }

  @override
  Future<void> resumeUnresolved({Set<String>? requestIds}) async {}
  @override
  Future<Map<String, dynamic>> commandResult(String requestId) async {
    if (pending) {
      throw const CryptoAuthorityPending('crypto_command_receipt_pending');
    }
    return {};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Runtime extends CryptoBusinessSession {
  _Runtime(super.account, super.access, super.db, this.commands);
  final _Queue commands;
  bool reusable = false;
  _Reader? reader;
  @override
  CryptoDomainCheckpointReader get checkpoints => reader ?? super.checkpoints;
  @override
  CryptoSyncRepository get queue => commands;
  @override
  Future<bool> hasReusableCheckpoint(
    String scope,
    String domain,
    CryptoReadContext read,
  ) async => reusable;
  @override
  Future<Map<String, dynamic>> financePolicy(String scope) async => {
    'revision': 1,
  };
}

Future<({_Database db, _Wire wire, _Access access, _Runtime runtime})>
_fixture() async {
  final db = _Database();
  addTearDown(db.close);
  final crypto = CryptoCodec(await SodiumInit.init());
  final session = DeviceSession(
    AccountSession(
      serverUrl: 'https://synthetic.invalid',
      serverId: crypto.randomId(),
      accountId: crypto.randomId(),
      userId: 1,
      username: 'Synthetic',
      displayName: 'Synthetic',
      deviceId: crypto.randomId(),
      expiresAt: DateTime.utc(2030),
    ),
    'synthetic-token',
  );
  final wire = _Wire();
  final directory = _Directory(
    reducer: AccountDirectoryV2(crypto),
    session: session,
    transport: wire,
    store: CryptoIdentityStore(db, _Secure(), session.profile.partition),
  );
  final account = AccountCryptoV2Workflow(directory);
  final access = _Access(account: account);
  final runtime = _Runtime(account, access, db, _Queue());
  await CryptoSyncStore(db, runtime.partition).checkpoint(
    scopeId: _scope,
    domain: 'finance',
    epoch: 1,
    accessRevision: 0,
    transportCursor: 0,
    projectionCursor: 0,
    scopeSequence: 1,
    complete: false,
  );
  await db.execute(
    'INSERT INTO crypto_domain_checkpoints VALUES(?,?,?,?,?,?,?,?,?,?,?,?)',
    [
      runtime.partition,
      _scope,
      'finance',
      _Access.read.headHash,
      1,
      0,
      1,
      'b' * 64,
      0,
      'synthetic-snapshot',
      '{}',
      'verifiedCheckpoint',
    ],
  );
  return (db: db, wire: wire, access: access, runtime: runtime);
}

Future<Map<String, dynamic>> _snapshot(_Runtime runtime) =>
    CryptoBusinessPayments(
      runtime,
    ).dispatch('finance3.payments', {'scopeId': _scope});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'completion follow-up optional sample failure keeps exact incomplete branch',
    () async {
      final f = await _fixture();
      f.db.failDiagnosticSample = true;
      final reply = await _snapshot(f.runtime);
      expect(reply['complete'], false);
      expect(reply['incompleteReason'], 'crypto_payment_records_pending');
      expect(reply['completionDiagnostics'], {
        'checkpointStep': 'commandAuthorityPending',
      });
    },
  );

  test(
    'completion follow-up actual reader missing checkpoint reports verification exit',
    () async {
      final f = await _fixture();
      f.runtime.commands.pending = false;
      final reply = await _snapshot(f.runtime);
      expect(reply['completionDiagnostics'], {
        'checkpointStep': 'checkpointVerificationPending',
      });
      expect(reply['complete'], false);
      expect(
        (await f.db.rows(
          'SELECT complete FROM crypto_scope_state',
        )).single['complete'],
        0,
      );
    },
  );

  for (final scenario in [
    ('completionStateMissing', 'DELETE FROM crypto_scope_state'),
    ('completionFloorChanged', 'UPDATE crypto_scope_state SET floor=2'),
    (
      'completionAccessRevisionChanged',
      'UPDATE crypto_scope_state SET access_revision=2',
    ),
    (
      'completionScopeSequenceChanged',
      'UPDATE crypto_scope_state SET scope_sequence=2',
    ),
    (
      'completionScanGenerationChanged',
      'UPDATE crypto_scope_state SET scan_generation=scan_generation+1',
    ),
    ('completionProjectionCursorBehind', ''),
  ]) {
    test(
      'completion follow-up exact final guard ${scenario.$1} retains incomplete state',
      () async {
        final f = await _fixture();
        f.runtime.commands.pending = false;
        f.runtime.reader = _Reader()
          ..beforeResult = () async {
            if (scenario.$2.isNotEmpty) await f.db.execute(scenario.$2);
          };
        final reply = await _snapshot(f.runtime);
        expect(reply['completionDiagnostics'], {'checkpointStep': scenario.$1});
        expect(reply['complete'], false);
        expect(
          await f.db.rows('SELECT * FROM crypto_scope_state WHERE complete=1'),
          isEmpty,
        );
        expect(
          await f.db.rows('SELECT * FROM crypto_domain_inventory_rows'),
          isEmpty,
        );
        expect(f.wire.reads, 1);
      },
    );
  }

  test(
    'completion diagnostics follows actual publisher uncovered exit without advancing state',
    () async {
      final f = await _fixture();
      await f.db.execute(
        '''INSERT INTO crypto_received
      (partition,scope_id,domain,record_id,revision,sequence,wire,verdict,error,batch_key)
      VALUES(?,?,?,?,?,?,?,?,?,?)''',
        [
          f.runtime.partition,
          _scope,
          'finance',
          'private-record-id',
          1,
          1,
          'private-payload',
          'received',
          'crypto_projection_pending',
          'private-batch',
        ],
      );
      final before = await f.db.rows('SELECT * FROM crypto_scope_state');
      final records = await f.db.rows('SELECT * FROM crypto_received');
      final reply = await _snapshot(f.runtime);
      expect(reply['complete'], false);
      expect(reply['incompleteReason'], 'crypto_payment_records_pending');
      expect(reply['completionDiagnostics'], {
        'checkpointStep': 'receivedInventoryUncovered',
        'recordVerdict': 'received',
        'recordReason': 'crypto_projection_pending',
      });
      expect(await f.db.rows('SELECT * FROM crypto_scope_state'), before);
      expect(await f.db.rows('SELECT * FROM crypto_received'), records);
      expect(
        await f.db.rows('SELECT * FROM crypto_domain_inventory_rows'),
        isEmpty,
      );
      expect(f.runtime.commands.commands, 0);
      expect(f.wire.reads, 1);
      expect(
        jsonEncode(reply['completionDiagnostics']),
        isNot(contains('private')),
      );
    },
  );

  test(
    'exact missing projection branch clears on next nonattesting and denied pulls',
    () async {
      final f = await _fixture();
      f.wire.descriptors = [
        {
          'id': 'private-wire-id',
          'revision': 1,
          'sequence': 1,
          'recordEpoch': 1,
          'recordProofHash': 'c' * 64,
        },
      ];
      final first = await _snapshot(f.runtime);
      expect(first['completionDiagnostics'], {
        'checkpointStep': 'projectedRecordMissing',
      });
      expect(f.runtime.completionDiagnosticsFor(_scope, 'content'), isNull);
      await f.runtime.pullVerified(_scope, 'finance', attest: false);
      expect(f.runtime.completionDiagnosticsFor(_scope, 'finance'), isNull);
      f.wire.descriptors = [];
      final second = await _snapshot(f.runtime);
      expect(second['completionDiagnostics'], {
        'checkpointStep': 'commandAuthorityPending',
      });
      f.access.denied = true;
      await expectLater(
        _snapshot(f.runtime),
        throwsA(isA<CollaborationException>()),
      );
      expect(f.runtime.completionDiagnosticsFor(_scope, 'finance'), isNull);
      expect(
        (await f.db.rows(
          'SELECT complete FROM crypto_scope_state',
        )).single['complete'],
        0,
      );
      expect(f.runtime.commands.commands, 1);
      expect(f.wire.reads, 2);
    },
  );

  test(
    'reusable publisher result carries no unresolved diagnostic or network work',
    () async {
      final f = await _fixture();
      f.runtime.reusable = true;
      final before = await f.db.rows('SELECT * FROM crypto_scope_state');
      expect(
        await CryptoDomainCheckpointPublisher(
          f.runtime,
        ).publish(_scope, 'finance'),
        PaymentCheckpointStep.reusableCheckpoint,
      );
      expect(f.runtime.completionDiagnosticsFor(_scope, 'finance'), isNull);
      expect(f.wire.reads, 0);
      expect(await f.db.rows('SELECT * FROM crypto_scope_state'), before);
    },
  );

  test(
    'untrusted diagnostic fields accept only finite categories and safe reasons',
    () {
      final parsed = PaymentCompletionDiagnostics.fromJson({
        'checkpointStep': 'receivedInventoryUncovered',
        'recordVerdict': 'quarantined',
        'recordReason': 'crypto_secret_private_payload',
        'scopeId': 'private-id',
      }, sanitizeReason: safeSyncFailureReason)!;
      expect(
        parsed.toSafeDiagnosticJson(sanitizeReason: safeSyncFailureReason),
        {
          'checkpointStep': 'receivedInventoryUncovered',
          'recordVerdict': 'quarantined',
          'recordReason': 'unknown',
        },
      );
      expect(
        PaymentCompletionDiagnostics.fromJson({
          'checkpointStep': 'private-step',
        }, sanitizeReason: safeSyncFailureReason),
        isNull,
      );
      final invalidVerdict = PaymentCompletionDiagnostics.fromJson({
        'checkpointStep': 'completionSessionChanged',
        'recordVerdict': 'private-state',
      }, sanitizeReason: safeSyncFailureReason)!;
      expect(invalidVerdict.recordVerdict, isNull);
    },
  );
}
