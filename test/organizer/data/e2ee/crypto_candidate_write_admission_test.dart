import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
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

class _Secure implements AccountCryptoStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

class _Transport extends HttpCollaborationTransport {
  Map<String, dynamic>? forgedCurrent;
  int grantReads = 0;
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    if (operation == 'crypto2.grants.list') grantReads++;
    if (operation == 'crypto2.scope.headGet' &&
        params['headHash'] == null &&
        forgedCurrent != null) {
      return forgedCurrent!;
    }
    return super.call(
      serverUrl: serverUrl,
      operation: operation,
      params: params,
      token: token,
      allowLocalHttp: allowLocalHttp,
    );
  }
}

DeviceSession _session(String url, Map wire) {
  final user = wire['user'] as Map, device = wire['device'] as Map;
  return DeviceSession(
    AccountSession(
      serverUrl: url,
      serverId: wire['serverId'],
      accountId: user['accountId'],
      userId: user['id'],
      username: user['username'],
      displayName: user['displayName'],
      deviceId: device['id'],
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        device['expiresAt'] * 1000,
      ),
      allowLocalHttp: true,
    ),
    wire['token'],
  );
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final path = Platform.environment['JIVIE_KEY_ADMISSION_FIXTURE'];
  late CollaborationDatabase db;
  late _Transport transport;
  late CryptoCodec crypto;
  late AccountCryptoV2Workflow account;
  late String scope;
  late Map fixture;
  late Map<String, dynamic> activeWire;
  AccountCryptoV2Workflow workflow(
    DeviceSession session,
    CollaborationDatabase database,
  ) => AccountCryptoV2Workflow(
    AccountDirectoryRepository(
      reducer: AccountDirectoryV2(crypto),
      session: session,
      transport: transport,
      store: CryptoIdentityStore(
        database,
        _Secure(),
        session.profile.partition,
      ),
      isCurrent: () => true,
    ),
  );
  setUpAll(() async {
    if (path == null) return;
    fixture = jsonDecode(await File(path).readAsString()) as Map;
    final url = fixture['serverUrl'] as String;
    if (fixture['synthetic'] != true || Uri.parse(url).host != '127.0.0.1') {
      throw StateError('Synthetic loopback only');
    }
    db = CollaborationDatabase(NativeDatabase.memory());
    transport = _Transport();
    crypto = CryptoCodec(await SodiumInit.init());
    account = workflow(
      _session(url, fixture['accounts']['owner']['session']),
      db,
    );
    final file = await account.prepareRecoveryFile();
    try {
      await account.verifyAndInitialize(file);
    } finally {
      file.fillRange(0, file.length, 0);
    }
    final access = SessionCryptoAccess(account: account),
        manager = ScopeCryptoManager(access);
    scope = crypto.randomId();
    await manager.ensurePersonal(scope);
    final catalog = await account.directory.call('crypto2.scopes.catalog');
    final metadata =
        (catalog['scopes'] as List).singleWhere((s) => s['id'] == scope) as Map;
    final active = await manager.initializeEmptyScope(
      scopeId: scope,
      accessRevision: metadata['accessRevision'],
      members: (metadata['members'] as List).cast<Map<String, dynamic>>(),
    );
    expect(active.active, true);
    expect(active.commitment('finance'), isNotNull);
    activeWire = await account.directory.call('crypto2.scope.headGet', {
      'scopeId': scope,
    });
    // This is the real public candidate grant path used for retained/recovered
    // keys. It verifies grants/manifests but deliberately marks them read-only.
    await access.hydrateExistingCandidateKeys(scope);
    expect(
      (await db.rows(
        'SELECT write_ready FROM crypto_scope_keys WHERE scope_id=?',
        [scope],
      )).every((r) => r['write_ready'] == 0),
      true,
    );
  });
  tearDownAll(() async {
    if (path != null) {
      transport.close();
      await db.close();
    }
  });
  group(
    'verified candidate write admission',
    () {
      test(
        'readable candidate becomes writable only through normal active grants',
        () async {
          final access = SessionCryptoAccess(account: account);
          final read = await access.getScopeKey(scope, 'finance', 1);
          final original = read.key.extractBytes();
          read.release();
          try {
            final before = transport.grantReads;
            final write = await access.writeContext(
              scope,
              'finance',
              online: true,
            );
            try {
              expect(write.key.key.extractBytes(), original);
              expect(write.headHash, activeWire['headHash']);
            } finally {
              write.key.release();
            }
            expect(transport.grantReads, greaterThan(before));
            final after = transport.grantReads;
            final repeated = await access.writeContext(
              scope,
              'finance',
              online: true,
            );
            repeated.key.release();
            expect(
              transport.grantReads,
              after,
              reason: 'ready keys do not rehydrate',
            );
          } finally {
            original.fillRange(0, original.length, 0);
          }
        },
      );
      test('missing activation cannot admit cached candidate key', () async {
        transport.forgedCurrent = Map<String, dynamic>.from(activeWire)
          ..remove('activationAuthorization');
        try {
          await expectLater(
            SessionCryptoAccess(
              account: account,
            ).writeContext(scope, 'finance', online: true),
            throwsA(
              isA<CryptoAuthorityPending>().having(
                (e) => e.reason,
                'reason',
                'scope_keys_pending',
              ),
            ),
          );
        } finally {
          transport.forgedCurrent = null;
        }
      });
      test('forged activation cannot admit cached candidate key', () async {
        final forged =
            jsonDecode(jsonEncode(activeWire)) as Map<String, dynamic>;
        forged['activationAuthorization']['signatureBase64'] = base64Encode(
          List<int>.filled(64, 0),
        );
        transport.forgedCurrent = forged;
        try {
          await expectLater(
            SessionCryptoAccess(
              account: account,
            ).writeContext(scope, 'finance', online: true),
            throwsA(isA<FormatException>()),
          );
        } finally {
          transport.forgedCurrent = null;
        }
      });
      test('changed current device snapshot still requires rotation', () async {
        final owner = fixture['accounts']['owner'] as Map;
        final login = await transport.call(
          serverUrl: fixture['serverUrl'],
          operation: 'auth.login',
          params: {
            'username': owner['username'],
            'password': owner['password'],
            'deviceName': 'Synthetic admission second device',
          },
          allowLocalHttp: true,
        );
        final otherDb = CollaborationDatabase(NativeDatabase.memory());
        try {
          final paired = workflow(
            _session(fixture['serverUrl'], login),
            otherDb,
          );
          final card = await paired.prepareDeviceRequest();
          final confirmation = await account.authorizeDeviceRequest(card);
          await paired.acceptDeviceConfirmation(confirmation);
          await account.directory.requireFresh();
          await expectLater(
            SessionCryptoAccess(
              account: account,
            ).writeContext(scope, 'finance', online: true),
            throwsA(
              isA<CryptoAuthorityPending>().having(
                (e) => e.reason,
                'reason',
                'scope_rotation_required',
              ),
            ),
          );
        } finally {
          await otherDb.close();
        }
      });
    },
    skip: path == null
        ? 'Explicit disposable synthetic fixture required'
        : false,
  );
}
