import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_repository.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_router.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_domain_checkpoint.dart';
import 'package:kanban/organizer/data/e2ee/crypto_domain_checkpoint_publisher.dart';
import 'package:kanban/organizer/data/e2ee/crypto_identity_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_record_proof_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_store.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:sodium/sodium.dart';

class _Secure implements AccountCryptoStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
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
  static final read = CryptoReadContext(
    epoch: 1,
    accessRevision: 0,
    headHash: 'a' * 64,
  );
  @override
  Future<CryptoReadContext> readContext(String scopeId, String domain) async =>
      read;
}

class _Wire implements CollaborationTransport {
  _Wire(this.scope);
  final String scope;
  Map<String, dynamic>? proof;
  int inventoryReads = 0;
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    if (operation != 'crypto2.domain.inventory') {
      throw StateError('unexpected_checkpoint_boundary_operation');
    }
    inventoryReads++;
    final payload = proof == null
        ? null
        : (CryptoJson.decode(cryptoBase64(proof!['commandBase64']))
                  as Map)['payload']
              as Map;
    return {
      'scopeId': scope,
      'domain': 'content',
      'epoch': 1,
      'membershipHeadHash': _Access.read.headHash,
      'scopeSequence': 0,
      'descriptors': [],
      'hasMore': false,
      'checkpoint': payload == null
          ? null
          : {
              'manifestHash': payload['manifestHash'],
              'recordCount': 0,
              'membershipHeadHash': _Access.read.headHash,
              'domainSequence': 0,
              'attestations': [
                {'authorization': proof},
              ],
              'hasMore': false,
            },
    };
  }

  @override
  void close() {}
}

// The command seam models the durable queue's direct transport mutation and
// nested fresh pre-delivery review. Inventory memo, signed reader, publisher,
// scope-state SQL and outer operation lease are the real implementations.
class _Commands implements CryptoSyncRepository {
  _Commands(this.access, this.wire, this.codec, this.key, this.pending);
  final _Access access;
  final _Wire wire;
  final CryptoRecordProofCodec codec;
  final KeyPair key;
  final bool pending;
  late Map<String, dynamic> command;
  @override
  Future<String> enqueueCommand({
    required String actionKey,
    required String operation,
    required Map<String, dynamic> payload,
    String? requestId,
  }) async {
    command = codec.signCommand({
      'version': 2,
      'operation': operation,
      'requestId': codec.crypto.randomId(),
      'serverId': access.account.directory.session.profile.serverId,
      'accountId': access.account.directory.accountId,
      'deviceId': access.account.deviceId,
      'signer': 'device',
      'payload': payload,
    }, key.secretKey);
    return 'checkpoint-request';
  }

  @override
  Future<void> resumeUnresolved({Set<String>? requestIds}) async {
    await access.withVerifiedOperation(() async {}, freshBoundary: true);
    if (!pending) wire.proof = command;
  }

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

class _Context extends CryptoBusinessSession {
  _Context(super.account, super.access, super.db, this.commands, this.signer);
  final _Commands commands;
  final KeyPair signer;
  @override
  CryptoSyncRepository get queue => commands;
  @override
  CryptoDomainCheckpointReader get checkpoints => CryptoDomainCheckpointReader(
    database: database,
    partition: partition,
    codec: codec,
    call: (op, params) => account.directory.call(op, params),
    verify: (proof) async {
      codec.crypto.verifyDomain(proof, signer.publicKey, 'JivieE2EE/v2\n');
      return 'verifiedCheckpoint';
    },
  );
}

void main() {
  for (final pending in [false, true]) {
    test(
      'checkpoint-boundary26 ${pending ? 'pending stays incomplete' : 'applied retires outer cached inventory'}',
      () async {
        final db = CollaborationDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final crypto = CryptoCodec(await SodiumInit.init());
        final key = crypto.sodium.crypto.sign.keyPair();
        addTearDown(key.dispose);
        final scope = crypto.randomId();
        final wire = _Wire(scope);
        final session = DeviceSession(
          AccountSession(
            serverUrl: 'https://checkpoint.invalid',
            serverId: crypto.randomId(),
            accountId: crypto.randomId(),
            userId: 1,
            username: 'synthetic',
            displayName: 'Synthetic',
            deviceId: crypto.randomId(),
            expiresAt: DateTime.utc(2030),
          ),
          'synthetic-token',
        );
        final directory = _Directory(
          reducer: AccountDirectoryV2(crypto),
          session: session,
          transport: wire,
          store: CryptoIdentityStore(db, _Secure(), session.profile.partition),
        );
        final account = AccountCryptoV2Workflow(directory);
        final access = _Access(account: account);
        final commands = _Commands(
          access,
          wire,
          CryptoRecordProofCodec(crypto),
          key,
          pending,
        );
        final context = _Context(account, access, db, commands, key);
        await CryptoSyncStore(db, session.profile.partition).checkpoint(
          scopeId: scope,
          domain: 'content',
          epoch: 1,
          accessRevision: 0,
          transportCursor: 0,
          projectionCursor: 0,
          scopeSequence: 0,
          complete: false,
        );
        await access.withVerifiedOperation(() async {
          await CryptoDomainCheckpointPublisher(
            context,
          ).publish(scope, 'content');
          final again = await directory.call('crypto2.domain.inventory', {
            'scopeId': scope,
            'domain': 'content',
            'accessRevision': 0,
            'limit': 50,
          });
          expect(again['checkpoint'] != null, !pending);
        });
        final state = (await db.rows(
          'SELECT complete FROM crypto_scope_state',
        )).single;
        expect(state['complete'], pending ? 0 : 1);
        expect(
          await context.hasReusableCheckpoint(scope, 'content', _Access.read),
          !pending,
        );
        expect(wire.inventoryReads, pending ? 1 : greaterThanOrEqualTo(2));
        expect(
          await db.rows('SELECT * FROM crypto_domain_checkpoints'),
          pending ? isEmpty : hasLength(1),
        );
      },
    );
  }
}
