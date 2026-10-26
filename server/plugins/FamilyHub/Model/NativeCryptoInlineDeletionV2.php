<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** Finite purpose coordinator. Staging never changes a business record. */
class NativeCryptoInlineDeletionV2 extends NativeDatabase
{
    protected $cryptoAccess=true;
    private function hash($v){return NativeCryptoInlineDeletionCodecV2::hash($v);}
    private function source($row){$a=json_decode($row['authorization'],true,34,JSON_THROW_ON_ERROR);[$b]=NativeCryptoCodec::decode($a['recordProof']);return [$b,$a];}
    private function descriptor($r){[$b,$a]=$this->source($r);return ['scopeId'=>$r['scope_id'],'id'=>$r['id'],'type'=>$r['type'],'domain'=>$b['domain'],'revision'=>(int)$r['revision'],'recordProofHash'=>$this->hash($a['recordProof'])];}
    private function context($sid,$actor)
    {
        $s=$this->scope($sid,$actor['user']['id'],true);$api=new NativeCryptoScopeV2($this->container,$this->bearer,$this->ip);$h=$api->current($sid);if(!$h)throw new NativeError('crypto_scope_head_missing',409);$b=$api->body($h);
        $api->author($sid,$h['head_hash'],(int)$h['epoch'],(int)$s['effective_access_revision'],$actor,'content');
        return [$s,$h,$b,(new NativeCryptoLifecycleV2($this->container))->closingHash($sid)];
    }
    private function reserved($scope,$kind)
    {
        $h=hash('sha256',"JivieReservedRecord/v2\n".$this->serverId().':'.$scope.':'.$kind);
        return substr($h,0,8).'-'.substr($h,8,4).'-4'.substr($h,13,3).'-a'.substr($h,17,3).'-'.substr($h,20,12);
    }
    private function graph($sid,$pid,$wire,$actor)
    {
        [$scope,$head,$body,$lifecycle]=$this->context($sid,$actor);
        if(($scope['project_root_id']??null)===$pid)throw new NativeError('crypto_inline_delete_scope_root',409);
        if(NativeCryptoRecordAddressV2::derive($this->serverId(),$sid,'content','records',$pid)!==$wire)throw new NativeError('crypto_record_identity_binding',409);
        $root=$this->one("SELECT * FROM familyhub_crypto_records WHERE scope_id=? AND id=? AND type='project' AND deleted=0",[$sid,$wire]);if(!$root)throw new NativeError('record_deleted',409);
        $selected=[$wire=>$root];$blocked=[];$changed=true;$passes=0;
        while($changed){if(++$passes>4)throw new NativeError('crypto_inline_delete_dependency_depth',409);$changed=false;
            foreach($this->iterate('SELECT * FROM familyhub_crypto_records WHERE scope_id=? AND deleted=0 ORDER BY id',[$sid]) as $row){
                if(isset($selected[$row['id']]))continue;[$b]=$this->source($row);$include=false;
                foreach($b['metadata']['references'] as $ref){
                    if($ref['scopeId']!==$sid||!isset($selected[$ref['id']]))continue;
                    $target=$selected[$ref['id']];
                    $direct=in_array($row['type'],['task','event','idea'],true)&&$target['id']===$wire&&$target['type']==='project';
                    $financial=in_array($row['type'],['financeEntry','personalFinanceEntry','financeAccount','personalFinanceAccount','financeTransfer','financeRecurrenceRule'],true)&&($target['id']===$wire&&$target['type']==='project'||$target['type']==='task');
                    $asset=$row['type']==='attachment'&&$target['type']==='task'||$row['type']==='ideaAsset'&&$target['type']==='idea';
                    $companion=$row['type']==='taskDerivationResolution'&&in_array($target['type'],['task','taskDerivationIntent'],true);
                    if($direct||$financial||$asset||$companion){$include=true;break;}
                }
                if(!$include&&$row['type']==='taskDerivationIntent')foreach($selected as $task){if($task['type']!=='task')continue;[$tb]=$this->source($task);$canonical=$this->reserved($sid,'taskDerivation:'.$tb['metadata']['identity']['canonicalId']);if($row['id']===NativeCryptoRecordAddressV2::derive($this->serverId(),$sid,'content','task_derivation_intents',$canonical)){$include=true;break;}}
                if(!$include)continue;
                if(in_array($row['type'],['paymentEvent','paymentProjection','cashMovement','financeAccountChoice'],true)){$blocked['payment_dependency']=['code'=>'cross_scope_payment_dependency'];continue;}
                if(!in_array($row['type'],['project','task','event','idea','attachment','ideaAsset','financeEntry','personalFinanceEntry','financeAccount','personalFinanceAccount','financeTransfer','financeRecurrenceRule','taskDerivationIntent','taskDerivationResolution'],true)){$blocked['unsupported_dependency']=['code'=>'crypto_inline_delete_dependency'];continue;}
                $selected[$row['id']]=$row;$changed=true;if(count($selected)>NativeCryptoInlineDeletionCodecV2::MAX_RECORDS)throw new NativeError('crypto_inline_delete_limit',409);
            }
        }
        // Foreign/current and retained historical payment edges cannot be
        // silently severed merely because their target is no longer current.
        foreach($this->iterate('SELECT scope_id,id,deleted,metadata FROM familyhub_crypto_records WHERE deleted=0 AND metadata LIKE ? ORDER BY scope_id,id', ['%'.$sid.'%']) as $r){
            if($r['scope_id']===$sid&&isset($selected[$r['id']]))continue;
            foreach(json_decode($r['metadata'],true,34,JSON_THROW_ON_ERROR)['references']??[] as $ref){if($ref['scopeId']===$sid&&isset($selected[$ref['id']]))$blocked['external']=['code'=>'cross_scope_payment_dependency'];}
        }
        foreach($this->iterate("SELECT h.scope_id,h.record_proof FROM familyhub_crypto_record_history h LEFT JOIN familyhub_crypto_records current_record ON current_record.scope_id=h.scope_id AND current_record.id=h.id WHERE h.domain='finance' AND (current_record.id IS NULL OR current_record.type IN ('paymentEvent','paymentProjection','cashMovement')) ORDER BY h.scope_id,h.id,h.revision") as $r){[$b]=NativeCryptoCodec::decode(json_decode($r['record_proof'],true,34,JSON_THROW_ON_ERROR));if(!in_array($b['type'],['paymentEvent','paymentProjection','cashMovement'],true))continue;foreach($b['metadata']['references']??[] as $ref){if($ref['scopeId']===$sid&&isset($selected[$ref['id']]))$blocked['payment_history']=['code'=>'cross_scope_payment_dependency'];}}
        ksort($selected,SORT_STRING);$descriptors=[];$counts=['spaces'=>0,'projects'=>0,'tasks'=>0,'events'=>0,'ideas'=>0,'photos'=>0,'tables'=>0,'attachments'=>0,'finance'=>0,'other'=>0];$finance=false;
        foreach($selected as $row){$d=$this->descriptor($row);$finance=$finance||$d['domain']==='finance';$descriptors[]=$d;$key=$d['domain']==='finance'?'finance':(['project'=>'projects','task'=>'tasks','event'=>'events','idea'=>'ideas','attachment'=>'attachments','ideaAsset'=>'photos'][$d['type']]??'other');$counts[$key]++;}
        if($finance){try{(new NativeFinanceAccess($this->container))->policyForCrypto($sid,$actor['user'],false,true);}catch(NativeError $e){return ['scopeId'=>$sid,'projectId'=>$pid,'projectWireId'=>$wire,'canDelete'=>false,'incomplete'=>true,'blockers'=>[['code'=>'finance_write_required']],'counts'=>array_fill_keys(array_keys($counts),0),'graphRoot'=>null,'graphCount'=>0];}
            try{(new NativeFinanceAccess($this->container))->policyForCrypto($sid,$actor['user'],true,true);}catch(NativeError $e){$blocked['finance_write']=['code'=>'finance_write_required'];}}
        $rootHash=NativeCryptoInlineDeletionCodecV2::graphRoot($descriptors);
        return ['scopeId'=>$sid,'projectId'=>$pid,'projectWireId'=>$wire,'membershipHeadHash'=>$head['head_hash'],'expectedAccessRevision'=>(int)$scope['effective_access_revision'],'lifecycleHash'=>$lifecycle,'canDelete'=>!$blocked,'incomplete'=>false,'blockers'=>array_values($blocked),'counts'=>$counts,'graphRoot'=>$rootHash['root'],'graphCount'=>$rootHash['count'],'descriptors'=>$descriptors];
    }
    public function preview($p,$actor){$this->fields($p,['scopeId','projectId','projectWireId']);$g=$this->graph($this->uuid($p['scopeId']),$this->uuid($p['projectId']),NativeCryptoRecordAddressV2::wireId($p['projectWireId']),$actor);unset($g['descriptors']);return $g;}
    private function plan($id,$actor,$active=true)
    {
        $r=$this->one('SELECT * FROM familyhub_crypto_inline_delete_plans_v2 WHERE action_id=?'.$this->lockSuffix(),[$this->uuid($id)]);
        if(!$r||$r['account_id']!==$actor['user']['account_id'])throw new NativeError('permission_revoked',403);
        if($active&&($r['state']!=='prepared'||(int)$r['expires_at']<time()||$r['device_id']!==$actor['device']['id']))throw new NativeError('crypto_inline_delete_plan_pending',409);return $r;
    }
    public function prepare($p,$actor,$proof,$command)
    {
        $this->fields($p,['actionId','scopeId','projectId','projectWireId','membershipHeadHash','expectedAccessRevision','lifecycleHash','authorDirectoryHeadHash','graphRoot','graphCount']);$id=$this->uuid($p['actionId']);
        if($this->one('SELECT action_id FROM familyhub_crypto_inline_delete_plans_v2 WHERE action_id=?',[$id]))throw new NativeError('crypto_inline_delete_action_immutable',409);
        $g=$this->graph($this->uuid($p['scopeId']),$this->uuid($p['projectId']),NativeCryptoRecordAddressV2::wireId($p['projectWireId']),$actor);if(!$g['canDelete'])throw new NativeError('scope_deletion_blocked',409,['blockers'=>$g['blockers']]);
        foreach(['membershipHeadHash','expectedAccessRevision','lifecycleHash','graphRoot','graphCount'] as $f)if($p[$f]!==$g[$f])throw new NativeError('scope_deletion_preview_changed',409);
        $own=(new NativeCryptoDirectoryV2($this->container))->current($actor['user']['account_id']);if($p['authorDirectoryHeadHash']!==$own['head_hash'])throw new NativeError('crypto_member_directory_changed',409);
        $hash=$this->hash($proof);$expiry=time()+1800;
        $this->change('INSERT INTO familyhub_crypto_inline_delete_plans_v2(action_id,scope_id,project_id,project_wire_id,account_id,device_id,head_hash,access_revision,lifecycle_hash,graph_root,graph_count,plan_hash,authorization,state,expires_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',[$id,$p['scopeId'],$p['projectId'],$p['projectWireId'],$actor['user']['account_id'],$actor['device']['id'],$p['membershipHeadHash'],$p['expectedAccessRevision'],$p['lifecycleHash'],$p['graphRoot'],$p['graphCount'],$hash,json_encode($proof,JSON_THROW_ON_ERROR),'prepared',$expiry]);
        foreach($g['descriptors'] as $d)$this->change('INSERT INTO familyhub_crypto_inline_delete_leaves_v2(action_id,id,domain,type,revision,record_proof_hash) VALUES(?,?,?,?,?,?)',[$id,$d['id'],$d['domain'],$d['type'],$d['revision'],$d['recordProofHash']]);
        return ['actionId'=>$id,'planHash'=>$hash,'graphRoot'=>$p['graphRoot'],'graphCount'=>$p['graphCount'],'expiresAt'=>$expiry];
    }
    public function leaves($p,$actor)
    {
        $this->fields($p,['actionId'],['afterId','limit']);$r=$this->plan($p['actionId'],$actor,false);$limit=$p['limit']??32;if(!is_int($limit)||$limit<1||$limit>32)throw new NativeError('validation_error');$after=$p['afterId']??'';if($after!=='')NativeCryptoRecordAddressV2::wireId($after);
        $rows=$this->many('SELECT * FROM familyhub_crypto_inline_delete_leaves_v2 WHERE action_id=? AND id>? ORDER BY id LIMIT '.($limit+1),[$r['action_id'],$after]);$more=count($rows)>$limit;$rows=array_slice($rows,0,$limit);$out=[];foreach($rows as $v)$out[]=['scopeId'=>$r['scope_id'],'id'=>$v['id'],'type'=>$v['type'],'domain'=>$v['domain'],'revision'=>(int)$v['revision'],'recordProofHash'=>$v['record_proof_hash']];
        return ['actionId'=>$r['action_id'],'planHash'=>$r['plan_hash'],'graphRoot'=>$r['graph_root'],'graphCount'=>(int)$r['graph_count'],'leaves'=>$out,'hasMore'=>$more,'nextAfterId'=>$rows?end($rows)['id']:$after,'state'=>$r['state']];
    }
    public function stage($p,$actor,$proof,$command,$key)
    {
        $this->fields($p,['actionId','planHash','batch']);$r=$this->plan($p['actionId'],$actor);if($r['plan_hash']!==$p['planHash'])throw new NativeError('crypto_inline_delete_binding',409);
        $entries=(new NativeCryptoRecordProofV2($this->container))->parseBatch($p['batch'],$command,$key);$hash=$this->hash($p['batch']);$saved=$this->one('SELECT batch_hash FROM familyhub_crypto_inline_delete_batches_v2 WHERE action_id=? AND batch_id=?',[$r['action_id'],$p['batch']['batchId']]);if($saved){if($saved['batch_hash']!==$hash)throw new NativeError('crypto_inline_delete_batch_immutable',409);return ['staged'=>true,'batchId'=>$p['batch']['batchId']];}
        foreach($entries as $e){$b=$e['record'];$tag=$b['metadata']['inlineDeletion']??[];$leaf=$this->one('SELECT * FROM familyhub_crypto_inline_delete_leaves_v2 WHERE action_id=? AND id=?',[$r['action_id'],$b['id']]);
            if(!$b['deleted']||$b['scopeId']!==$r['scope_id']||($tag['actionId']??null)!==$r['action_id']||($tag['planHash']??null)!==$r['plan_hash']||!$leaf||$leaf['type']!==$b['type']||$leaf['domain']!==$b['domain']||(int)$leaf['revision']!==$b['expectedRevision']||$leaf['record_proof_hash']!==$b['previousRecordHash']||$leaf['tombstone_hash']!==null)throw new NativeError('crypto_inline_delete_source_changed',409);
            $this->change('UPDATE familyhub_crypto_inline_delete_leaves_v2 SET tombstone_hash=?,tombstone_proof=?,batch_id=?,batch_commitment=? WHERE action_id=? AND id=?',[$e['recordProofHash'],json_encode($e['recordProof'],JSON_THROW_ON_ERROR),$p['batch']['batchId'],json_encode($p['batch']['commitment'],JSON_THROW_ON_ERROR),$r['action_id'],$b['id']]);
        }
        $this->change('INSERT INTO familyhub_crypto_inline_delete_batches_v2 VALUES(?,?,?,?)',[$r['action_id'],$p['batch']['batchId'],$hash,json_encode($p['batch'],JSON_THROW_ON_ERROR)]);return ['staged'=>true,'batchId'=>$p['batch']['batchId']];
    }
    public function commit($p,$actor,$outerProof,$command,$key)
    {
        $this->fields($p,['actionId','planHash','certificateProof','accountEventProof']);$r=$this->plan($p['actionId'],$actor);if($r['plan_hash']!==$p['planHash'])throw new NativeError('crypto_inline_delete_binding',409);
        [$c,$bytes,$signature]=NativeCryptoCodec::decode($p['certificateProof']);NativeCryptoV2Codec::verify($bytes,$signature,$key,NativeCryptoInlineDeletionCodecV2::DOMAIN);NativeCryptoInlineDeletionCodecV2::certificate($c);
        $directory=new NativeCryptoDirectoryV2($this->container);$own=$directory->current($actor['user']['account_id']);
        $expected=['version'=>2,'serverId'=>$this->serverId(),'scopeId'=>$r['scope_id'],'projectId'=>$r['project_id'],'projectWireId'=>$r['project_wire_id'],'actionId'=>$r['action_id'],'planHash'=>$r['plan_hash'],'requestId'=>$command['requestId'],'membershipHeadHash'=>$r['head_hash'],'accessRevision'=>(int)$r['access_revision'],'lifecycleHash'=>$r['lifecycle_hash'],'graphRoot'=>$r['graph_root'],'graphCount'=>(int)$r['graph_count'],'accountId'=>$actor['user']['account_id'],'deviceId'=>$actor['device']['id'],'authorDirectoryHeadHash'=>$own['head_hash']];
        foreach($expected as $f=>$value)if($c[$f]!==$value)throw new NativeError('crypto_inline_delete_certificate',409);
        $g=$this->graph($r['scope_id'],$r['project_id'],$r['project_wire_id'],$actor);
        if(!$g['canDelete']||$g['graphRoot']!==$r['graph_root']||$g['graphCount']!==(int)$r['graph_count']||$g['membershipHeadHash']!==$r['head_hash']||$g['expectedAccessRevision']!==(int)$r['access_revision']||$g['lifecycleHash']!==$r['lifecycle_hash'])throw new NativeError('scope_deletion_preview_changed',409);
        $descriptors=[];$batches=[];$batchHashes=[];
        foreach($this->iterate('SELECT * FROM familyhub_crypto_inline_delete_leaves_v2 WHERE action_id=? ORDER BY id',[$r['action_id']]) as $leaf){
            if($leaf['tombstone_hash']===null||$leaf['tombstone_proof']===null||$leaf['batch_commitment']===null)throw new NativeError('crypto_inline_delete_incomplete',409);
            $descriptors[]=['id'=>$leaf['id'],'domain'=>$leaf['domain'],'type'=>$leaf['type'],'expectedRevision'=>(int)$leaf['revision'],'previousRecordHash'=>$leaf['record_proof_hash'],'recordProofHash'=>$leaf['tombstone_hash'],'batchCommitmentHash'=>$this->hash(json_decode($leaf['batch_commitment'],true,34,JSON_THROW_ON_ERROR))];
        }
        foreach($this->iterate('SELECT * FROM familyhub_crypto_inline_delete_batches_v2 WHERE action_id=? ORDER BY batch_id',[$r['action_id']]) as $batch){$payload=json_decode($batch['authorization'],true,34,JSON_THROW_ON_ERROR);if($this->hash($payload)!==$batch['batch_hash'])throw new NativeError('crypto_inline_delete_batch_immutable',409);$batches[]=$payload;$batchHashes[]=$this->hash($payload['commitment']);}
        sort($batchHashes,SORT_STRING);$t=NativeCryptoInlineDeletionCodecV2::tombstoneRoot($descriptors);$b=NativeCryptoInlineDeletionCodecV2::batchRoot($batchHashes);
        if($c['tombstoneRoot']!==$t['root']||$c['tombstoneCount']!==$t['count']||$c['batchRoot']!==$b['root']||$c['batchCount']!==$b['count'])throw new NativeError('crypto_inline_delete_inclusion',409);
        [$event,$eventBytes,$eventSig]=NativeCryptoCodec::decode($p['accountEventProof']);$certHash=$this->hash($p['certificateProof']);$token=NativeCryptoInlineDeletionCodecV2::token($c);
        if(($event['operation']??null)!=='crypto2.account.scopeDeletion'||($event['accountId']??null)!==$actor['user']['account_id']||($event['deviceId']??null)!==$actor['device']['id']||($event['serverId']??null)!==$command['serverId']||($event['requestId']??null)!==$command['requestId']||($event['payload']['scopeToken']??null)!==$token||($event['payload']['certificateHash']??null)!==$certHash)throw new NativeError('crypto_inline_delete_event_binding',409);
        $eventKey=$directory->authorize($event,$own);NativeCryptoV2Codec::verify($eventBytes,$eventSig,$eventKey);$next=$directory->reduce($event,$own);
        $this->change("UPDATE familyhub_crypto_inline_delete_plans_v2 SET state='committing' WHERE action_id=?",[$r['action_id']]);
        $results=(new NativeCryptoStorageV2($this->container,$this->bearer,$this->ip))->installInlineDeletion($r['action_id'],$batches,$actor,$command,$key);
        $entry=$directory->append($event,$p['accountEventProof'],$next);
        $this->change('UPDATE familyhub_crypto_accounts SET generation=?,generation_certificate=?,updated_at=? WHERE account_id=?',[$entry['generation'],json_encode($p['accountEventProof'],JSON_THROW_ON_ERROR),time(),$actor['user']['account_id']]);
        $eventHash=hash('sha256',$eventBytes);
        $this->change("UPDATE familyhub_crypto_inline_delete_plans_v2 SET state='committed',certificate_hash=?,certificate_authorization=?,event_authorization=?,event_head_hash=?,event_command_hash=? WHERE action_id=?",[$certHash,json_encode($p['certificateProof'],JSON_THROW_ON_ERROR),json_encode($p['accountEventProof'],JSON_THROW_ON_ERROR),$entry['headHash'],$eventHash,$r['action_id']]);
        return ['deleted'=>true,'scopeId'=>$r['scope_id'],'projectId'=>$r['project_id'],'deletedScopeIds'=>[],'actionId'=>$r['action_id'],'planHash'=>$r['plan_hash'],'certificateHash'=>$certHash,'certificateProof'=>$p['certificateProof'],'eventAuthorization'=>$p['accountEventProof'],'eventHeadHash'=>$entry['headHash'],'eventCommandHash'=>$eventHash,'batches'=>$results,'cleanupPending'=>false];
    }

    /** Current authorized scoped readers obtain the exact publication witness;
     * no staged proof or SQL state is itself an authority claim. */
    public function evidence($p,$actor)
    {
        $this->fields($p,['scopeId','actionId'],['recordProofHash','id','recordBodyHash','afterHash','limit']);$sid=$this->uuid($p['scopeId']);$this->scope($sid,$actor['user']['id']);
        $bodySelector=isset($p['recordBodyHash']);
        if($bodySelector){if(isset($p['recordProofHash'])||!isset($p['id'])||!is_string($p['id']))throw new NativeError('validation_error');NativeCryptoInlineDeletionCodecV2::digest($p['recordBodyHash']);}
        else {if(isset($p['id'])||!isset($p['recordProofHash']))throw new NativeError('validation_error');NativeCryptoInlineDeletionCodecV2::digest($p['recordProofHash']);}
        $r=$this->one("SELECT * FROM familyhub_crypto_inline_delete_plans_v2 WHERE scope_id=? AND action_id=? AND state='committed'",[$sid,$this->uuid($p['actionId'])]);
        $leaf=$r?($bodySelector?$this->one('SELECT * FROM familyhub_crypto_inline_delete_leaves_v2 WHERE action_id=? AND id=?',[$r['action_id'],$p['id']]):$this->one('SELECT * FROM familyhub_crypto_inline_delete_leaves_v2 WHERE action_id=? AND tombstone_hash=?',[$r['action_id'],$p['recordProofHash']])):null;if(!$leaf)throw new NativeError('crypto_inline_delete_publication_pending',409);
        $recordProof=json_decode($leaf['tombstone_proof'],true,34,JSON_THROW_ON_ERROR);[$record,$recordBytes]=NativeCryptoCodec::decode($recordProof);
        if($bodySelector&&hash('sha256',$recordBytes)!==$p['recordBodyHash'])throw new NativeError('crypto_inline_delete_record_binding',409);
        $proofHash=$leaf['tombstone_hash'];
        if($leaf['domain']==='finance')(new NativeFinanceAccess($this->container))->policyForCrypto($sid,$actor['user'],false,true);
        $limit=$p['limit']??32;if(!is_int($limit)||$limit<1||$limit>32)throw new NativeError('validation_error');$after=$p['afterHash']??null;if($after!==null)NativeCryptoInlineDeletionCodecV2::digest($after);
        $hashes=[];$own=null;
        foreach($this->iterate('SELECT * FROM familyhub_crypto_inline_delete_leaves_v2 WHERE action_id=? ORDER BY id',[$r['action_id']]) as $v){
            $descriptor=['id'=>$v['id'],'domain'=>$v['domain'],'type'=>$v['type'],'expectedRevision'=>(int)$v['revision'],'previousRecordHash'=>$v['record_proof_hash'],'recordProofHash'=>$v['tombstone_hash'],'batchCommitmentHash'=>$this->hash(json_decode($v['batch_commitment'],true,34,JSON_THROW_ON_ERROR))];
            $hashes[]=NativeCryptoInlineDeletionCodecV2::tombstoneLeaf($descriptor);if($v['tombstone_hash']===$proofHash)$own=$descriptor;
        }
        sort($hashes,SORT_STRING);$remaining=array_values(array_filter($hashes,fn($v)=>$after===null||strcmp($v,$after)>0));$more=count($remaining)>$limit;$page=array_slice($remaining,0,$limit);
        $batchHashes=[];foreach($this->iterate('SELECT authorization FROM familyhub_crypto_inline_delete_batches_v2 WHERE action_id=? ORDER BY batch_id',[$r['action_id']]) as $v){$batch=json_decode($v['authorization'],true,34,JSON_THROW_ON_ERROR);$batchHashes[]=$this->hash($batch['commitment']);}sort($batchHashes,SORT_STRING);
        return ['recordProof'=>$recordProof,'batchCommitment'=>json_decode($leaf['batch_commitment'],true,34,JSON_THROW_ON_ERROR),'certificateProof'=>json_decode($r['certificate_authorization'],true,34,JSON_THROW_ON_ERROR),'eventAuthorization'=>json_decode($r['event_authorization'],true,34,JSON_THROW_ON_ERROR),'eventHeadHash'=>$r['event_head_hash'],'eventCommandHash'=>$r['event_command_hash'],'descriptor'=>$own,'tombstoneDigests'=>$page,'batchDigests'=>$batchHashes,'hasMore'=>$more,'nextAfterHash'=>$page?end($page):$after];
    }

    /** Exact historical public-prefix references; never a latest-tail grant. */
    public function directoryReferences($scopeId,$headHash,$targetAccount)
    {
        $references=[];
        foreach($this->iterate("SELECT certificate_authorization,event_head_hash FROM familyhub_crypto_inline_delete_plans_v2 WHERE scope_id=? AND account_id=? AND head_hash=? AND state='committed'",[$scopeId,$targetAccount,$headHash]) as $row){
            $proof=json_decode($row['certificate_authorization'],true,34,JSON_THROW_ON_ERROR);[$body]=NativeCryptoCodec::decode($proof);
            NativeCryptoInlineDeletionCodecV2::certificate($body);
            if($body['scopeId']!==$scopeId||$body['membershipHeadHash']!==$headHash||$body['accountId']!==$targetAccount)throw new NativeError('crypto_inline_delete_binding',409);
            $references[]=$body['authorDirectoryHeadHash'];$references[]=$row['event_head_hash'];
        }
        return array_values(array_unique($references));
    }

    public function cancel($p,$actor){$this->fields($p,['actionId','planHash']);$r=$this->plan($p['actionId'],$actor,false);if($r['plan_hash']!==$p['planHash']||$r['state']==='committed')throw new NativeError('crypto_inline_delete_binding',409);$this->change("UPDATE familyhub_crypto_inline_delete_plans_v2 SET state='cancelled' WHERE action_id=?",[$r['action_id']]);return ['cancelled'=>true,'sourceUnchanged'=>true];}
}
