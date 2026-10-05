import 'dart:async';
import 'dart:convert';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/remote_push_store.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'collaboration_repository_test.dart' show FakeTransport;

class MemoryPushStore implements RemotePushStore {
  RemotePushIntent? value;
  List<RemotePushCleanup> cleanups = [];
  bool failWrite = false;
  Future<void> Function()? beforeWrite;
  @override
  Future<RemotePushIntent?> read() async => value;
  @override
  Future<void> write(RemotePushIntent intent) async {
    await beforeWrite?.call();
    if (failWrite) throw const CollaborationException('secure_storage');
    value = intent;
  }

  @override
  Future<void> clear() async => value = null;
  @override
  Future<List<RemotePushCleanup>> readCleanups() async => [...cleanups];
  @override
  Future<void> writeCleanups(List<RemotePushCleanup> values) async {
    if (failWrite) throw const CollaborationException('secure_storage');
    cleanups = [...values];
  }
}

class PushTransport extends FakeTransport {
  PushTransport(super.server);
  bool enabled = true, loseRegisterReply = false, loseUnregisterReply = false;
  bool denyGroup = false;
  String projectId = 'test-project';
  final registrations = <String, Map<String, dynamic>>{};
  final items = <SharedInboxEntry>[];
  final calls =
      <({String operation, String? token, Map<String, Object?> params})>[];
  Future<void> Function(
    String operation,
    String? token,
    Map<String, Object?> params,
  )?
  before;
  Map<String, dynamic> Function(Map<String, Object?> params)? groupOverride;
  Map<String, dynamic> registration(String token) => registrations.putIfAbsent(
    token,
    () => {
      'registered': false,
      'platform': null,
      'language': null,
      'revision': 0,
      'updatedAt': null,
    },
  );
  Map<String, dynamic> publicRegistration(String token) => {
    for (final entry in registration(token).entries)
      if (!const {'token', 'projectId'}.contains(entry.key))
        entry.key: entry.value,
  };
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    if (offline) throw const CollaborationException('network');
    calls.add((
      operation: operation,
      token: token,
      params: jsonDecode(jsonEncode(params)) as Map<String, dynamic>,
    ));
    await before?.call(operation, token, params);
    if (operation == 'capabilities') {
      return {
        'serverId': server.serverId,
        'api': 'familyhub_native',
        'version': 1,
        'enabled': true,
        'recordContractVersions': [1],
        'pushProjectId': enabled ? projectId : null,
        'features': {
          'recordSync': true,
          'inbox': false,
          'finance': false,
          'externalPush': enabled,
        },
      };
    }
    if (operation.startsWith('push.') || operation.startsWith('inbox.')) {
      if (!server.tokens.containsKey(token)) {
        throw const CollaborationApiException('device_revoked');
      }
      final current = registration(token!);
      if (operation == 'push.state') {
        return {'registration': publicRegistration(token)};
      }
      if (operation == 'push.register') {
        if (!enabled) throw const CollaborationApiException('push_unavailable');
        if (params['projectId'] != projectId) {
          throw const CollaborationApiException('push_project_mismatch');
        }
        final identical =
            current['registered'] == true &&
            current['token'] == params['token'] &&
            current['platform'] == params['platform'] &&
            current['language'] == params['language'];
        if (!identical) {
          if (params['expectedRevision'] != current['revision']) {
            throw CollaborationApiException(
              'push_conflict',
              details: {'registration': publicRegistration(token)},
            );
          }
          if (registrations.entries.any(
            (e) =>
                e.key != token &&
                e.value['registered'] == true &&
                e.value['token'] == params['token'],
          )) {
            throw const CollaborationApiException('push_token_bound');
          }
          registrations[token] = {
            'registered': true,
            'token': params['token'],
            'platform': params['platform'],
            'language': params['language'],
            'projectId': params['projectId'],
            'revision': (current['revision'] as int) + 1,
            'updatedAt': '2026-10-05T12:00:00Z',
          };
        }
        if (loseRegisterReply) {
          loseRegisterReply = false;
          throw const CollaborationException('network');
        }
        return {'registration': publicRegistration(token)};
      }
      if (operation == 'push.unregister') {
        if (current['registered'] == true) {
          if (params.containsKey('expectedRevision') &&
              params['expectedRevision'] != current['revision']) {
            throw CollaborationApiException(
              'push_conflict',
              details: {'registration': publicRegistration(token)},
            );
          }
          registrations[token] = {
            'registered': false,
            'platform': null,
            'language': null,
            'revision': (current['revision'] as int) + 1,
            'updatedAt': '2026-10-05T12:00:00Z',
          };
        }
        if (loseUnregisterReply) {
          loseUnregisterReply = false;
          throw const CollaborationException('network');
        }
        return {'registration': publicRegistration(token)};
      }
      if (operation == 'inbox.group') {
        if (denyGroup) {
          throw const CollaborationApiException('permission_revoked');
        }
        if (groupOverride != null) return groupOverride!(params);
        final anchor = items.where((i) => i.id == params['id']).firstOrNull;
        if (anchor == null) {
          throw const CollaborationApiException('permission_revoked');
        }
        final found =
            items
                .where(
                  (i) =>
                      i.id <= anchor.id &&
                      i.groupKey == anchor.groupKey &&
                      i.scopeId == anchor.scopeId &&
                      i.category == anchor.category &&
                      i.kind == anchor.kind &&
                      i.audience == anchor.audience &&
                      (params['beforeId'] == null ||
                          i.id < (params['beforeId'] as int)),
                )
                .toList()
              ..sort((a, b) => b.id.compareTo(a.id));
        final limit = params['limit'] as int? ?? 100,
            page = found.take(limit).toList();
        return {
          'items': page.map((i) => i.toJson()).toList(),
          'hasMore': found.length > limit,
          'nextBeforeId': found.length > limit ? page.last.id : null,
        };
      }
      if (operation == 'inbox.open') {
        if (denyGroup) {
          throw const CollaborationApiException('permission_revoked');
        }
        final item = items.singleWhere((i) => i.id == params['id']);
        return {
          'item': item.toJson(),
          'target': {
            'scopeId': item.scopeId,
            'type': item.targetType,
            'id': item.targetId,
          },
          'record': server.records[item.scopeId]?[item.targetId],
        };
      }
    }
    final reply = await super.call(
      serverUrl: serverUrl,
      operation: operation,
      params: params,
      token: token,
      allowLocalHttp: allowLocalHttp,
    );
    if (operation == 'auth.revoke') registrations.remove(token);
    return reply;
  }
}
