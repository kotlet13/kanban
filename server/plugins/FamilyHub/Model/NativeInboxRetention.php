<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** Seven days from first read; no content or unbounded deletion tombstones. */
class NativeInboxRetention extends NativeDatabase
{
    const READ_RETENTION_SECONDS = 7 * 86400;

    public static function cutoff($now = null)
    {
        return gmdate('Y-m-d\TH:i:s\Z', ($now ?? time()) - self::READ_RETENTION_SECONDS);
    }

    public static function expired(array $row, $now = null)
    {
        return $row['read_at'] !== null && $row['read_at'] <= self::cutoff($now);
    }

    /** Caller holds the recipient user lock in its transaction. */
    public function pruneForUser(array $user, $limit = 100, $now = null)
    {
        $cryptoLease=\Kanboard\Plugin\FamilyHub\Schema\CryptoSchema::ready($this->pdo)?NativeCryptoMaintenanceLease::acquire():null;
        if(NativeCryptoFence::cleanupPaused($this->pdo)){return 0;}
        if (!is_int($limit) || $limit < 1 || $limit > 500 || ($now !== null && !is_int($now))) { throw new NativeError('validation_error'); }
        $account = $user['account_id'];
        $writer = new NativeNotificationWriter($this->container);
        $writer->state($account);
        // Inbox writes also hold this state lock. Read/unread cannot change the
        // deadline between selection and deletion; delivery holds the user lock.
        $rows = $this->many('SELECT id FROM familyhub_inbox WHERE recipient_account_id=? AND read_at IS NOT NULL AND read_at<=? ORDER BY read_at,id LIMIT '.(int)$limit, [$account, self::cutoff($now)]);
        if (!$rows) { return 0; }
        $ids = array_column($rows, 'id'); $placeholders = implode(',', array_fill(0, count($ids), '?'));
        $this->change('DELETE FROM familyhub_push_jobs WHERE inbox_id IN ('.$placeholders.')', $ids);
        $this->change('DELETE FROM familyhub_deliveries WHERE inbox_id IN ('.$placeholders.')', $ids);
        $deleted = $this->change('DELETE FROM familyhub_inbox WHERE id IN ('.$placeholders.') AND recipient_account_id=? AND read_at IS NOT NULL AND read_at<=?', array_merge($ids, [$account, self::cutoff($now)]));
        if ($deleted) { $writer->visibilityChanged([$account]); }
        return $deleted;
    }

    /** Bounded existing cron cleanup, also for accounts with no active device. */
    public function run($limit = 100, $now = null)
    {
        if (!is_int($limit) || $limit < 1 || $limit > 500 || !defined('FAMILYHUB_ENABLE_NATIVE_API') || FAMILYHUB_ENABLE_NATIVE_API !== true) { throw new NativeError('feature_disabled', 503); }
        if ($now !== null && !is_int($now)) { throw new NativeError('validation_error'); }
        $now = $now ?? time(); $deleted = 0; $deadline = microtime(true) + 5;
        $previousTimeout = $this->sqlite ? (int)$this->one('PRAGMA busy_timeout')['timeout'] : (int)$this->one('SELECT @@SESSION.innodb_lock_wait_timeout AS seconds')['seconds'];
        $this->pdo->exec($this->sqlite ? 'PRAGMA busy_timeout=5000' : 'SET SESSION innodb_lock_wait_timeout=5');
        try {
            $accounts = $this->many('SELECT recipient_account_id FROM familyhub_inbox WHERE read_at IS NOT NULL AND read_at<=? GROUP BY recipient_account_id ORDER BY MIN(read_at),recipient_account_id LIMIT '.$limit, [self::cutoff($now)]);
            foreach ($accounts as $candidate) {
                if ($deleted >= $limit || microtime(true) >= $deadline) { break; }
                $deleted += $this->transaction(function () use ($candidate, $limit, $deleted, $now) {
                    $binding = $this->one('SELECT user_id FROM familyhub_accounts WHERE account_id=?', [$candidate['recipient_account_id']]);
                    if (!$binding) { return 0; }
                    $user = $this->one('SELECT id FROM users WHERE id=?'.$this->lockSuffix(), [$binding['user_id']]);
                    $account = $this->one('SELECT account_id FROM familyhub_accounts WHERE user_id=?', [$binding['user_id']]);
                    if (!$user || !$account || $account['account_id'] !== $candidate['recipient_account_id']) { return 0; }
                    $user['account_id'] = $account['account_id'];
                    return $this->pruneForUser($user, $limit - $deleted, $now);
                });
            }
            return ['deleted' => $deleted];
        } finally { $this->pdo->exec($this->sqlite ? 'PRAGMA busy_timeout='.$previousTimeout : 'SET SESSION innodb_lock_wait_timeout='.$previousTimeout); }
    }
}
