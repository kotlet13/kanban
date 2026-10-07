<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** Computes a deletion graph without writing. Returned mutations remain internal. */
class NativeDeletionPlan extends NativeDatabase
{
    const SYSTEM_ACTOR = '00000000-0000-4000-8000-000000000000';

    public function build(array $user, array $scopes)
    {
        $id=(int)$user['id'];$account=$user['account_id'];$mutations=[];$resolutions=[];$owned=[];$shared=[];$blocks=[];$versions=[];
        $impact=['personalScopes'=>0,'personalRecords'=>0,'personalFinanceRecords'=>0,'devices'=>$this->n('familyhub_devices','user_id=?',[$id]),'sharedMemberships'=>0,'kanboardAssignedTasks'=>$this->n('tasks','owner_id=?',[$id]),'kanboardAssignedSubtasks'=>$this->n('subtasks','user_id=?',[$id]),'sharedRecordsDeleted'=>0,'sharedRecordsUpdated'=>0,'sharedFinanceRecordsDeleted'=>0,'sharedFinanceRecordsUpdated'=>0,'kanboardTasksDeleted'=>$this->n('tasks','creator_id=?',[$id]),'kanboardCommentsDeleted'=>$this->n('comments','user_id=?',[$id]),'kanboardFilesDeleted'=>$this->n('task_has_files','user_id=?',[$id])+$this->n('project_has_files','user_id=?',[$id])];
        if ($user['role']==='app-admin' && $this->n('users',"role='app-admin' AND is_active=1",[])<2) { $blocks[]=['code'=>'last_admin','count'=>1]; }
        // Shared legacy projects and tasks lack durable author IDs/revision contracts.
        // Their owned private-project deletion is allowed only without other members.
        $private=$this->many('SELECT p.id FROM projects p WHERE p.is_private=1 AND p.owner_id=?',[$id]);
        foreach ($private as $p) {
            if ($this->n('project_has_users','project_id=? AND user_id<>?',[$p['id'],$id]) || $this->n('tasks','project_id=? AND creator_id<>?',[$p['id'],$id]) || $this->n('comments','task_id IN (SELECT id FROM tasks WHERE project_id=?) AND user_id<>?',[$p['id'],$id]) || $this->n('project_has_files','project_id=? AND user_id<>?',[$p['id'],$id]) || $this->n('task_has_files','task_id IN (SELECT id FROM tasks WHERE project_id=?) AND user_id<>?',[$p['id'],$id]) || $this->n('subtasks','task_id IN (SELECT id FROM tasks WHERE project_id=?)',[$p['id']]) || $this->n('subtask_time_tracking','subtask_id IN (SELECT id FROM subtasks WHERE task_id IN (SELECT id FROM tasks WHERE project_id=?)) AND user_id<>?',[$p['id'],$id])) { $blocks[]=['code'=>'legacy_shared_private_project','count'=>1]; }
        }
        $unsafeTasks=$this->many('SELECT id FROM tasks WHERE creator_id=?',[$id]);
        foreach ($unsafeTasks as $task) {
            if ($this->n('comments','task_id=? AND user_id<>?',[$task['id'],$id]) || $this->n('task_has_files','task_id=? AND user_id<>?',[$task['id'],$id]) || $this->n('subtasks','task_id=?',[$task['id']])) { $blocks[]=['code'=>'legacy_task_has_other_contributions','count'=>1]; }
        }
        foreach ($scopes as $s) {
            $sid=$s['id'];$members=$this->many('SELECT m.*,u.name,u.username,u.is_active FROM familyhub_members m LEFT JOIN users u ON u.id=m.user_id WHERE scope_id=? ORDER BY user_id',[$sid]);
            $generic=$this->many('SELECT * FROM familyhub_records WHERE scope_id=? ORDER BY id',[$sid]);
            $finance=$this->many('SELECT * FROM familyhub_finance_records WHERE scope_id=? ORDER BY id',[$sid]);
            $related=(int)$s['owner_id']===$id || count(array_filter($members,fn($m)=>(int)$m['user_id']===$id));
            foreach (array_merge($generic,$finance) as $r) { if ($r['created_by']===$account || $r['updated_by']===$account || str_contains($r['payload']??'',$account)) { $related=true;break; } }
            if (!$related) { continue; }
            $versions[]=[$s,$members,$generic,$finance,$this->one('SELECT * FROM familyhub_finance_policy WHERE scope_id=?',[$sid])];
            if ($s['kind']==='personal' && (int)$s['owner_id']===$id) {
                $impact['personalScopes']++;$impact['personalRecords']+=count($generic);$impact['personalFinanceRecords']+=count($finance);
                if (count(array_filter($members,fn($m)=>(int)$m['user_id']!==$id))) { $blocks[]=['code'=>'personal_scope_has_other_member','count'=>1,'scopeId'=>$sid]; }
                continue;
            }
            $member=array_values(array_filter($members,fn($m)=>(int)$m['user_id']===$id));
            if ($member) { $impact['sharedMemberships']++;if ((new NativeFinanceAccess($this->container))->visible($sid,$account)) { $shared[]=['id'=>$sid,'kind'=>$s['kind'],'name'=>$s['name'],'role'=>$member[0]['role']]; } }
            if ((int)$s['owner_id']===$id) {
                $eligible=array_values(array_filter($members,fn($m)=>(int)$m['user_id']!==$id && (int)$m['active']===1 && (int)$m['is_active']===1 && $this->one('SELECT user_id FROM familyhub_accounts WHERE account_id=? AND user_id=?',[$m['account_id'],$m['user_id']])));
                $foreign=count(array_filter($members,fn($m)=>(int)$m['user_id']!==$id)) || count(array_filter(array_merge($generic,$finance),fn($r)=>!(int)$r['deleted'] && $r['payload']!==null && !in_array($r['created_by'],[$account,self::SYSTEM_ACTOR],true)));
                $owned[]=['id'=>$sid,'kind'=>$s['kind'],'name'=>$s['name'],'canDeleteScope'=>!$foreign,'eligibleSuccessors'=>array_map(fn($m)=>['accountId'=>$m['account_id'],'displayName'=>$m['name'] ?: $m['username']],$eligible)];
                $blocks[]=['code'=>count($eligible) || !$foreign ?'shared_scope_owner':'shared_scope_without_successor','count'=>1,'scopeId'=>$sid];
            }
            $ownGeneric=array_column(array_filter($generic,fn($r)=>$r['created_by']===$account),'type','id');
            $ownFinance=array_column(array_filter($finance,fn($r)=>$r['created_by']===$account),'type','id');
            foreach ([['familyhub_records',$generic,$ownGeneric,false],['familyhub_finance_records',$finance,$ownFinance,true]] as [$table,$records,$own,$isFinance]) {
                foreach ($records as $r) {
                    $payload=$r['payload']===null ? null:json_decode($r['payload'],true,32,JSON_THROW_ON_ERROR);$before=$payload;$deleted=(int)$r['deleted'];$created=$r['created_by'];$updated=$r['updated_by'];$ownRecord=isset($own[$r['id']]);$structural=false;
                    if ($ownRecord && !$deleted) {
                        if ($r['type']==='shoppingList') {
                            $structural=(bool)array_filter($generic,fn($c)=>$c['type']==='shoppingItem' && !(int)$c['deleted'] && $c['created_by']!==$account && (json_decode($c['payload'],true)['listId']??null)===$r['id']);
                            if ($structural) { $payload['title']='Shared shopping list'; }
                        }
                        if ($r['type']==='financeAccount') {
                            $structural=(bool)array_filter($finance,function($c) use ($account,$r) { $p=json_decode($c['payload']??'null',true); return !(int)$c['deleted'] && $c['created_by']!==$account && in_array($r['id'],[$p['accountId']??null,$p['fromAccountId']??null,$p['toAccountId']??null],true); });
                            if ($structural) { $payload['name']='Shared financial account';$payload['ownerAccountId']=null; }
                        }
                        if ($structural) {
                            $canRead=(new NativeFinanceAccess($this->container))->visible($sid,$account,$isFinance);
                            // Opaque resolution ID is meaningful only for this
                            // actor/preview; no financial UUID leaks after revocation.
                            $opaque=hash_hmac('sha256',$sid.':'.$r['id'],$this->fingerprint($user));
                            $token=substr($opaque,0,8).'-'.substr($opaque,8,4).'-4'.substr($opaque,13,3).'-a'.substr($opaque,17,3).'-'.substr($opaque,20,12);
                            $resolution=['scopeId'=>$canRead ? $sid:$token,'recordId'=>$token,'type'=>$r['type'],'action'=>'preserveStructure','name'=>$canRead ? ($before['title']??$before['name']):null];
                            if ($isFinance && $canRead) { $resolution['currency']=$before['currency'];$resolution['openingBalanceMinor']=$before['openingBalanceMinor']; }
                            $resolutions[]=$resolution;
                            $blocks[]=['code'=>'shared_structure_resolution','count'=>1,'scopeId'=>$canRead ? $sid:$token];
                        } else { $deleted=1;$payload=null; }
                    }
                    if ($payload!==null) {
                        if (isset($payload['projectId']) && ($ownGeneric[$payload['projectId']]??null)==='project') { $payload['projectId']=null; }
                        if (isset($payload['assigneeAccountIds'])) { $payload['assigneeAccountIds']=array_values(array_filter($payload['assigneeAccountIds'],fn($a)=>$a!==$account)); }
                        foreach (['ownerAccountId','payerAccountId','recipientAccountId'] as $key) { if (($payload[$key]??null)===$account) { $payload[$key]=null; } }
                    }
                    if ($created===$account) { $created=$isFinance || $structural ? self::SYSTEM_ACTOR:null; }
                    if ($updated===$account || $payload!==$before || $deleted!==(int)$r['deleted']) { $updated=$isFinance ? self::SYSTEM_ACTOR:null; }
                    if ($payload!==$before || $deleted!==(int)$r['deleted'] || $created!==$r['created_by'] || $updated!==$r['updated_by']) {
                        $mutations[]=['table'=>$table,'scopeId'=>$sid,'id'=>$r['id'],'payload'=>$payload,'deleted'=>$deleted,'created'=>$created,'updated'=>$updated,'revision'=>(int)$r['revision']+1,'ownRecord'=>$ownRecord,'preservedStructure'=>$structural];
                        if ((new NativeFinanceAccess($this->container))->visible($sid,$account,$isFinance)) { $impact[$isFinance ? ($deleted?'sharedFinanceRecordsDeleted':'sharedFinanceRecordsUpdated'):($deleted?'sharedRecordsDeleted':'sharedRecordsUpdated')]++; }
                    }
                }
            }
        }
        $plan=['serverId'=>$this->serverId(),'accountId'=>$account,'policyVersion'=>1,'canDelete'=>!$blocks,'blockers'=>$blocks,'impact'=>$impact,'sharedScopes'=>$shared,'ownedScopes'=>$owned,'resolutions'=>$resolutions];
        $plan['previewHash']=hash('sha256',$this->canonical([$plan,$versions,$this->fingerprint($user)]));
        return ['wire'=>$plan,'mutations'=>$mutations,'privateProjects'=>array_column($private,'id')];
    }

    private function n($table,$where,$params) { return (int)$this->one('SELECT COUNT(*) n FROM '.$table.' WHERE '.$where,$params)['n']; }
}
