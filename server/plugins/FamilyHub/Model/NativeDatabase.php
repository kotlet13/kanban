<?php
namespace Kanboard\Plugin\FamilyHub\Model;

use Kanboard\Core\Base;
use PDO;

/** Shared transaction, validation and ACL primitives; no web-session identity. */
abstract class NativeDatabase extends Base
{
    protected $pdo;
    protected $bearer;
    protected $ip;
    protected $sqlite;

    public function __construct($container, $bearer = '', $ip = 'unknown')
    {
        parent::__construct($container);
        $this->pdo = $this->db->getConnection();
        $this->sqlite = $this->pdo->getAttribute(PDO::ATTR_DRIVER_NAME) === 'sqlite';
        $this->bearer = $bearer;
        $this->ip = $ip;
    }

    protected function query($sql, array $params = [])
    {
        $statement = $this->pdo->prepare($sql);
        $statement->execute($params);
        return $statement;
    }

    protected function one($sql, array $params = [])
    {
        $statement = $this->query($sql, $params);
        $row = $statement->fetch(PDO::FETCH_ASSOC);
        $statement->closeCursor();
        return $row ?: null;
    }

    protected function many($sql, array $params = [])
    {
        $statement = $this->query($sql, $params);
        $rows = $statement->fetchAll(PDO::FETCH_ASSOC);
        $statement->closeCursor();
        return $rows;
    }

    protected function iterate($sql, array $params = [])
    {
        $buffered = !$this->sqlite ? $this->pdo->getAttribute(PDO::MYSQL_ATTR_USE_BUFFERED_QUERY) : null;
        if (!$this->sqlite) { $this->pdo->setAttribute(PDO::MYSQL_ATTR_USE_BUFFERED_QUERY, false); }
        $statement = null;
        try {
            $statement = $this->query($sql, $params);
            while ($row = $statement->fetch(PDO::FETCH_ASSOC)) { yield $row; }
        } finally {
            if ($statement) { $statement->closeCursor(); }
            if (!$this->sqlite) { $this->pdo->setAttribute(PDO::MYSQL_ATTR_USE_BUFFERED_QUERY, $buffered); }
        }
    }

    protected function change($sql, array $params = [])
    {
        $statement = $this->query($sql, $params);
        $count = $statement->rowCount();
        $statement->closeCursor();
        return $count;
    }

    protected function lockSuffix() { return $this->sqlite ? '' : ' FOR UPDATE'; }

    protected function transaction(callable $callback, $global = false)
    {
        if ($this->sqlite) { $this->pdo->exec('BEGIN IMMEDIATE'); }
        else {
            // Earlier identity reads must not establish a stale repeatable-read
            // snapshot before waiting for the scope lock and reading its cursor.
            $this->pdo->exec('SET TRANSACTION ISOLATION LEVEL READ COMMITTED');
            $this->pdo->beginTransaction();
        }
        try {
            if ($global) {
                $this->one('SELECT counter FROM familyhub_native_lock WHERE id = 1'.$this->lockSuffix());
            }
            $result = $callback();
            if ($this->sqlite) { $this->pdo->exec('COMMIT'); }
            else { $this->pdo->commit(); }
            return $result;
        } catch (\Throwable $error) {
            if ($this->sqlite) { $this->pdo->exec('ROLLBACK'); }
            elseif ($this->pdo->inTransaction()) { $this->pdo->rollBack(); }
            throw $error;
        }
    }

    public function rate(array $buckets)
    {
        $retry = $this->transaction(function () use ($buckets) {
            $now = time(); $retry = 0;
            foreach ($buckets as [$key, $maximum, $duration]) {
                $id = hash('sha256', $key);
                $row = $this->one('SELECT * FROM familyhub_rate_limits WHERE id = ?', [$id]);
                if (!$row) {
                    $this->change('INSERT INTO familyhub_rate_limits(id,window_start,attempts) VALUES(?,?,1)', [$id, $now]);
                } elseif ((int)$row['window_start'] + $duration <= $now) {
                    $this->change('UPDATE familyhub_rate_limits SET window_start = ?, attempts = 1 WHERE id = ?', [$now, $id]);
                } else {
                    $attempts = (int)$row['attempts'] + 1;
                    $this->change('UPDATE familyhub_rate_limits SET attempts = ? WHERE id = ?', [$attempts, $id]);
                    if ($attempts > $maximum) { $retry = max($retry, (int)$row['window_start'] + $duration - $now); }
                }
            }
            return $retry;
        }, true);
        // Rate counters survive the denied operation's transaction rollback.
        if ($retry > 0) { throw new NativeError('rate_limited', 429, ['retryAfter' => $retry]); }
    }

    protected function actor($lock = true)
    {
        if (!preg_match('/^Bearer (fh1_[a-f0-9]{64})$/D', $this->bearer, $match)) {
            throw new NativeError('auth_required', 401);
        }
        $hash = hash('sha256', $match[1]);
        $device = $this->one('SELECT * FROM familyhub_devices WHERE token_hash = ?', [$hash]);
        if (!$device || $device['revoked_at'] !== null || (int)$device['expires_at'] <= time()) {
            throw new NativeError('device_revoked', 401);
        }
        $user = $this->one('SELECT * FROM users WHERE id = ?'.($lock ? $this->lockSuffix() : ''), [$device['user_id']]);
        // Lock order is user -> device -> scope. Revoking another device of the
        // same user cannot deadlock with that device's in-flight request.
        if ($lock) {
            $device = $this->one('SELECT * FROM familyhub_devices WHERE token_hash = ?'.$this->lockSuffix(), [$hash]);
            if (!$device || $device['revoked_at'] !== null || (int)$device['expires_at'] <= time()) {
                throw new NativeError('device_revoked', 401);
            }
        }
        $account = $this->one('SELECT * FROM familyhub_accounts WHERE user_id = ?', [$device['user_id']]);
        if (!$user || (int)$user['is_active'] !== 1 || (int)$user['is_ldap_user'] !== 0 ||
                !$account || !hash_equals($device['account_id'], $account['account_id']) ||
                (int)$user['disable_login_form'] !== 0 || !hash_equals($device['credentials_hash'], $this->fingerprint($user))) {
            throw new NativeError('device_revoked', 401);
        }
        $user['account_id'] = $account['account_id'];
        return ['user' => $user, 'device' => $device];
    }

    protected function fingerprint(array $user)
    {
        return hash('sha256', json_encode([$user['password'], (int)$user['twofactor_activated'], $user['twofactor_secret']], JSON_THROW_ON_ERROR));
    }

    protected function scope($id, $userId, $write = false, $owner = false)
    {
        $scope = $this->one('SELECT * FROM familyhub_scopes WHERE id = ?'.$this->lockSuffix(), [$id]);
        $member = $scope ? $this->one('SELECT * FROM familyhub_members WHERE scope_id = ? AND user_id = ?', [$id, $userId]) : null;
        $account = $this->one('SELECT account_id FROM familyhub_accounts WHERE user_id = ?', [$userId]);
        if (!$scope || !$member || !$account || $member['account_id'] !== $account['account_id'] || (int)$member['active'] !== 1 || ($write && $member['role'] === 'viewer') || ($owner && $member['role'] !== 'owner')) {
            throw new NativeError('permission_revoked', 403);
        }
        if ($scope['kind'] === 'personal') {
            $private = $this->one('SELECT scope_id FROM familyhub_personal_scopes WHERE account_id=?', [$account['account_id']]);
            if ((int)$scope['owner_id'] !== (int)$userId || $member['role'] !== 'owner' || !$private || $private['scope_id'] !== $id) { throw new NativeError('permission_revoked', 403); }
        }
        $scope['role'] = $member['role'];
        return $scope;
    }

    protected function advance($scope)
    {
        $sequence = (int)$scope['sequence'] + 1;
        $this->change('UPDATE familyhub_scopes SET sequence = ? WHERE id = ?', [$sequence, $scope['id']]);
        return $sequence;
    }

    protected function scopeWire(array $scope)
    {
        return ['id' => $scope['id'], 'kind' => $scope['kind'], 'name' => $scope['name'], 'role' => $scope['role'], 'sequence' => (int)$scope['sequence']];
    }

    protected function userWire(array $user)
    {
        return ['id' => (int)$user['id'], 'accountId' => $user['account_id'], 'username' => $user['username'], 'displayName' => $user['name'] ?: $user['username']];
    }

    protected function serverId() { return $this->one('SELECT server_id FROM familyhub_instance WHERE id = 1')['server_id']; }

    protected function deviceWire(array $device)
    {
        return ['id' => $device['id'], 'name' => $device['name'], 'expiresAt' => (int)$device['expires_at']];
    }

    protected function uuid($value)
    {
        if (!is_string($value) || !preg_match('/^[a-f0-9]{8}-[a-f0-9]{4}-[1-5][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/D', $value)) {
            throw new NativeError('validation_error');
        }
        return $value;
    }

    protected function newUuid()
    {
        $bytes = random_bytes(16);
        $bytes[6] = chr((ord($bytes[6]) & 15) | 64);
        $bytes[8] = chr((ord($bytes[8]) & 63) | 128);
        $hex = bin2hex($bytes);
        return substr($hex, 0, 8).'-'.substr($hex, 8, 4).'-'.substr($hex, 12, 4).'-'.substr($hex, 16, 4).'-'.substr($hex, 20);
    }

    protected function text($value, $maximum, $empty = false)
    {
        if (!is_string($value) || strlen($value) > $maximum || (!$empty && trim($value) === '') || str_contains($value, "\0") || !mb_check_encoding($value, 'UTF-8')) {
            throw new NativeError('validation_error');
        }
        return $value;
    }

    protected function username($value)
    {
        $name = strtolower(trim($this->text($value, 64)));
        if ($name === 'jsonrpc' || !preg_match('/^[a-z0-9_.-]{3,64}$/D', $name)) { throw new NativeError('validation_error'); }
        return $name;
    }

    protected function fields(array $value, array $required, array $optional = [])
    {
        if (array_diff($required, array_keys($value)) || array_diff(array_keys($value), array_merge($required, $optional))) {
            throw new NativeError('validation_error');
        }
    }

    protected function hashRequest($operation, array $params)
    {
        return hash('sha256', $this->canonical(['op' => $operation, 'params' => $params]));
    }

    protected function canonical($value)
    {
        if (is_array($value)) {
            if (!array_is_list($value)) { ksort($value); }
            foreach ($value as &$part) { $part = json_decode($this->canonical($part), true, 32, JSON_THROW_ON_ERROR); }
        }
        return json_encode($value, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR);
    }

    protected function replay($scopeId, $userId, $id, $hash)
    {
        $saved = $this->one('SELECT * FROM familyhub_operations WHERE scope_id = ? AND user_id = ? AND id = ?', [$scopeId, $userId, $id]);
        if (!$saved) { return null; }
        if (!hash_equals($saved['request_hash'], $hash)) { throw new NativeError('idempotency_mismatch', 409); }
        return ['status' => (int)$saved['status'], 'body' => json_decode($saved['response'], true, 32, JSON_THROW_ON_ERROR)];
    }

    protected function remember($scopeId, $userId, $id, $hash, array $body, $status = 200)
    {
        $this->change('INSERT INTO familyhub_operations(scope_id,user_id,id,request_hash,response,status) VALUES(?,?,?,?,?,?)', [$scopeId, $userId, $id, $hash, json_encode($body, JSON_THROW_ON_ERROR), $status]);
    }
}
