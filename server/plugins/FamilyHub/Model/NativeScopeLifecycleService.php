<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** A confirmed, closed deletion graph. Scope identities and record tombstones never disappear. */
class NativeScopeLifecycleService extends NativeDatabase
{
    public function inTransaction($operation,array $params,array $user)
    {
        $this->fields($params,['scopeId'],$operation==='scopes.delete'?['projectId','previewHash','requestId']:['projectId']);
        $sid=$this->uuid($params['scopeId']);$pid=isset($params['projectId'])?$this->uuid($params['projectId']):null;
        $raw=$this->one('SELECT * FROM familyhub_scopes WHERE id=?',[$sid]);
        if (!$raw || ($pid===null && (int)$raw['owner_id']!==(int)$user['id'])) { throw new NativeError('permission_revoked',403); }
        if ($operation==='scopes.delete') {
            $request=$this->uuid($params['requestId']??null);$hash=$this->hashRequest($operation,$params);
            if (($raw['deleted_at']??null)===null) { $this->scope($sid,$user['id'],$pid!==null); }
            $saved=$this->replay($sid,$user['id'],$request,$hash);if ($saved) { return $saved['body']; }
        }
        $scope=$this->scope($sid,$user['id'],false,true);
        if (($pid===null && $scope['role']!=='owner') || ($pid!==null && $scope['role']==='viewer') || ($scope['kind']==='personal' && $pid===null)) { throw new NativeError('permission_revoked',403); }
        if ($pid!==null && ($scope['project_root_id']??null)===$pid) { if ($scope['role']!=='owner') { throw new NativeError('permission_revoked',403); }$pid=null; }
        $graph=$this->graph($scope,$pid);
        if ($pid!==null && $graph['preview']['counts']['finance']>0) { (new NativeFinanceAccess($this->container))->policy($sid,$user,true); }
        if ($operation==='scopes.deletionPreview') { return $graph['preview']; }
        if (!is_string($params['previewHash']??null) || !hash_equals($graph['preview']['previewHash'],$params['previewHash'])) { throw new NativeError('scope_deletion_preview_changed',409); }
        if (!$graph['preview']['canDelete']) { throw new NativeError('scope_deletion_blocked',409,['blockers'=>$graph['preview']['blockers']]); }
        $stamp=gmdate('Y-m-d\TH:i:s\Z');$accounts=[];$deletedScopes=[];$recordTombstones=[];$financeTombstones=[];
        foreach ($graph['scopes'] as $s) {
            $id=$s['id'];$full=$pid===null;
            if ($full) {
                $accounts=array_merge($accounts,$graph['members'][$id]);
                // Include inactive historical members: their offline replicas must receive an explicit deletion.
                $historical=$this->many('SELECT account_id FROM familyhub_members WHERE scope_id=?',[$id]);
                $accounts=array_merge($accounts,array_column($historical,'account_id'));
                foreach (array_unique(array_merge(array_column($historical,'account_id'),$graph['members'][$id])) as $account) {
                    if (!$this->one('SELECT scope_id FROM familyhub_scope_revocations WHERE scope_id=? AND account_id=?',[$id,$account])) { $this->change('INSERT INTO familyhub_scope_revocations VALUES(?,?)',[$id,$account]); }
                }
                $this->change('UPDATE familyhub_scopes SET deleted_at=?,archived=1,access_revision=access_revision+1,sequence=sequence+1 WHERE id=?',[time(),$id]);
                $this->change('UPDATE familyhub_members SET active=0 WHERE scope_id=?',[$id]);
                $this->change("UPDATE familyhub_finance_grants SET access_level='none' WHERE scope_id=?",[$id]);
                $this->change('UPDATE familyhub_invitations SET revoked_at=? WHERE scope_id=? AND revoked_at IS NULL',[time(),$id]);
                $this->change("UPDATE familyhub_invitation_mail SET state='cancelled',token_cipher=NULL,lease_token=NULL WHERE invitation_id IN (SELECT id FROM familyhub_invitations WHERE scope_id=?) AND state<>'accepted'",[$id]);
                $this->change('DELETE FROM familyhub_organization_leaders WHERE scope_id=?',[$id]);
                $deletedScopes[]=$id;
            }
            foreach ([false=>$graph['records'][$id],true=>$graph['finance'][$id]] as $financial=>$rows) {
                $table=$financial?'familyhub_finance_records':'familyhub_records';$policy=$financial?'familyhub_finance_policy':'familyhub_scopes';$key=$financial?'scope_id':'id';
                foreach ($rows as $r) {
                    if ((int)$r['deleted']) { continue; }
                    $this->change('UPDATE '.$policy.' SET sequence=sequence+1 WHERE '.$key.'=?',[$id]);
                    $sequence=(int)$this->one('SELECT sequence FROM '.$policy.' WHERE '.$key.'=?',[$id])['sequence'];
                    $this->change('UPDATE '.$table.' SET deleted=1,payload=NULL,revision=revision+1,sequence=?,updated_at=? WHERE scope_id=? AND id=?',[$sequence,$stamp,$id,$r['id']]);
                    $this->change("UPDATE familyhub_reminders SET state='cancelled',revision=revision+1 WHERE scope_id=? AND target_id=? AND target_type=? AND state='pending'",[$id,$r['id'],$r['type']]);
                    $this->change('DELETE FROM familyhub_push_jobs WHERE inbox_id IN (SELECT id FROM familyhub_inbox WHERE scope_id=? AND target_id=? AND target_type=?)',[$id,$r['id'],$r['type']]);
                    $this->change('DELETE FROM familyhub_deliveries WHERE inbox_id IN (SELECT id FROM familyhub_inbox WHERE scope_id=? AND target_id=? AND target_type=?)',[$id,$r['id'],$r['type']]);
                    $this->change('DELETE FROM familyhub_inbox WHERE scope_id=? AND target_id=? AND target_type=?',[$id,$r['id'],$r['type']]);
                    $this->change("UPDATE familyhub_moderation_reports SET snapshot=NULL,details=NULL,status='redacted',redacted_at=? WHERE scope_id=? AND target_id=? AND target_type=?",[time(),$id,$r['id'],$financial?'finance':'record']);
                    if ($financial) {
                        $this->change('DELETE FROM familyhub_finance_audit WHERE scope_id=? AND record_id=?',[$id,$r['id']]);
                        $this->change('DELETE FROM familyhub_payment_events WHERE scope_id=? AND entry_id=?',[$id,$r['id']]);
                        $financeTombstones[]=['scopeId'=>$id,'id'=>$r['id'],'type'=>$r['type'],'revision'=>(int)$r['revision']+1,'deleted'=>true,'payload'=>null,'sequence'=>$sequence,'updatedAt'=>$stamp];
                    } else {
                        $recordTombstones[]=['scopeId'=>$id,'id'=>$r['id'],'type'=>$r['type'],'revision'=>(int)$r['revision']+1,'deleted'=>true,'payload'=>null,'sequence'=>$sequence,'updatedAt'=>$stamp];
                    }
                }
            }
            foreach ($graph['assets'][$id] as $asset) {
                $path='familyhub/ideas/'.hash('sha256',$id.':'.$asset['board_id']).'/'.$asset['sha256'];
                if (!$this->one('SELECT path_hash FROM familyhub_scope_deletion_files WHERE scope_id=? AND path_hash=?',[$id,hash('sha256',$path)])) { $this->change('INSERT INTO familyhub_scope_deletion_files VALUES(?,?,?)',[$id,hash('sha256',$path),$path]); }
                $this->change('DELETE FROM familyhub_idea_assets WHERE scope_id=? AND board_id=? AND sha256=?',[$id,$asset['board_id'],$asset['sha256']]);
                $this->change('DELETE FROM familyhub_idea_report_assets WHERE scope_id=? AND board_id=? AND sha256=?',[$id,$asset['board_id'],$asset['sha256']]);
            }
            // Prior successful operation responses contain deleted content, so scrub
            // snapshots while retaining their immutable hashes/IDs for stale clients.
            foreach (['familyhub_operations','familyhub_finance_operations'] as $table) {
                if ($full) { $this->change('UPDATE '.$table.' SET response=?,status=409 WHERE scope_id=?',[json_encode(['errorCode'=>'scope_deleted','details'=>(object)[]]),$id]); }
                else { foreach (array_merge($graph['records'][$id],$graph['finance'][$id]) as $r) { $this->change('UPDATE '.$table.' SET response=?,status=409 WHERE scope_id=? AND response LIKE ?',[json_encode(['errorCode'=>'record_deleted','details'=>(object)[]]),$id,'%'.$r['id'].'%']); } }
            }
            if ($full) {
                $this->change("UPDATE familyhub_reminders SET state='cancelled',revision=revision+1 WHERE scope_id=? AND state='pending'",[$id]);
                $this->change("UPDATE familyhub_moderation_reports SET snapshot=NULL,details=NULL,status='redacted',redacted_at=? WHERE scope_id=?",[time(),$id]);
                foreach (['familyhub_payment_events','familyhub_payment_cash','familyhub_payment_projections','familyhub_inbox_preferences'] as $table) { $this->change('DELETE FROM '.$table.' WHERE scope_id=?',[$id]); }
                $this->change('DELETE FROM familyhub_push_jobs WHERE inbox_id IN (SELECT id FROM familyhub_inbox WHERE scope_id=?)',[$id]);
                $this->change('DELETE FROM familyhub_deliveries WHERE inbox_id IN (SELECT id FROM familyhub_inbox WHERE scope_id=?)',[$id]);
                $this->change('DELETE FROM familyhub_inbox WHERE scope_id=?',[$id]);
            }
        }
        (new NativeNotificationWriter($this->container))->visibilityChanged(array_values(array_unique($accounts)));
        $result=['deleted'=>true,'scopeId'=>$sid,'projectId'=>$pid,'deletedScopeIds'=>$deletedScopes,'records'=>$recordTombstones,'financeRecords'=>$financeTombstones,'cleanupPending'=>!empty(array_filter($graph['assets']))];
        $this->remember($sid,$user['id'],$request,$hash,$result);return $result;
    }

    private function graph($scope,$pid)
    {
        $sid=$scope['id'];$members=[];$scopes=[$scope];$blockers=[];$records=[];$money=[];$assets=[];$counts=['spaces'=>0,'projects'=>0,'tasks'=>0,'events'=>0,'ideas'=>0,'photos'=>0,'finance'=>0,'other'=>0];
        if ($pid===null) {
            foreach ((new NativeOrganizationAccess($this->container))->relatedScopeIds($sid) as $id) {
                if ($id===$sid) { continue; }
                $child=$this->one('SELECT * FROM familyhub_scopes WHERE id=?'.$this->lockSuffix(),[$id]);
                if ($child && ($child['deleted_at']??null)===null) { $scopes[]=$child;if ((int)$child['owner_id']!==(int)$scope['owner_id']) { $blockers[]=['code'=>'child_owner_transfer_required','scopeId'=>$id]; } }
            }
        }
        $name=$scope['name'];$snapshot=[];
        foreach ($scopes as $s) {
            $id=$s['id'];$members[$id]=array_column((new NativeOrganizationAccess($this->container))->members($id),'accountId');$all=$this->many('SELECT * FROM familyhub_records WHERE scope_id=? ORDER BY id',[$id]);$finance=$this->many('SELECT * FROM familyhub_finance_records WHERE scope_id=? ORDER BY id',[$id]);$selected=[];$tasks=[];
            if ($pid!==null) {
                $project=array_values(array_filter($all,fn($r)=>$r['id']===$pid && $r['type']==='project' && !(int)$r['deleted']));
                if (!$project) { throw new NativeError('record_deleted',409); }
                $name=json_decode($project[0]['payload'],true,32,JSON_THROW_ON_ERROR)['title'];
                foreach ($all as $r) { $p=json_decode($r['payload']??'null',true,32,JSON_THROW_ON_ERROR);if ($r['id']===$pid || (in_array($r['type'],['task','event','idea'],true) && ($p['projectId']??null)===$pid)) { $selected[]=$r;if ($r['type']==='task') { $tasks[]=$r['id']; } } }
                $finance=array_values(array_filter($finance,function($r)use($pid,$tasks){$p=json_decode($r['payload']??'null',true,32,JSON_THROW_ON_ERROR);return ($p['projectId']??null)===$pid || in_array($p['taskId']??null,$tasks,true);}));
            } else { $selected=$all;$counts['spaces']++; }
            $records[$id]=$selected;$money[$id]=$finance;$ids=array_column($selected,'id');
            $assets[$id]=array_values(array_filter($this->many('SELECT * FROM familyhub_idea_assets WHERE scope_id=? ORDER BY board_id,sha256',[$id]),fn($a)=>$pid===null || in_array($a['board_id'],$ids,true)));
            foreach ($selected as $r) { if ((int)$r['deleted']) { continue; }$key=['project'=>'projects','task'=>'tasks','event'=>'events','idea'=>'ideas'][$r['type']]??'other';$counts[$key]++; }
            $counts['photos']+=count($assets[$id]);$counts['finance']+=count(array_filter($finance,fn($r)=>!(int)$r['deleted']));
            $external=$this->many('SELECT scope_id,event_id FROM familyhub_payment_projections WHERE source_scope_id=? ORDER BY scope_id,event_id',[$id]);
            $closed=array_column($scopes,'id');$financeIds=array_column($finance,'id');
            if ($pid===null) {
                foreach ($this->many('SELECT source_scope_id FROM familyhub_payment_projections WHERE scope_id=?',[$id]) as $incoming) { if (!in_array($incoming['source_scope_id'],$closed,true)) { $blockers[]=['code'=>'cross_scope_payment_dependency']; } }
                foreach ($this->many('SELECT scope_id,data FROM familyhub_payment_events ORDER BY scope_id,event_id') as $payment) {
                    $event=json_decode($payment['data'],true,32,JSON_THROW_ON_ERROR);
                    foreach ($event['reimbursements']??[] as $leg) {
                        $ledgerScope=$leg['organizationAccountScopeId']??$payment['scope_id'];
                        if ((in_array($payment['scope_id'],$closed,true) && !in_array($ledgerScope,$closed,true)) || (!in_array($payment['scope_id'],$closed,true) && in_array($ledgerScope,$closed,true))) { $blockers[]=['code'=>'cross_scope_payment_dependency']; }
                    }
                }
            }

            foreach ($external as $projection) {
                $event=$this->one('SELECT entry_id FROM familyhub_payment_events WHERE scope_id=? AND event_id=?',[$id,$projection['event_id']]);
                if (!in_array($projection['scope_id'],$closed,true) && ($pid===null || ($event && in_array($event['entry_id'],$financeIds,true)))) { $blockers[]=['code'=>'cross_scope_payment_dependency']; }
            }
            $snapshot[]=[$s,$all,$this->many('SELECT * FROM familyhub_finance_records WHERE scope_id=? ORDER BY id',[$id]),$assets[$id],$external];
        }
        $preview=['scopeId'=>$sid,'projectId'=>$pid,'name'=>$name,'scopeNames'=>array_column($scopes,'name'),'counts'=>$counts,'canDelete'=>!$blockers,'blockers'=>$blockers];
        $preview['previewHash']=hash('sha256',$this->canonical([$snapshot,$preview]));return ['preview'=>$preview,'scopes'=>$scopes,'records'=>$records,'finance'=>$money,'assets'=>$assets,'members'=>$members];
    }

    /** Retryable private cleanup after SQL commit. No payload/path is returned to callers. */
    public function finishFiles()
    {
        foreach ($this->many('SELECT * FROM familyhub_scope_deletion_files ORDER BY scope_id,path_hash LIMIT 500') as $file) {
            if (!preg_match('/^familyhub\/ideas\/[a-f0-9]{64}\/[a-f0-9]{64}$/D',$file['path'])) { continue; }
            $path=DATA_DIR.'/'.$file['path'];
            if ((is_file($path)||is_link($path)) && !@unlink($path)) { continue; }
            if (file_exists($path)||is_link($path)) { continue; }
            $this->change('DELETE FROM familyhub_scope_deletion_files WHERE scope_id=? AND path_hash=?',[$file['scope_id'],$file['path_hash']]);
        }
    }
}
