<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** Durable reference-only delivery queue. SMTP acceptance is not inbox exactly-once. */
class NativeDeliveryService extends NativeDatabase
{
    public function enqueue($inboxId)
    {
        if (!NativeSmtpTransport::configured()) { return; }
        $insert = $this->sqlite ? 'INSERT OR IGNORE' : 'INSERT IGNORE';
        $this->change($insert.' INTO familyhub_deliveries(inbox_id,state,attempts,next_attempt,expires_at) VALUES(?,\'pending\',0,?,?)', [$inboxId, time(), time() + 86400]);
    }

    public function run($limit = 20, $transport = null)
    {
        if (!NativeSmtpTransport::configured() || !defined('FAMILYHUB_ENABLE_NATIVE_API') || FAMILYHUB_ENABLE_NATIVE_API !== true) { throw new NativeError('smtp_unavailable', 503); }
        if (!is_int($limit) || $limit < 1 || $limit > 50) { throw new NativeError('validation_error'); }
        $previousTimeout = $this->sqlite ? (int)$this->one('PRAGMA busy_timeout')['timeout'] : (int)$this->one('SELECT @@SESSION.innodb_lock_wait_timeout AS seconds')['seconds'];
        $this->pdo->exec($this->sqlite ? 'PRAGMA busy_timeout=5000' : 'SET SESSION innodb_lock_wait_timeout=5');
        try {
        // Match account-mail: reserve the command deadline plus final socket wait.
        $deadline = microtime(true) + 60; $transport = $transport ?? new NativeSmtpTransport();
        $counts = ['examined' => 0, 'accepted' => 0, 'retry' => 0, 'cancelled' => 0];
        $rows = $this->many('SELECT d.inbox_id,i.scope_id FROM familyhub_deliveries d JOIN familyhub_inbox i ON i.id=d.inbox_id WHERE (d.state=\'pending\' AND d.next_attempt<=?) OR (d.state=\'processing\' AND d.lease_until<=?) ORDER BY d.next_attempt,d.inbox_id LIMIT '.$limit, [time(), time()]);
        foreach ($rows as $candidate) {
            if (microtime(true) + 50 > $deadline) { break; }
            $counts['examined']++;
            $lease = $this->transaction(function () use ($candidate) {
                $row = $this->one('SELECT * FROM familyhub_deliveries WHERE inbox_id=?'.$this->lockSuffix(), [$candidate['inbox_id']]);
                if (!$row || !in_array($row['state'], ['pending', 'processing'], true) || ($row['state'] === 'processing' && (int)$row['lease_until'] > time()) || ($row['state'] === 'pending' && (int)$row['next_attempt'] > time())) { return null; }
                if ((int)$row['expires_at'] <= time() || (int)$row['attempts'] >= 5) {
                    $this->change('UPDATE familyhub_deliveries SET state=\'cancelled\',lease_token=NULL,lease_until=NULL WHERE inbox_id=?', [$row['inbox_id']]); return false;
                }
                $lease = bin2hex(random_bytes(16));
                $this->change('UPDATE familyhub_deliveries SET state=\'processing\',attempts=attempts+1,lease_token=?,lease_until=? WHERE inbox_id=?', [$lease, time() + 120, $row['inbox_id']]);
                return $lease;
            });
            if ($lease === null) { continue; }
            if ($lease === false) { $counts['cancelled']++; continue; }
            $counts[$this->deliver($candidate['inbox_id'], $lease, $transport, $deadline)]++;
        }
        return $counts;
        } finally { $this->pdo->exec($this->sqlite ? 'PRAGMA busy_timeout='.$previousTimeout : 'SET SESSION innodb_lock_wait_timeout='.$previousTimeout); }
    }

    private function deliver($id, $lease, $transport, $deadline)
    {
        return $this->transaction(function () use ($id, $lease, $transport, $deadline) {
            $inbox = $this->one('SELECT * FROM familyhub_inbox WHERE id=?', [$id]);
            $binding = $inbox ? $this->one('SELECT user_id FROM familyhub_accounts WHERE account_id=?', [$inbox['recipient_account_id']]) : null;
            // Native mutations lock user -> scope. Core user updates also wait on
            // this row; the Native global mutex alone would not protect email.
            $user = $binding ? $this->one('SELECT id,email,is_active FROM users WHERE id=?'.$this->lockSuffix(), [$binding['user_id']]) : null;
            if ($inbox) { $deliveryScope=$this->one('SELECT id,archived FROM familyhub_scopes WHERE id=?'.$this->lockSuffix(), [$inbox['scope_id']]); }
            $job = $this->one('SELECT * FROM familyhub_deliveries WHERE inbox_id=?'.$this->lockSuffix(), [$id]);
            if (!$job || $job['state'] !== 'processing' || $job['lease_token'] !== $lease) { return 'cancelled'; }
            // Refresh all references after lock waits, including account deletion.
            $inbox = $this->one('SELECT * FROM familyhub_inbox WHERE id=?', [$id]);
            $account = $user ? $this->one('SELECT account_id FROM familyhub_accounts WHERE user_id=?', [$user['id']]) : null;
            $settings = $inbox ? $this->one('SELECT settings FROM familyhub_inbox_preferences WHERE scope_id=? AND account_id=? AND category=?', [$inbox['scope_id'], $inbox['recipient_account_id'], $inbox['category']]) : null;
            $settings = $settings ? json_decode($settings['settings'], true, 32, JSON_THROW_ON_ERROR) : [];
            $visible = $inbox && !(int)($deliveryScope['archived']??0) && (new NativeFinanceAccess($this->container))->visible($inbox['scope_id'], $inbox['recipient_account_id'], $this->financialRecordType($inbox['target_type']));
            if (!$user || (int)$user['is_active'] !== 1 || !$account || !$inbox || $account['account_id'] !== $inbox['recipient_account_id'] || !$visible || !($settings['email'] ?? false) || !filter_var($user['email'], FILTER_VALIDATE_EMAIL) || (int)$job['expires_at'] <= time() || (int)$job['attempts'] > 5) {
                $this->finish($id, $lease, 'cancelled'); return 'cancelled';
            }
            if (microtime(true) + 50 > $deadline) { $this->finish($id, $lease, 'pending', 60); return 'retry'; }
            // Ordinary inbox mail follows the current address; it carries no code
            // or source content. Security mail remains bound to its own identity.
            try { $transport->send($user['email'], (int)$id, $inbox['recipient_account_id']); $accepted = true; }
            catch (\Throwable $ignored) { $accepted = false; } // Never log SMTP exceptions.
            $state = $accepted ? 'sent' : ((int)$job['attempts'] >= 5 ? 'cancelled' : 'pending');
            $this->finish($id, $lease, $state, min(3600, 30 * (2 ** (int)$job['attempts'])));
            return $accepted ? 'accepted' : ($state === 'cancelled' ? 'cancelled' : 'retry');
        });
    }

    private function finish($id, $lease, $state, $delay = 0)
    {
        $this->change('UPDATE familyhub_deliveries SET state=?,next_attempt=?,sent_at=?,lease_token=NULL,lease_until=NULL WHERE inbox_id=? AND lease_token=?', [$state, time() + $delay, $state === 'sent' ? time() : null, $id, $lease]);
    }
}
