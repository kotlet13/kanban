<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** Extracts a closed project graph. Shared household dependencies never follow silently. */
class NativeProjectSharingService extends NativeDatabase
{
    public function inTransaction($operation, $params, $user)
    {
        $this->fields($params,['scopeId','projectId'],$operation==='scopes.projectSharingApply'?['previewHash','requestId']:[]);
        $sid=$this->uuid($params['scopeId']);$pid=$this->uuid($params['projectId']);$scope=$this->scope($sid,$user['id'],true,true);
        if ($scope['kind']!=='household' || (int)$scope['access_policy_version']!==3) { throw new NativeError('access_migration_required',409); }
        if ($operation==='scopes.projectSharingApply') {
            $request=$this->uuid($params['requestId']??null);$hash=$this->hashRequest($operation,$params);$replay=$this->replay($sid,$user['id'],$request,$hash);
            if ($replay) { return $replay['body']; }
        }
        $graph=$this->graph($scope,$pid);$preview=$graph['preview'];
        if ($operation==='scopes.projectSharingPreview') { return $preview; }
        if (!is_string($params['previewHash']??null) || !hash_equals($preview['previewHash'],$params['previewHash'])) { throw new NativeError('project_sharing_preview_changed',409); }
        if (!$preview['canApply']) { throw new NativeError('project_sharing_blocked',409,['blockers'=>$preview['blockers']]); }
        $project=$graph['records'][$pid];$payload=json_decode($project['payload'],true,32,JSON_THROW_ON_ERROR);
        $this->change('INSERT INTO familyhub_scopes(id,kind,name,owner_id,sequence,created_at,required_record_contract,project_root_id,parent_scope_id,access_policy_version) VALUES(?,\'project\',?,?,0,?,3,?,?,3)',[$pid,$payload['title'],$scope['owner_id'],time(),$pid,$sid]);
        $owner=$this->one('SELECT * FROM familyhub_members WHERE scope_id=? AND role=\'owner\' AND active=1',[$sid]);
        if (!$owner) { throw new NativeError('permission_revoked',403); }
        $this->change('INSERT INTO familyhub_members(scope_id,user_id,account_id,role,active) VALUES(?,?,?,\'owner\',1)',[$pid,$owner['user_id'],$owner['account_id']]);
        $this->change('INSERT INTO familyhub_finance_policy(scope_id,enabled,revision,sequence,required_contract_version) VALUES(?,1,1,0,?)',[$pid,$graph['financeVersion']]);
        $this->change('INSERT INTO familyhub_finance_grants VALUES(?,?,\'write\')',[$pid,$owner['account_id']]);
        foreach ([false=>$graph['records'],true=>$graph['finance']] as $finance=>$records) {
            $table=$finance?'familyhub_finance_records':'familyhub_records';$policy=$finance?'familyhub_finance_policy':'familyhub_scopes';$key=$finance?'scope_id':'id';$sequence=0;
            foreach ($records as $id=>$row) {
                $sequence++;$copy=$row;$copy['scope_id']=$pid;$copy['sequence']=$sequence;
                $columns=array_keys($copy);$this->change('INSERT INTO '.$table.'('.implode(',',$columns).') VALUES('.implode(',',array_fill(0,count($columns),'?')).')',array_values($copy));
                $this->change('UPDATE '.$policy.' SET sequence=sequence+1 WHERE '.$key.'=?',[$sid]);
                $sourceSequence=$this->one('SELECT sequence FROM '.$policy.' WHERE '.$key.'=?',[$sid])['sequence'];
                $this->change('UPDATE '.$table.' SET deleted=1,payload=NULL,revision=revision+1,sequence=?,updated_at=? WHERE scope_id=? AND id=?',[$sourceSequence,gmdate('Y-m-d\TH:i:s\Z'),$sid,$id]);
                $this->change('INSERT INTO familyhub_record_relocations VALUES(?,?,?,?)',[$sid,$id,(int)$finance,$pid]);
                if ($finance) { $this->change('UPDATE familyhub_finance_audit SET scope_id=? WHERE scope_id=? AND record_id=?',[$pid,$sid,$id]); }
                $this->change('UPDATE familyhub_inbox SET scope_id=? WHERE scope_id=? AND target_id=? AND target_type=?',[$pid,$sid,$id,$row['type']]);
            }
            $this->change('UPDATE '.$policy.' SET sequence=? WHERE '.$key.'=?',[$sequence,$pid]);
        }
        foreach ($preview['movedReminderIds'] as $id) { $this->change('UPDATE familyhub_reminders SET scope_id=? WHERE scope_id=? AND id=?',[$pid,$sid,$id]); }
        $affected=array_column((new NativeOrganizationAccess($this->container))->members($sid),'accountId');(new NativeNotificationWriter($this->container))->visibilityChanged($affected);
        $result=['scope'=>$this->scopeWire($this->scope($pid,$user['id'])),'projectRoot'=>(new NativeRecordPolicy($this->container))->wire($this->one('SELECT * FROM familyhub_records WHERE scope_id=? AND id=?',[$pid,$pid]),3),'movedRecordIds'=>$preview['movedRecordIds'],'movedFinanceRecordIds'=>$preview['movedFinanceRecordIds'],'movedReminderIds'=>$preview['movedReminderIds']];
        $this->remember($sid,$user['id'],$request,$hash,$result);return $result;
    }

    private function graph($scope, $pid)
    {
        $sid=$scope['id'];$all=$this->many('SELECT * FROM familyhub_records WHERE scope_id=? ORDER BY id',[$sid]);$money=$this->many('SELECT * FROM familyhub_finance_records WHERE scope_id=? ORDER BY id',[$sid]);$selected=[];$fin=[];$blockers=[];$personIds=[];$taskIds=[];
        $project=array_values(array_filter($all,fn($r)=>$r['id']===$pid && $r['type']==='project' && !(int)$r['deleted']));
        if (!$project) { throw new NativeError('parent_missing'); }
        if ($this->one('SELECT id FROM familyhub_scopes WHERE id=?',[$pid])) { $blockers[]=['code'=>'project_scope_id_collision']; }
        if ((int)$project[0]['contract_version']<3) { $blockers[]=['code'=>'project_record_upgrade_required','recordId'=>$pid]; }
        foreach ($all as $row) {
            $p=json_decode($row['payload']??'null',true,32,JSON_THROW_ON_ERROR);
            if ($row['id']===$pid || (in_array($row['type'],['task','event'],true) && ($p['projectId']??null)===$pid)) {
                $selected[$row['id']]=$row;
                if ($row['type']==='task') { $taskIds[]=$row['id']; }
                foreach (array_merge([$p['assigneePersonId']??null],$p['subjectPersonIds']??[]) as $person) { if ($person!==null) { $personIds[$person]=true; } }
            }
        }
        $accounts=[];$rules=[];
        foreach ($money as $row) {
            $p=json_decode($row['payload']??'null',true,32,JSON_THROW_ON_ERROR);
            if (in_array($p['taskId']??null,$taskIds,true)) {
                $fin[$row['id']]=$row;
                foreach (['accountId','ledgerAccountId'] as $field) { if (($p[$field]??null)!==null) { $accounts[$p[$field]]=true; } }
                if (($p['recurrenceRuleId']??null)!==null) { $rules[$p['recurrenceRuleId']]=true; }
                foreach (['payerPersonId','recipientPersonId','createdByPersonId'] as $field) { if (($p[$field]??null)!==null) { $personIds[$p[$field]]=true; } }
            }
        }
        foreach ($money as $row) {
            $p=json_decode($row['payload']??'null',true,32,JSON_THROW_ON_ERROR);
            if ($row['type']==='financeRecurrenceRule' && isset($rules[$row['id']])) { $fin[$row['id']]=$row;if (($p['ledgerAccountId']??null)!==null) { $accounts[$p['ledgerAccountId']]=true; } }
        }
        foreach ($money as $row) {
            $p=json_decode($row['payload']??'null',true,32,JSON_THROW_ON_ERROR);
            if ($row['type']==='financeAccount' && isset($accounts[$row['id']])) { $fin[$row['id']]=$row;continue; }
            if (isset($fin[$row['id']]) || (int)$row['deleted']) { continue; }
            if ($row['type']==='financeTransfer' && isset($accounts[$p['fromAccountId']??'']) && isset($accounts[$p['toAccountId']??''])) { $fin[$row['id']]=$row;continue; }
            if (isset($rules[$p['recurrenceRuleId']??''])) { $blockers[]=['code'=>'project_recurrence_shared','recordId'=>$row['id']]; }
            $references=array_filter(array_intersect_key($p??[],array_flip(['accountId','ledgerAccountId','fromAccountId','toAccountId'])),fn($v)=>$v!==null && isset($accounts[$v]));
            if ($references) { $blockers[]=['code'=>$row['type']==='financeTransfer'?'project_transfer_cross_scope':'project_finance_account_shared','recordId'=>$row['id']]; }
        }
        foreach ($all as $row) { if ($row['type']==='householdPerson' && isset($personIds[$row['id']])) { $selected[$row['id']]=$row; } }
        foreach (array_merge($all,$money) as $row) {
            if (isset($selected[$row['id']]) || isset($fin[$row['id']]) || (int)$row['deleted']) { continue; }
            $p=json_decode($row['payload']??'null',true,32,JSON_THROW_ON_ERROR);
            foreach (array_merge([$p['assigneePersonId']??null,$p['payerPersonId']??null,$p['recipientPersonId']??null,$p['createdByPersonId']??null],$p['subjectPersonIds']??[]) as $person) { if ($person && isset($personIds[$person])) { $blockers[]=['code'=>'project_person_shared','recordId'=>$row['id']];break; } }
        }
        foreach (array_keys($fin) as $id) { if ($this->one('SELECT event_id FROM familyhub_payment_events WHERE scope_id=? AND entry_id=?',[$sid,$id])) { $blockers[]=['code'=>'project_linked_payment_dependency','recordId'=>$id]; } }
        foreach (array_keys($accounts) as $id) { if ($this->one("SELECT movement_id FROM familyhub_payment_cash WHERE scope_id=? AND json_extract(data,'$.accountId')=?",[$sid,$id]) || $this->one("SELECT event_id FROM familyhub_payment_projections WHERE scope_id=? AND json_extract(data,'$.privateAccountId')=?",[$sid,$id])) { $blockers[]=['code'=>'project_linked_payment_dependency','recordId'=>$id]; } }
        $reminders=$this->many('SELECT * FROM familyhub_reminders WHERE scope_id=? ORDER BY id',[$sid]);$movedReminders=array_values(array_filter($reminders,fn($r)=>(isset($selected[$r['target_id']]) && $selected[$r['target_id']]['type']===$r['target_type']) || (isset($fin[$r['target_id']]) && $fin[$r['target_id']]['type']===$r['target_type'])));
        $version=1;foreach ($fin as $r) { $version=max($version,(int)$r['contract_version']); }
        $wire=['scopeId'=>$sid,'projectId'=>$pid,'projectName'=>json_decode($project[0]['payload'],true)['title'],'canApply'=>!$blockers,'blockers'=>$blockers,'movedRecordIds'=>array_keys($selected),'movedFinanceRecordIds'=>array_keys($fin),'movedReminderIds'=>array_column($movedReminders,'id')];
        $wire['financeAccounts']=array_values(array_map(function($r) { $p=json_decode($r['payload']??'null',true,32,JSON_THROW_ON_ERROR);return ['id'=>$r['id'],'name'=>$p['name'],'currency'=>$p['currency'],'openingBalanceMinor'=>$p['openingBalanceMinor'],'openingBalanceAt'=>$p['openingBalanceAt']??null]; },array_filter($fin,fn($r)=>$r['type']==='financeAccount' && !(int)$r['deleted'])));
        $wire['householdPeople']=array_values(array_map(function($r) { $p=json_decode($r['payload']??'null',true,32,JSON_THROW_ON_ERROR);return ['id'=>$r['id'],'name'=>$p['name'],'notes'=>$p['notes']]; },array_filter($selected,fn($r)=>$r['type']==='householdPerson' && !(int)$r['deleted'])));
        $wire['previewHash']=hash('sha256',$this->canonical([$scope,$all,$money,$reminders,$wire]));
        return ['preview'=>$wire,'records'=>$selected,'finance'=>$fin,'financeVersion'=>$version];
    }
}
