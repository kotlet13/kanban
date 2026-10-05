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

    public function run($limit = 20)
    {
        if (!NativeSmtpTransport::configured() || !defined('FAMILYHUB_ENABLE_NATIVE_API') || FAMILYHUB_ENABLE_NATIVE_API !== true) { throw new NativeError('smtp_unavailable', 503); }
        if (!is_int($limit) || $limit < 1 || $limit > 50) { throw new NativeError('validation_error'); }
        $deadline = microtime(true) + 40; $counts = ['examined' => 0, 'accepted' => 0, 'retry' => 0, 'cancelled' => 0];
        $rows = $this->many('SELECT d.inbox_id,i.scope_id FROM familyhub_deliveries d JOIN familyhub_inbox i ON i.id=d.inbox_id WHERE (d.state=\'pending\' AND d.next_attempt<=?) OR (d.state=\'processing\' AND d.lease_until<=?) ORDER BY d.next_attempt,d.inbox_id LIMIT '.$limit, [time(), time()]);
        foreach ($rows as $candidate) {
            if (microtime(true) >= $deadline) { break; }
            $counts['examined']++;
            $job = $this->transaction(function () use ($candidate) {
                $this->one('SELECT id FROM familyhub_scopes WHERE id=?'.$this->lockSuffix(), [$candidate['scope_id']]);
                $row = $this->one('SELECT d.*,i.recipient_account_id,i.scope_id,i.category,i.target_type FROM familyhub_deliveries d JOIN familyhub_inbox i ON i.id=d.inbox_id WHERE d.inbox_id=?'.$this->lockSuffix(), [$candidate['inbox_id']]);
                if (!$row || !in_array($row['state'], ['pending', 'processing'], true) || ($row['state'] === 'processing' && (int)$row['lease_until'] > time()) || ($row['state'] === 'pending' && (int)$row['next_attempt'] > time())) { return null; }
                $settings = $this->one('SELECT settings FROM familyhub_inbox_preferences WHERE scope_id=? AND account_id=? AND category=?', [$row['scope_id'], $row['recipient_account_id'], $row['category']]);
                $user = $this->one('SELECT u.email FROM users u JOIN familyhub_accounts a ON a.user_id=u.id WHERE a.account_id=? AND u.is_active=1', [$row['recipient_account_id']]);
                $visible = (new NativeFinanceAccess($this->container))->visible($row['scope_id'], $row['recipient_account_id'], str_starts_with($row['target_type'], 'finance'));
                if (!$visible || !$settings || !json_decode($settings['settings'], true, 32, JSON_THROW_ON_ERROR)['email'] || !$user || !filter_var($user['email'], FILTER_VALIDATE_EMAIL) || (int)$row['expires_at'] <= time() || (int)$row['attempts'] >= 5) {
                    $this->change('UPDATE familyhub_deliveries SET state=\'cancelled\',lease_token=NULL WHERE inbox_id=?', [$row['inbox_id']]); return ['cancelled' => true];
                }
                $lease = bin2hex(random_bytes(16));
                $this->change('UPDATE familyhub_deliveries SET state=\'processing\',attempts=attempts+1,lease_token=?,lease_until=? WHERE inbox_id=?', [$lease, time() + 120, $row['inbox_id']]);
                return ['inboxId' => (int)$row['inbox_id'], 'accountId' => $row['recipient_account_id'], 'recipient' => $user['email'], 'lease' => $lease, 'attempts' => (int)$row['attempts'] + 1];
            });
            if (!$job) { continue; } if (isset($job['cancelled'])) { $counts['cancelled']++; continue; }
            try { (new NativeSmtpTransport())->send($job['recipient'], $job['inboxId'], $job['accountId']); $accepted = true; }
            catch (\Throwable $error) { $accepted = false; } // No address/password/SMTP exception in logs.
            $state = $accepted ? 'sent' : ($job['attempts'] >= 5 ? 'cancelled' : 'pending');
            $this->change('UPDATE familyhub_deliveries SET state=?,next_attempt=?,sent_at=?,lease_token=NULL,lease_until=NULL WHERE inbox_id=? AND lease_token=?', [$state, time() + min(3600, 30 * (2 ** $job['attempts'])), $accepted ? time() : null, $job['inboxId'], $job['lease']]);
            $counts[$accepted ? 'accepted' : ($state === 'cancelled' ? 'cancelled' : 'retry')]++;
        }
        return $counts;
    }
}
