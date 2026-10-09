<?php
namespace Kanboard\Plugin\FamilyHub\Model;
/** One authority for derived read access. Never creates project edit grants. */

class NativeOrganizationAccess extends NativeDatabase
{

    public function leader($organization, $accountId)
    {
        if (!$organization || $organization['kind'] !== 'organization' || (int)$organization['access_policy_version'] !== 2) {
            return false;
        }
        $member = $this->one('SELECT m.role FROM familyhub_members m JOIN familyhub_accounts a ON a.account_id=m.account_id AND a.user_id=m.user_id JOIN users u ON u.id=a.user_id WHERE m.scope_id=? AND m.account_id=? AND m.active=1 AND u.is_active=1', [$organization['id'], $accountId]);
        return $member && ($member['role'] === 'owner' || (bool)$this->one('SELECT account_id FROM familyhub_organization_leaders WHERE scope_id=? AND account_id=?', [$organization['id'], $accountId]));
    }

    public function decorate($scope, $accountId, $directRole = null)
    {
        $organization = $scope['kind'] === 'organization' ? $scope : (!empty($scope['organization_id']) ? $this->one('SELECT * FROM familyhub_scopes WHERE id=?', [$scope['organization_id']]) : null);
        $leader = $this->leader($organization, $accountId);
        if ($directRole === null && !($scope['kind'] === 'project' && $leader)) {
            return null;
        }
        $scope['role'] = $directRole ?? 'viewer';
        $scope['effective_access_policy_version'] = (int)($organization['access_policy_version'] ?? $scope['access_policy_version'] ?? 1);
        $scope['effective_access_revision'] = (int)($organization['access_revision'] ?? $scope['access_revision'] ?? 0);
        $scope['organization_leader'] = $leader;
        $scope['access_source'] = $directRole === null ? 'leadership' : 'direct';
        return $scope;
    }

    public function automaticFinanceRead($scope)
    {
        return (int)($scope['effective_access_policy_version'] ?? 1) === 2 && (($scope['kind'] === 'project' && !empty($scope['organization_id'])) || ($scope['kind'] === 'organization' && !empty($scope['organization_leader'])));
    }
    /** Explicit server decision, never synthesized from a missing listing. */

    public function reconcileRevocations($scopeIds, $accountId)
    {
        foreach (array_unique($scopeIds) as $scopeId) {
            $this->change('DELETE FROM familyhub_scope_revocations WHERE scope_id=? AND account_id=?', [$scopeId, $accountId]);
            if (!$this->visibleScope($scopeId, $accountId) && $this->one('SELECT id FROM familyhub_scopes WHERE id=?', [$scopeId])) {
                $this->change('INSERT INTO familyhub_scope_revocations VALUES(?,?)', [$scopeId, $accountId]);
            }
        }
    }

    public function relatedScopeIds($scopeId)
    {
        return array_merge([$scopeId], array_column($this->many('SELECT id FROM familyhub_scopes WHERE organization_id=? ORDER BY id', [$scopeId]), 'id'));
    }

    public function visibleScope($scopeId, $accountId)
    {
        $scope = $this->one('SELECT * FROM familyhub_scopes WHERE id=?', [$scopeId]);
        if (!$scope) {
            return null;
        }
        $member = $this->one('SELECT m.role FROM familyhub_members m JOIN familyhub_accounts a ON a.account_id=m.account_id AND a.user_id=m.user_id JOIN users u ON u.id=a.user_id WHERE m.scope_id=? AND m.account_id=? AND m.active=1 AND u.is_active=1', [$scopeId, $accountId]);
        return $this->decorate($scope, $accountId, $member['role'] ?? null);
    }
}
