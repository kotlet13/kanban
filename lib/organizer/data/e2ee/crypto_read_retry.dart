import 'dart:async';
import 'dart:convert';

import '../collaboration_database.dart';
import '../collaboration_transport.dart';
import 'crypto_sync_repository.dart';

/// Read availability only. The queue retains its bounded progress and every
/// reply still passes the normal fresh READ/signature/reference checks. This
/// marker is never a checkpoint, authority floor or completeness proof.
Future<T> cryptoReadWithRatePause<T>({
  required CollaborationDatabase database,
  required String partition,
  required String scopeId,
  required String domain,
  required bool Function() isCurrent,
  required void Function() invalidateOperation,
  required Future<T> Function() read,
}) async {
  final name = 'crypto_read_retry:$partition:$scopeId:$domain';
  void current() {
    if (!isCurrent()) {
      throw const CryptoAuthorityPending('crypto_stale_identity');
    }
  }

  Future<void> pause(int seconds) async {
    current();
    invalidateOperation();
    await database.execute(
      'INSERT INTO local_meta(name,value) VALUES(?,?) ON CONFLICT(name) DO UPDATE SET value=excluded.value',
      [
        name,
        jsonEncode({
          'version': 1,
          'scopeId': scopeId,
          'domain': domain,
          'notBefore': DateTime.now().millisecondsSinceEpoch ~/ 1000 + seconds,
        }),
      ],
    );
    final elapsed = Completer<void>();
    final timer = Timer(Duration(seconds: seconds), elapsed.complete);
    final guard = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!isCurrent() && !elapsed.isCompleted) elapsed.complete();
    });
    try {
      await elapsed.future;
    } finally {
      timer.cancel();
      guard.cancel();
    }
    current();
    invalidateOperation();
  }

  current();
  final saved = await database.rows(
    'SELECT value FROM local_meta WHERE name=?',
    [name],
  );
  if (saved.isNotEmpty) {
    final value = jsonDecode(saved.single['value'] as String);
    if (value is! Map ||
        value.length != 4 ||
        value['version'] != 1 ||
        value['scopeId'] != scopeId ||
        value['domain'] != domain ||
        value['notBefore'] is! int) {
      throw const CryptoAuthorityPending('crypto_read_retry_pending');
    }
    final remaining =
        (value['notBefore'] as int) -
        DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (remaining > 60) {
      throw const CryptoAuthorityPending('crypto_read_retry_pending');
    }
    if (remaining > 0) await pause(remaining);
  }
  final result = await withCollaborationRateLimitPause(read, pause: pause);
  current();
  await database.execute('DELETE FROM local_meta WHERE name=?', [name]);
  return result;
}
