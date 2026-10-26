import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/authority_reuse_controller.dart';
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

class _Secure implements AccountCryptoStore {
  _Secure(File input)
    : values = (jsonDecode(input.readAsStringSync()) as Map)
          .cast<String, String>();
  final Map<String, String> values;
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class _ReadOnlyWire extends HttpCollaborationTransport {
  final calls = <String>[];
  int rejectedMutations = 0;
  static const allowed = {
    'capabilities',
    'crypto2.account.status',
    'crypto2.account.directory',
    'crypto2.account.scopeObservations',
    'crypto2.authority.snapshot',
    'crypto2.scopes.catalog',
    'crypto2.scope.headGet',
    'crypto2.directory.status',
    'crypto2.directory.read',
    'crypto2.scope.lifecycle.baseline',
    'crypto2.scope.lifecycle.current',
    'crypto2.scope.lifecycle.list',
    'crypto2.scope.financePolicy.current',
    'crypto2.scope.recordPolicy.status',
    'crypto2.scope.recordPolicy.baseline',
    'crypto2.scope.closureGet',
    'crypto2.grants.list',
    'crypto2.grants.manifest',
  };
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    if (!allowed.contains(operation) || params.containsKey('commandBase64')) {
      rejectedMutations++;
      throw StateError('Non-read intercepted before transport');
    }
    if (calls.length >= 180)
      throw StateError('Finite new read experiment bound');
    calls.add(operation);
    return super.call(
      serverUrl: serverUrl,
      operation: operation,
      params: params,
      token: token,
      allowLocalHttp: allowLocalHttp,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  final fixture = Platform.environment['JIVIE_AUTHORITY_READ_FIXTURE'];
  final root = Platform.environment['JIVIE_AUTHORITY_READ_ROOT'];
  test(
    'new full signed head consumers across fresh accesses reuse unchanged account scope evidence',
    () async {
      final input = jsonDecode(await File(fixture!).readAsString()) as Map;
      final url = input['serverUrl'] as String;
      if (input['synthetic'] != true ||
          Uri.parse(url).host != '127.0.0.1' ||
          Uri.parse(url).port != 59777 ||
          !root!.startsWith('/tmp/jivie-authority-change-driven-20261025')) {
        throw StateError(
          'Only preserved synthetic59777 private copied seed allowed',
        );
      }
      final sessionWire = input['accounts']['owner']['session'] as Map;
      final user = sessionWire['user'] as Map,
          device = sessionWire['device'] as Map;
      final session = DeviceSession(
        AccountSession(
          serverUrl: url,
          serverId: sessionWire['serverId'],
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
        sessionWire['token'],
      );
      final counts = <String, Map<String, dynamic>>{};
      final headSets = <String, List<String>>{};
      for (final label in ['baseline', 'optimized']) {
        final db = CollaborationDatabase(
          NativeDatabase(File('$root/$label/client.sqlite')),
        );
        addTearDown(db.close);
        final wire = _ReadOnlyWire();
        addTearDown(wire.close);
        final controller = AuthorityReuseController();
        if (label == 'optimized')
          controller.allowIfCurrent(controller.generation);
        final directory = AccountDirectoryRepository(
          reducer: AccountDirectoryV2(CryptoCodec(await SodiumInit.init())),
          session: session,
          transport: wire,
          store: CryptoIdentityStore(
            db,
            _Secure(File('$root/$label/secure.json')),
            session.profile.partition,
          ),
          isCurrent: () => true,
          authorityReuse: controller,
        );
        final account = AccountCryptoV2Workflow(directory);
        final scopes = await db.rows(
          "SELECT DISTINCT h.scope_id FROM crypto_scope_heads h JOIN scopes s ON s.partition=h.partition AND s.id=h.scope_id WHERE h.partition=? ORDER BY h.scope_id",
          [session.profile.partition],
        );
        if (scopes.length != 2)
          throw StateError('Exactly two retained signed scopes required');
        final seen = <String>[];
        final moduleCounts = <int>[];
        for (var module = 0; module < 3; module++) {
          // Each consumer starts a distinct mutable SessionCryptoAccess. Only raw
          // admitted wire evidence belongs to the common account repository.
          final access = SessionCryptoAccess(account: account);
          final before = wire.calls.length;
          for (final row in scopes) {
            final scope = row['scope_id'] as String;
            final value = await access.withVerifiedOperation(() async {
              final head = await access.currentHead(scope, online: true);
              final descriptor = await access.verifiedScopeDescriptor(scope);
              expect(descriptor['id'], scope);
              expect(head.member(session.profile.accountId)['role'], 'owner');
              return head;
            });
            seen.add('${value.scopeId}:${value.headHash}');
          }
          moduleCounts.add(wire.calls.length - before);
        }
        expect(wire.rejectedMutations, 0);
        headSets[label] = seen;
        counts[label] = {
          'transportCalls': wire.calls.length,
          'moduleRequests': moduleCounts,
          'operations': {
            for (final op in wire.calls.toSet())
              op: wire.calls.where((v) => v == op).length,
          },
          'mutationsSent': 0,
          'fullSignedHeadAdmissions': seen.length,
        };
      }
      expect(headSets['optimized'], headSets['baseline']);
      // First consumer verifies and admits; later consumers independently replay
      // complete signed authority with substantial transport-call reduction.
      final baseline = counts['baseline']!['transportCalls'] as int;
      final optimized = counts['optimized']!['transportCalls'] as int;
      expect(optimized, lessThan(baseline));
      expect(
        (counts['optimized']!['moduleRequests'] as List)[2],
        lessThan((counts['baseline']!['moduleRequests'] as List)[2]),
      );
      // ignore: avoid_print
      print(
        jsonEncode({
          'newSignedHeadReadCounts': counts,
          'retainedServerDataMutated': false,
        }),
      );
    },
    skip: fixture == null || root == null
        ? 'Explicit preserved synthetic read-only experiment not selected'
        : false,
    timeout: const Timeout(Duration(seconds: 90)),
  );
}
