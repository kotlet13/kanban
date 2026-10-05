<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** Durable encrypted codes; jobs never run in unauthenticated HTTP request. */
class NativeAccountMailQueue extends NativeDatabase
{
    public function run($limit = 20, $transport = null)
    {
        if (!defined('FAMILYHUB_ENABLE_NATIVE_API') || FAMILYHUB_ENABLE_NATIVE_API !== true || !NativeAccountMailCrypto::configured()) { throw new NativeError('email_unavailable', 503); }
        if (!is_int($limit) || $limit < 1 || $limit > 50) { throw new NativeError('validation_error'); }
        $previousTimeout = $this->sqlite ? (int)$this->one('PRAGMA busy_timeout')['timeout'] : (int)$this->one('SELECT @@SESSION.innodb_lock_wait_timeout AS seconds')['seconds'];
        $this->pdo->exec($this->sqlite ? 'PRAGMA busy_timeout=5000' : 'SET SESSION innodb_lock_wait_timeout=5');
        try {
        $deadline = microtime(true) + 60; $transport = $transport ?? new NativeAccountMailTransport();
        $counts = ['examined' => 0, 'accepted' => 0, 'retry' => 0, 'cancelled' => 0];
        $rows = $this->many('SELECT token_id FROM familyhub_account_mail WHERE (state=\'pending\' AND next_attempt<=?) OR (state=\'processing\' AND lease_until<=?) ORDER BY next_attempt,token_id LIMIT '.$limit, [time(), time()]);
        foreach ($rows as $row) {
            // SMTP's command deadline plus a final socket wait can take 50s.
            if (microtime(true) + 50 > $deadline) { break; }
            $lease = $this->transaction(function () use ($row) {
                $job = $this->one('SELECT * FROM familyhub_account_mail WHERE token_id=?'.$this->lockSuffix(), [$row['token_id']]);
                if (!$job || !in_array($job['state'], ['pending', 'processing'], true) || ($job['state'] === 'processing' && (int)$job['lease_until'] > time()) || ($job['state'] === 'pending' && (int)$job['next_attempt'] > time())) { return null; }
                $lease = bin2hex(random_bytes(16));
                $this->change('UPDATE familyhub_account_mail SET state=\'processing\',attempts=attempts+1,lease_token=?,lease_until=? WHERE token_id=?', [$lease, time()+120, $row['token_id']]);
                return $lease;
            });
            if (!$lease) { continue; }
            $counts['examined']++;
            $counts[$this->deliver($row['token_id'], $lease, $transport, $deadline)]++;
        }
        return $counts;
        } finally { $this->pdo->exec($this->sqlite ? 'PRAGMA busy_timeout='.$previousTimeout : 'SET SESSION innodb_lock_wait_timeout='.$previousTimeout); }
    }

    private function deliver($id, $lease, $transport, $deadline)
    {
        return $this->transaction(function () use ($id, $lease, $transport, $deadline) {
            $row = $this->one('SELECT * FROM familyhub_account_tokens WHERE id=?', [$id]);
            $account = $row ? $this->one('SELECT user_id FROM familyhub_accounts WHERE account_id=?', [$row['account_id']]) : null;
            $user = $account ? $this->one('SELECT * FROM users WHERE id=?'.$this->lockSuffix(), [$account['user_id']]) : null;
            $job = $this->one('SELECT * FROM familyhub_account_mail WHERE token_id=?'.$this->lockSuffix(), [$id]);
            if (!$job || $job['state'] !== 'processing' || $job['lease_token'] !== $lease) { return 'cancelled'; }
            // Refresh token after user lock; verification/reset issuance shares it.
            $row = $this->one('SELECT * FROM familyhub_account_tokens WHERE id=?', [$id]);
            $identity = $row ? $this->one('SELECT * FROM familyhub_email_identities WHERE account_id=?', [$row['account_id']]) : null;
            $valid = $user && (int)$user['is_active'] === 1 && (int)$user['is_ldap_user'] === 0 && (int)$user['disable_login_form'] === 0 && $row && $row['revoked_at'] === null && $row['consumed_at'] === null && (int)$row['expires_at'] > time() && $job['attempts'] <= 5 && hash_equals($row['fingerprint'], $this->fingerprint($user)) && $identity && (int)$identity['revision'] === (int)$row['identity_revision'] && ($row['purpose'] === 'verify' ? $identity['pending_email'] === $row['email'] : $identity['verified_at'] !== null && $identity['email'] === $row['email']);
            if (!$valid) { $this->finish($id, $lease, 'cancelled'); return 'cancelled'; }
            if (microtime(true) + 50 > $deadline) { $this->retry($id, $lease, 60); return 'retry'; }
            try {
                $code = NativeAccountMailCrypto::decrypt($job['token_cipher'], (new NativeAccountTokens($this->container))->aad($id, $row['account_id']));
                if (!hash_equals($row['token_hash'], hash('sha256', $code))) { throw new NativeError('email_unavailable', 503); }
                if (($transport->send($row['email'], $row['purpose'], $code, $id, $job['language'])['accepted'] ?? false) !== true) { throw new NativeError('email_unavailable', 503); }
                $this->finish($id, $lease, 'accepted'); return 'accepted';
            } catch (\Throwable $ignored) {
                if ((int)$job['attempts'] >= 5) { $this->finish($id, $lease, 'cancelled'); return 'cancelled'; }
                $this->retry($id, $lease, min(900, 60 * (2 ** (int)$job['attempts']))); return 'retry';
            }
        });
    }
    private function finish($id, $lease, $state)
    {
        $this->change('UPDATE familyhub_account_mail SET state=?,token_cipher=NULL,lease_token=NULL,accepted_at=? WHERE token_id=? AND lease_token=?', [$state, $state === 'accepted' ? time() : null, $id, $lease]);
    }
    private function retry($id, $lease, $seconds)
    {
        $this->change('UPDATE familyhub_account_mail SET state=\'pending\',lease_token=NULL,next_attempt=? WHERE token_id=? AND lease_token=?', [time()+$seconds, $id, $lease]);
    }
}
