<?php
namespace Kanboard\Plugin\FamilyHub\Model;
/** Explicit permission transition and leadership management under the organization lock. */

class NativeSpacesAccessService extends NativeDatabase
{

    public function inTransaction($operation, $params, $user)
    {
        if (($params['targetVersion']??2)===3) { return (new NativeSpaceSharingAccessService($this->container))->inTransaction($operation,$params,$user); }
        $optional = match ($operation) {
            'scopes.setLeader' => ['accountId', 'enabled', 'requestId'],
            'scopes.accessMigrationApply' => ['previewHash', 'requestId','targetVersion'],
            'scopes.accessMigrationPreview' => ['targetVersion'],
            default => [],
        };
        $this->fields($params, ['scopeId'], $optional);
        $id = $this->uuid($params['scopeId']);
        $scope = $this->scope($id, $user['id'], false, true);
        if (isset($params['targetVersion']) && $params['targetVersion']!==2) { throw new NativeError('validation_error'); }
        if ((int)$scope['access_policy_version']>=3) { throw new NativeError('client_upgrade_required',409); }
        if ($scope['role']!=='owner') { throw new NativeError('permission_revoked',403); }
        if ($scope['kind'] !== 'organization') {
            throw new NativeError('validation_error');
        }
        if ($operation === 'scopes.accessMigrationPreview') {
            return $this->preview($scope);
        }
        $request = $this->uuid($params['requestId'] ?? null);
        $hash = $this->hashRequest($operation, $params);
        $replay = $this->replay($id, $user['id'], $request, $hash);
        if ($replay) {
            return $replay['body'];
        }
        if ($operation === 'scopes.setLeader') {
            if ((int)$scope['access_policy_version'] !== 2) {
                throw new NativeError('access_migration_required', 409);
            }
            $account = $this->uuid($params['accountId'] ?? null);
            if (!is_bool($params['enabled'] ?? null)) {
                throw new NativeError('validation_error');
            }
            $member = $this->one('SELECT m.role FROM familyhub_members m JOIN familyhub_accounts a ON a.account_id=m.account_id AND a.user_id=m.user_id JOIN users u ON u.id=a.user_id WHERE m.scope_id=? AND m.account_id=? AND m.active=1 AND u.is_active=1', [$id, $account]);
            if (!$member) {
                throw new NativeError('assignee_not_member');
            }
            if ($member['role'] === 'owner' && !$params['enabled']) {
                throw new NativeError('cannot_remove_owner');
            }
            $access = new NativeOrganizationAccess($this->container);
            $related = $access->relatedScopeIds($id);
            $formerlyVisible = array_values(array_filter($related, fn($sid) => $access->visibleScope($sid, $account)));
            $this->change('DELETE FROM familyhub_organization_leaders WHERE scope_id=? AND account_id=?', [$id, $account]);
            if ($params['enabled'] && $member['role'] !== 'owner') {
                $this->change('INSERT INTO familyhub_organization_leaders VALUES(?,?)', [$id, $account]);
            }
            $this->change('UPDATE familyhub_scopes SET access_revision=access_revision+1,sequence=sequence+1 WHERE id=?', [$id]);
            $access->reconcileRevocations($params['enabled']?$related:$formerlyVisible, $account);
            (new NativeNotificationWriter($this->container))->visibilityChanged([$account]);
            $result = ['members' => $this->members($id), 'accessRevision' => (int)$scope['access_revision']+1];
        }
        elseif ($operation === 'scopes.accessMigrationApply') {
            $preview = $this->preview($scope);
            if (!is_string($params['previewHash'] ?? null) || !hash_equals($preview['previewHash'], $params['previewHash'])) {
                throw new NativeError('access_preview_changed', 409);
            }
            if ((int)$scope['access_policy_version'] !== 2) {
                $this->change('UPDATE familyhub_scopes SET access_policy_version=2,access_revision=access_revision+1,sequence=sequence+1 WHERE id=?', [$id]);
                $this->enableManagedFinance($id);
                foreach ($this->many('SELECT id FROM familyhub_scopes WHERE organization_id=? ORDER BY id', [$id]) as $child) {
                    $this->enableManagedFinance($child['id']);
                }
                $affected = array_column($this->many('SELECT DISTINCT m.account_id FROM familyhub_members m JOIN familyhub_scopes s ON s.id=m.scope_id WHERE (s.id=? OR s.organization_id=?) AND m.active=1', [$id, $id]), 'account_id');
                (new NativeNotificationWriter($this->container))->visibilityChanged($affected);
            }
            $result = ['scope' => $this->scopeWire($this->scope($id, $user['id'])), 'preview' => $preview];
        }
        else {
            throw new NativeError('unsupported_operation', 404);
        }
        $this->remember($id, $user['id'], $request, $hash, $result);
        return $result;
    }

    private function enableManagedFinance($scopeId)
    {
        $insert = $this->sqlite?'INSERT OR IGNORE':'INSERT IGNORE';
        $this->change($insert.' INTO familyhub_finance_policy(scope_id,enabled,revision,sequence) VALUES(?,0,0,0)', [$scopeId]);
        $this->change('UPDATE familyhub_finance_policy SET enabled=1,revision=revision+1 WHERE scope_id=?', [$scopeId]);
        $owner = $this->one("SELECT m.account_id FROM familyhub_members m WHERE m.scope_id=? AND m.role='owner' AND m.active=1", [$scopeId]);
        if ($owner) {
            $this->change($insert." INTO familyhub_finance_grants(scope_id,account_id,access_level) VALUES(?,?,'write')", [$scopeId, $owner['account_id']]);
        }
    }

    public function members($scopeId)
    {
        $scope = $this->one('SELECT * FROM familyhub_scopes WHERE id=?', [$scopeId]);
        $access = new NativeOrganizationAccess($this->container);
        $rows = $this->many('SELECT m.user_id,m.role,u.username,u.name,m.account_id FROM familyhub_members m JOIN users u ON u.id=m.user_id JOIN familyhub_accounts a ON a.user_id=m.user_id AND a.account_id=m.account_id WHERE m.scope_id=? AND m.active=1 AND u.is_active=1 ORDER BY m.user_id', [$scopeId]);
        return array_map(fn($r) => ['userId' => (int)$r['user_id'], 'accountId' => $r['account_id'], 'username' => $r['username'], 'displayName' => $r['name']?:$r['username'], 'role' => $r['role'], 'active' => true, 'organizationLeader' => $access->leader($scope, $r['account_id'])], $rows);
    }

    private function preview($organization)
    {
        $id = $organization['id'];
        $projects = [];
        $fingerprint = ['organization' => $organization];
        $leaders = $this->many('SELECT m.*,u.name,u.username FROM familyhub_members m JOIN familyhub_accounts a ON a.account_id=m.account_id AND a.user_id=m.user_id JOIN users u ON u.id=a.user_id LEFT JOIN familyhub_organization_leaders l ON l.scope_id=m.scope_id AND l.account_id=m.account_id WHERE m.scope_id=? AND m.active=1 AND u.is_active=1 AND (m.role=\'owner\' OR l.account_id IS NOT NULL) ORDER BY m.account_id', [$id]);
        $fingerprint['leaders'] = $leaders;
        foreach ($this->many('SELECT * FROM familyhub_scopes WHERE organization_id=? ORDER BY id', [$id]) as $child) {
            $members = $this->many('SELECT m.*,u.name,u.username,g.access_level FROM familyhub_members m JOIN familyhub_accounts a ON a.account_id=m.account_id AND a.user_id=m.user_id JOIN users u ON u.id=a.user_id LEFT JOIN familyhub_finance_grants g ON g.scope_id=m.scope_id AND g.account_id=m.account_id WHERE m.scope_id=? AND m.active=1 AND u.is_active=1 ORDER BY m.account_id', [$child['id']]);
            $policy = $this->one('SELECT * FROM familyhub_finance_policy WHERE scope_id=?', [$child['id']]);
            $fingerprint['projects'][] = ['scope' => $child, 'members' => $members, 'policy' => $policy];
            $additional = [];
            if ((int)$organization['access_policy_version'] === 1) {
                foreach ($members as $m) {
                    if (!(int)($policy['enabled'] ?? 0) || !in_array($m['access_level'], ['read', 'write'], true)) {
                        $additional[$m['account_id']] = ['accountId' => $m['account_id'], 'displayName' => $m['name']?:$m['username'], 'accessSource' => 'projectMembership'];
                    }
                }
                foreach ($leaders as $l) {
                    $direct = array_values(array_filter($members, fn($m) => $m['account_id'] === $l['account_id']));
                    if (!(int)($policy['enabled'] ?? 0) || !$direct || !in_array($direct[0]['access_level'], ['read', 'write'], true)) {
                        $additional[$l['account_id']] = ['accountId' => $l['account_id'], 'displayName' => $l['name']?:$l['username'], 'accessSource' => 'leadership'];
                    }
                }
            }
            ksort($additional);
            $projects[] = ['scopeId' => $child['id'], 'name' => $child['name'], 'financeWasEnabled' => (bool)($policy['enabled'] ?? false), 'additionalReaders' => array_values($additional)];
        }
        return ['scopeId' => $id, 'fromVersion' => (int)$organization['access_policy_version'], 'toVersion' => 2, 'projects' => $projects, 'previewHash' => hash('sha256', $this->canonical($fingerprint))];
    }
}
