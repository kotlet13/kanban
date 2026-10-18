<?php

namespace Kanboard\Plugin\FamilyHub\Model;

/** A member can request removal; only the existing component managers can apply it. */
class NativeCryptoLeaveV2 extends NativeDatabase
{
    protected $cryptoAccess = true;

    private function digest($value)
    {
        if (!is_string($value) || !preg_match('/^[a-f0-9]{64}$/D', $value)) {
            throw new NativeError('validation_error');
        }
    }

    private function scopes()
    {
        return new NativeCryptoScopeV2($this->container, $this->bearer, $this->ip);
    }

    private function row($hash)
    {
        $this->digest($hash);
        $row = $this->one('SELECT * FROM familyhub_crypto_leave_requests_v2 WHERE request_hash=?', [$hash]);
        if (!$row) {
            throw new NativeError('crypto_leave_request_unavailable', 409);
        }
        return $row;
    }

    private function payload($row)
    {
        [$command] = NativeCryptoCodec::decode(json_decode($row['authorization'], true, 34, JSON_THROW_ON_ERROR));
        return $command['payload'];
    }

    /** Exact original membership generation: an old request cannot survive a leave/rejoin. */
    public function assertPending($hash, $scopeId, $target)
    {
        $row = $this->row($hash);
        $p = $this->payload($row);
        if ($row['scope_id'] !== $scopeId || $row['account_id'] !== $target ||
            $row['state'] !== 'pending' || (int)$row['expires_at'] <= time()) {
            throw new NativeError('crypto_leave_request_changed', 409);
        }
        $head = $this->scopes()->current($scopeId);
        $scope = $this->one('SELECT * FROM familyhub_scopes WHERE id=? AND deleted_at IS NULL', [$scopeId]);
        $member = $this->one('SELECT m.*,u.is_active FROM familyhub_members m JOIN familyhub_accounts a ON a.account_id=m.account_id AND a.user_id=m.user_id JOIN users u ON u.id=m.user_id WHERE m.scope_id=? AND m.account_id=? AND m.active=1', [$scopeId,$target]);
        if (!$head || !$scope || !$member || !(int)$member['is_active'] || $member['role'] === 'owner' ||
            $head['head_hash'] !== $p['membershipHeadHash']) {
            throw new NativeError('crypto_leave_request_changed', 409);
        }
        $effective = (new NativeOrganizationAccess($this->container))->visibleScope($scopeId, $target);
        if (!$effective || (int)$effective['effective_access_revision'] !== $p['expectedAccessRevision']) {
            throw new NativeError('crypto_leave_request_changed', 409);
        }
        // Unrelated own-log events are harmless; root/device-set changes require
        // a new explicit request, even if a host retains the old request row.
        $this->scopes()->currentAuthorReference($p['authorDirectoryHeadHash'], [
            'user' => ['account_id' => $target], 'device' => ['id' => $row['device_id']],
        ]);
        return $row;
    }

    public function validatePlan($row)
    {
        [$prepare] = NativeCryptoCodec::decode(json_decode($row['authorization'], true, 34, JSON_THROW_ON_ERROR));
        $p = $prepare['payload'];
        if (!array_key_exists('leaveRequestHash', $p)) {
            return;
        }
        if (($p['action']['kind'] ?? null) !== 'memberRemove') {
            throw new NativeError('validation_error');
        }
        $this->assertPending($p['leaveRequestHash'], $row['scope_id'], $p['action']['accountId']);
    }

    /** Called only after every real scope head has atomically activated. */
    public function completePlan($row)
    {
        [$prepare] = NativeCryptoCodec::decode(json_decode($row['authorization'], true, 34, JSON_THROW_ON_ERROR));
        $p = $prepare['payload'];
        if (!isset($p['leaveRequestHash'])) {
            return;
        }
        $target = $p['action']['accountId'];
        $remaining = (new NativeOrganizationAccess($this->container))->visibleScope($row['scope_id'], $target);
        $head = $this->scopes()->current($row['scope_id']);
        if ($remaining || !$head || $this->scopes()->member($this->scopes()->body($head), $target)) {
            throw new NativeError('crypto_leave_not_applied', 409);
        }
        $this->change("UPDATE familyhub_crypto_leave_requests_v2 SET state='applied',intent_hash=?,result_head_hash=? WHERE request_hash=? AND state='pending'", [$row['intent_hash'],$head['head_hash'],$p['leaveRequestHash']]);
    }

    public function write($op, $p, $actor, $proof, $command)
    {
        if ($op === 'crypto2.access.leaveCancel') {
            $this->fields($p, ['requestHash']);
            $row = $this->row($p['requestHash']);
            if ($row['account_id'] !== $actor['user']['account_id']) {
                throw new NativeError('permission_revoked', 403);
            }
            if ($row['state'] === 'applied') {
                throw new NativeError('crypto_leave_already_applied', 409);
            }
            $this->change("UPDATE familyhub_crypto_leave_requests_v2 SET state='cancelled' WHERE request_hash=?", [$row['request_hash']]);
            return ['requestHash' => $row['request_hash'], 'state' => 'cancelled'];
        }
        if ($op !== 'crypto2.access.leaveRequest') {
            throw new NativeError('unsupported_operation', 404);
        }
        $this->fields($p, ['scopeId','membershipHeadHash','expectedAccessRevision','authorDirectoryHeadHash','expiresAtEpoch']);
        $scope = $this->scope($this->uuid($p['scopeId']), $actor['user']['id']);
        NativeCryptoScopeCreationV2::guardBusiness($this->pdo, $scope['id']);
        $this->digest($p['membershipHeadHash']);
        $this->scopes()->currentAuthorReference($p['authorDirectoryHeadHash'], $actor);
        $head = $this->scopes()->current($scope['id']);
        $member = $head ? $this->scopes()->member($this->scopes()->body($head), $actor['user']['account_id']) : null;
        if (!$member || $member['role'] === 'owner') {
            throw new NativeError('scope_owner_transfer_required', 409);
        }
        if (!is_int($p['expectedAccessRevision']) || $p['expectedAccessRevision'] !== (int)$scope['effective_access_revision'] ||
            !$head || $head['head_hash'] !== $p['membershipHeadHash'] ||
            !is_int($p['expiresAtEpoch']) || $p['expiresAtEpoch'] <= time() || $p['expiresAtEpoch'] > time() + 604800) {
            throw new NativeError('crypto_leave_request_changed', 409);
        }
        $current = (new NativeCryptoDirectoryV2($this->container))->current($actor['user']['account_id']);
        if ($member['deviceSnapshotHash'] !== $current['device_snapshot_hash']) {
            throw new NativeError('scope_rotation_required', 409);
        }
        $direct = $this->one('SELECT role FROM familyhub_members WHERE scope_id=? AND account_id=? AND active=1', [$scope['id'],$actor['user']['account_id']]);
        if (!$direct) {
            throw new NativeError('crypto_membership_parent_action_required', 409);
        }
        $count = $this->one("SELECT COUNT(*) n FROM familyhub_crypto_leave_requests_v2 WHERE scope_id=? AND account_id=? AND state='pending' AND expires_at>?", [$scope['id'],$actor['user']['account_id'],time()]);
        if ((int)$count['n'] >= 4) {
            throw new NativeError('crypto_leave_requests_full', 409);
        }
        $hash = NativeCryptoV2Codec::hash((object)$proof);
        $this->change('INSERT INTO familyhub_crypto_leave_requests_v2(request_hash,scope_id,account_id,device_id,authorization,state,expires_at,intent_hash,result_head_hash) VALUES(?,?,?,?,?,?,?,NULL,NULL)', [$hash,$scope['id'],$actor['user']['account_id'],$actor['device']['id'],json_encode($proof, JSON_THROW_ON_ERROR),'pending',$p['expiresAtEpoch']]);
        return ['requestHash' => $hash, 'state' => 'pending'];
    }

    public function read($op, $p, $actor)
    {
        if ($op === 'crypto2.access.leaveStatus') {
            $this->fields($p, ['requestHash']);
            $row = $this->row($p['requestHash']);
            if ($row['account_id'] !== $actor['user']['account_id']) {
                throw new NativeError('permission_revoked', 403);
            }
            $state=$row['state'];
            if ($state==='pending') {
                if ((int)$row['expires_at']<=time()) $state='expired';
                else {
                    try { $this->assertPending($row['request_hash'],$row['scope_id'],$row['account_id']); }
                    catch (NativeError $error) {
                        if (!in_array($error->errorCode,['crypto_leave_request_changed','crypto_member_directory_changed','crypto_device_unapproved'],true)) throw $error;
                        $state='renewalRequired';
                    }
                }
            }
            return ['requestHash' => $row['request_hash'], 'state' => $state, 'intentHash' => $row['intent_hash'], 'headHash' => $row['result_head_hash']];
        }
        if ($op !== 'crypto2.access.leaveRequests') {
            throw new NativeError('unsupported_operation', 404);
        }
        $this->fields($p, ['scopeId'], ['afterHash','limit']);
        $scope = $this->scope($this->uuid($p['scopeId']), $actor['user']['id'], false, true);
        $this->scopes()->manager($this->scopes()->current($scope['id']), $scope, $actor);
        $after = $p['afterHash'] ?? '';
        if ($after !== '') $this->digest($after);
        $limit = $p['limit'] ?? 20;
        if (!is_int($limit) || $limit < 1 || $limit > 20) throw new NativeError('validation_error');
        $rows = $this->many("SELECT request_hash,authorization FROM familyhub_crypto_leave_requests_v2 WHERE scope_id=? AND state='pending' AND expires_at>? AND request_hash>? ORDER BY request_hash LIMIT ".($limit + 1), [$scope['id'],time(),$after]);
        $more = count($rows) > $limit;
        if ($more) array_pop($rows);
        $items = [];
        foreach ($rows as $row) {
            $items[] = ['requestHash' => $row['request_hash'], 'authorization' => json_decode($row['authorization'], true, 34, JSON_THROW_ON_ERROR)];
        }
        return ['requests' => $items, 'hasMore' => $more, 'nextAfterHash' => $items ? $items[count($items)-1]['requestHash'] : null];
    }
}
