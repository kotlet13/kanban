<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** Caller holds user transaction lock. Durable DB stores hashes and encrypted mail only. */
class NativeAccountTokens extends NativeDatabase
{
    public function issue(array $user, $purpose, $email, $revision, $language)
    {
        if (!in_array($language, ['sl', 'en'], true)) { throw new NativeError('validation_error'); }
        $this->revoke($user['account_id'], $purpose);
        $id = $this->newUuid(); $token = ($purpose === 'verify' ? 'fhv1_' : 'fhr1_').bin2hex(random_bytes(32)); $now = time();
        $this->change('INSERT INTO familyhub_account_tokens(id,account_id,purpose,token_hash,email,identity_revision,fingerprint,created_at,expires_at) VALUES(?,?,?,?,?,?,?,?,?)', [$id, $user['account_id'], $purpose, hash('sha256', $token), $email, $revision, $this->fingerprint($user), $now, $now + ($purpose === 'verify' ? 1800 : 900)]);
        $aad = $this->aad($id, $user['account_id']);
        $cipher = NativeAccountMailCrypto::encrypt($token, $aad);
        $this->change('INSERT INTO familyhub_account_mail(token_id,token_cipher,language,state,next_attempt) VALUES(?,?,?,\'pending\',?)', [$id, $cipher, $language, $now]);
    }
    public function aad($id, $account) { return $this->serverId().':'.$account.':'.$id; }
    public function lookup($token, $purpose)
    {
        $prefix = $purpose === 'verify' ? 'fhv1_' : 'fhr1_';
        if (!is_string($token) || !preg_match('/^'.$prefix.'[a-f0-9]{64}$/D', $token)) { throw new NativeError('account_token_invalid', 404); }
        $row = $this->one('SELECT * FROM familyhub_account_tokens WHERE token_hash=? AND purpose=?', [hash('sha256', $token), $purpose]);
        if (!$row) { throw new NativeError('account_token_invalid', 404); }
        return $row;
    }
    public function valid($token, $purpose, array $user)
    {
        $row = $this->lookup($token, $purpose);
        if ($row['account_id'] !== $user['account_id'] || $row['consumed_at'] !== null || $row['revoked_at'] !== null || (int)$row['expires_at'] <= time() || !hash_equals($row['fingerprint'], $this->fingerprint($user))) { throw new NativeError('account_token_invalid', 404); }
        return $row;
    }
    public function consume(array $row)
    {
        if ($this->change('UPDATE familyhub_account_tokens SET consumed_at=? WHERE id=? AND consumed_at IS NULL AND revoked_at IS NULL AND expires_at>?', [time(), $row['id'], time()]) !== 1) { throw new NativeError('account_token_invalid', 404); }
        $this->change('UPDATE familyhub_account_mail SET token_cipher=NULL,state=\'cancelled\',lease_token=NULL WHERE token_id=? AND state<>\'accepted\'', [$row['id']]);
    }
    public function revoke($account, $purpose)
    {
        $this->change('UPDATE familyhub_account_tokens SET revoked_at=? WHERE account_id=? AND purpose=? AND revoked_at IS NULL AND consumed_at IS NULL', [time(), $account, $purpose]);
        $this->change('UPDATE familyhub_account_mail SET token_cipher=NULL,state=\'cancelled\',lease_token=NULL WHERE token_id IN (SELECT id FROM familyhub_account_tokens WHERE account_id=? AND purpose=? AND revoked_at IS NOT NULL) AND state<>\'accepted\'', [$account, $purpose]);
    }
}
