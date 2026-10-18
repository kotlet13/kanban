<?php

namespace Kanboard\Plugin\FamilyHub\Model;

/** Security notices contain only a fixed event category, never a recovery file or key. */
class NativeSecurityMailQueue extends NativeDatabase
{
    public function run($limit = 20, $transport = null)
    {
        if (!\Kanboard\Plugin\FamilyHub\Schema\CryptoSchema::ready($this->pdo)) {
            return ['sent' => 0,'retry' => 0,'cancelled' => 0];
        }
        if (!is_int($limit) || $limit < 1 || $limit > 50) {
            throw new NativeError('validation_error');
        }
        if ($transport === null && !NativeSmtpTransport::configured()) {
            throw new NativeError('email_unavailable', 503);
        }$transport = $transport ?? new NativeAccountMailTransport();
        $counts = ['sent' => 0,'retry' => 0,'cancelled' => 0];
        $rows = $this->many("SELECT id,account_id FROM familyhub_crypto_security_events WHERE state IN ('pending','retry') AND next_attempt<=? ORDER BY created_at,id LIMIT ".$limit, [time()]);
        foreach ($rows as $row) {
            $state = $this->transaction(function () use ($row, $transport) {
                $binding = $this->one('SELECT user_id FROM familyhub_accounts WHERE account_id=?', [$row['account_id']]);
                $user = $binding ? $this->one('SELECT * FROM users WHERE id=?'.$this->lockSuffix(), [$binding['user_id']]) : null;
                $event = $this->one('SELECT * FROM familyhub_crypto_security_events WHERE id=?'.$this->lockSuffix(), [$row['id']]);
                if (!$event || !in_array($event['state'], ['pending','retry'], true) || (int)$event['next_attempt'] > time()) {
                    return null;
                }
                // The address was verified when this immutable event was
                // enqueued. A later email-change request must not suppress a
                // recovery/reset warning to that original address. No token,
                // new address, key or account content enters this notice.
                $knownKind = in_array($event['kind'], ['crypto.initialized','crypto.deviceAdded','crypto.deviceRevoked',
                    'auth.resetRequested','auth.resetCompleted','crypto.recoveryStarted','crypto.recoveryCompleted'], true);
                if (!$user || !(int)$user['is_active'] || NativeCryptoAccountTombstoneV2::account($this->pdo,$row['account_id']) ||
                    !$knownKind || !filter_var($event['email'],FILTER_VALIDATE_EMAIL) ||
                    (int)$event['attempts'] >= 5 || (int)$event['created_at'] < time() - 86400) {
                    $this->change("UPDATE familyhub_crypto_security_events SET state='cancelled' WHERE id=?", [$event['id']]);
                    return 'cancelled';
                }
                $attempt = (int)$event['attempts'] + 1;
                try {
                    $language = in_array(($user['language'] ?? null), ['sl','en'], true) ? $user['language'] : 'bilingual';
                    $transport->send($event['email'], 'security', '', $event['id'], $language, ['eventKind' => $event['kind']]);
                    $state = 'sent';
                } catch (\Throwable $ignored) {
                    $state = $attempt >= 5 ? 'cancelled' : 'retry';
                }
                $this->change('UPDATE familyhub_crypto_security_events SET state=?,attempts=?,next_attempt=? WHERE id=?', [$state,$attempt,time() + min(3600, 30 * (2 ** $attempt)),$event['id']]);
                return $state;
            });
            if ($state !== null) {
                $counts[$state]++;
            }
        }
        return $counts;
    }
}
