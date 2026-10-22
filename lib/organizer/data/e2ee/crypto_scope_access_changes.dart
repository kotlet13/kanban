import '../../domain/shared_payload_validation.dart';

/// An authenticated denial notice only withdraws UI access. It is never a
/// membership proof, a readable scope, or authority to deliver queued work.
({List<String> revoked, List<String> deleted})? parseScopeAccessChanges(
  Object? reply, {
  required List<String> requested,
  required String serverId,
  required String accountId,
  required String deviceId,
}) {
  if (reply is! Map || reply['accessChangesVersion'] != 1) return null;
  const keys = {
    'accessChangesVersion',
    'serverId',
    'accountId',
    'deviceId',
    'scopeIds',
    'revokedScopeIds',
    'deletedScopeIds',
  };
  if (reply.length != keys.length ||
      !reply.keys.every(keys.contains) ||
      reply['serverId'] != serverId ||
      reply['accountId'] != accountId ||
      reply['deviceId'] != deviceId ||
      requested.isEmpty ||
      requested.length > 50 ||
      requested.toSet().length != requested.length ||
      !requested.every(isSharedUuid) ||
      requested.join(':') != (List<String>.from(requested)..sort()).join(':')) {
    return null;
  }
  final echo = reply['scopeIds'],
      revoked = reply['revokedScopeIds'],
      deleted = reply['deletedScopeIds'];
  if (echo is! List ||
      revoked is! List ||
      deleted is! List ||
      echo.length != requested.length ||
      revoked.length > requested.length ||
      deleted.length > revoked.length ||
      !echo.every((id) => id is String && isSharedUuid(id)) ||
      !revoked.every(
        (id) => id is String && isSharedUuid(id) && requested.contains(id),
      ) ||
      !deleted.every(
        (id) => id is String && isSharedUuid(id) && revoked.contains(id),
      ) ||
      echo.toSet().length != echo.length ||
      revoked.toSet().length != revoked.length ||
      deleted.toSet().length != deleted.length ||
      echo.join(':') != requested.join(':')) {
    return null;
  }
  return (
    revoked: List<String>.unmodifiable(revoked.cast<String>()),
    deleted: List<String>.unmodifiable(deleted.cast<String>()),
  );
}
