import 'package:kanban/organizer/data/e2ee/crypto_finance_account_choices.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
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
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:sodium/sodium.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_router.dart';

class _DiskSecure implements AccountCryptoStore {
  _DiskSecure(this.file);
  final File file;
  Future<Map<String, dynamic>> _read() async => await file.exists()
      ? Map<String, dynamic>.from(jsonDecode(await file.readAsString()) as Map)
      : {};
  Future<void> _tail = Future<void>.value();
  @override
  Future<String?> read(String partition) async {
    await _tail;
    return (await _read())[partition] as String?;
  }

  @override
  Future<void> write(String partition, String value) {
    final task = _tail.then((_) async {
      final rows = await _read();
      rows[partition] = value;
      await file.writeAsString(jsonEncode(rows), flush: true);
    });
    _tail = task;
    return task;
  }
}

DeviceSession _session(String url, Map<String, dynamic> wire) {
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

class _BaseHttp extends HttpCollaborationTransport {
  final operations = <String>[];
  final sentAt = <DateTime>[];
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    // Only this disposable HTTP fixture paces its own requests. Production
    // quotas, scheduling, and verification remain unchanged.
    var now = DateTime.now();
    sentAt.removeWhere((t) => now.difference(t).inSeconds > 60);
    if (sentAt.length >= 440) {
      await Future<void>.delayed(
        const Duration(seconds: 61) - now.difference(sentAt.first),
      );
      now = DateTime.now();
      sentAt.clear();
    }
    sentAt.add(now);
    operations.add(operation);
    return super.call(
      serverUrl: serverUrl,
      operation: operation,
      params: params,
      token: token,
      allowLocalHttp: allowLocalHttp,
    );
  }
}

class _ReceiptHttp extends _BaseHttp {
  String? rejectedRequest;
  String? mode;
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    if (operation == 'crypto2.records.pull' && mode == 'stale-current') {
      throw const CryptoAuthorityPending('scope_current_anchor_required');
    }
    if (operation == 'crypto2.records.pull' && mode == 'forbidden') {
      throw const CollaborationApiException('finance_forbidden');
    }
    final result = await super.call(
      serverUrl: serverUrl,
      operation: operation,
      params: params,
      token: token,
      allowLocalHttp: allowLocalHttp,
    );
    if (operation == 'crypto2.receipt.get' &&
        params['requestId'] == rejectedRequest) {
      if (mode == 'inconsistent-outcome') {
        return {...result, 'outcome': 'applied'};
      }
      if (mode == 'unknown') {
        return {'requestId': rejectedRequest, 'outcome': 'unknown'};
      }
      if (mode == 'nonconflict') {
        return {
          ...result,
          'status': 409,
          'response': {'errorCode': 'crypto_scope_head_changed'},
        };
      }
      if (mode == 'denied') {
        return {
          ...result,
          'status': 403,
          'response': {'errorCode': 'permission_revoked'},
        };
      }
      if (mode == 'wrong-hash') return {...result, 'requestHash': '0' * 64};
      if (mode == 'wrong-authorization') {
        return {...result, 'authorization': <String, dynamic>{}};
      }
    }
    return result;
  }
}

void main() {
  final path = Platform.environment['JIVIE_INTERRUPTED_SHARING_FIXTURE'];
  test(
    'rejected choice receipt controls fail closed without a current projection',
    () async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final fixture = jsonDecode(await File(path!).readAsString()) as Map;
      final url = fixture['serverUrl'] as String;
      if (fixture['synthetic'] != true || Uri.parse(url).host != '127.0.0.1') {
        throw StateError('Disposable synthetic loopback required');
      }
      final dir = Directory(fixture['clientStateDir']);
      final inherited =
          jsonDecode(await File('${dir.path}/interrupted.json').readAsString())
              as Map;
      final state =
          jsonDecode(
                await File('${dir.path}/choice-conflict.json').readAsString(),
              )
              as Map;
      expect(state['held'], isTrue);
      expect(
        state['winnerPublished'],
        isNot(true),
        reason: 'The expanded cold race did not establish a winning projection',
      );
      final child = inherited['child'] as String;
      final proof = Map<String, dynamic>.from(state['winner'] as Map);
      final codec = CryptoCodec(await SodiumInit.init()), http = _ReceiptHttp();
      final session = _session(url, fixture['accounts']['other']['session']);
      final db = CollaborationDatabase(
        NativeDatabase(File('${dir.path}/${session.profile.deviceId}.sqlite')),
      );
      final account = AccountCryptoV2Workflow(
        AccountDirectoryRepository(
          reducer: AccountDirectoryV2(codec),
          session: session,
          transport: http,
          store: CryptoIdentityStore(
            db,
            _DiskSecure(
              File('${dir.path}/${session.profile.deviceId}.secure.json'),
            ),
            session.profile.partition,
          ),
          isCurrent: () => true,
        ),
      );
      final runtime = CryptoBusinessSession(
        account,
        SessionCryptoAccess(account: account),
        db,
      );
      CryptoBusinessRouter.configurePayloads(runtime);
      final choices = CryptoFinanceAccountChoices(runtime);
      Future<List<Map<String, Object?>>> rejected() => db.rows(
        'SELECT o.request_id,o.request_hash,o.signed_body,o.state,o.response FROM crypto_business_requests b JOIN crypto_outbox o ON o.partition=b.partition AND o.request_id=b.request_id WHERE b.partition=? AND b.operation_id=?',
        [runtime.partition, proof['operationId']],
      );
      Future<Map<String, dynamic>> materialize() => choices.materialize(
        child,
        offerAuthorization: Map<String, dynamic>.from(proof['offer'] as Map),
        delegationAuthorization: Map<String, dynamic>.from(
          proof['delegation'] as Map,
        ),
        certificateAuthorization: Map<String, dynamic>.from(
          proof['certificate'] as Map,
        ),
        operationId: proof['operationId'],
      );
      final pending = throwsA(
        isA<CryptoAuthorityPending>().having(
          (e) => e.reason,
          'reason',
          'crypto_business_delivery_pending',
        ),
      );
      try {
        final before = await rejected();
        expect(before.single['state'], 'rejected');
        final receipt = jsonDecode(before.single['response'] as String) as Map;
        expect(receipt['status'], 409);
        expect(receipt['response']['errorCode'], 'conflict');
        http.rejectedRequest = before.single['request_id'] as String;
        for (final mode in [
          'unknown',
          'inconsistent-outcome',
          'nonconflict',
          'denied',
          'wrong-hash',
          'wrong-authorization',
          'stale-current',
          'forbidden',
        ]) {
          http.mode = mode;
          final failure = mode == 'wrong-hash' || mode == 'wrong-authorization'
              ? throwsFormatException
              : mode == 'stale-current'
              ? throwsA(
                  isA<CryptoAuthorityPending>().having(
                    (e) => e.reason,
                    'reason',
                    'scope_current_anchor_required',
                  ),
                )
              : mode == 'forbidden'
              ? throwsA(
                  isA<CollaborationApiException>().having(
                    (e) => e.code,
                    'code',
                    'finance_forbidden',
                  ),
                )
              : pending;
          await expectLater(
            materialize(),
            failure,
            reason: '$mode must not satisfy the derived cache',
          );
        }
        http.mode = null;
        await expectLater(
          materialize(),
          throwsA(
            isA<CryptoAuthorityPending>().having(
              (e) => e.reason,
              'reason',
              'crypto_account_choices_publication_required',
            ),
          ),
          reason:
              'Even an authentic terminal conflict cannot replace a verified current choice',
        );
        expect(
          await cryptoSha256(CryptoJson.encode(await rejected())),
          await cryptoSha256(CryptoJson.encode(before)),
          reason:
              'All original signed bytes, receipt and terminal state stay untouched',
        );
        expect(
          http.operations.where(
            (op) => [
              'crypto2.records.batch',
              'crypto2.exports.propose',
              'crypto2.exports.delegate',
              'crypto2.exports.certify',
              'crypto2.invitations.accept',
              'crypto2.scope.create',
              'crypto2.scope.activate',
              'crypto2.grants.put',
            ].contains(op),
          ),
          isEmpty,
        );
        debugPrint(
          'CHOICE_CONFLICT_GUARDS ${jsonEncode({'negativeControls': 9, 'originalRejectedJournalUnchanged': true, 'noMutationRpc': true, 'currentProjectionUnavailableRemainsPending': true, 'recoverySuccessNotEstablished': true, 'operations': http.operations.length})}',
        );
      } finally {
        http.close();
        await db.close();
      }
    },
    skip: path == null,
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
