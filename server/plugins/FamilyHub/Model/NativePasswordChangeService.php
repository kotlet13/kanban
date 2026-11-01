<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** Authenticated credential change, never an E2EE recovery or key operation. */
class NativePasswordChangeService extends NativeDatabase
{
    public function execute($operation, array $params)
    {
        if ($operation !== 'account.password.change') { throw new NativeError('unsupported_operation', 404); }
        $this->fields($params, ['currentPassword', 'newPassword'], ['otp']);
        // text() preserves all bytes, matching login/enrollment; bcrypt accepts
        // at most 72 bytes. Never trim or silently truncate a password.
        $current = $this->text($params['currentPassword'], 72);
        $password = $this->text($params['newPassword'], 72);
        if (strlen($password) < 12) { throw new NativeError('password_too_short'); }
        $this->rate([['password-change-ip:'.$this->ip, 20, 900]]);
        $initial = $this->actor(false);
        $this->rate([['password-change-account:'.$initial['user']['account_id'], 10, 900]]);
        $result = $this->transaction(function () use ($params, $current, $password) {
            // Re-read under user -> device locks after rate limiting. Reset,
            // revoke, provider changes and another password change cannot use
            // the earlier actor snapshot to keep a revoked session alive.
            $actor = $this->actor();
            $user = $actor['user']; $device = $actor['device'];
            $error = (new NativeAuthService($this->container))->stepUp($user, $current, $params['otp'] ?? null);
            if ($error) { return $error; } // Commit failure counters/TOTP state.
            $user['password'] = password_hash($password, PASSWORD_BCRYPT);
            $this->change('UPDATE users SET password=?,nb_failed_login=0,lock_expiration_date=0 WHERE id=?', [$user['password'], $user['id']]);
            // The exact initiating token, expiry, identity and push registration
            // survive. Only its credentials binding changes with the password.
            $this->change('UPDATE familyhub_devices SET credentials_hash=? WHERE id=?', [$this->fingerprint($user), $device['id']]);
            $others = $this->many('SELECT id FROM familyhub_devices WHERE user_id=? AND account_id=? AND id<>? AND revoked_at IS NULL'.$this->lockSuffix(), [$user['id'], $user['account_id'], $device['id']]);
            foreach ($others as $other) {
                $this->change('UPDATE familyhub_devices SET revoked_at=? WHERE id=?', [time(), $other['id']]);
                (new NativePushService($this->container))->revokeDevice($other['id']);
            }
            $tokens = new NativeAccountTokens($this->container);
            $tokens->revoke($user['account_id'], 'reset');
            $tokens->revoke($user['account_id'], 'verify');
            $this->change('UPDATE familyhub_email_identities SET pending_email=NULL WHERE account_id=?', [$user['account_id']]);
            (new NativeCryptoService($this->container))->event($user['account_id'], 'auth.passwordChanged');
            return ['changed' => true, 'sessionPreserved' => true, 'accountId' => $user['account_id'], 'deviceId' => $device['id']];
        }, true);
        if ($result instanceof NativeError) { throw $result; }
        return $result;
    }
}
