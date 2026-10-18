import 'account_directory_v2.dart';
import 'crypto_identity_store.dart';

Future<VerifiedAccountDirectory?> finishCryptoDirectoryPromotion({
  required CryptoIdentityStore store,
  required AccountDirectoryV2 reducer,
  required String accountId,
  required String serverId,
  required bool Function() isCurrent,
}) async {
  final anchor = await store.anchor(accountId);
  if (anchor == null || (anchor['generation'] as int? ?? 0) == 0) return null;
  final live = await store.database.rows(
    'SELECT head_hash FROM crypto_directory_entries WHERE partition=? AND account_id=? AND generation=?',
    [store.partition, accountId, anchor['generation']],
  );
  if (live.length == 1 && live.single['head_hash'] == anchor['headHash'])
    return null;
  final runs = await store.database.rows(
    'SELECT DISTINCT run_id FROM crypto_directory_replay_staging WHERE partition=? AND account_id=? AND generation=? AND head_hash=?',
    [store.partition, accountId, anchor['generation'], anchor['headHash']],
  );
  if (runs.isEmpty) return null;
  final run = runs.first['run_id'] as String;
  VerifiedAccountDirectory? state;
  final pin = anchor['genesisFingerprint'] ?? anchor['fingerprint'];
  await for (final e in store.streamEntries(accountId)) {
    if (e['generation'] > anchor['generation']) break;
    state = await reducer.apply(
      previous: state,
      entry: e,
      serverId: serverId,
      accountId: accountId,
      pinnedRootFingerprint: pin,
    );
  }
  await for (final e in store.streamEntries(accountId, runId: run)) {
    if (e['generation'] > anchor['generation']) break;
    if (state != null && e['generation'] <= state.generation) {
      if (!state.includesAnchor(e['generation'], e['headHash']))
        throw const CryptoDirectoryException('directory_promotion_fork');
      continue;
    }
    state = await reducer.apply(
      previous: state,
      entry: e,
      serverId: serverId,
      accountId: accountId,
      pinnedRootFingerprint: pin,
    );
  }
  if (state == null ||
      state.generation != anchor['generation'] ||
      state.headHash != anchor['headHash'] ||
      state.snapshotHash != anchor['snapshotHash'] ||
      state.rootFingerprint != anchor['fingerprint'])
    throw const CryptoDirectoryException('directory_promotion_invalid');
  final current = await store.anchor(accountId);
  if (current?['headHash'] != anchor['headHash'] ||
      current?['fingerprint'] != anchor['fingerprint'])
    throw const CryptoDirectoryException('directory_promotion_retry');
  if (!isCurrent())
    throw const CryptoDirectoryException('directory_stale_identity');
  await store.database.transaction(() async {
    await for (final e in store.streamEntries(accountId, runId: run)) {
      if (e['generation'] <= anchor['generation'])
        await store.append(accountId, e);
    }
    await store.database.execute(
      'DELETE FROM crypto_directory_replay_staging WHERE partition=? AND run_id=?',
      [store.partition, run],
    );
  });
  return state;
}
