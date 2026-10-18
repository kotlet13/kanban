<?php

namespace Kanboard\Plugin\FamilyHub\Model;

/** Existing 90-second organization-table coordination, with no plaintext document or holder name. */
class NativeCryptoTableV2 extends NativeDatabase
{
    protected $cryptoAccess = true;
    public const LEASE_SECONDS = 90;

    public function read($p, $actor)
    {
        $this->fields($p, ['scopeId', 'id', 'accessRevision']);
        $scope = $this->scope($this->uuid($p['scopeId']), $actor['user']['id']);
        if ($scope['kind'] !== 'organization' || $p['accessRevision'] !== (int)$scope['effective_access_revision']) {
            throw new NativeError('crypto_access_changed', 409);
        }
        $id = NativeCryptoRecordAddressV2::wireId($p['id']);
        $row = $this->one('SELECT * FROM familyhub_crypto_table_leases WHERE scope_id=? AND id=?', [$scope['id'], $id]);
        $head = (new NativeCryptoScopeV2($this->container))->current($scope['id']);
        return ['lease' => $row && $head && $row['head_hash'] === $head['head_hash'] ? $this->wire($row, $actor) : null];
    }

    public function write($op, $p, $actor)
    {
        $required = ['scopeId', 'id', 'domain', 'epoch', 'accessRevision', 'membershipHeadHash'];
        $this->fields($p, $op === 'crypto2.table.acquire' ? $required : array_merge($required, ['tokenBase64']), $op === 'crypto2.table.acquire' ? ['tokenBase64'] : []);
        if (!in_array($op, ['crypto2.table.acquire', 'crypto2.table.renew', 'crypto2.table.release'], true) || $p['domain'] !== 'content') {
            throw new NativeError('validation_error');
        }
        [$scope] = (new NativeCryptoScopeV2($this->container, $this->bearer, $this->ip))->author($p['scopeId'], $p['membershipHeadHash'], $p['epoch'], $p['accessRevision'], $actor, 'content');
        if ($scope['kind'] !== 'organization') {
            throw new NativeError('tables_scope_unsupported', 403);
        }
        $id = NativeCryptoRecordAddressV2::wireId($p['id']);
        $table = $this->one("SELECT id FROM familyhub_crypto_records WHERE scope_id=? AND id=? AND type='table' AND deleted=0", [$scope['id'], $id]);
        if (!$table) {
            throw new NativeError('table_unavailable', 404);
        }
        $row = $this->one('SELECT * FROM familyhub_crypto_table_leases WHERE scope_id=? AND id=?', [$scope['id'], $id]);
        if ($op === 'crypto2.table.acquire') {
            $active = $row && $row['head_hash'] === $p['membershipHeadHash'] && (int)$row['expires_at'] > time();
            if ($active && !$this->valid($row, $actor, $p['tokenBase64'] ?? $this->derive($row))) {
                throw new NativeError('table_locked', 409, ['lease' => $this->wire($row, null)]);
            }
            if (!$active) {
                $row = ['scope_id' => $scope['id'], 'id' => $id, 'head_hash' => $p['membershipHeadHash'], 'account_id' => $actor['user']['account_id'], 'device_id' => $actor['device']['id'], 'nonce' => base64_encode(random_bytes(32)), 'expires_at' => 0];
                $row['token_hash'] = hash('sha256', $this->derive($row));
            }
            $row['expires_at'] = time() + self::LEASE_SECONDS;
            $this->change('DELETE FROM familyhub_crypto_table_leases WHERE scope_id=? AND id=?', [$scope['id'], $id]);
            $this->change('INSERT INTO familyhub_crypto_table_leases VALUES(?,?,?,?,?,?,?,?)', [$row['scope_id'], $id, $row['head_hash'], $row['account_id'], $row['device_id'], $row['nonce'], $row['token_hash'], $row['expires_at']]);
            $wire = $this->wire($row, $actor);
            if (!isset($wire['tokenBase64']) && isset($p['tokenBase64'])) {
                $wire['tokenBase64'] = $p['tokenBase64'];
            }
            return ['lease' => $wire];
        }
        if (!$row || $row['head_hash'] !== $p['membershipHeadHash'] || !$this->valid($row, $actor, $p['tokenBase64'])) {
            throw new NativeError('lease_lost', 409);
        }
        if ($op === 'crypto2.table.release') {
            $this->change('DELETE FROM familyhub_crypto_table_leases WHERE scope_id=? AND id=?', [$scope['id'], $id]);
            return ['released' => true];
        }
        $row['expires_at'] = time() + self::LEASE_SECONDS;
        $this->change('UPDATE familyhub_crypto_table_leases SET expires_at=? WHERE scope_id=? AND id=?', [$row['expires_at'], $scope['id'], $id]);
        $wire = $this->wire($row, $actor);
        // A bearer refresh cannot erase a valid explicitly supplied token held by this device.
        $wire['tokenBase64'] = $p['tokenBase64'];
        return ['lease' => $wire];
    }

    public function assertBatch($payload, $prepared, $actor)
    {
        $tokens = [];
        $leases = $payload['tableLeases'] ?? [];
        if (!is_array($leases) || !array_is_list($leases) || count($leases) > 32) {
            throw new NativeError('validation_error');
        }
        foreach ($leases as $lease) {
            if (!is_array($lease)) {
                throw new NativeError('validation_error');
            }
            $this->fields($lease, ['scopeId', 'id', 'tokenBase64']);
            $sid = $this->uuid($lease['scopeId']);
            $id = NativeCryptoRecordAddressV2::wireId($lease['id']);
            NativeCryptoCodec::base64($lease['tokenBase64'], 32, 32);
            $key = $sid.':'.$id;
            if (isset($tokens[$key])) {
                throw new NativeError('validation_error');
            }
            $tokens[$key] = $lease['tokenBase64'];
        }
        $counts = [];
        foreach ($prepared as $key => $entry) {
            $r = $entry['record'];
            if ($r['type'] !== 'table') {
                continue;
            }
            $scope = $this->scope($r['scopeId'], $actor['user']['id'], true);
            if ($scope['kind'] !== 'organization') {
                throw new NativeError('tables_scope_unsupported', 403);
            }
            if (!isset($counts[$r['scopeId']])) {
                $counts[$r['scopeId']] = (int)$this->one("SELECT COUNT(*) AS n FROM familyhub_crypto_records WHERE scope_id=? AND type='table' AND deleted=0", [$r['scopeId']])['n'];
            }
            $old = $entry['old'];
            $counts[$r['scopeId']] += ($r['deleted'] ? 0 : 1) - ($old && !(int)$old['deleted'] ? 1 : 0);
            if ($r['expectedRevision'] > 0) {
                $row = $this->one('SELECT * FROM familyhub_crypto_table_leases WHERE scope_id=? AND id=?', [$r['scopeId'], $r['id']]);
                if (!$row || $row['head_hash'] !== $r['membershipHeadHash'] || !$this->valid($row, $actor, $tokens[$key] ?? null)) {
                    throw new NativeError('lease_lost', 409);
                }
                unset($tokens[$key]);
            }
        }
        if ($tokens) {
            throw new NativeError('validation_error');
        }
        foreach ($counts as $count) {
            if ($count > 100) {
                throw new NativeError('table_limit', 422);
            }
        }
    }

    private function derive($row)
    {
        return base64_encode(hash_hmac('sha256', "JivieTableLease/v2\n".NativeCryptoCodec::canonical((object)['scopeId' => $row['scope_id'], 'id' => $row['id'], 'headHash' => $row['head_hash'], 'nonce' => $row['nonce']]), $this->bearer, true));
    }

    private function valid($row, $actor, $token)
    {
        if (!is_string($token) || (int)$row['expires_at'] <= time() || $row['account_id'] !== $actor['user']['account_id'] || $row['device_id'] !== $actor['device']['id']) {
            return false;
        }
        NativeCryptoCodec::base64($token, 32, 32);
        return hash_equals($row['token_hash'], hash('sha256', $token));
    }

    private function wire($row, $actor)
    {
        if ((int)$row['expires_at'] <= time()) {
            return null;
        }
        $wire = ['holderAccountId' => $row['account_id'], 'holderDeviceId' => $row['device_id'], 'expiresAt' => (int)$row['expires_at']];
        if ($actor && $row['account_id'] === $actor['user']['account_id'] && $row['device_id'] === $actor['device']['id']) {
            $token = $this->derive($row);
            if (hash_equals($row['token_hash'], hash('sha256', $token))) {
                $wire['tokenBase64'] = $token;
            }
        }
        return $wire;
    }
}
