<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** Fail closed for unresolved shared contributions; never deletes another member's scope. */
class NativeAccountDeletionService extends NativeDatabase
{
    public static function available()
    {
        return defined('FAMILYHUB_ACCOUNT_MODE') && FAMILYHUB_ACCOUNT_MODE === 'self_hosted';
    }

    public function execute($operation, array $params)
    {
        if (!self::available()) { throw new NativeError('feature_disabled',503); }
        $this->rate([['account-delete-ip:'.$this->ip, 120, 60]]);
        if (in_array($operation,['account.deletion.status','account.deletion.cancelPending'],true)) {
            $this->fields($params, ['operationId', 'receiptToken']);
            $id = $this->uuid($params['operationId']); $hash = $this->receiptHash($params['receiptToken']);
            if ($operation==='account.deletion.cancelPending') {
                $candidate=$this->one('SELECT token_hash FROM familyhub_deletion_receipts WHERE operation_id=?',[$id]);
                if (!$candidate) {
                    try { $cancelActor=$this->actor(false); }
                    catch (NativeError $error) {
                        // Original confirm may have committed between the lookup
                        // and auth read. Existing receipts still need no bearer.
                        $candidate=$this->one('SELECT token_hash FROM familyhub_deletion_receipts WHERE operation_id=?',[$id]);
                        if (!$candidate) { throw $error; }
                    }
                    if (!$candidate) { $this->rate([['account-delete-cancel:'.$cancelActor['user']['account_id'],10,900]]); }
                }
                $row=$this->transaction(function() use ($id,$hash) {
                    $row=$this->one('SELECT token_hash,complete,cancelled FROM familyhub_deletion_receipts WHERE operation_id=?',[$id]);
                    if ($row && !hash_equals($row['token_hash'],$hash)) { throw new NativeError('idempotency_mismatch',409); }
                    if (!$row) {
                        // Only an active local account may create durable marker
                        // rows. Revalidate after the same mutex wait as confirm.
                        $this->actor();
                        $this->change('INSERT INTO familyhub_deletion_receipts(operation_id,token_hash,deleted_at,complete,cancelled) VALUES(?,?,?,1,1)',[$id,$hash,time()]);
                        $row=['token_hash'=>$hash,'complete'=>1,'cancelled'=>1];
                    }
                    return $row;
                },true);
            } else { $row=$this->one('SELECT token_hash,complete,cancelled FROM familyhub_deletion_receipts WHERE operation_id=?',[$id]); }
            if (!$row || !hash_equals($row['token_hash'],$hash)) { return ['deleted'=>false,'cleanupPending'=>false,'cancelled'=>false,'serverId'=>$this->serverId()]; }
            if ((int)$row['cancelled']===1) { return ['deleted'=>false,'cleanupPending'=>false,'cancelled'=>true,'serverId'=>$this->serverId()]; }
            return $this->finishFiles($id);
        }
        if (!in_array($operation, ['account.deletion.preview','account.deletion.confirm'], true)) { throw new NativeError('unsupported_operation',404); }
        $actor = $this->actor(false);
        $this->rate([[$operation.':'.$actor['user']['account_id'], $operation==='account.deletion.preview' ? 60:10, $operation==='account.deletion.preview' ? 60:900]]);
        $result = $this->transaction(function () use ($operation, $params) {
            $user = $this->actor()['user'];
            // Successor and last-admin eligibility cannot change while deleting.
            // Native account deletions share global lock; ordinary requests lock
            // one user before their scope, so these locks precede scope locks too.
            $this->many('SELECT id FROM users ORDER BY id'.$this->lockSuffix());
            $this->many('SELECT id FROM tasks WHERE creator_id=? OR project_id IN (SELECT id FROM projects WHERE owner_id=? AND is_private=1) ORDER BY id'.$this->lockSuffix(),[$user['id'],$user['id']]);
            // Lock scopes in stable order. Every native write locks its actor first,
            // then scope; after waiting the plan is recomputed from current state.
            $scopes = $this->many('SELECT * FROM familyhub_scopes ORDER BY CASE WHEN kind=\'organization\' THEN 0 ELSE 1 END,id'.$this->lockSuffix());
            $graph = (new NativeDeletionPlan($this->container))->build($user,$scopes);
            $plan = $graph['wire'];
            if ($operation === 'account.deletion.preview') {
                $this->fields($params, [], ['policyVersion']);
                if (!in_array($params['policyVersion']??1,[1,2,3],true)) { throw new NativeError('validation_error'); }
                if (($params['policyVersion']??1)<$plan['policyVersion']) { throw new NativeError('client_upgrade_required',409); }
                return $plan;
            }
            $this->fields($params, ['operationId','receiptToken','previewHash','password','confirmation'], ['otp','ownershipTransfers','resolutions','ownedScopeDeletions','policyVersion']);
            if (($params['policyVersion']??1)<$plan['policyVersion']) { throw new NativeError('client_upgrade_required',409); }
            $id = $this->uuid($params['operationId']); $hash = $this->receiptHash($params['receiptToken']);
            if ($params['confirmation'] !== 'DELETE') { throw new NativeError('validation_error'); }
            $receipt=$this->one('SELECT token_hash,cancelled FROM familyhub_deletion_receipts WHERE operation_id=?',[$id]);
            if ($receipt) { throw new NativeError(hash_equals($receipt['token_hash'],$hash) && (int)$receipt['cancelled']===1 ? 'deletion_cancelled':'idempotency_mismatch',409); }
            $deleteScopes=$this->resolve($plan,$params,$user);
            if (!is_string($params['previewHash']) || !hash_equals($plan['previewHash'],$params['previewHash'])) { throw new NativeError('deletion_preview_stale',409); }
            $error = (new NativeAuthService($this->container))->stepUp($user,$params['password'],$params['otp'] ?? null);
            if ($error) { return $error; } // Commit failed counters/TOTP replay state.
            foreach ($params['ownershipTransfers']??[] as $transfer) {
                $next=$this->one('SELECT user_id FROM familyhub_accounts WHERE account_id=?',[$transfer['successorAccountId']]);
                $this->change("UPDATE familyhub_members SET role='member' WHERE scope_id=? AND user_id=?",[$transfer['scopeId'],$user['id']]);
                $this->change("UPDATE familyhub_members SET role='owner' WHERE scope_id=? AND user_id=?",[$transfer['scopeId'],$next['user_id']]);
                $this->change('UPDATE familyhub_scopes SET owner_id=?,sequence=sequence+1 WHERE id=?',[$next['user_id'],$transfer['scopeId']]);
            }
            $this->change('INSERT INTO familyhub_deletion_receipts(operation_id,token_hash,deleted_at) VALUES(?,?,?)',[$id,$hash,time()]);
            $this->applyShared($graph,$user,$deleteScopes);
            $this->purge($user,$scopes,$deleteScopes);
            $this->purgeLegacy($user,$graph['privateProjects'],$id);
            return ['operationId'=>$id];
        }, true);
        if ($result instanceof NativeError) { throw $result; }
        return isset($result['operationId']) ? $this->finishFiles($result['operationId']) : $result;
    }

    private function receiptHash($value)
    {
        if (!is_string($value) || !preg_match('/^[a-f0-9]{64}$/D',$value)) { throw new NativeError('validation_error'); }
        return hash('sha256',$value);
    }

    private function countRows($table,$where,array $params)
    {
        return (int)$this->one('SELECT COUNT(*) AS n FROM '.$table.' WHERE '.$where,$params)['n'];
    }

    private function resolve(array $plan,array $params,array $user)
    {
        $deletions=$params['ownedScopeDeletions']??[];$transfers=$params['ownershipTransfers']??[];$resolutions=$params['resolutions']??[];
        foreach ([$deletions,$transfers,$resolutions] as $list) { if (!is_array($list) || !array_is_list($list) || count($list)>500) { throw new NativeError('validation_error'); } }
        $resolved=[];
        foreach ($plan['ownedScopes'] as $scope) {
            if (in_array($scope['id'],$deletions,true) && $scope['canDeleteScope']) { $resolved[]=$scope['id']; continue; }
            $choice=array_values(array_filter($transfers,fn($t)=>is_array($t)&&($t['scopeId']??null)===$scope['id']));
            if (count($choice)!==1 || !in_array($choice[0]['successorAccountId']??null,array_column($scope['eligibleSuccessors'],'accountId'),true)) { throw new NativeError('deletion_blocked',409,['blockers'=>$plan['blockers']]); }
        }
        foreach ($plan['resolutions'] as $required) {
            if ($required['action']==='detachOrganization') {
                if (!in_array($required['scopeId'],$resolved,true) || ($required['childScopeId']!==null && in_array($required['childScopeId'],$resolved,true))) { continue; }
            } elseif (in_array($required['scopeId'],$resolved,true)) { continue; }
            if (!array_filter($resolutions,fn($r)=>is_array($r)&&($r['scopeId']??null)===$required['scopeId']&&($r['recordId']??null)===$required['recordId']&&($r['action']??null)===$required['action'])) { throw new NativeError('deletion_blocked',409,['blockers'=>$plan['blockers']]); }
        }
        foreach ($plan['blockers'] as $b) { if (!in_array($b['code'],['shared_scope_owner','shared_structure_resolution'],true)) { throw new NativeError('deletion_blocked',409,['blockers'=>$plan['blockers']]); } }
        if (array_diff($deletions,$resolved)) { throw new NativeError('validation_error'); }
        foreach ($transfers as $t) {
            $this->fields($t,['scopeId','successorAccountId']);
            if (!in_array($t['scopeId'],array_column($plan['ownedScopes'],'id'),true) || in_array($t['scopeId'],$resolved,true)) { throw new NativeError('validation_error'); }
        }
        foreach ($resolutions as $r) {
            $this->fields($r,['scopeId','recordId','action']);
            if (!array_filter($plan['resolutions'],fn($p)=>$p['scopeId']===$r['scopeId'] && $p['recordId']===$r['recordId'] && $r['action']===$p['action'])) { throw new NativeError('validation_error'); }
        }
        // Actual transfer waits until after preview hash and step-up validation.
        return $resolved;
    }

    private function redact($value,$account)
    {
        if (is_array($value)) { foreach ($value as $key=>&$child) { $child=$this->redact($child,$account); } }
        elseif ($value===$account) { return null; }
        return $value;
    }

    private function applyShared(array $graph,array $user,array $deleteScopes)
    {
        $account=$user['account_id'];$changedScopes=[];$affectedRecipients=[];
        foreach ($graph['organizationLinks']??[] as $link) {
            if (in_array($link['organizationId'],$deleteScopes,true) && !in_array($link['childScopeId'],$deleteScopes,true)) {
                $access=new NativeOrganizationAccess($this->container);
                $readers=array_column($this->many('SELECT account_id FROM familyhub_members WHERE scope_id=? AND active=1',[$link['organizationId']]),'account_id');
                $formerlyVisible=array_values(array_filter($readers,fn($aid)=>$access->visibleScope($link['childScopeId'],$aid)));
                $this->change('UPDATE familyhub_scopes SET organization_id=NULL,sequence=sequence+1 WHERE id=? AND organization_id=?',[$link['childScopeId'],$link['organizationId']]);
                foreach ($formerlyVisible as $aid) { $access->reconcileRevocations([$link['childScopeId']],$aid); }
                (new NativeNotificationWriter($this->container))->visibilityChanged($formerlyVisible);
            }
        }
        foreach ($graph['mutations'] as $m) {
            if (in_array($m['scopeId'],$deleteScopes,true)) { continue; }
            $finance=$m['table']==='familyhub_finance_records';$policyTable=$finance ? 'familyhub_finance_policy':'familyhub_scopes';
            $this->change('UPDATE '.$policyTable.' SET sequence=sequence+1 WHERE '.($finance?'scope_id':'id').'=?',[$m['scopeId']]);
            $sequence=$this->one('SELECT sequence FROM '.$policyTable.' WHERE '.($finance?'scope_id':'id').'=?',[$m['scopeId']])['sequence'];
            $this->change('UPDATE '.$m['table'].' SET payload=?,deleted=?,created_by=?,updated_by=?,revision=?,sequence=?,updated_at=? WHERE scope_id=? AND id=?',[$m['payload']===null ? null:json_encode($m['payload'],JSON_THROW_ON_ERROR),$m['deleted'],$m['created'],$m['updated'],$m['revision'],$sequence,gmdate('Y-m-d\TH:i:s\Z'),$m['scopeId'],$m['id']]);
            if (!$finance && $m['preservedStructure'] && $m['payload']!==null && isset($m['payload']['title'])) {
                $this->change('UPDATE familyhub_scopes SET name=? WHERE id=? AND project_root_id=?',[$m['payload']['title'],$m['scopeId'],$m['id']]);
            }
            if ($finance && !$m['deleted']) {
                $linked=$this->one('SELECT * FROM familyhub_payment_events WHERE scope_id=? AND entry_id=?',[$m['scopeId'],$m['id']]);
                if($linked) {
                    $event=json_decode($linked['data'],true,32,JSON_THROW_ON_ERROR);$event['sourceRevision']=$m['revision'];$event['revision']++;
                    $this->change('UPDATE familyhub_payment_events SET revision=?,data=? WHERE scope_id=? AND event_id=?',[$event['revision'],json_encode($event,JSON_THROW_ON_ERROR),$m['scopeId'],$event['eventId']]);
                    foreach($this->many('SELECT * FROM familyhub_payment_projections WHERE source_scope_id=? AND event_id=?',[$m['scopeId'],$event['eventId']]) as $projection) {
                        $receipt=json_decode($projection['data'],true,32,JSON_THROW_ON_ERROR);$receipt['sourceRevision']=$m['revision'];$receipt['revision']=$event['revision'];$receipt['paymentRevision']=$event['revision'];
                        $this->change('UPDATE familyhub_payment_projections SET data=? WHERE scope_id=? AND event_id=?',[json_encode($receipt,JSON_THROW_ON_ERROR),$projection['scope_id'],$event['eventId']]);
                    }
                }
            }
            $changedScopes[$m['scopeId']]=true;
            if ($finance && ($m['deleted'] || $m['preservedStructure'])) { $this->change('DELETE FROM familyhub_finance_audit WHERE scope_id=? AND record_id=?',[$m['scopeId'],$m['id']]); }
            // Response caches can embed old payloads inside success/conflict replies
            // belonging to another actor. Remove all copies for changed records.
            foreach (['familyhub_operations','familyhub_finance_operations'] as $table) { $this->change('UPDATE '.$table.' SET response=?,status=409 WHERE scope_id=? AND response LIKE ?',[json_encode(['errorCode'=>'operation_redacted','details'=>(object)[]]),$m['scopeId'],'%'.$m['id'].'%']); }
            if ($m['deleted']) {
                $affectedRecipients=array_merge($affectedRecipients,array_column($this->many('SELECT DISTINCT recipient_account_id FROM familyhub_inbox WHERE scope_id=? AND target_id=?',[$m['scopeId'],$m['id']]),'recipient_account_id'));
                $this->change('DELETE FROM familyhub_push_jobs WHERE inbox_id IN (SELECT id FROM familyhub_inbox WHERE scope_id=? AND target_id=?)',[$m['scopeId'],$m['id']]);
                $this->change('DELETE FROM familyhub_deliveries WHERE inbox_id IN (SELECT id FROM familyhub_inbox WHERE scope_id=? AND target_id=?)',[$m['scopeId'],$m['id']]);
                $this->change('DELETE FROM familyhub_inbox WHERE scope_id=? AND target_id=?',[$m['scopeId'],$m['id']]);
                $this->change('DELETE FROM familyhub_reminders WHERE scope_id=? AND target_id=?',[$m['scopeId'],$m['id']]);
            }
        }
        $this->change('DELETE FROM familyhub_finance_audit WHERE actor_account_id=?',[$account]);
        foreach ($this->many('SELECT * FROM familyhub_finance_audit WHERE before_json LIKE ? OR after_json LIKE ?',['%'.$account.'%','%'.$account.'%']) as $audit) {
            $before=$audit['before_json']===null ? null:$this->redact(json_decode($audit['before_json'],true,32,JSON_THROW_ON_ERROR),$account);
            $after=$this->redact(json_decode($audit['after_json'],true,32,JSON_THROW_ON_ERROR),$account);
            $this->change('UPDATE familyhub_finance_audit SET before_json=?,after_json=? WHERE scope_id=? AND record_id=? AND revision=?',[$before===null?null:json_encode($before,JSON_THROW_ON_ERROR),json_encode($after,JSON_THROW_ON_ERROR),$audit['scope_id'],$audit['record_id'],$audit['revision']]);
        }
        foreach (['familyhub_operations','familyhub_finance_operations'] as $table) {
            foreach ($this->many('SELECT * FROM '.$table.' WHERE response LIKE ?',['%'.$account.'%']) as $row) {
                $response=$this->redact(json_decode($row['response'],true,32,JSON_THROW_ON_ERROR),$account);
                $this->change('UPDATE '.$table.' SET response=? WHERE scope_id=? AND '.($table==='familyhub_operations'?'user_id':'account_id').'=? AND id=?',[json_encode($response,JSON_THROW_ON_ERROR),$row['scope_id'],$row[$table==='familyhub_operations'?'user_id':'account_id'],$row['id']]);
            }
        }
        $accounts=$this->many('SELECT DISTINCT recipient_account_id FROM familyhub_inbox WHERE actor_account_id=?',[$account]);
        $this->change('DELETE FROM familyhub_push_jobs WHERE inbox_id IN (SELECT id FROM familyhub_inbox WHERE actor_account_id=?)',[$account]);
        $this->change('DELETE FROM familyhub_deliveries WHERE inbox_id IN (SELECT id FROM familyhub_inbox WHERE actor_account_id=?)',[$account]);
        $this->change('DELETE FROM familyhub_inbox WHERE actor_account_id=?',[$account]);
        (new NativeNotificationWriter($this->container))->visibilityChanged(array_values(array_diff(array_unique(array_merge($affectedRecipients,array_column($accounts,'recipient_account_id'))),[$account])));
    }

    private function purgeLegacy(array $user,array $privateProjects,$operation)
    {
        $uid=(int)$user['id'];$files=[];
        if (!empty($user['avatar_path'])) { $files[]=$user['avatar_path']; }
        $tasks=$this->many('SELECT id FROM tasks WHERE creator_id=?',[$uid]);$taskIds=array_column($tasks,'id');
        foreach (['task_has_files','project_has_files'] as $table) {
            foreach ($this->many('SELECT path FROM '.$table.' WHERE user_id=?',[$uid]) as $r) { $files[]=$r['path']; }
            $this->change('DELETE FROM '.$table.' WHERE user_id=?',[$uid]);
        }
        foreach ($privateProjects as $pid) {
            foreach ($this->many('SELECT path FROM project_has_files WHERE project_id=?',[$pid]) as $r) { $files[]=$r['path']; }
            $taskIds=array_merge($taskIds,array_column($this->many('SELECT id FROM tasks WHERE project_id=?',[$pid]),'id'));
        }
        foreach (array_unique($taskIds) as $tid) {
            foreach ($this->many('SELECT path FROM task_has_files WHERE task_id=?',[$tid]) as $r) { $files[]=$r['path']; }
            $this->change('DELETE FROM tasks WHERE id=?',[$tid]);
        }
        foreach ($privateProjects as $pid) { $this->change('DELETE FROM projects WHERE id=?',[$pid]); }
        $this->change('DELETE FROM comments WHERE user_id=?',[$uid]);
        $this->change('DELETE FROM subtask_time_tracking WHERE user_id=?',[$uid]);
        $this->change('UPDATE projects SET owner_id=0 WHERE owner_id=?',[$uid]);
        $emails=array_unique(array_filter(array_merge([$user['email']],array_column($this->many('SELECT email FROM familyhub_account_tokens WHERE account_id=?',[$user['account_id']]),'email'))));
        foreach ($emails as $email) { $this->change('DELETE FROM invites WHERE email=?',[$email]); }
        foreach (['user_has_metadata','task_has_metadata','project_has_metadata','settings'] as $table) { $this->change('UPDATE '.$table.' SET changed_by=0 WHERE changed_by=?',[$uid]); }
        foreach ($this->many('SELECT id,data FROM project_activities') as $row) {
            $data=json_decode($row['data']??'null',true);
            if (is_array($data) && $this->legacyReferences($data,$uid,$user['username'])) { $this->change('DELETE FROM project_activities WHERE id=?',[$row['id']]); }
        }
        foreach (array_unique(array_filter($files)) as $path) {
            if (strlen($path)>1024 || str_contains($path,'..') || str_starts_with($path,'/') || str_contains($path,"\0")) { throw new NativeError('unsafe_file_path',409); }
            $this->change('INSERT INTO familyhub_deletion_files(operation_id,path_hash,path) VALUES(?,?,?)',[$operation,hash('sha256',$path),$path]);
        }
        if ($this->change('DELETE FROM users WHERE id=?',[$uid])!==1) { throw new NativeError('device_revoked',401); }
    }

    private function legacyReferences(array $data,$uid,$username)
    {
        foreach ($data as $key=>$value) {
            if (in_array($key,['owner_id','user_id','creator_id'],true) && (int)$value===$uid) { return true; }
            if (is_array($value)) {
                if (in_array($key,['user','owner','creator','assignee'],true) && (int)($value['id']??0)===$uid) { return true; }
                if ($this->legacyReferences($value,$uid,$username)) { return true; }
            } elseif ($value===$username) { return true; }
        }
        return false;
    }

    public function finishFiles($id)
    {
        foreach ($this->many('SELECT path FROM familyhub_deletion_files WHERE operation_id=?',[$id]) as $row) {
            try {
                if (!method_exists($this->objectStorage,'getSanitizedFilePath')) { continue; }
                $path=$this->objectStorage->getSanitizedFilePath($row['path']);
                if (file_exists($path) || is_link($path)) {
                    if (!@$this->objectStorage->remove($row['path'])) { continue; }
                }
                if (file_exists($path) || is_link($path)) { continue; }
                $this->change('DELETE FROM familyhub_deletion_files WHERE operation_id=? AND path=?',[$id,$row['path']]);
            }
            catch (\Throwable $error) { /* Persistent queue; no private path/error in logs. */ }
        }
        $pending=$this->countRows('familyhub_deletion_files','operation_id=?',[$id])>0;
        if (!$pending) { $this->change('UPDATE familyhub_deletion_receipts SET complete=1 WHERE operation_id=?',[$id]); }
        return ['deleted'=>!$pending,'cleanupPending'=>$pending,'cancelled'=>false,'serverId'=>$this->serverId()];
    }

    private function purge(array $user,array $scopes,array $deleteScopes)
    {
        $id=(int)$user['id'];$account=$user['account_id'];
        $financeScopes=array_column($this->many('SELECT scope_id FROM familyhub_finance_grants WHERE account_id=?',[$account]),'scope_id');
        $this->change('DELETE FROM familyhub_push_jobs WHERE device_id IN (SELECT id FROM familyhub_devices WHERE user_id=?) OR inbox_id IN (SELECT id FROM familyhub_inbox WHERE recipient_account_id=?)',[$id,$account]);
        $this->change('DELETE FROM familyhub_deliveries WHERE inbox_id IN (SELECT id FROM familyhub_inbox WHERE recipient_account_id=?)',[$account]);
        $this->change('DELETE FROM familyhub_inbox WHERE recipient_account_id=?',[$account]);
        foreach (['familyhub_inbox_state','familyhub_inbox_preferences','familyhub_reminders','familyhub_finance_grants','familyhub_finance_operations','familyhub_organization_leaders','familyhub_scope_revocations'] as $table) { $this->change('DELETE FROM '.$table.' WHERE account_id=?',[$account]); }
        foreach ($this->many('SELECT * FROM familyhub_payment_projections WHERE owner_account_id=?',[$account]) as $projection) {
            $receipt=json_decode($projection['data'],true,32,JSON_THROW_ON_ERROR);
            if(isset($receipt['privateAccountId'])) {
                $this->change('DELETE FROM familyhub_payment_projections WHERE scope_id=? AND event_id=?',[$projection['scope_id'],$projection['event_id']]);
            }
        }
        foreach ($deleteScopes as $sourceScope) {
            foreach($this->many('SELECT * FROM familyhub_payment_projections WHERE source_scope_id=?',[$sourceScope]) as $projection) {
                $receipt=json_decode($projection['data'],true,32,JSON_THROW_ON_ERROR);$receipt['state']='sourceRemoved';
                $this->change('UPDATE familyhub_payment_projections SET data=? WHERE scope_id=? AND event_id=?',[json_encode($receipt,JSON_THROW_ON_ERROR),$projection['scope_id'],$projection['event_id']]);
            }
        }
        $this->change('DELETE FROM familyhub_operations WHERE user_id=?',[$id]);
        $this->change('DELETE FROM familyhub_invitations WHERE creator_id=? OR accepted_by=? OR recipient_username=? OR recipient_account_id=?',[$id,$id,$user['username'],$user['account_id']]);
        $this->change('UPDATE familyhub_scopes SET access_revision=access_revision+1 WHERE kind=\'organization\' AND id IN (SELECT scope_id FROM familyhub_members WHERE user_id=? AND active=1)',[$id]);
        $this->change('DELETE FROM familyhub_members WHERE user_id=?',[$id]);
        foreach ($scopes as $s) {
            if (($s['kind']==='personal' && (int)$s['owner_id']===$id) || in_array($s['id'],$deleteScopes,true)) {
                $sid=$s['id'];
                $this->change('DELETE FROM familyhub_push_jobs WHERE inbox_id IN (SELECT id FROM familyhub_inbox WHERE scope_id=?)',[$sid]);
                $this->change('DELETE FROM familyhub_deliveries WHERE inbox_id IN (SELECT id FROM familyhub_inbox WHERE scope_id=?)',[$sid]);
                foreach (['familyhub_payment_events','familyhub_payment_projections','familyhub_payment_cash','familyhub_scope_revocations','familyhub_organization_leaders','familyhub_inbox','familyhub_inbox_preferences','familyhub_reminders','familyhub_finance_grants','familyhub_finance_operations','familyhub_finance_audit','familyhub_finance_records','familyhub_finance_policy','familyhub_operations','familyhub_records','familyhub_invitations','familyhub_members','familyhub_personal_scopes'] as $table) { $this->change('DELETE FROM '.$table.' WHERE scope_id=?',[$sid]); }
                $this->change('DELETE FROM familyhub_scopes WHERE id=?',[$sid]);
            } elseif (in_array($s['id'],$financeScopes,true)) {
                $this->change('UPDATE familyhub_finance_policy SET revision=revision+1 WHERE scope_id=?',[$s['id']]);
            }
        }
        $this->change('DELETE FROM familyhub_push_registrations WHERE account_id=?',[$account]);
        $this->change('DELETE FROM familyhub_devices WHERE user_id=?',[$id]);
        $this->change('DELETE FROM familyhub_totp_state WHERE user_id=?',[$id]);
        // SessionHandler uses php_serialize; no object construction on decode.
        foreach ($this->many('SELECT id,data FROM sessions') as $session) {
            $data=@unserialize($session['data'],['allowed_classes'=>false]);
            if (is_array($data) && (int)($data['user']['id'] ?? 0)===$id) { $this->change('DELETE FROM sessions WHERE id=?',[$session['id']]); }
        }
        $this->change('UPDATE tasks SET owner_id=0 WHERE owner_id=?',[$id]);
        $this->change('UPDATE subtasks SET user_id=0 WHERE user_id=?',[$id]);
        // Profile/metadata/remember-me/login histories/account token/mail cascade.
        // Core remove() is deliberately not used: it commits nested transactions
        // and removes avatar before SQL, and retains anonymized comment bodies.
        // Core user deletion runs after staging its file paths in purgeLegacy().
    }
}
