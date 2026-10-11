<?php
namespace Kanboard\Plugin\FamilyHub\Model;

class NativeAccountService extends NativeDatabase
{
    public function execute($operation, array $params)
    {
        if ($operation !== 'account.status' && !NativeAccountMailCrypto::configured()) { throw new NativeError('email_unavailable', 503); }
        $this->rate($operation === 'account.status' ? [['account-status-ip:'.$this->ip, 2400, 60]] : [['account-email-ip:'.$this->ip, 20, 900]]);
        $actor = $this->actor(false);
        if ($operation === 'account.status') { $this->rate([['account-status:'.$actor['user']['account_id'], 600, 60]]); }
        if ($operation === 'account.email.request') { $this->rate([['account-email:'.$actor['user']['account_id'], 3, 900]]); }
        $result = $this->transaction(function () use ($operation, $params) {
            $user = $this->actor()['user'];
            $identity = $this->one('SELECT * FROM familyhub_email_identities WHERE account_id=?', [$user['account_id']]);
            if ($operation === 'account.status') {
                $this->fields($params, []);
                return ['email' => $identity['email'] ?? null, 'emailVerified' => isset($identity['verified_at']), 'pendingEmail' => $identity['pending_email'] ?? null, 'resetAvailable' => NativeAccountMailCrypto::configured() && isset($identity['verified_at'])];
            }
            if ($operation === 'account.email.request') {
                $this->fields($params, ['email', 'language', 'password'], ['otp']);
                $email = strtolower(trim($this->text($params['email'], 254)));
                if (!filter_var($email, FILTER_VALIDATE_EMAIL) || !preg_match('/^[\x21-\x7e]+$/D', $email)) { throw new NativeError('validation_error'); }
                $error = (new NativeAuthService($this->container))->stepUp($user, $params['password'], $params['otp'] ?? null);
                if ($error) { return $error; }
                if (!$identity) { $this->change('INSERT INTO familyhub_email_identities(account_id,revision) VALUES(?,0)', [$user['account_id']]); }
                $revision = (int)($identity['revision'] ?? 0) + 1;
                $this->change('UPDATE familyhub_email_identities SET pending_email=?,revision=? WHERE account_id=?', [$email, $revision, $user['account_id']]);
                (new NativeAccountTokens($this->container))->issue($user, 'verify', $email, $revision, $params['language']);
                return ['accepted' => true];
            }
            if ($operation === 'account.email.confirm') {
                $this->fields($params, ['token']);
                $tokens = new NativeAccountTokens($this->container);
                $row = $tokens->valid($params['token'], 'verify', $user);
                if (!$identity || $identity['pending_email'] !== $row['email'] || (int)$identity['revision'] !== (int)$row['identity_revision']) { throw new NativeError('account_token_invalid', 404); }
                $other=$this->one('SELECT account_id FROM familyhub_email_identities WHERE email=? AND verified_at IS NOT NULL AND account_id<>?',[$row['email'],$user['account_id']]);
                if ($other) { throw new NativeError('email_unavailable',409); }
                $tokens->consume($row);
                $this->change('UPDATE familyhub_email_identities SET email=?,verified_at=?,pending_email=NULL WHERE account_id=?', [$row['email'], time(), $user['account_id']]);
                $this->change('UPDATE familyhub_invitations SET recipient_account_id=? WHERE recipient_email=? AND recipient_account_id IS NULL',[$user['account_id'],$row['email']]);
                $this->change('UPDATE users SET email=? WHERE id=?', [$row['email'], $user['id']]);
                $tokens->revoke($user['account_id'], 'reset');
                return ['verified' => true];
            }
            throw new NativeError('unsupported_operation', 404);
        },$operation==='account.email.confirm');
        if ($result instanceof NativeError) { throw $result; }
        return $result;
    }
}
