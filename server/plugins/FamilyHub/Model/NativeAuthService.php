<?php
namespace Kanboard\Plugin\FamilyHub\Model;

use Otp\Otp;
use Base32\Base32;

class NativeAuthService extends NativeDatabase
{
    public const SESSION_SECONDS = 2592000;
    public const RENEWAL_WINDOW_SECONDS = 604800;

    public function execute($operation, array $params)
    {
        if ($operation === 'auth.enroll') { return (new NativeEnrollmentService($this->container, $this->bearer, $this->ip))->execute($operation, $params); }
        if (str_starts_with($operation, 'auth.reset.')) { return (new NativePasswordResetService($this->container, $this->bearer, $this->ip))->execute($operation, $params); }
        if ($operation === 'auth.login') { return $this->login($params); }
        if (in_array($operation,['auth.registerInvitation2','auth.registerInvitation3'],true)) { return (new NativeEmailInvitationService($this->container, $this->bearer, $this->ip))->register($params,$operation==='auth.registerInvitation3'?3:2); }
        if ($operation === 'auth.register') {
            return (new NativeInvitationService($this->container, $this->bearer, $this->ip))->register($params);
        }
        $this->rate([['device-ip:'.$this->ip, 600, 60]]);
        return $this->transaction(function () use ($operation, $params) {
            $actor = $this->actor();
            if ($operation === 'auth.renew') {
                $this->fields($params, ['deviceId']);
                if ($this->uuid($params['deviceId']) !== $actor['device']['id']) {
                    throw new NativeError('permission_revoked', 403);
                }
                // actor() locks user then device and rejects expiry, revocation,
                // changed credentials/TOTP, deactivation and recycled accounts.
                // Keep the token stable so a lost reply or failed secure write
                // can safely retry without creating an orphan device session.
                $now = time();
                if ((int)$actor['device']['expires_at'] <= $now + self::RENEWAL_WINDOW_SECONDS) {
                    $actor['device']['expires_at'] = $now + self::SESSION_SECONDS;
                    $this->change('UPDATE familyhub_devices SET expires_at=? WHERE id=?', [$actor['device']['expires_at'], $actor['device']['id']]);
                }
                return ['serverId' => $this->serverId(), 'user' => $this->userWire($actor['user']), 'device' => $this->deviceWire($actor['device'])];
            }
            if ($operation === 'auth.me') {
                $this->fields($params, []);
                return ['serverId' => $this->serverId(), 'user' => $this->userWire($actor['user']), 'device' => $this->deviceWire($actor['device'])];
            }
            if ($operation === 'auth.devices') {
                $this->fields($params, []);
                $devices = $this->many('SELECT * FROM familyhub_devices WHERE user_id = ? AND account_id = ? AND revoked_at IS NULL AND expires_at > ? ORDER BY created_at,id', [$actor['user']['id'], $actor['user']['account_id'], time()]);
                return ['devices' => array_map(fn ($row) => $this->deviceWire($row), $devices)];
            }
            if ($operation === 'auth.revoke') {
                $this->fields($params, ['deviceId']);
                $id = $this->uuid($params['deviceId']);
                $device = $this->one('SELECT * FROM familyhub_devices WHERE id = ? AND user_id = ? AND account_id = ?', [$id, $actor['user']['id'], $actor['user']['account_id']]);
                if (!$device) { throw new NativeError('permission_revoked', 403); }
                $this->change('UPDATE familyhub_devices SET revoked_at = ? WHERE id = ? AND revoked_at IS NULL', [time(), $id]);
                (new NativePushService($this->container))->revokeDevice($id);
                return ['revoked' => true];
            }
            throw new NativeError('unsupported_operation', 404);
        }, true);
    }

    private function login(array $params)
    {
        $this->fields($params, ['username', 'password', 'deviceName'], ['otp']);
        $username = strtolower(trim($this->text($params['username'], 255)));
        $password = $this->text($params['password'], 72);
        $deviceName = $this->text($params['deviceName'], 80);
        if ($username === 'jsonrpc') { throw new NativeError('invalid_credentials', 401); }
        $this->rate([['login-account:'.$username, 10, 60], ['login-ip:'.$this->ip, 60, 60]]);
        $result = $this->transaction(function () use ($username, $password, $deviceName, $params) {
            $user = $this->one('SELECT * FROM users WHERE LOWER(username) = ?'.$this->lockSuffix(), [$username]);
            $dummy = '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2uheWG/igi';
            $verified = password_verify($password, $user['password'] ?? $dummy);
            if ($user && (int)$user['lock_expiration_date'] >= time()) { return new NativeError('invalid_credentials', 401); }
            if (!$user || !$verified || (int)$user['is_active'] !== 1) {
                if ($user) { $this->failed($user); }
                return new NativeError('invalid_credentials', 401);
            }
            if ((int)$user['is_ldap_user'] !== 0 || (int)$user['disable_login_form'] !== 0) {
                return new NativeError('auth_provider_unsupported', 401);
            }
            $secondFactor = $this->verifySecondFactor($user, $params['otp'] ?? null);
            if ($secondFactor) { return $secondFactor; }
            $this->change('UPDATE users SET nb_failed_login = 0, lock_expiration_date = 0 WHERE id = ?', [$user['id']]);
            return $this->issue($user, $deviceName);
        }, true);
        // Commit failed-login counters and replay prevention before reporting errors.
        if ($result instanceof NativeError) { throw $result; }
        return $result;
    }


    /** Caller holds user lock; return errors so failed counters commit. */
    public function stepUp(array $user, $password, $otp = null)
    {
        $password = $this->text($password, 72);
        if ((int)$user['lock_expiration_date'] >= time()) { return new NativeError('invalid_credentials', 401); }
        if (!password_verify($password, $user['password'])) { $this->failed($user); return new NativeError('invalid_credentials', 401); }
        $error = $this->verifySecondFactor($user, $otp);
        if (!$error) { $this->change('UPDATE users SET nb_failed_login=0,lock_expiration_date=0 WHERE id=?', [$user['id']]); }
        return $error;
    }

    /** Never clears TOTP. Used by login, email step-up and token-bound reset. */
    public function verifySecondFactor(array $user, $code)
    {
        if ((int)$user['twofactor_activated'] !== 1) { return null; }
        if ($code === null || $code === '') { return new NativeError('two_factor_required', 401); }
        $step = $this->validTotp($user, $code);
        if ($step === null) { $this->failed($user); return new NativeError('invalid_credentials', 401); }
        $state = $this->one('SELECT * FROM familyhub_totp_state WHERE user_id=?', [$user['id']]);
        $secretHash = hash('sha256', $user['twofactor_secret']);
        if ($state && $state['secret_hash'] === $secretHash && $step <= (int)$state['last_step']) { $this->failed($user); return new NativeError('invalid_credentials', 401); }
        if ($state) { $this->change('UPDATE familyhub_totp_state SET secret_hash=?,last_step=? WHERE user_id=?', [$secretHash, $step, $user['id']]); }
        else { $this->change('INSERT INTO familyhub_totp_state VALUES(?,?,?)', [$user['id'], $secretHash, $step]); }
        return null;
    }

    private function failed(array $user)
    {
        $count = (int)$user['nb_failed_login'] + 1;
        $until = (int)$user['lock_expiration_date'];
        if ($count > BRUTEFORCE_LOCKDOWN) { $until = max($until, time() + BRUTEFORCE_LOCKDOWN_DURATION * 60); }
        $this->change('UPDATE users SET nb_failed_login = ?, lock_expiration_date = ? WHERE id = ?', [$count, $until, $user['id']]);
    }

    private function validTotp(array $user, $code)
    {
        if (!is_string($code) || !preg_match('/^[0-9]{6}$/D', $code)) { return null; }
        try {
            $otp = new Otp(); $secret = Base32::decode($user['twofactor_secret']);
            $step = intdiv(time(), 30);
            foreach ([$step, $step - 1, $step + 1] as $candidate) {
                if (hash_equals($otp->totp($secret, $candidate), $code)) { return $candidate; }
            }
        } catch (\Throwable $error) { return null; }
        return null;
    }

    /** Called only within the caller's already serialized auth transaction. */
    public function issue(array $user, $deviceName)
    {
        $account = $this->one('SELECT * FROM familyhub_accounts WHERE user_id = ?', [$user['id']]);
        if (!$account) {
            $account = ['account_id' => $this->newUuid()];
            $this->change('INSERT INTO familyhub_accounts(user_id,account_id) VALUES(?,?)', [$user['id'], $account['account_id']]);
        }
        $user['account_id'] = $account['account_id'];
        $token = 'fh1_'.bin2hex(random_bytes(32)); $now = time();
        $device = ['id' => $this->newUuid(), 'name' => $deviceName, 'expires_at' => $now + self::SESSION_SECONDS];
        $this->change('INSERT INTO familyhub_devices(id,user_id,account_id,name,token_hash,credentials_hash,created_at,expires_at) VALUES(?,?,?,?,?,?,?,?)',
            [$device['id'], $user['id'], $account['account_id'], $deviceName, hash('sha256', $token), $this->fingerprint($user), $now, $device['expires_at']]);
        return ['serverId' => $this->serverId(), 'user' => $this->userWire($user), 'device' => $this->deviceWire($device), 'token' => $token];
    }
}
