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

    public function directMember($scopeId, $accountId)
    {
        return $this->one('SELECT m.*,u.username,u.name FROM familyhub_members m JOIN familyhub_accounts a ON a.account_id=m.account_id AND a.user_id=m.user_id JOIN users u ON u.id=a.user_id WHERE m.scope_id=? AND m.account_id=? AND m.active=1 AND u.is_active=1', [$scopeId, $accountId]);
    }

    public function decorate($scope, $accountId, $directRole = null)
    {
        $parentId = $scope['parent_scope_id'] ?? $scope['organization_id'] ?? null;
        $parent = $parentId ? $this->one('SELECT * FROM familyhub_scopes WHERE id=?', [$parentId]) : null;
        $organization = $scope['kind'] === 'organization' ? $scope : ($parent && $parent['kind']==='organization' ? $parent : null);
        $leader = $this->leader($organization, $accountId);
        $version = (int)($parent['access_policy_version'] ?? $scope['access_policy_version'] ?? 1);
        $inherited = $version===3 && $scope['kind']==='project' && $parent && in_array($parent['kind'],['household','organization'],true) ? $this->directMember($parentId,$accountId) : null;
        if ($directRole === null && !$inherited && !($scope['kind']==='project' && $leader)) { return null; }
        $role = $directRole ?? ($inherited ? ($inherited['role']==='owner' ? 'member' : $inherited['role']) : 'viewer');
        if ($inherited && $inherited['role']!=='viewer' && $role==='viewer') { $role='member'; }
        $scope['role'] = $role;
        $scope['effective_access_policy_version'] = $version;
        $scope['effective_access_revision'] = (int)($scope['access_revision']??0) + ($parent ? (int)$parent['access_revision'] : 0);
        $scope['organization_leader'] = $version===3 ? $scope['kind']==='organization' && $role==='owner' : $leader;
        $scope['parent_scope_kind'] = $parent['kind'] ?? null;
        $scope['access_source'] = $directRole === null ? ($inherited ? 'spaceMembership' : 'leadership') : 'direct';
        return $scope;
    }

    public function automaticFinanceRead($scope)
    {
        $version=(int)($scope['effective_access_policy_version'] ?? 1);
        return $version===3 && $scope['kind']!=='personal' || $version===2 && (($scope['kind']==='project' && !empty($scope['organization_id'])) || ($scope['kind']==='organization' && !empty($scope['organization_leader'])));
    }

    /** Effective union, used by notifications, assignees and member management. */
    public function members($scopeId)
    {
        $scope=$this->one('SELECT * FROM familyhub_scopes WHERE id=?',[$scopeId]);
        if (!$scope) { return []; }
        $ids=[$scopeId];$parent=$scope['parent_scope_id']??$scope['organization_id']??null;
        if ($parent && (int)($this->one('SELECT access_policy_version FROM familyhub_scopes WHERE id=?',[$parent])['access_policy_version']??1)===3) { $ids[]=$parent; }
        $accounts=$this->many('SELECT DISTINCT m.account_id FROM familyhub_members m WHERE m.scope_id IN ('.implode(',',array_fill(0,count($ids),'?')).') AND m.active=1 ORDER BY m.account_id',$ids);
        $result=[];
        foreach ($accounts as $account) {
            $effective=$this->visibleScope($scopeId,$account['account_id']);
            if (!$effective) { continue; }
            $direct=$this->directMember($scopeId,$account['account_id']);$member=$direct??$this->directMember($parent,$account['account_id']);
            $result[]=['userId'=>(int)$member['user_id'],'accountId'=>$member['account_id'],'username'=>$member['username'],'displayName'=>$member['name']?:$member['username'],'role'=>$effective['role'],'active'=>true,'accessSource'=>$effective['access_source'],'membershipScopeId'=>$direct?$scopeId:$parent,'accessSources'=>array_values(array_filter([$direct?'direct':null,$parent && $this->directMember($parent,$account['account_id'])?'spaceMembership':null])),'inheritedFromScopeId'=>$parent && $this->directMember($parent,$account['account_id'])?$parent:null,'organizationLeader'=>$effective['organization_leader']];
        }
        return $result;
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
        return array_merge([$scopeId], array_column($this->many('SELECT id FROM familyhub_scopes WHERE parent_scope_id=? OR organization_id=? ORDER BY id', [$scopeId,$scopeId]), 'id'));
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
