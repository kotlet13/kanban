<?php
namespace Kanboard\Plugin\FamilyHub\Model;

class NativeEnrollmentService extends NativeDatabase
{
    public function available()
    {
        return in_array($this->pdo->getAttribute(\PDO::ATTR_DRIVER_NAME), ['sqlite', 'mysql'], true) && defined('FAMILYHUB_ENABLE_NATIVE_API') && FAMILYHUB_ENABLE_NATIVE_API === true && !$this->one('SELECT user_id FROM familyhub_accounts LIMIT 1');
    }
    public function formId() { return $this->newUuid(); }
    public function issue($adminUserId, $issuanceId = null)
    {
        if (!defined('FAMILYHUB_ENABLE_NATIVE_API') || FAMILYHUB_ENABLE_NATIVE_API !== true || !in_array($this->pdo->getAttribute(\PDO::ATTR_DRIVER_NAME), ['sqlite', 'mysql'], true)) { throw new NativeError('feature_disabled', 503); }
        $issuanceId = $issuanceId === null ? $this->newUuid() : $this->uuid($issuanceId);
        return $this->transaction(function () use ($adminUserId, $issuanceId) {
            $admin = $this->one('SELECT role,is_active FROM users WHERE id=?'.$this->lockSuffix(), [$adminUserId]);
            if (!$admin || $admin['role'] !== 'app-admin' || (int)$admin['is_active'] !== 1) { throw new NativeError('permission_revoked', 403); }
            if (!$this->available()) { throw new NativeError('enrollment_closed', 409); }
            if ($this->one('SELECT id FROM familyhub_enrollment WHERE id=?', [$issuanceId])) { throw new NativeError('enrollment_issue_replayed', 409); }
            $now = time(); $code = 'fhe1_'.bin2hex(random_bytes(32));
            $this->change('UPDATE familyhub_enrollment SET revoked_at=? WHERE consumed_at IS NULL AND revoked_at IS NULL', [$now]);
            $this->change('INSERT INTO familyhub_enrollment(id,token_hash,created_at,expires_at) VALUES(?,?,?,?)', [$issuanceId, hash('sha256', $code), $now, $now + 900]);
            return ['code' => $code, 'expiresAt' => $now + 900];
        }, true);
    }
    public function execute($operation, array $params)
    {
        if ($operation !== 'auth.enroll') { throw new NativeError('unsupported_operation', 404); }
        $this->fields($params, ['code', 'username', 'password', 'displayName', 'deviceName']);
        $username = $this->username($params['username']); $password = $this->text($params['password'], 72);
        if (strlen($password) < 12) { throw new NativeError('password_too_short'); }
        $name = $this->text($params['displayName'], 100); $device = $this->text($params['deviceName'], 80);
        $this->rate([['enroll-ip:'.$this->ip, 10, 600]]);
        return $this->transaction(function () use ($params, $username, $password, $name, $device) {
            if (!$this->available()) { throw new NativeError('enrollment_closed', 409); }
            if (!is_string($params['code']) || !preg_match('/^fhe1_[a-f0-9]{64}$/D', $params['code'])) { throw new NativeError('enrollment_invalid', 404); }
            $row = $this->one('SELECT * FROM familyhub_enrollment WHERE token_hash=?'.$this->lockSuffix(), [hash('sha256', $params['code'])]);
            if (!$row || $row['consumed_at'] !== null || $row['revoked_at'] !== null || (int)$row['expires_at'] <= time()) { throw new NativeError('enrollment_invalid', 404); }
            if ($this->one('SELECT id FROM users WHERE LOWER(username)=?', [$username])) { throw new NativeError('username_unavailable', 409); }
            $id = $this->userModel->create(['username' => $username, 'password' => $password, 'name' => $name, 'role' => 'app-user', 'is_active' => 1]);
            if (!$id) { throw new NativeError('registration_failed', 500); }
            $session = (new NativeAuthService($this->container))->issue($this->one('SELECT * FROM users WHERE id=?', [$id]), $device);
            if ($this->change('UPDATE familyhub_enrollment SET consumed_at=? WHERE id=? AND consumed_at IS NULL AND revoked_at IS NULL AND expires_at>?', [time(), $row['id'], time()]) !== 1) { throw new NativeError('enrollment_invalid', 404); }
            return $session;
        }, true);
    }
}
