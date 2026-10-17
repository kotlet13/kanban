<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** One canonical project entry, with an explicit account reference to its parent. */
class NativeOrganizationFinancePolicy extends NativeDatabase
{
    public function validate($type,$payload,$scopeId,$current)
    {
        if (!is_array($payload) || array_is_list($payload)) { throw new NativeError('validation_error'); }
        $scope=$this->one('SELECT * FROM familyhub_scopes WHERE id=?',[$scopeId]);
        $parentId=$scope['parent_scope_id']??$scope['organization_id']??null;
        if ($type==='financeAccount' && !$current && $scope['kind']==='project' && $parentId!==null) { throw new NativeError('finance_account_parent_required',409); }
        $accountScope=$scopeId;
        if ($type==='financeEntry') {
            $accountScope=$payload['accountScopeId']??$scopeId;
            if ($accountScope!==$scopeId) {
                $this->uuid($accountScope);$this->uuid($payload['accountId']??null);
                if ($scope['kind']!=='project' || $accountScope!==$parentId || (int)$scope['access_policy_version']!==3) { throw new NativeError('parent_missing'); }
                // scope() already takes the parent lock before its child lock.
                $parent=$this->one('SELECT * FROM familyhub_scopes WHERE id=?',[$accountScope]);
                $policy=$this->one('SELECT enabled FROM familyhub_finance_policy WHERE scope_id=?',[$accountScope]);
                if (!$parent || !in_array($parent['kind'],['organization','household'],true) || (int)$parent['access_policy_version']!==3 || ($parent['deleted_at']??null)!==null || (int)$parent['archived'] || !$policy || !(int)$policy['enabled']) { throw new NativeError('parent_missing'); }
                if (($payload['recurrenceRuleId']??null)!==null) { throw new NativeError('validation_error'); }
            } elseif (($payload['accountScopeId']??null)!==null) {
                // Same-scope references have one canonical representation.
                throw new NativeError('validation_error');
            }
            $projectId=$payload['projectId']??null;
            if ($projectId!==null) {
                $this->uuid($projectId);
                // Native project scopes use their scope/root identity, never an inline tag.
                if ($scope['kind']==='project' || !$this->one("SELECT id FROM familyhub_records WHERE scope_id=? AND id=? AND type='project' AND deleted=0",[$scopeId,$projectId])) { throw new NativeError('parent_missing'); }
                if (($payload['taskId']??null)!==null) {
                    $task=$this->one("SELECT payload FROM familyhub_records WHERE scope_id=? AND id=? AND type='task' AND deleted=0",[$scopeId,$payload['taskId']]);
                    if (!$task || (json_decode($task['payload'],true,32,JSON_THROW_ON_ERROR)['projectId']??null)!==$projectId) { throw new NativeError('parent_missing'); }
                }
            }
            unset($payload['accountScopeId'],$payload['projectId']);
        }
        (new NativeFinancePlanningPolicy($this->container))->validate($type,$payload,$scopeId,$current,$accountScope);
    }

    public function accountChoices($params,$scopeId,$user,$acl)
    {
        $this->fields($params,['scopeId']);
        $scope=$this->scope($scopeId,$user['id']);
        $parentId=$scope['parent_scope_id']??$scope['organization_id']??null;
        $result=['accounts'=>[],'accessRevision'=>$acl['revision'],'accountScopeId'=>null,'accountSequence'=>0];
        if ($scope['kind']!=='project' || !$parentId || (int)$scope['effective_access_policy_version']!==3) { return $result; }
        $parent=$this->one('SELECT * FROM familyhub_scopes WHERE id=?',[$parentId]);
        $policy=$this->one('SELECT * FROM familyhub_finance_policy WHERE scope_id=?',[$parentId]);
        // The project grant permits these names/currencies only. Never call parent pull
        // or return opening balances, account owners, totals, siblings or parent name.
        if (!$parent || !in_array($parent['kind'],['household','organization'],true) || (int)$parent['access_policy_version']!==3 || ($parent['deleted_at']??null)!==null || (int)$parent['archived'] || !$policy || !(int)$policy['enabled']) { return $result; }
        $result['accountScopeId']=$parentId;$result['accountSequence']=(int)$policy['sequence'];
        foreach ($this->many("SELECT id,payload FROM familyhub_finance_records WHERE scope_id=? AND type='financeAccount' AND deleted=0 ORDER BY id",[$parentId]) as $row) {
            $p=json_decode($row['payload'],true,32,JSON_THROW_ON_ERROR);
            $result['accounts'][]=['scopeId'=>$parentId,'id'=>$row['id'],'name'=>$p['name'],'currency'=>$p['currency'],'archived'=>(bool)($p['archived']??false)];
        }
        if (strlen(json_encode($result,JSON_UNESCAPED_UNICODE|JSON_THROW_ON_ERROR))>524288) { throw new NativeError('finance_accounts_too_large',413); }
        return $result;
    }

    /** Parent scope lock is held by every child finance operation. */
    public function touchParents($scopeId,$payload,$current)
    {
        $before=$current && $current['payload']!==null?json_decode($current['payload'],true,32,JSON_THROW_ON_ERROR):[];
        foreach (array_unique(array_filter([$before['accountScopeId']??null,$payload['accountScopeId']??null])) as $parentId) {
            if ($parentId===$scopeId) { continue; }
            // Required v3 also fences OLD parent clients against an incomplete balance.
            $this->change('UPDATE familyhub_finance_policy SET required_contract_version=CASE WHEN required_contract_version<3 THEN 3 ELSE required_contract_version END,revision=revision+1,sequence=sequence+1 WHERE scope_id=?',[$parentId]);
        }
    }

    /** Never disclose an inaccessible contributor's identity, only incompleteness. */
    public function contributionVisibility($scopeId,$user)
    {
        $scope=$this->one('SELECT kind FROM familyhub_scopes WHERE id=?',[$scopeId]);
        $result=['organizationFinanceComplete'=>true,'organizationFinanceScopeIds'=>[],'organizationFinanceSequences'=>(object)[]];
        if (!in_array($scope['kind'],['organization','household'],true)) { return $result; }
        $sources=$this->many("SELECT DISTINCT scope_id FROM familyhub_finance_records WHERE type='financeEntry' AND deleted=0 AND json_extract(payload,'$.accountScopeId')=? ORDER BY scope_id",[$scopeId]);
        foreach ($sources as $source) {
            $child=$this->one('SELECT * FROM familyhub_scopes WHERE id=?',[$source['scope_id']]);
            $parent=$child['parent_scope_id']??$child['organization_id']??null;
            if (!$child || $child['kind']!=='project' || $parent!==$scopeId || !(new NativeFinanceAccess($this->container))->visible($child['id'],$user['account_id'],true)) { $result['organizationFinanceComplete']=false;continue; }
            $result['organizationFinanceScopeIds'][]=$child['id'];
            $policy=$this->one('SELECT sequence FROM familyhub_finance_policy WHERE scope_id=?',[$child['id']]);
            $result['organizationFinanceSequences']->{$child['id']}=(int)$policy['sequence'];
        }
        return $result;
    }

    public function noExternalChildren($scopeId,$accountId)
    {
        if ($this->one("SELECT id FROM familyhub_finance_records WHERE scope_id<>? AND type='financeEntry' AND deleted=0 AND json_extract(payload,'$.accountScopeId')=? AND json_extract(payload,'$.accountId')=? LIMIT 1",[$scopeId,$scopeId,$accountId])) { throw new NativeError('live_children'); }
    }
}
