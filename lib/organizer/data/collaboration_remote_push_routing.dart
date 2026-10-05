part of 'collaboration_repository.dart';

/// Resolve provider references through the recipient's persisted inbox. No route,
/// server URL, record payload or financial value is accepted from provider data.
extension CollaborationRemotePushRouting on CollaborationRepository {
  static const _maxPushGroupItems = 500;
  Future<SharedInboxEntry?> _cachedPushAnchor(
    DeviceSession session,
    int id,
  ) async {
    final p = session.profile.partition;
    final inbox = await database.rows(
      'SELECT data FROM inbox WHERE partition=? AND id=?',
      [p, id],
    );
    final stored = await database.rows(
      'SELECT value FROM local_meta WHERE name=?',
      ['push_reference:$p:$id'],
    );
    return inbox.isNotEmpty
        ? SharedInboxEntry.fromJson(
            CollaborationRepository._map(inbox.first['data']),
          )
        : stored.isNotEmpty
        ? SharedInboxEntry.fromJson(
            CollaborationRepository._map(stored.first['value']),
          )
        : null;
  }

  Future<List<SharedInboxEntry>> _cachedPushGroup(
    DeviceSession session,
    int id,
  ) async {
    final p = session.profile.partition;
    final markers = await database.rows(
      'SELECT value FROM local_meta WHERE name=?',
      ['push_group:$p:$id'],
    );
    if (markers.isEmpty) {
      return []; // A partial inbox snapshot cannot prove a complete group.
    }
    final ids =
        (CollaborationRepository._map(markers.first['value'])['ids'] as List)
            .cast<int>();
    if (ids.isEmpty ||
        ids.length > _maxPushGroupItems ||
        !ids.contains(id) ||
        ids.toSet().length != ids.length) {
      throw const CollaborationException('invalid_response');
    }
    final rows = await database.rows(
      'SELECT value FROM local_meta WHERE name IN (${List.filled(ids.length, '?').join(',')})',
      [for (final entryId in ids) 'push_reference:$p:$entryId'],
    );
    final entries = rows
        .map(
          (r) => SharedInboxEntry.fromJson(
            CollaborationRepository._map(r['value']),
          ),
        )
        .toList();
    if (entries.length != ids.length) return [];
    final anchor = entries.singleWhere((e) => e.id == id);
    if (entries.any((e) => e.id > id || !_samePushGroup(anchor, e))) {
      throw const CollaborationException('invalid_response');
    }
    return entries;
  }

  bool _samePushGroup(SharedInboxEntry a, SharedInboxEntry b) =>
      a.scopeId == b.scopeId &&
      a.groupKey == b.groupKey &&
      a.kind == b.kind &&
      a.audience == b.audience &&
      a.category == b.category &&
      a.createdAt.difference(b.createdAt).abs() <= const Duration(minutes: 5);
  void _validatePushItem(SharedInboxEntry entry) {
    if (entry.id <= 0 ||
        !isSharedUuid(entry.scopeId) ||
        !isSharedUuid(entry.targetId) ||
        !const {
          'task',
          'project',
          'event',
          'shoppingList',
          'shoppingItem',
          'membership',
          'financeAccount',
          'financeEntry',
          'financeTransfer',
        }.contains(entry.targetType)) {
      throw const CollaborationException('invalid_response');
    }
  }

  Future<RemotePushOpenResult> openRemotePushReference(
    RemotePushReference reference,
  ) async {
    RemotePushReference.parse(reference.toData());
    final session = _session, epoch = _epoch;
    if (session == null || _sessionInvalidReason != null) {
      return const RemotePushOpenResult(
        status: RemotePushOpenStatus.requiresLogin,
      );
    }
    if (!reference.matches(session.profile)) {
      return const RemotePushOpenResult(
        status: RemotePushOpenStatus.wrongAccount,
      );
    }
    var entries = <SharedInboxEntry>[];
    var offline = false;
    try {
      await _negotiate(session, epoch);
      int? before;
      var more = true;
      SharedInboxEntry? anchor;
      while (more) {
        final reply = await _callSession(session, epoch, 'inbox.group', {
          'id': reference.notificationId,
          if (before != null) 'beforeId': before,
          'limit': 100,
        });
        final page = (reply['items'] as List)
            .map((j) => SharedInboxEntry.fromJson(j as Map<String, dynamic>))
            .toList();
        var previousId = before ?? reference.notificationId + 1;
        for (final item in page) {
          _validatePushItem(item);
          if (item.id == reference.notificationId) anchor = item;
          if (item.id >= previousId ||
              item.id > reference.notificationId ||
              entries.any((e) => e.id == item.id)) {
            throw const CollaborationException('invalid_response');
          }
          previousId = item.id;
        }
        entries.addAll(page);
        more = readBool(reply, 'hasMore');
        if (page.length > 100 ||
            entries.length > _maxPushGroupItems ||
            (more && page.isEmpty)) {
          throw const CollaborationException('invalid_response');
        }
        if (more) {
          final next = reply['nextBeforeId'];
          if (next is! int ||
              next <= 0 ||
              next != page.last.id ||
              (before != null && next >= before)) {
            throw const CollaborationException('invalid_response');
          }
          before = next;
        }
      }
      if (anchor == null || entries.any((e) => !_samePushGroup(anchor!, e))) {
        throw const CollaborationException('invalid_response');
      }
      await syncNow();
      _checkEpoch(epoch);
      await database.transaction(() async {
        _checkEpoch(epoch);
        await database.execute(
          'INSERT INTO local_meta(name,value) VALUES(?,?) ON CONFLICT(name) DO UPDATE SET value=excluded.value',
          [
            'push_group:${session.profile.partition}:${reference.notificationId}',
            jsonEncode({
              'ids': entries.map((e) => e.id).toList(),
              'scopeId': anchor!.scopeId,
              'category': anchor.category,
            }),
          ],
        );
        for (final entry in entries) {
          if (entry.category == 'finance' &&
              !(await _cachedFinancePolicy(
                session.profile.partition,
                entry.scopeId,
              )).canRead) {
            continue;
          }
          await database.execute(
            'INSERT INTO local_meta(name,value) VALUES(?,?) ON CONFLICT(name) DO UPDATE SET value=excluded.value',
            [
              'push_reference:${session.profile.partition}:${entry.id}',
              jsonEncode(entry.toJson()),
            ],
          );
        }
      });
    } on CollaborationException catch (e) {
      _checkEpoch(epoch);
      if (e.code == 'network') {
        offline = true;
        entries = await _cachedPushGroup(session, reference.notificationId);
      } else if (e.code == 'permission_revoked' ||
          e.code == 'finance_forbidden') {
        final cachedAnchor = await _cachedPushAnchor(
          session,
          reference.notificationId,
        );
        if (cachedAnchor != null) {
          if (e.code == 'permission_revoked') {
            await _blockScope(
              session.profile.partition,
              cachedAnchor.scopeId,
              epoch,
            );
          } else {
            await database.transaction(() async {
              _checkEpoch(epoch);
              await _storeFinancePolicy(
                session.profile.partition,
                cachedAnchor.scopeId,
                const SharedFinancePolicy(),
              );
            });
          }
          await refreshLocal();
        }
        return const RemotePushOpenResult(
          status: RemotePushOpenStatus.permissionDenied,
        );
      } else {
        rethrow;
      }
    }
    _checkEpoch(epoch);
    if (entries.isEmpty) {
      return const RemotePushOpenResult(
        status: RemotePushOpenStatus.requiresConnection,
      );
    }
    for (final entry in entries) {
      _validatePushItem(entry);
    }
    final target = SharedInboxGroup(entries).targetFor(session.profile);
    final opened = await openNotificationTarget(target);
    final status = RemotePushOpenStatus.values.byName(opened.status.name);
    return RemotePushOpenResult(
      status: offline && status == RemotePushOpenStatus.available
          ? RemotePushOpenStatus.offline
          : status,
      target: opened.target,
    );
  }
}
