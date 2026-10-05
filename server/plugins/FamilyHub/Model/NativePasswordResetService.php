<?php
namespace Kanboard\Plugin\FamilyHub\Model;

class NativePasswordResetService extends NativeDatabase
{
    public function execute($operation, array $params)
    {
        if (!NativeAccountMailCrypto::configured()) { throw new NativeError('email_unavailable', 503); }
        if ($operation === 'auth.reset.request') { return $this->request($params); }
        if ($operation !== 'auth.reset.confirm') { throw new NativeError('unsupported_operation', 404); }
        $this->fields($params, ['token', 'password'], ['otp']);
        $password = $this->text($params['password'], 72);
        if (strlen($password) < 12) { throw new NativeError('password_too_short'); }
        $this->rate([['reset-confirm-ip:'.$this->ip, 20, 900], ['reset-confirm-code:'.hash('sha256', is_string($params['token']) ? $params['token'] : ''), 10, 900]]);
        $result = $this->transaction(function () use ($params, $password) {
            $tokens = new NativeAccountTokens($this->container);
            $initial = $tokens->lookup($params['token'], 'reset');
            $binding = $this->one('SELECT user_id FROM familyhub_accounts WHERE account_id=?', [$initial['account_id']]);
            $user = $binding ? $this->one('SELECT * FROM users WHERE id=?'.$this->lockSuffix(), [$binding['user_id']]) : null;
            if (!$user || (int)$user['is_active'] !== 1 || (int)$user['is_ldap_user'] !== 0 || (int)$user['disable_login_form'] !== 0) { throw new NativeError('account_token_invalid', 404); }
            $user['account_id'] = $initial['account_id']; $row = $tokens->valid($params['token'], 'reset', $user);
            $identity = $this->one('SELECT * FROM familyhub_email_identities WHERE account_id=?', [$user['account_id']]);
            if (!$identity || $identity['verified_at'] === null || $identity['email'] !== $row['email'] || (int)$identity['revision'] !== (int)$row['identity_revision']) { throw new NativeError('account_token_invalid', 404); }
            $error = (new NativeAuthService($this->container))->verifySecondFactor($user, $params['otp'] ?? null);
            if ($error) { return $error; }
            $tokens->consume($row);
            $this->change('UPDATE users SET password=?,nb_failed_login=0,lock_expiration_date=0 WHERE id=?', [password_hash($password, PASSWORD_BCRYPT), $user['id']]);
            $devices = $this->many('SELECT id FROM familyhub_devices WHERE user_id=? AND account_id=? AND revoked_at IS NULL'.$this->lockSuffix(), [$user['id'], $user['account_id']]);
            foreach ($devices as $device) {
                $this->change('UPDATE familyhub_devices SET revoked_at=? WHERE id=?', [time(), $device['id']]);
                (new NativePushService($this->container))->revokeDevice($device['id']);
            }
            $tokens->revoke($user['account_id'], 'reset'); $tokens->revoke($user['account_id'], 'verify');
            $this->change('UPDATE familyhub_email_identities SET pending_email=NULL WHERE account_id=?', [$user['account_id']]);
            return ['reset' => true];
        });
        if ($result instanceof NativeError) { throw $result; }
        return $result;
    }

    private function request(array $params)
    {
        $this->fields($params, ['username', 'language']);
        $username = $this->username($params['username']);
        if (!in_array($params['language'], ['sl', 'en'], true)) { throw new NativeError('validation_error'); }
        $this->rate([['reset-user:'.$username, 3, 900], ['reset-ip:'.$this->ip, 20, 900]]);
        return $this->transaction(function () use ($params, $username) {
            $user = $this->one('SELECT * FROM users WHERE LOWER(username)=?'.$this->lockSuffix(), [$username]);
            if ($user && (int)$user['is_active'] === 1 && (int)$user['is_ldap_user'] === 0 && (int)$user['disable_login_form'] === 0) {
                $account = $this->one('SELECT account_id FROM familyhub_accounts WHERE user_id=?', [$user['id']]);
                $identity = $account ? $this->one('SELECT * FROM familyhub_email_identities WHERE account_id=?', [$account['account_id']]) : null;
                if ($identity && $identity['verified_at'] !== null && $identity['email']) {
                    $user['account_id'] = $account['account_id'];
                    (new NativeAccountTokens($this->container))->issue($user, 'reset', $identity['email'], $identity['revision'], $params['language']);
                }
            }
            return ['accepted' => true];
        });
    }
}
