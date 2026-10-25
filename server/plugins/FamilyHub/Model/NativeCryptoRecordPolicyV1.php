<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** Admission policy over signed commitments. Honest readers also bind every
 * commitment to decrypted fields: the host cannot inspect opaque ciphertext. */
class NativeCryptoRecordPolicyV1 extends NativeDatabase
{
    protected $cryptoAccess=true;
    /** Derived/control records retain their existing source/role guards. They
     * never receive the content viewer exception used for assignees/checkboxes. */
    public function business($type)
    {
        return in_array($type,['project','task','event','shoppingList','shoppingItem','householdPerson','garden','idea',
            'financeAccount','financeEntry','financeTransfer','personalFinanceEntry','personalFinanceAccount','financeRecurrenceRule','table','attachment'],true);
    }
    /** The one derived content leg needed by an authorized task edit. Neither
     * a claimed hash nor the internal record type alone grants write access. */
    public function companion($record,$entries)
    {
        $tag=$record['metadata']['recordPolicyCompanion']??null;
        if($tag===null)return false;
        if($record['type']!=='taskDerivationIntent'||$record['contentContract']!==6||$record['deleted']||!$this->active($record['scopeId']))throw new NativeError('crypto_record_policy_companion',409);
        foreach($entries as $entry){
            $task=$entry['record'];
            if($task['id']!==$tag['taskId']||$task['type']!=='task'||$task['domain']!=='content'||$task['contentContract']!==7||!isset($task['metadata']['recordPolicy'])||
                $entry['recordProofHash']!==$tag['taskProofHash']||$task['expectedRevision']+1!==$tag['taskRevision'])continue;
            foreach(['scopeId','accountId','deviceId','batchId','operationId'] as $field){if($task[$field]!==$record[$field])throw new NativeError('crypto_record_policy_companion',409);}
            $canonical=NativeCryptoReservedRecordV2::derive($task['serverId'],$task['scopeId'],'taskDerivation:'.$task['metadata']['identity']['canonicalId']);
            if($record['metadata']['identity']['canonicalId']!==$canonical)throw new NativeError('crypto_record_policy_companion',409);
            return true;
        }
        throw new NativeError('crypto_record_policy_companion',409);
    }
    public static function available($pdo)
    {
        try{$q=$pdo->query('SELECT policy_version FROM familyhub_crypto_record_policy_state_v1 WHERE 1=0');$q->closeCursor();return true;}
        catch(\PDOException $e){return false;}
    }
    public function active($sid)
    {
        return $this->one('SELECT baseline_id,policy_version FROM familyhub_crypto_record_policy_state_v1 WHERE scope_id=?',[$sid]);
    }
    private function digest($value)
    {
        if(!is_string($value)||!preg_match('/^[a-f0-9]{64}$/D',$value))throw new NativeError('crypto_record_policy_invalid',409);
    }
    public function validate($policy)
    {
        if(!is_array($policy))throw new NativeError('crypto_record_policy_invalid',409);
        $this->fields($policy,['version','createdByAccountId','operation','fieldCommitments']);
        if($policy['version']!==1||!in_array($policy['operation'],['create','edit','delete','shoppingCheck','restore'],true))throw new NativeError('crypto_record_policy_invalid',409);
        if($policy['createdByAccountId']!==null)$this->uuid($policy['createdByAccountId']);
        if(!is_array($policy['fieldCommitments']))throw new NativeError('crypto_record_policy_invalid',409);
        $this->fields($policy['fieldCommitments'],['content','assignment','checked']);
        foreach($policy['fieldCommitments'] as $value)$this->digest($value);
    }
    public function validateRestore($tag)
    {
        if(!is_array($tag))throw new NativeError('crypto_record_restore_invalid',409);
        $this->fields($tag,['version','tombstoneProofHash','previousLiveProofHash']);
        if($tag['version']!==1)throw new NativeError('crypto_record_restore_invalid',409);
        $this->digest($tag['tombstoneProofHash']);$this->digest($tag['previousLiveProofHash']);
    }

    /** Accepted opaque history binds the nearest live ancestor. Readers also
     * verify its decrypted payload and preserve the original per-record key. */
    private function restoreAncestor($record,$old,$tag)
    {
        $this->validateRestore($tag);
        if($tag['tombstoneProofHash']!==$record['previousRecordHash']||(int)$old['revision']!==$record['expectedRevision'])throw new NativeError('crypto_record_restore_predecessor',409);
        $hash=$record['previousRecordHash'];$revision=$record['expectedRevision'];
        for($count=0;$count<64&&$revision>0;$count++,$revision--){
            $row=$this->one('SELECT record_proof_hash,record_proof FROM familyhub_crypto_record_history WHERE scope_id=? AND id=? AND domain=? AND revision=?',[$record['scopeId'],$record['id'],$record['domain'],$revision]);
            if(!$row||$row['record_proof_hash']!==$hash)throw new NativeError('crypto_record_restore_history_pending',409);
            $proof=json_decode($row['record_proof'],true,34,JSON_THROW_ON_ERROR);
            if(NativeCryptoV2Codec::hash((object)$proof)!==$hash)throw new NativeError('crypto_record_restore_history_pending',409);
            [$ancestor]=NativeCryptoCodec::decode($proof);
            foreach(['scopeId','id','type','domain'] as $field){if(($ancestor[$field]??null)!==$record[$field])throw new NativeError('crypto_record_restore_predecessor',409);}
            if(($ancestor['expectedRevision']??null)!==$revision-1||!is_bool($ancestor['deleted']??null))throw new NativeError('crypto_record_restore_predecessor',409);
            if(!$ancestor['deleted']){
                if($count===0||$hash!==$tag['previousLiveProofHash'])throw new NativeError('crypto_record_restore_predecessor',409);
                return;
            }
            $hash=$ancestor['previousRecordHash'];
        }
        throw new NativeError('crypto_record_restore_history_pending',409);
    }

    protected function owner($p,$actor)
    {
        // A policy2 parent owner can be projected as a child viewer. Exact
        // signed parent ownership below is the authority, not broad canEdit.
        $scope=$this->scope($this->uuid($p['scopeId']),$actor['user']['id']);
        if((int)($scope['archived']??0)===1)throw new NativeError('scope_archived',403);
        $scopes=new NativeCryptoScopeV2($this->container,$this->bearer,$this->ip);
        $head=$scopes->current($scope['id']);
        if(!$head||$head['head_hash']!==$p['membershipHeadHash']||!is_int($p['accessRevision'])||$p['accessRevision']!==(int)$scope['effective_access_revision'])throw new NativeError('crypto_record_policy_baseline_changed',409);
        $scopes->assertCurrentMembership($scope,$head);
        if(!$this->isOwner($scope,$actor,$head))throw new NativeError('crypto_record_policy_owner_required',403);
        return [$scope,$head,$scopes];
    }
    public function isOwner($scope,$actor,$head=null)
    {
        if($scope['role']==='owner')return true;
        $parent=$scope['parent_scope_id']??$scope['organization_id']??null;
        if($parent===null||$scope['kind']!=='project')return false;
        $access=new NativeOrganizationAccess($this->container);
        $parentScope=$access->visibleScope($parent,$actor['user']['account_id']);
        $member=$access->directMember($parent,$actor['user']['account_id']);
        if(!$parentScope||!$member||$member['role']!=='owner'||!in_array((int)$parentScope['access_policy_version'],[2,3],true))return false;
        $scopes=new NativeCryptoScopeV2($this->container,$this->bearer,$this->ip);$head=$head??$scopes->current($scope['id']);$parentHead=$scopes->current($parent);
        if(!$head||!$parentHead||NativeCryptoCodec::canonical($scopes->body($head)['accessBasis'])!==NativeCryptoCodec::canonical($scopes->accessBasis($scope)))return false;
        $scopes->assertCurrentMembership($parentScope,$parentHead);
        foreach($scopes->body($parentHead)['members'] as $participant){if($participant['accountId']===$actor['user']['account_id'])return $participant['role']==='owner';}
        return false;
    }
    private function baseline($sid,$id)
    {
        $row=$this->one('SELECT * FROM familyhub_crypto_record_policy_baselines_v1 WHERE scope_id=? AND baseline_id=?',[$sid,$id]);
        if(!$row)throw new NativeError('crypto_record_policy_baseline_missing',409);
        return $row;
    }
    private function unchanged($baseline,$scopes,$p)
    {
        if($baseline['membership_head_hash']!==$p['membershipHeadHash']||(int)$baseline['access_revision']!==$p['accessRevision']||
            (int)$baseline['content_sequence']!==$scopes->domainSequence($p['scopeId'],'content')||
            (int)$baseline['finance_sequence']!==$scopes->domainSequence($p['scopeId'],'finance'))throw new NativeError('crypto_record_policy_baseline_changed',409);
    }
    public function write($operation,$p,$actor,$proof)
    {
        $common=['scopeId','membershipHeadHash','accessRevision','baselineId'];
        $action=substr($operation,strlen('crypto2.scope.recordPolicy.'));
        $this->fields($p,array_merge($common,match($action){
            'prepare'=>['policyVersion','expectedContentSequence','expectedFinanceSequence'],
            'stage'=>['records'], 'activate'=>['policyVersion','baselineCount','baselineRoot'],
            default=>throw new NativeError('unsupported_operation',404),
        }));
        $this->uuid($p['baselineId']);$this->digest($p['membershipHeadHash']);
        [$scope,$head,$scopes]=$this->owner($p,$actor);$sid=$scope['id'];
        $active=$this->active($sid);
        if($active&&$active['baseline_id']!==$p['baselineId'])throw new NativeError('crypto_record_policy_already_active',409);
        if($action==='prepare'){
            if($p['policyVersion']!==1||!is_int($p['expectedContentSequence'])||!is_int($p['expectedFinanceSequence'])||
                $p['expectedContentSequence']!==$scopes->domainSequence($sid,'content')||$p['expectedFinanceSequence']!==$scopes->domainSequence($sid,'finance'))throw new NativeError('crypto_record_policy_baseline_changed',409);
            $old=$this->one('SELECT * FROM familyhub_crypto_record_policy_baselines_v1 WHERE scope_id=? AND baseline_id=?',[$sid,$p['baselineId']]);
            if($old){
                if($old['membership_head_hash']!==$p['membershipHeadHash']||(int)$old['access_revision']!==$p['accessRevision']||
                    (int)$old['content_sequence']!==$p['expectedContentSequence']||(int)$old['finance_sequence']!==$p['expectedFinanceSequence'])throw new NativeError('crypto_record_policy_baseline_immutable',409);
            }else{
                // Stale attempts remain as exact evidence, but cannot exhaust
                // a lifetime upgrade budget after the scope has moved on.
                $count=$this->one('SELECT COUNT(*) AS n FROM familyhub_crypto_record_policy_baselines_v1 WHERE scope_id=? AND membership_head_hash=? AND content_sequence=? AND finance_sequence=? AND activation_authorization IS NULL',[$sid,$p['membershipHeadHash'],$p['expectedContentSequence'],$p['expectedFinanceSequence']]);
                if((int)$count['n']>=32)throw new NativeError('crypto_record_policy_baselines_full',409);
                $this->change('INSERT INTO familyhub_crypto_record_policy_baselines_v1(scope_id,baseline_id,membership_head_hash,access_revision,content_sequence,finance_sequence,account_id,device_id,prepare_authorization) VALUES(?,?,?,?,?,?,?,?,?)',[$sid,$p['baselineId'],$p['membershipHeadHash'],$p['accessRevision'],$p['expectedContentSequence'],$p['expectedFinanceSequence'],$actor['user']['account_id'],$actor['device']['id'],json_encode($proof,JSON_THROW_ON_ERROR)]);
            }
            return ['version'=>1,'scopeId'=>$sid,'baselineId'=>$p['baselineId'],'prepared'=>true];
        }
        $baseline=$this->baseline($sid,$p['baselineId']);$this->unchanged($baseline,$scopes,$p);
        if($baseline['account_id']!==$actor['user']['account_id'])throw new NativeError('crypto_record_policy_owner_required',403);
        if($action==='stage'){
            if(!is_array($p['records'])||!array_is_list($p['records'])||count($p['records'])<1||count($p['records'])>32)throw new NativeError('validation_error');
            $domain=null;
            foreach($p['records'] as $entry){
                $this->fields($entry,['id','domain','type','recordProofHash','createdByAccountId','fieldCommitments','policyEnvelopeBase64']);
                NativeCryptoRecordAddressV2::wireId($entry['id']);$this->digest($entry['recordProofHash']);
                if($entry['domain']!==NativeCryptoRecordAddressV2::domain($entry['type']))throw new NativeError('crypto_record_policy_invalid',409);
                if($domain!==null&&$domain!==$entry['domain'])throw new NativeError('crypto_record_policy_mixed_domains',409);
                $domain=$entry['domain'];
                $this->validate(['version'=>1,'createdByAccountId'=>$entry['createdByAccountId'],'operation'=>'edit','fieldCommitments'=>$entry['fieldCommitments']]);
                if(strlen(NativeCryptoCodec::base64($entry['policyEnvelopeBase64'],2048))<48)throw new NativeError('crypto_record_policy_invalid',409);
                $current=$this->one('SELECT r.type,r.revision,h.record_proof_hash AS proof_hash FROM familyhub_crypto_records r LEFT JOIN familyhub_crypto_record_history h ON h.scope_id=r.scope_id AND h.id=r.id AND h.revision=r.revision WHERE r.scope_id=? AND r.id=?',[$sid,$entry['id']]);
                if(!$current||$current['type']!==$entry['type']||$current['proof_hash']!==$entry['recordProofHash'])throw new NativeError('crypto_record_policy_baseline_changed',409);
                $bytes=NativeCryptoCodec::canonical((object)$entry);
                $old=$this->one('SELECT entry FROM familyhub_crypto_record_policy_entries_v1 WHERE scope_id=? AND baseline_id=? AND id=?',[$sid,$p['baselineId'],$entry['id']]);
                if($old){if($old['entry']!==$bytes)throw new NativeError('crypto_record_policy_baseline_immutable',409);}
                else $this->change('INSERT INTO familyhub_crypto_record_policy_entries_v1 VALUES(?,?,?,?,?,?)',[$sid,$p['baselineId'],$entry['id'],$entry['recordProofHash'],$bytes,json_encode($proof,JSON_THROW_ON_ERROR)]);
            }
            return ['version'=>1,'scopeId'=>$sid,'baselineId'=>$p['baselineId'],'staged'=>count($p['records'])];
        }
        if($p['policyVersion']!==1||!is_int($p['baselineCount'])||$p['baselineCount']<0)throw new NativeError('validation_error');$this->digest($p['baselineRoot']);
        if($baseline['activation_authorization']!==null){
            if((int)$baseline['baseline_count']!==$p['baselineCount']||$baseline['baseline_root']!==$p['baselineRoot'])throw new NativeError('crypto_record_policy_baseline_immutable',409);
            return ['version'=>1,'scopeId'=>$sid,'baselineId'=>$p['baselineId'],'active'=>true,'policyVersion'=>1,'baselineCount'=>$p['baselineCount'],'baselineRoot'=>$p['baselineRoot']];
        }
        $count=$this->one('SELECT COUNT(*) AS n FROM familyhub_crypto_records WHERE scope_id=?',[$sid]);
        $staged=$this->one('SELECT COUNT(*) AS n FROM familyhub_crypto_record_policy_entries_v1 WHERE scope_id=? AND baseline_id=?',[$sid,$p['baselineId']]);
        if((int)$count['n']!==$p['baselineCount']||(int)$staged['n']!==$p['baselineCount'])throw new NativeError('crypto_record_policy_baseline_incomplete',409);
        $root=hash_init('sha256');hash_update($root,"JivieRecordPolicyBaseline/v1\n");
        foreach($this->iterate('SELECT e.entry,e.record_proof_hash,r.id,h.record_proof_hash AS proof_hash FROM familyhub_crypto_record_policy_entries_v1 e LEFT JOIN familyhub_crypto_records r ON r.scope_id=e.scope_id AND r.id=e.id LEFT JOIN familyhub_crypto_record_history h ON h.scope_id=r.scope_id AND h.id=r.id AND h.revision=r.revision WHERE e.scope_id=? AND e.baseline_id=? ORDER BY e.id',[$sid,$p['baselineId']]) as $entry){
            if($entry['id']===null||$entry['record_proof_hash']!==$entry['proof_hash'])throw new NativeError('crypto_record_policy_baseline_changed',409);
            hash_update($root,hash('sha256',"JivieRecordPolicyBaselineLeaf/v1\n".$entry['entry'])."\n");
        }
        if(!hash_equals(hash_final($root),$p['baselineRoot']))throw new NativeError('crypto_record_policy_baseline_incomplete',409);
        if(!$active)$this->change('INSERT INTO familyhub_crypto_record_policy_state_v1 VALUES(?,?,1)',[$sid,$p['baselineId']]);
        $this->change('UPDATE familyhub_crypto_record_policy_baselines_v1 SET activation_authorization=?,baseline_count=?,baseline_root=? WHERE scope_id=? AND baseline_id=?',[json_encode($proof,JSON_THROW_ON_ERROR),$p['baselineCount'],$p['baselineRoot'],$sid,$p['baselineId']]);
        $this->change('UPDATE familyhub_scopes SET metadata_revision=metadata_revision+1 WHERE id=?',[$sid]);
        return ['version'=>1,'scopeId'=>$sid,'baselineId'=>$p['baselineId'],'active'=>true,'policyVersion'=>1,'baselineCount'=>$p['baselineCount'],'baselineRoot'=>$p['baselineRoot']];
    }

    public function read($operation,$p,$actor)
    {
        $status=$operation==='crypto2.scope.recordPolicy.status';
        $this->fields($p,['scopeId'],$status?[]:['baselineId','afterId','limit','recordId']);
        $scope=$this->scope($this->uuid($p['scopeId']),$actor['user']['id']);$sid=$scope['id'];$active=$this->active($sid);
        $id=$p['baselineId']??($active['baseline_id']??null);
        if($id!==null)$this->uuid($id);
        $baseline=$id===null?null:$this->baseline($sid,$id);
        $out=['version'=>1,'serverId'=>$this->serverId(),'accountId'=>$actor['user']['account_id'],'deviceId'=>$actor['device']['id'],
            'scopeId'=>$sid,'active'=>$active!==null&&$id===$active['baseline_id'],'activeBaselineId'=>$active['baseline_id']??null,'baselineId'=>$id,'policyVersion'=>$active?1:0,
            'membershipHeadHash'=>$baseline['membership_head_hash']??null,'accessRevision'=>$baseline?(int)$baseline['access_revision']:null,
            'expectedContentSequence'=>$baseline?(int)$baseline['content_sequence']:null,'expectedFinanceSequence'=>$baseline?(int)$baseline['finance_sequence']:null,
            'baselineCount'=>isset($baseline['baseline_count'])?(int)$baseline['baseline_count']:null,'baselineRoot'=>$baseline['baseline_root']??null];
        if($status)return $out;
        $limit=$p['limit']??32;if(!is_int($limit)||$limit<1||$limit>32)throw new NativeError('invalid_cursor');
        $after=isset($p['afterId'])?NativeCryptoRecordAddressV2::wireId($p['afterId']):'';
        $recordId=isset($p['recordId'])?NativeCryptoRecordAddressV2::wireId($p['recordId']):null;
        if($recordId!==null&&isset($p['afterId']))throw new NativeError('invalid_cursor');
        $finance=(new NativeFinanceAccess($this->container))->policyForCrypto($sid,$actor['user'],false,false);
        $financeVisible=$finance['enabled']&&$finance['grant']!=='none';
        // Filter before paging: a hidden finance row must not leak its ID as a
        // continuation cursor. The typed metadata stays inside the server.
        $domain=$financeVisible?'':($this->sqlite?" AND json_extract(entry,'$.domain')='content'":" AND JSON_UNQUOTE(JSON_EXTRACT(entry,'$.domain'))='content'");
        $rows=$id===null?[]:$this->many('SELECT id,entry,stage_authorization FROM familyhub_crypto_record_policy_entries_v1 WHERE scope_id=? AND baseline_id=? AND id'.($recordId===null?'>':'=').'?'.$domain.' ORDER BY id LIMIT '.($recordId===null?$limit+1:1),[$sid,$id,$recordId??$after]);
        $page=array_slice($rows,0,$limit);
        $records=[];$bytes=0;$scanned=0;$next=null;
        foreach($page as $row){
            $entry=json_decode($row['entry'],true,8,JSON_THROW_ON_ERROR);
            $visible=$entry['domain']!=='finance'||$finance['enabled']&&$finance['grant']!=='none';
            $item=$visible?['entry'=>$entry,'stageAuthorization'=>json_decode($row['stage_authorization'],true,34,JSON_THROW_ON_ERROR)]:null;
            $size=$visible?strlen(json_encode($item,JSON_THROW_ON_ERROR)):0;
            if($records&&$bytes+$size>900000)break;
            if($visible){$records[]=$item;$bytes+=$size;}
            $scanned++;$next=$row['id'];
        }
        return $out+['prepareAuthorization'=>$baseline?json_decode($baseline['prepare_authorization'],true,34,JSON_THROW_ON_ERROR):null,
            'activationAuthorization'=>$baseline&&$baseline['activation_authorization']!==null?json_decode($baseline['activation_authorization'],true,34,JSON_THROW_ON_ERROR):null,
            'records'=>$records,
            'hasMore'=>$recordId===null&&count($rows)>$scanned,'nextAfterId'=>$next];
    }

    public function admit($record,$old,$scope,$actor,$head=null)
    {
        if(!$this->active($record['scopeId'])){
            if(isset($record['metadata']['recordPolicy'])||isset($record['metadata']['recordPolicyCompanion'])||isset($record['metadata']['recordRestore'])||in_array($record['contentContract']??null,[4,7],true))throw new NativeError('crypto_record_policy_not_active',409);
            return;
        }
        if(!$this->business($record['type'])){
            if(!in_array($record['type'],['scopeMetadata','financeAccountChoice','taskDerivationIntent','taskDerivationResolution','paymentEvent','paymentProjection','cashMovement','notification','reminder'],true))throw new NativeError('crypto_record_policy_type',409);
            return;
        }
        if(($record['contentContract']??null)!==($record['domain']==='finance'?4:7))throw new NativeError('crypto_upgrade_required',409,['requiredRecordPolicyVersion'=>1]);
        $policy=$record['metadata']['recordPolicy']??null;$this->validate($policy);
        $restore=$record['metadata']['recordRestore']??null;
        $restoring=$old&&(int)($old['deleted']??0)===1&&!$record['deleted'];
        if($restoring&&($restore===null||$policy['operation']!=='restore'))throw new NativeError('crypto_record_restore_intent_required',409);
        if(!$restoring&&($restore!==null||$policy['operation']==='restore'))throw new NativeError('crypto_record_restore_invalid',409);
        $account=$actor['user']['account_id'];$owner=$this->isOwner($scope,$actor,$head);
        if(!$old){
            if($record['deleted']||$policy['operation']!=='create'||$policy['createdByAccountId']!==$account)throw new NativeError('crypto_record_policy_creator',403);
            if($scope['role']==='viewer')throw new NativeError('record_edit_forbidden',403);
            return;
        }
        $oldMetadata=json_decode($old['metadata'],true,34,JSON_THROW_ON_ERROR);$previous=$oldMetadata['recordPolicy']??null;
        if($previous===null){
            $state=$this->active($record['scopeId']);
            $baseline=$this->one('SELECT entry,record_proof_hash FROM familyhub_crypto_record_policy_entries_v1 WHERE scope_id=? AND baseline_id=? AND id=?',[$record['scopeId'],$state['baseline_id'],$record['id']]);
            if(!$baseline||$baseline['record_proof_hash']!==$record['previousRecordHash'])throw new NativeError('crypto_record_policy_baseline_changed',409);
            $entry=json_decode($baseline['entry'],true,8,JSON_THROW_ON_ERROR);$previous=['version'=>1,'createdByAccountId'=>$entry['createdByAccountId'],'operation'=>'edit','fieldCommitments'=>$entry['fieldCommitments']];
        }
        $this->validate($previous);
        if($policy['createdByAccountId']!==$previous['createdByAccountId'])throw new NativeError('crypto_record_policy_creator',403);
        if($record['deleted']!==($policy['operation']==='delete')||$policy['operation']==='create')throw new NativeError('crypto_record_policy_invalid',409);
        $author=$previous['createdByAccountId']!==null&&$previous['createdByAccountId']===$account;
        if($restoring){
            if(!$owner&&!$author)throw new NativeError('record_restore_forbidden',403);
            $this->restoreAncestor($record,$old,$restore);
            return;
        }
        if($record['deleted']){
            if(!$owner&&!$author)throw new NativeError('record_delete_forbidden',403);
            if(NativeCryptoCodec::canonical((object)$policy['fieldCommitments'])!==NativeCryptoCodec::canonical((object)$previous['fieldCommitments']))throw new NativeError('crypto_record_policy_invalid',409);
            return;
        }
        if($owner||$author)return;
        if($record['type']==='task'&&$policy['operation']==='edit'&&in_array($account,$oldMetadata['notificationState']['assigneeAccountIds']??[],true)){
            if($policy['fieldCommitments']['assignment']!==$previous['fieldCommitments']['assignment']||
                ($record['metadata']['notificationState']['assigneeAccountIds']??[])!==($oldMetadata['notificationState']['assigneeAccountIds']??[]))throw new NativeError('record_assignment_forbidden',403);
            return;
        }
        if($record['type']==='shoppingItem'&&$policy['operation']==='shoppingCheck'&&
            $policy['fieldCommitments']['content']===$previous['fieldCommitments']['content']&&$policy['fieldCommitments']['assignment']===$previous['fieldCommitments']['assignment']){
            foreach(['references','uniqueRefs','blobIds','identity'] as $field){
                if(($record['metadata'][$field]??null)!==($oldMetadata[$field]??null))throw new NativeError('record_edit_forbidden',403);
            }
            foreach(['assigneeAccountIds','groupTargetId'] as $field){
                if(($record['metadata']['notificationState'][$field]??null)!==($oldMetadata['notificationState'][$field]??null))throw new NativeError('record_edit_forbidden',403);
            }
            return;
        }
        throw new NativeError('record_edit_forbidden',403);
    }

    /** Compare accepted predecessors, before the batch detaches/deletes children.
     * The ordinary reference guard separately prevents surviving orphans. */
    public function admitCascade($record,$scope,$actor,$head=null)
    {
        if(!$record['deleted']||!in_array($record['type'],['project','shoppingList'],true)||!$this->active($record['scopeId'])||$this->isOwner($scope,$actor,$head))return;
        $ids=[$record['scopeId']];$parent=$scope['parent_scope_id']??$scope['organization_id']??null;
        if($parent!==null)$ids[]=$parent;
        foreach($this->many('SELECT id FROM familyhub_scopes WHERE parent_scope_id=? OR organization_id=?',[$record['scopeId'],$record['scopeId']]) as $child)$ids[]=$child['id'];
        $ids=array_values(array_unique($ids));
        $rows=$this->many('SELECT r.scope_id,r.id,r.type,r.metadata,h.record_proof_hash FROM familyhub_crypto_records r LEFT JOIN familyhub_crypto_record_history h ON h.scope_id=r.scope_id AND h.id=r.id AND h.revision=r.revision WHERE r.scope_id IN ('.implode(',',array_fill(0,count($ids),'?')).') AND r.deleted=0',$ids);
        $pending=[$record['scopeId'].':'.$record['id']=>true];$seen=[];
        do{
            $added=false;
            foreach($rows as $row){
                $key=$row['scope_id'].':'.$row['id'];if(isset($seen[$key])||isset($pending[$key]))continue;
                $metadata=json_decode($row['metadata'],true,34,JSON_THROW_ON_ERROR);$dependent=false;
                foreach($metadata['references']??[] as $ref){if(isset($pending[$ref['scopeId'].':'.$ref['id']])){$dependent=true;break;}}
                if(!$dependent)continue;
                $seen[$key]=true;$pending[$key]=true;$added=true;
                if(!$this->business($row['type']))continue;
                $policy=$metadata['recordPolicy']??null;
                if($policy===null){
                    $state=$this->active($row['scope_id']);
                    $entry=$state?$this->one('SELECT entry,record_proof_hash FROM familyhub_crypto_record_policy_entries_v1 WHERE scope_id=? AND baseline_id=? AND id=?',[$row['scope_id'],$state['baseline_id'],$row['id']]):null;
                    if(!$entry||$entry['record_proof_hash']!==$row['record_proof_hash'])throw new NativeError('record_delete_forbidden',403,['reason'=>'dependent_creator_unverified']);
                    $policy=json_decode($entry['entry'],true,8,JSON_THROW_ON_ERROR);
                }
                if(($policy['createdByAccountId']??null)!==$actor['user']['account_id'])throw new NativeError('record_delete_forbidden',403,['reason'=>'foreign_dependent']);
            }
        }while($added);
    }

    /** Blob staging can use an existing record's edit right, never a claimed
     * new creator, checkbox right, internal type or financial permission. */
    public function authorizeBlobTarget($scope,$target,$actor,$head=null)
    {
        if(!is_array($target))throw new NativeError('crypto_blob_target_invalid',409);
        $this->fields($target,['type','wireId','currentRecordProofHash']);
        if(!is_string($target['type'])||!in_array($target['type'],['project','task','event','shoppingList','shoppingItem','householdPerson','garden','idea','table','attachment'],true)||!$this->active($scope['id']))throw new NativeError('crypto_blob_target_invalid',409);
        $id=NativeCryptoRecordAddressV2::wireId($target['wireId']);$this->digest($target['currentRecordProofHash']);
        $record=$this->one('SELECT r.id,r.type,r.revision,r.deleted,r.metadata,h.record_proof_hash,p.domain FROM familyhub_crypto_records r LEFT JOIN familyhub_crypto_record_history h ON h.scope_id=r.scope_id AND h.id=r.id AND h.revision=r.revision LEFT JOIN familyhub_crypto_record_positions p ON p.scope_id=r.scope_id AND p.id=r.id WHERE r.scope_id=? AND r.id=?'.$this->lockSuffix(),[$scope['id'],$id]);
        if(!$record||(int)$record['deleted']||$record['type']!==$target['type']||$record['domain']!=='content'||$record['record_proof_hash']!==$target['currentRecordProofHash'])throw new NativeError('crypto_blob_target_changed',409);
        if($this->isOwner($scope,$actor,$head))return;
        $metadata=json_decode($record['metadata'],true,34,JSON_THROW_ON_ERROR);$policy=$metadata['recordPolicy']??null;
        if($policy===null){
            $active=$this->active($scope['id']);
            $baseline=$this->one('SELECT entry,record_proof_hash FROM familyhub_crypto_record_policy_entries_v1 WHERE scope_id=? AND baseline_id=? AND id=?',[$scope['id'],$active['baseline_id'],$id]);
            if(!$baseline||$baseline['record_proof_hash']!==$record['record_proof_hash'])throw new NativeError('crypto_record_policy_baseline_changed',409);
            $entry=json_decode($baseline['entry'],true,8,JSON_THROW_ON_ERROR);
            $policy=['version'=>1,'createdByAccountId'=>$entry['createdByAccountId'],'operation'=>'edit','fieldCommitments'=>$entry['fieldCommitments']];
        }
        $this->validate($policy);$account=$actor['user']['account_id'];
        if($policy['createdByAccountId']===$account||$record['type']==='task'&&in_array($account,$metadata['notificationState']['assigneeAccountIds']??[],true))return;
        throw new NativeError('record_edit_forbidden',403);
    }

    /** Lease acquisition is an edit right, not a way for any writer to lock a
     * foreign document. Release still validates its own device/token separately. */
    public function authorizeTable($scope,$table,$actor,$head=null)
    {
        if(!$this->active($scope['id'])||$this->isOwner($scope,$actor,$head))return;
        $metadata=json_decode($table['metadata'],true,34,JSON_THROW_ON_ERROR);$policy=$metadata['recordPolicy']??null;
        if($policy===null){
            $active=$this->active($scope['id']);
            $baseline=$this->one('SELECT e.entry,e.record_proof_hash,h.record_proof_hash AS current_hash FROM familyhub_crypto_record_policy_entries_v1 e LEFT JOIN familyhub_crypto_record_history h ON h.scope_id=e.scope_id AND h.id=e.id AND h.revision=? WHERE e.scope_id=? AND e.baseline_id=? AND e.id=?',[(int)$table['revision'],$scope['id'],$active['baseline_id'],$table['id']]);
            if(!$baseline||$baseline['record_proof_hash']!==$baseline['current_hash'])throw new NativeError('crypto_record_policy_baseline_changed',409);
            $entry=json_decode($baseline['entry'],true,8,JSON_THROW_ON_ERROR);
            $creator=$entry['createdByAccountId'];
        }else{
            $this->validate($policy);$creator=$policy['createdByAccountId'];
        }
        if($creator!==$actor['user']['account_id'])throw new NativeError('record_edit_forbidden',403);
    }
}
