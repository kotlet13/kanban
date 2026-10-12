<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** Shared effects for member removal and administrator scoped restrictions. Caller holds scope transaction. */
class NativeMembershipRevocation extends NativeDatabase
{
    public function apply(array $scope,$accountId,$userId=null,$moderation=false)
    {
        $id=$scope['id'];$access=new NativeOrganizationAccess($this->container);
        $formerlyVisible=array_values(array_filter($access->relatedScopeIds($id),fn($sid)=>$access->visibleScope($sid,$accountId)));
        if ($moderation) {
            if (!$this->one('SELECT scope_id FROM familyhub_moderation_blocks WHERE scope_id=? AND account_id=?',[$id,$accountId])) { $this->change('INSERT INTO familyhub_moderation_blocks VALUES(?,?,?)',[$id,$accountId,time()]); }
        } else { $this->change('UPDATE familyhub_members SET active=0 WHERE scope_id=? AND user_id=?',[$id,$userId]); }
        if (!$moderation && ($scope['kind']==='organization' || (int)($scope['effective_access_policy_version']??$scope['access_policy_version'])===3)) { $this->change('DELETE FROM familyhub_organization_leaders WHERE scope_id=? AND account_id=?',[$id,$accountId]); }
        if ($moderation || $scope['kind']==='organization' || (int)($scope['effective_access_policy_version']??$scope['access_policy_version'])===3) { $this->change('UPDATE familyhub_scopes SET access_revision=access_revision+1 WHERE id=?',[$id]); }
        if (!$moderation) { $this->change("UPDATE familyhub_finance_grants SET access_level='none' WHERE scope_id=? AND account_id=?",[$id,$accountId]); }
        $this->change('UPDATE familyhub_finance_policy SET revision=revision+1 WHERE scope_id=?',[$id]);
        $access->reconcileRevocations($formerlyVisible,$accountId);
        (new NativeNotificationWriter($this->container))->visibilityChanged([$accountId]);
        $this->advance($scope);
    }
    public function undoModeration(array $scope,$accountId)
    {
        $this->change('DELETE FROM familyhub_moderation_blocks WHERE scope_id=? AND account_id=?',[$scope['id'],$accountId]);
        $this->change('UPDATE familyhub_scopes SET access_revision=access_revision+1 WHERE id=?',[$scope['id']]);
        $this->change('UPDATE familyhub_finance_policy SET revision=revision+1 WHERE scope_id=?',[$scope['id']]);
        $access=new NativeOrganizationAccess($this->container);
        $access->reconcileRevocations($access->relatedScopeIds($scope['id']),$accountId);
        (new NativeNotificationWriter($this->container))->visibilityChanged([$accountId]);
        $this->advance($scope);
    }
}
