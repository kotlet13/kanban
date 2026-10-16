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
        } else {
            $targets=in_array($scope['kind'],['organization','household'],true)?$access->relatedScopeIds($id):[$id];
            // A removed space member loses direct child grants too. Never silently
            // strand a project whose owner is being removed: transfer it first.
            foreach ($targets as $sid) {
                if ($sid!==$id && $this->one("SELECT s.id FROM familyhub_scopes s JOIN familyhub_members m ON m.scope_id=s.id WHERE s.id=? AND s.deleted_at IS NULL AND m.account_id=? AND m.role='owner' AND m.active=1",[$sid,$accountId])) { throw new NativeError('project_owner_transfer_required',409); }
            }
            $recipient=$this->one('SELECT username FROM users WHERE id=?',[$userId]);
            foreach ($targets as $sid) {
                $this->change('UPDATE familyhub_members SET active=0 WHERE scope_id=? AND account_id=?',[$sid,$accountId]);
                $this->change('DELETE FROM familyhub_organization_leaders WHERE scope_id=? AND account_id=?',[$sid,$accountId]);
                $this->change("UPDATE familyhub_finance_grants SET access_level='none' WHERE scope_id=? AND account_id=?",[$sid,$accountId]);
                $this->change('UPDATE familyhub_scopes SET access_revision=access_revision+1,sequence=sequence+1 WHERE id=?',[$sid]);
                $this->change('UPDATE familyhub_finance_policy SET revision=revision+1 WHERE scope_id=?',[$sid]);
                $this->change("UPDATE familyhub_reminders SET state='cancelled',revision=revision+1 WHERE scope_id=? AND account_id=? AND state='pending'",[$sid,$accountId]);
                $this->change('UPDATE familyhub_invitations SET revoked_at=? WHERE scope_id=? AND accepted_at IS NULL AND revoked_at IS NULL AND (recipient_account_id=? OR (invitation_contract<>3 AND recipient_username=?))',[time(),$sid,$accountId,strtolower($recipient['username']??'')]);
                $this->change("UPDATE familyhub_invitation_mail SET state='cancelled',token_cipher=NULL,lease_token=NULL WHERE invitation_id IN (SELECT id FROM familyhub_invitations WHERE scope_id=? AND revoked_at IS NOT NULL) AND state<>'accepted'",[$sid]);
            }
        }
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
