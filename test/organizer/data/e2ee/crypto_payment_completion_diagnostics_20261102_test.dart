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
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
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
  Future<Map<String, dynamic>> Function(String, Map<String, Object?>)? handler;
  List<Map<String, dynamic>> descriptors = [];
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    if (handler != null) return handler!(operation, params);
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
  bool realReusable = false;
  CryptoSyncRepository? realCommands;
  _Reader? reader;
  @override
  CryptoDomainCheckpointReader get checkpoints => reader ?? super.checkpoints;
  @override
  CryptoSyncRepository get queue => realCommands ?? commands;
  @override
  Future<bool> hasReusableCheckpoint(
    String scope,
    String domain,
    CryptoReadContext read,
  ) async => realReusable
      ? super.hasReusableCheckpoint(scope, domain, read)
      : reusable;
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
  for (final scenario in [
    'pending',
    'blocked',
    'blocked_rejected',
    'unknown',
    'denied',
    'substituted',
    'mismatched_authorization',
    'mismatched_scope',
  ]) {
    test(
      'new reusable checkpoint settles exact $scenario lost ACK without resend',
      () async {
        final f = await _fixture();
        final crypto = f.runtime.account.directory.reducer.crypto;
        final signing = crypto.sodium.crypto.sign.keyPair();
        addTearDown(signing.secretKey.dispose);
        var preflights = 0;
        final queue = CryptoSyncRepository(
          crypto: crypto,
          session: f.runtime.account.directory.session,
          transport: f.wire,
          store: CryptoSyncStore(f.db, f.runtime.partition),
          signingKey: () async => CryptoKeyLease.borrowed(signing.secretKey),
          authorKey: (_) async => throw StateError('unexpected author read'),
          contentKey: (_) async => throw StateError('unexpected key read'),
          project: (_) async => throw StateError('unexpected projection'),
          isCurrent: () => true,
          beforeDelivery: (_) async {
            preflights++;
          },
        );
        f.runtime.realCommands = queue;
        f.runtime.realReusable = true;
        final payload = <String, dynamic>{
          'scopeId': _scope,
          'domain': 'finance',
          'epoch': 1,
          'membershipHeadHash': _Access.read.headHash,
          'accessRevision': 0,
          'authorDirectoryHeadHash': 'b' * 64,
          'expectedSequence': 1,
          'recordCount': 0,
          'manifestHash': 'c' * 64,
          'historyBasis': 'verifiedCheckpoint',
        };
        final request = await queue.enqueueCommand(
          actionKey: 'new-exact-lost-checkpoint',
          operation: 'crypto2.domain.checkpoint',
          payload: payload,
        );
        final ignored = await queue.enqueueCommand(
          actionKey: 'new-unrelated-checkpoint',
          operation: 'crypto2.domain.checkpoint',
          payload: {...payload, 'expectedSequence': 2},
        );
        final untouched = await queue.store.outgoing(ignored);
        if (scenario != 'pending') {
          await queue.store.outcome(request, 'blocked', {
            'outcome': 'unresolved',
            'reason': 'authority_pending',
          });
        }
        final original = (await queue.store.outgoing(request))!;
        final signed = Map<String, dynamic>.from(
          jsonDecode(original['signed_body'] as String) as Map,
        );
        var checkpointProof = signed;
        if (scenario == 'mismatched_authorization') {
          checkpointProof = {
            ...signed,
            'signatureBase64': base64Encode(List<int>.filled(64, 0)),
          };
        }
        if (scenario == 'mismatched_scope') {
          final command = Map<String, dynamic>.from(
            CryptoJson.decode(cryptoBase64(signed['commandBase64'])) as Map,
          );
          command['payload'] = {...payload, 'scopeId': crypto.randomId()};
          checkpointProof = {
            ...signed,
            'commandBase64': base64Encode(CryptoJson.encode(command)),
          };
        }
        await f.db.execute(
          'UPDATE crypto_domain_checkpoints SET authorization=?,manifest_hash=? WHERE partition=? AND scope_id=?',
          [
            jsonEncode(checkpointProof),
            payload['manifestHash'],
            f.runtime.partition,
            _scope,
          ],
        );
        await f.db.execute(
          'UPDATE crypto_scope_state SET complete=1,projection_cursor=1 WHERE partition=? AND scope_id=?',
          [f.runtime.partition, _scope],
        );
        final claims = await f.db.rows('SELECT * FROM crypto_command_keys');
        final attempts = await f.db.rows(
          'SELECT * FROM crypto_outbox_attempts',
        );
        var lookups = 0;
        f.wire.handler = (operation, params) async {
          expect(operation, 'crypto2.receipt.get');
          expect(params['requestId'], request);
          lookups++;
          if (scenario == 'unknown') return {'outcome': 'unknown'};
          if (scenario == 'denied') {
            throw const CollaborationApiException('permission_revoked');
          }
          return {
            'requestId': request,
            'requestHash': scenario == 'substituted'
                ? '0' * 64
                : original['request_hash'],
            'authorization': signed,
            'status': scenario == 'blocked_rejected' ? 409 : 200,
            'response': scenario == 'blocked_rejected'
                ? {'errorCode': 'crypto_checkpoint_changed'}
                : {'status': 'applied'},
          };
        };
        final publication = CryptoDomainCheckpointPublisher(
          f.runtime,
        ).publish(_scope, 'finance');
        if (scenario == 'substituted') {
          await expectLater(publication, throwsFormatException);
        } else {
          expect(await publication, PaymentCheckpointStep.reusableCheckpoint);
        }
        final settled = (await queue.store.outgoing(request))!;
        final terminal = const {
          'pending',
          'blocked',
          'blocked_rejected',
        }.contains(scenario);
        expect(
          settled['state'],
          terminal
              ? scenario == 'blocked_rejected'
                    ? 'rejected'
                    : 'applied'
              : 'blocked',
        );
        if (!terminal) expect(settled, original);
        expect(lookups, scenario.startsWith('mismatched') ? 0 : 1);
        expect(preflights, 0);
        for (final field in [
          'request_id',
          'operation',
          'signed_body',
          'request_hash',
          'sequence',
        ]) {
          expect(settled[field], original[field]);
        }
        expect(await queue.store.outgoing(ignored), untouched);
        expect(await f.db.rows('SELECT * FROM crypto_command_keys'), claims);
        expect(
          await f.db.rows('SELECT * FROM crypto_outbox_attempts'),
          attempts,
        );
        expect((await queue.store.scope(_scope, 'finance'))!['complete'], 1);
      },
    );
  }
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
