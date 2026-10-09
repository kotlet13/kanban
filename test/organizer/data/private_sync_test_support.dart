import 'dart:async';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/organizer_storage.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'collaboration_repository_test.dart' show FakeServer, FakeTransport;

class PersonalTransport extends FakeTransport {
  PersonalTransport(super.server);
  final finances = FakeServer();
  final privateScopes = <String, String>{};
  Future<void> Function()? beforeReset;
  bool revokeMe = false;
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    if (offline) throw const CollaborationException('network');
    if (operation == 'capabilities') {
      return {
        ...await super.call(serverUrl: serverUrl, operation: operation),
        'recordContractVersions': [1, 2],
        'features': {
          'recordSync': true,
          'scopeAccessChanges': true,
          'finance': true,
          'privateSync': true,
          'personalFinanceEntry': true,
          'emailVerification': true,
          'passwordReset': true,
        },
      };
    }
    if (operation == 'auth.reset.confirm') {
      await beforeReset?.call();
      return {'reset': true};
    }
    if (operation == 'auth.me') {
      if (revokeMe) throw const CollaborationApiException('device_revoked');
      return {};
    }
    if (operation == 'account.email.request') {
      throw const CollaborationApiException('invalid_credentials');
    }
    final user = server.tokens[token];
    if (operation == 'personal.ensure') {
      final id = privateScopes.putIfAbsent(user!, () => newSharedId());
      if (!server.scopes.containsKey(id)) {
        await server.call('scopes.create', {
          'id': id,
          'name': 'Personal',
          'kind': 'personal',
        }, token);
      }
      return {
        'scope': {...server.scopes[id]!, 'role': 'owner'},
      };
    }
    if (operation == 'scopes.members') {
      return {
        'members': [
          {
            'accountId': server.accountIds[user],
            'userId': user == 'alice' ? 1 : 2,
            'username': user,
            'displayName': user,
            'role': 'owner',
            'active': true,
          },
        ],
      };
    }
    if (operation == 'finance.policy') {
      return {'enabled': true, 'grant': 'write', 'revision': 1};
    }
    if (operation.startsWith('finance.')) {
      final scope = params['scopeId'] as String;
      finances.tokens.addAll(server.tokens);
      finances.members[scope] = Map.of(server.members[scope]!);
      finances.records.putIfAbsent(scope, () => {});
      finances.sequence.putIfAbsent(scope, () => 0);
      if (operation == 'finance.push') {
        final op = params['operation'] as Map;
        final project = (op['payload'] as Map?)?['projectId'];
        if (project != null &&
            (server.records[scope]?[project] == null ||
                server.records[scope]![project]!['deleted'] == true)) {
          throw const CollaborationApiException('parent_missing');
        }
        return finances.call('sync.push', params, token);
      }
      if (operation == 'finance.pull') {
        return {
          ...await finances.call('sync.pull', params, token),
          'accessRevision': 1,
        };
      }
      if (operation == 'finance.audit') return {'entries': []};
    }
    if (operation == 'sync2.push') {
      final op = params['operation'] as Map, scope = params['scopeId'];
      if (op['type'] == 'project' &&
          op['deleted'] == true &&
          (finances.records[scope]?.values.any(
                (r) =>
                    r['deleted'] == false &&
                    (r['payload'] as Map?)?['projectId'] == op['recordId'],
              ) ??
              false)) {
        throw const CollaborationApiException('live_children');
      }
    }
    return super.call(
      serverUrl: serverUrl,
      operation: operation == 'sync2.pull'
          ? 'sync.pull'
          : operation == 'sync2.push'
          ? 'sync.push'
          : operation,
      params: params,
      token: token,
      allowLocalHttp: allowLocalHttp,
    );
  }
}

class LegacyMemory implements OrganizerStorage {
  LegacyMemory(this.snapshot);
  OrganizerSnapshot snapshot;
  bool closed = false;
  @override
  Future<OrganizerSnapshot> read() async => snapshot;
  @override
  Future<void> write(OrganizerSnapshot value) async {
    snapshot = value;
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}
