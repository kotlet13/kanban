<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** Policy3 opt-in: owner reviews every expanded audience and pending invitation. */
class NativeSpaceSharingAccessService extends NativeDatabase
{
    public function inTransaction($operation, $params, $user)
    {
        if (!in_array($operation,['scopes.accessMigrationPreview','scopes.accessMigrationApply'],true)) { throw new NativeError('validation_error'); }
        $this->fields($params,['scopeId','targetVersion'],$operation==='scopes.accessMigrationApply'?['previewHash','requestId']:[]);
        if ($params['targetVersion']!==3) { throw new NativeError('validation_error'); }
        $id=$this->uuid($params['scopeId']);$scope=$this->scope($id,$user['id'],false,true);
        if (!in_array($scope['kind'],['household','organization','project'],true) || $scope['role']!=='owner' || !empty($scope['parent_scope_id']) || !empty($scope['organization_id'])) { throw new NativeError('permission_revoked',403); }
        if ($operation==='scopes.accessMigrationPreview') { return $this->preview($scope); }
        $request=$this->uuid($params['requestId']??null);$hash=$this->hashRequest($operation,$params);$replay=$this->replay($id,$user['id'],$request,$hash);
        if ($replay) { return $replay['body']; }
        $preview=$this->preview($scope);
        if (!($preview['canApply']??true)) { throw new NativeError('access_migration_blocked',409,['blockers'=>$preview['blockers']]); }
        if (!is_string($params['previewHash']??null) || !hash_equals($preview['previewHash'],$params['previewHash'])) { throw new NativeError('access_preview_changed',409); }
        if ((int)$scope['access_policy_version']!==3) {
            if ($scope['kind']==='project' && empty($scope['project_root_id'])) { $root=$this->one("SELECT id FROM familyhub_records WHERE scope_id=? AND type='project' AND deleted=0",[$id]);$this->change('UPDATE familyhub_scopes SET project_root_id=?,required_record_contract=3 WHERE id=?',[$root['id'],$id]); }
            $this->change('UPDATE familyhub_scopes SET access_policy_version=3,access_revision=access_revision+1,sequence=sequence+1 WHERE id=?',[$id]);
            $insert=$this->sqlite?'INSERT OR IGNORE':'INSERT IGNORE';$affected=[];
            foreach ((new NativeOrganizationAccess($this->container))->relatedScopeIds($id) as $sid) {
                if ($sid!==$id) { $this->change('UPDATE familyhub_scopes SET access_policy_version=3,access_revision=access_revision+1 WHERE id=?',[$sid]); }
                $this->change($insert.' INTO familyhub_finance_policy(scope_id,enabled,revision,sequence) VALUES(?,0,0,0)',[$sid]);
                $this->change('UPDATE familyhub_finance_policy SET enabled=1,revision=revision+1 WHERE scope_id=?',[$sid]);
                $this->change('UPDATE familyhub_invitations SET revoked_at=? WHERE scope_id=? AND accepted_at IS NULL AND revoked_at IS NULL', [time(),$sid]);
                $this->change("UPDATE familyhub_invitation_mail SET state='cancelled',token_cipher=NULL,lease_token=NULL WHERE invitation_id IN (SELECT id FROM familyhub_invitations WHERE scope_id=? AND revoked_at IS NOT NULL) AND state<>'accepted'",[$sid]);
                foreach ((new NativeOrganizationAccess($this->container))->members($sid) as $member) { $affected[]=$member['accountId']; }
            }
            foreach (array_unique($affected) as $account) { (new NativeOrganizationAccess($this->container))->reconcileRevocations((new NativeOrganizationAccess($this->container))->relatedScopeIds($id),$account); }
            (new NativeNotificationWriter($this->container))->visibilityChanged($affected);
        }
        $result=['scope'=>$this->scopeWire($this->scope($id,$user['id'])),'preview'=>$preview];$this->remember($id,$user['id'],$request,$hash,$result);return $result;
    }

    private function preview($scope)
    {
        $access=new NativeOrganizationAccess($this->container);$id=$scope['id'];$rootMembers=$access->members($id);$fingerprint=[$scope,$rootMembers];$projects=[];$revoked=[];$blockers=[];
        if ($scope['kind']==='project') { $roots=$this->many("SELECT * FROM familyhub_records WHERE scope_id=? AND type='project' AND deleted=0",[$id]);if (count($roots)!==1) { $blockers[]=['code'=>'project_scope_requires_single_root']; }
            $records=$this->many('SELECT * FROM familyhub_records WHERE scope_id=? ORDER BY id',[$id]);$fingerprint[]=$records;
            foreach ($records as $r) { if ((int)$r['deleted']) { continue; }$payload=json_decode($r['payload'],true,32,JSON_THROW_ON_ERROR);if ($r['type']==='project' && (int)$r['contract_version']<3) { $blockers[]=['code'=>'project_record_upgrade_required','recordId'=>$r['id']]; }
                if (in_array($r['type'],['task','event'],true) && (count($roots)!==1 || ($payload['projectId']??null)!==$roots[0]['id'])) { $blockers[]=['code'=>'project_scope_unrelated_content','recordId'=>$r['id']]; } } }
        foreach ($access->relatedScopeIds($id) as $sid) {
            $target=$this->one('SELECT * FROM familyhub_scopes WHERE id=?',[$sid]);$members=$access->members($sid);$policy=$this->one('SELECT * FROM familyhub_finance_policy WHERE scope_id=?',[$sid]);$grants=$this->many('SELECT * FROM familyhub_finance_grants WHERE scope_id=? ORDER BY account_id',[$sid]);
            $invitations=$this->many('SELECT * FROM familyhub_invitations WHERE scope_id=? AND accepted_at IS NULL AND revoked_at IS NULL AND expires_at>? ORDER BY id',[$sid,time()]);$fingerprint[]=[$target,$members,$policy,$grants,$invitations];
            foreach ($invitations as $invite) { $revoked[]=$invite['id']; }
            $audience=[];foreach (array_merge($members,$rootMembers) as $m) { if (!isset($audience[$m['accountId']]) || ($audience[$m['accountId']]['role']==='viewer' && $m['role']!=='viewer')) { $audience[$m['accountId']]=$m; } }
            $readers=[];$writers=[];
            foreach ($audience as $account=>$member) {
                $before=$access->visibleScope($sid,$account);$finance=(new NativeFinanceAccess($this->container))->visible($sid,$account,true);
                $bound=$this->one('SELECT u.*,a.account_id FROM users u JOIN familyhub_accounts a ON a.user_id=u.id WHERE a.account_id=?',[$account]);
                $beforePolicy=$before && $bound ? (new NativeFinanceAccess($this->container))->policy($sid,$bound,false,false) : null;
                $beforeWrite=$beforePolicy && $beforePolicy['enabled'] && $beforePolicy['grant']==='write';
                $wire=['accountId'=>$account,'displayName'=>$member['displayName'],'accessSource'=>$sid===$id?'spaceMembership':(in_array($account,array_column($rootMembers,'accountId'),true)?'spaceMembership':'projectMembership')];
                if (!$finance) { $readers[]=$wire; }
                if ($member['role']!=='viewer' && !$beforeWrite) { $writers[]=$wire; }
            }
            $projects[]=['scopeId'=>$sid,'name'=>$target['name'],'financeWasEnabled'=>(bool)($policy['enabled']??false),'additionalReaders'=>$readers,'additionalWriters'=>$writers];
        }
        return ['scopeId'=>$id,'fromVersion'=>(int)$scope['access_policy_version'],'toVersion'=>3,'canApply'=>!$blockers,'blockers'=>$blockers,'projects'=>$projects,'revokedInvitationIds'=>$revoked,'previewHash'=>hash('sha256',$this->canonical($fingerprint))];
    }
}
