<?php
namespace Kanboard\Plugin\FamilyHub\Model;

class NativeScopeService extends NativeDatabase
{
    public function execute($operation, array $params)
    {
        if (in_array($operation, ['scopes.list', 'scopes.members'], true)) {
            // Household devices share a NAT address. Reads have an individual
            // account budget as well as a broader pre-authentication IP envelope.
            $this->rate([['scopes-read-ip:'.$this->ip, 2400, 60]]);
            $actor = $this->actor(false);
            $this->rate([['scopes-read-account:'.$actor['user']['account_id'], 600, 60]]);
        } else {
            $this->rate([['scopes-ip:'.$this->ip, 120, 60]]);
        }
        return $this->transaction(function () use ($operation, $params) {
            $actor = $this->actor(); $user = $actor['user'];
            if ($operation === 'scopes.list') {
                $this->fields($params, [], ['includePersonal']);
                $includePersonal = $params['includePersonal'] ?? false;
                if (!is_bool($includePersonal)) { throw new NativeError('validation_error'); }
                $rows = $this->many('SELECT s.*,m.role FROM familyhub_scopes s JOIN familyhub_members m ON s.id=m.scope_id WHERE m.user_id=? AND m.account_id=? AND m.active=1 AND (s.kind<>\'personal\' OR (s.owner_id=m.user_id AND m.role=\'owner\' AND EXISTS (SELECT 1 FROM familyhub_personal_scopes p WHERE p.account_id=m.account_id AND p.scope_id=s.id))) ORDER BY s.created_at,s.id', [$user['id'], $user['account_id']]);
                return ['scopes' => array_map(fn ($row) => $this->scopeWire($row), array_values(array_filter($rows, fn ($row) => $includePersonal || $row['kind'] !== 'personal')))];
            }
            if ($operation === 'scopes.create') {
                $this->fields($params, ['id', 'kind', 'name', 'requestId']);
                $id = $this->uuid($params['id']); $request = $this->uuid($params['requestId']);
                if (!in_array($params['kind'], ['household', 'project'], true)) { throw new NativeError('validation_error'); }
                $name = $this->text($params['name'], 200); $hash = $this->hashRequest($operation, $params);
                $existing = $this->one('SELECT * FROM familyhub_scopes WHERE id = ?'.$this->lockSuffix(), [$id]);
                if ($existing) {
                    $this->scope($id, $user['id'], true, true);
                    $replay = $this->replay($id, $user['id'], $request, $hash);
                    if ($replay) { return $replay['body']; }
                    throw new NativeError('conflict', 409);
                }
                $this->change('INSERT INTO familyhub_scopes(id,kind,name,owner_id,sequence,created_at) VALUES(?,?,?,?,0,?)', [$id, $params['kind'], $name, $user['id'], time()]);
                $this->change('INSERT INTO familyhub_members(scope_id,user_id,account_id,role,active) VALUES(?,?,?,\'owner\',1)', [$id, $user['id'], $user['account_id']]);
                $result = ['scope' => $this->scopeWire(['id' => $id, 'kind' => $params['kind'], 'name' => $name, 'role' => 'owner', 'sequence' => 0])];
                $this->remember($id, $user['id'], $request, $hash, $result);
                return $result;
            }
            if ($operation === 'scopes.members') {
                $this->fields($params, ['scopeId']);
                $id = $this->uuid($params['scopeId']); $authorized = $this->scope($id, $user['id']);
                $rows = $this->many('SELECT m.user_id,m.role,u.username,u.name,m.account_id FROM familyhub_members m JOIN users u ON u.id=m.user_id JOIN familyhub_accounts a ON a.user_id=m.user_id AND a.account_id=m.account_id WHERE m.scope_id=? AND m.active=1 AND u.is_active=1 ORDER BY m.user_id', [$id]);
                if ($authorized['kind'] === 'personal') { $rows = array_values(array_filter($rows, fn ($row) => $row['account_id'] === $user['account_id'])); }
                return ['members' => array_map(fn ($row) => ['userId' => (int)$row['user_id'], 'accountId' => $row['account_id'], 'username' => $row['username'], 'displayName' => $row['name'] ?: $row['username'], 'role' => $row['role'], 'active' => true], $rows)];
            }
            if ($operation === 'scopes.removeMember') {
                $this->fields($params, ['scopeId', 'userId', 'requestId']);
                $id = $this->uuid($params['scopeId']); $request = $this->uuid($params['requestId']);
                $scope = $this->scope($id, $user['id'], true, true);
                if ($scope['kind'] === 'personal') { throw new NativeError('personal_not_shareable', 403); }
                if (!is_int($params['userId']) || $params['userId'] <= 0) { throw new NativeError('validation_error'); }
                $hash = $this->hashRequest($operation, $params);
                $replay = $this->replay($id, $user['id'], $request, $hash);
                if ($replay) { return $replay['body']; }
                $member = $this->one('SELECT * FROM familyhub_members WHERE scope_id = ? AND user_id = ?', [$id, $params['userId']]);
                if (!$member || $member['role'] === 'owner') { throw new NativeError('cannot_remove_owner'); }
                $this->change('UPDATE familyhub_members SET active=0 WHERE scope_id=? AND user_id=?', [$id, $params['userId']]);
                $this->change('UPDATE familyhub_finance_grants SET access_level=\'none\' WHERE scope_id=? AND account_id=?', [$id, $member['account_id']]);
                $this->change('UPDATE familyhub_finance_policy SET revision=revision+1 WHERE scope_id=?', [$id]);
                if ($member['account_id']) { (new NativeNotificationWriter($this->container))->visibilityChanged([$member['account_id']]); }
                $this->advance($scope);
                $result = ['removed' => true]; $this->remember($id, $user['id'], $request, $hash, $result);
                return $result;
            }
            throw new NativeError('unsupported_operation', 404);
        }, $operation === 'scopes.create');
    }
}
