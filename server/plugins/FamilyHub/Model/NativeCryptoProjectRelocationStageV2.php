<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** Private bounded staging. Signed batches and blob commands are immutable
 * candidates; none is available through normal record/blob reads. */
class NativeCryptoProjectRelocationStageV2 extends NativeDatabase
{
    protected $cryptoAccess=true;
    private const MAX_STAGE_BYTES=33554432;

    private function hash($value){return NativeCryptoProjectRelocationCodecV2::hash($value);}
    private function api(){return new NativeCryptoProjectRelocationV2($this->container,$this->bearer,$this->ip);}

    public function records($p,$actor,$proof,$command,$key)
    {
        $this->fields($p,['actionId','planHash','batch','bindings']);
        $action=$this->uuid($p['actionId']);NativeCryptoProjectRelocationCodecV2::digest($p['planHash']);
        $verified=$this->api()->validateSources($action,$actor);
        $row=$verified['plan'];$plan=$verified['body'];
        if($row['plan_hash']!==$p['planHash'])throw new NativeError('crypto_relocation_plan',409);
        if(!is_array($p['bindings'])||!array_is_list($p['bindings'])||count($p['bindings'])>32){
            throw new NativeError('crypto_relocation_capacity',409);
        }
        if(!empty($p['batch']['exportBindings'])||!empty($p['batch']['tableLeases'])){
            throw new NativeError('crypto_relocation_batch_binding',409);
        }
        $entries=(new NativeCryptoRecordProofV2($this->container))->parseBatch($p['batch'],$command,$key);
        $batchHash=$this->hash($p['batch']);
        $saved=$this->one('SELECT batch_hash FROM familyhub_crypto_project_relocation_batches_v2 WHERE action_id=? AND batch_id=?',[$action,$p['batch']['batchId']]);
        if($saved){
            if($saved['batch_hash']!==$batchHash)throw new NativeError('crypto_relocation_batch_immutable',409);
            return ['staged'=>true,'batchId'=>$p['batch']['batchId']];
        }
        $encodedBatch=json_encode($p['batch'],JSON_THROW_ON_ERROR);
        $usage=$this->one('SELECT COALESCE(SUM(LENGTH(authorization)),0) AS bytes FROM familyhub_crypto_project_relocation_batches_v2 WHERE action_id=?',[$action]);
        if((int)$usage['bytes']>self::MAX_STAGE_BYTES-strlen($encodedBatch))throw new NativeError('crypto_relocation_capacity',409);
        $bindings=[];
        foreach($p['bindings'] as $binding){
            $this->fields($binding,['sourceWireId','targetWireId']);
            NativeCryptoRecordAddressV2::wireId($binding['sourceWireId']);NativeCryptoRecordAddressV2::wireId($binding['targetWireId']);
            if(isset($bindings[$binding['targetWireId']]))throw new NativeError('crypto_relocation_duplicate',409);
            $bindings[$binding['targetWireId']]=$binding['sourceWireId'];
        }
        $descriptors=[];
        foreach($verified['descriptors'] as $descriptor)$descriptors[$descriptor['wireId']]=$descriptor;
        $parsed=[];
        foreach($entries as $entry){
            $r=$entry['record'];$tag=$r['metadata']['projectRelocation']??null;
            if(!$tag||$tag['actionId']!==$action||$tag['planHash']!==$p['planHash'])throw new NativeError('crypto_relocation_tag',409);
            $side=$tag['side'];$sourceId=$side==='source'?$r['id']:($bindings[$r['id']]??null);
            if($side==='source'&&$r['type']==='scopeMetadata'){
                if($r['scopeId']!==$plan['sourceScopeId']||$r['deleted']||$r['expectedRevision']<1||$r['previousRecordHash']!==$plan['parentMetadataProofHash']||$r['metadata']['identity']['canonicalId']!==NativeCryptoReservedRecordV2::derive($this->serverId(),$plan['sourceScopeId'],'scopeMetadata'))throw new NativeError('crypto_relocation_parent_metadata',409);
                $sourceId=null;$logical=$r['expectedRevision']+1;
            }elseif($side==='target'&&$r['type']==='scopeMetadata'){
                if($sourceId!==null||$r['scopeId']!==$plan['targetScopeId']||$r['deleted']||$r['metadata']['identity']['canonicalId']!==NativeCryptoReservedRecordV2::derive($this->serverId(),$plan['targetScopeId'],'scopeMetadata'))throw new NativeError('crypto_relocation_metadata_binding',409);
                $logical=1;
            }else{
                $source=$descriptors[$sourceId]??null;
                if(!$source||$source['type']!==$r['type']||$source['domain']!==$r['domain'])throw new NativeError('crypto_relocation_record_binding',409);
                $logical=$source['logicalRevision']+($side==='source'?1:0);
                if($logical>9007199254740991||$source['revision']>=9007199254740991)throw new NativeError('crypto_relocation_revision_exhausted',409);
                if($side==='source'){
                    if($r['scopeId']!==$plan['sourceScopeId']||!$r['deleted']||$r['expectedRevision']!==$source['revision']||$r['previousRecordHash']!==$source['recordProofHash'])throw new NativeError('crypto_relocation_source_changed',409);
                }elseif($r['scopeId']!==$plan['targetScopeId']||$r['expectedRevision']!==0||$r['deleted']!==$source['deleted']){
                    throw new NativeError('crypto_relocation_target_binding',409);
                }
                // Scope-reserved technical companions are explicitly mapped by
                // the manager. Ordinary canonical business identities persist.
                if(!in_array($r['type'],['taskDerivationIntent','taskDerivationResolution'],true)&&$r['metadata']['identity']['canonicalId']!==$source['id'])throw new NativeError('crypto_relocation_identity_changed',409);
            }
            $existing=$this->one('SELECT record_proof_hash FROM familyhub_crypto_project_relocation_staged_v2 WHERE action_id=? AND scope_id=? AND wire_id=?',[$action,$r['scopeId'],$r['id']]);
            if($existing)throw new NativeError('crypto_relocation_record_immutable',409);
            $parsed[]=['entry'=>$entry,'source'=>$sourceId,'logical'=>$logical];
        }
        if(count($bindings)!==count(array_filter($parsed,fn($e)=>$e['entry']['record']['metadata']['projectRelocation']['side']==='target'&&$e['source']!==null))){
            throw new NativeError('crypto_relocation_binding_extras',409);
        }
        // Validate exact target head/epoch/current actor authority while the
        // target is still invisible. Full reference overlay is checked at final.
        $this->api()->withTarget($action,$p['planHash'],$actor,function($row,$plan,$scope)use($parsed,$actor){
            $heads=new NativeCryptoScopeV2($this->container,$this->bearer,$this->ip);
            foreach($parsed as $item){$r=$item['entry']['record'];$heads->author($r['scopeId'],$r['membershipHeadHash'],$r['epoch'],$r['accessRevision'],$actor,$r['domain']);}
        });
        $this->change('INSERT INTO familyhub_crypto_project_relocation_batches_v2(action_id,batch_id,batch_hash,authorization,stage_authorization) VALUES(?,?,?,?,?)',[$action,$p['batch']['batchId'],$batchHash,$encodedBatch,json_encode($proof,JSON_THROW_ON_ERROR)]);
        foreach($parsed as $item){$e=$item['entry'];$r=$e['record'];
            $this->change('INSERT INTO familyhub_crypto_project_relocation_staged_v2(action_id,scope_id,wire_id,source_wire_id,side,logical_revision,record_proof_hash,batch_id) VALUES(?,?,?,?,?,?,?,?)',[$action,$r['scopeId'],$r['id'],$item['source'],$r['metadata']['projectRelocation']['side'],$item['logical'],$e['recordProofHash'],$p['batch']['batchId']]);
        }
        return ['staged'=>true,'batchId'=>$p['batch']['batchId']];
    }

    public function blob($p,$actor,$proof,$command,$key)
    {
        $this->fields($p,['actionId','planHash','authorization']);
        [$nested,$bytes,$signature]=NativeCryptoCodec::decode($p['authorization']);
        $this->fields($nested,['version','operation','requestId','serverId','accountId','deviceId','signer','payload']);
        if($nested['version']!==2||!in_array($nested['operation'],['crypto2.blob.begin','crypto2.blob.chunk','crypto2.blob.complete'],true)||$nested['serverId']!==$command['serverId']||$nested['accountId']!==$command['accountId']||$nested['deviceId']!==$command['deviceId']||$nested['signer']!=='device')throw new NativeError('crypto_relocation_blob_command',409);
        $this->uuid($nested['requestId']);NativeCryptoV2Codec::verify($bytes,$signature,$key);
        $action=$this->uuid($p['actionId']);$id=$this->uuid($nested['payload']['id']??null);$operation=$nested['operation'];
        if($operation==='crypto2.blob.begin'&&!$this->one('SELECT id FROM familyhub_crypto_project_relocation_blobs_v2 WHERE action_id=? AND id=?',[$action,$id])){
            $objects=$this->many('SELECT descriptor FROM familyhub_crypto_project_relocation_blobs_v2 WHERE action_id=? LIMIT 1001',[$action]);
            $bytes=0;foreach($objects as $object){$d=json_decode($object['descriptor'],true,34,JSON_THROW_ON_ERROR);$bytes+=(int)$d['size'];}
            $size=$nested['payload']['size']??null;
            if(count($objects)>=1000||!is_int($size)||$size<48||$size>NativeCryptoStorageV2::MAX_BLOB||$bytes>536870912-$size)throw new NativeError('crypto_relocation_capacity',409);
        }
        $result=$this->api()->withTarget($action,$p['planHash'],$actor,function($row,$plan,$scope)use($nested,$p,$id,$actor,$operation){
            if(($nested['payload']['scopeId']??null)!==$plan['targetScopeId'])throw new NativeError('crypto_relocation_blob_command',409);
            $saved=$this->one('SELECT descriptor FROM familyhub_crypto_project_relocation_blobs_v2 WHERE action_id=? AND id=?',[$row['action_id'],$id]);
            if($saved){$values=json_decode($saved['descriptor'],true,34,JSON_THROW_ON_ERROR);$this->insertBlobRow('familyhub_crypto_blobs_v2',$values);}
            if($operation!=='crypto2.blob.begin'){
                $suffix=$operation==='crypto2.blob.chunk'?' AND chunk_offset=?':'';
                $args=[$row['action_id'],$id];if($suffix)$args[]=$nested['payload']['offset']??null;
                foreach($this->many('SELECT chunk_offset,data FROM familyhub_crypto_project_relocation_blob_chunks_v2 WHERE action_id=? AND blob_id=?'.$suffix.' ORDER BY chunk_offset',$args) as $chunk){$this->change('INSERT INTO familyhub_crypto_blob_chunks_v2 VALUES(?,?,?,?)',[$plan['targetScopeId'],$id,$chunk['chunk_offset'],$chunk['data']]);}
            }
            $response=(new NativeCryptoStorageV2($this->container,$this->bearer,$this->ip))->write($operation,$nested['payload'],$actor,$p['authorization'],$nested,null);
            $descriptor=$this->one('SELECT * FROM familyhub_crypto_blobs_v2 WHERE scope_id=? AND id=?',[$plan['targetScopeId'],$id]);
            return ['response'=>$response,'descriptor'=>$descriptor];
        });
        $encoded=NativeCryptoCodec::canonical((object)$result['descriptor']);
        $saved=$this->one('SELECT id FROM familyhub_crypto_project_relocation_blobs_v2 WHERE action_id=? AND id=?',[$action,$id]);
        if($saved)$this->change('UPDATE familyhub_crypto_project_relocation_blobs_v2 SET descriptor=? WHERE action_id=? AND id=?',[$encoded,$action,$id]);
        else $this->change('INSERT INTO familyhub_crypto_project_relocation_blobs_v2(action_id,id,descriptor) VALUES(?,?,?)',[$action,$id,$encoded]);
        if($operation==='crypto2.blob.chunk'){
            $offset=$nested['payload']['offset'];$data=$nested['payload']['dataBase64'];
            $old=$this->one('SELECT data FROM familyhub_crypto_project_relocation_blob_chunks_v2 WHERE action_id=? AND blob_id=? AND chunk_offset=?',[$action,$id,$offset]);
            if($old&&$old['data']!==$data)throw new NativeError('crypto_blob_chunk_conflict',409);
            if(!$old)$this->change('INSERT INTO familyhub_crypto_project_relocation_blob_chunks_v2 VALUES(?,?,?,?)',[$action,$id,$offset,$data]);
        }
        return ['candidate'=>true,'result'=>$result['response']];
    }

    private function insertBlobRow($table,$values)
    {
        $allowed=['scope_id','id','head_hash','domain','owner_account_id','epoch','size','sha256','manifest','authorization','received','complete'];
        $keys=array_keys($values);sort($keys);$expected=$allowed;sort($expected);
        if($keys!==$expected)throw new NativeError('crypto_relocation_blob_descriptor',409);
        $this->change('INSERT INTO '.$table.'('.implode(',',$allowed).') VALUES('.implode(',',array_fill(0,count($allowed),'?')).')',array_map(fn($k)=>$values[$k],$allowed));
    }

    /** Reconstruct the complete immutable proof set before any final effect.
     * Counts are derived from signed source descriptors, never supplied totals. */
    public function prepareInstall($actionId,$planHash,$actor,$command,$key)
    {
        if(!$this->transactionActive())throw new NativeError('crypto_relocation_transaction',409);
        $verified=$this->api()->validateSources($actionId,$actor);
        $row=$verified['plan'];$plan=$verified['body'];
        if($row['plan_hash']!==$planHash)throw new NativeError('crypto_relocation_plan',409);
        $sources=[];foreach($verified['descriptors'] as $d)$sources[$d['wireId']]=$d;
        $groups=[];$all=[];$leaves=['source'=>[],'target'=>[]];$batches=['source'=>[],'target'=>[]];
        $sourceCoverage=[];$targetCoverage=[];$blobIds=[];$metadataCount=0;$parentMetadataCount=0;$originalReminderStates=[];
        $usage=$this->one('SELECT COALESCE(SUM(LENGTH(authorization)),0) AS bytes FROM familyhub_crypto_project_relocation_batches_v2 WHERE action_id=?',[$actionId]);
        if((int)$usage['bytes']>self::MAX_STAGE_BYTES)throw new NativeError('crypto_relocation_capacity',409);
        foreach($this->many('SELECT * FROM familyhub_crypto_project_relocation_batches_v2 WHERE action_id=? ORDER BY batch_id',[$actionId]) as $batch){
            $payload=json_decode($batch['authorization'],true,34,JSON_THROW_ON_ERROR);
            if($this->hash($payload)!==$batch['batch_hash'])throw new NativeError('crypto_relocation_batch_immutable',409);
            $entries=(new NativeCryptoRecordProofV2($this->container))->parseBatch($payload,$command,$key);$sides=[];
            foreach($entries as $entry){
                $r=$entry['record'];$tag=$r['metadata']['projectRelocation']??null;
                if(!$tag||$tag['actionId']!==$actionId||$tag['planHash']!==$planHash||isset($all[$r['scopeId'].':'.$r['id']]))throw new NativeError('crypto_relocation_record_binding',409);
                $side=$tag['side'];$sides[$side]=true;
                if($r['scopeId']!==$plan[$side==='source'?'sourceScopeId':'targetScopeId'])throw new NativeError('crypto_relocation_record_binding',409);
                $staged=$this->one('SELECT * FROM familyhub_crypto_project_relocation_staged_v2 WHERE action_id=? AND scope_id=? AND wire_id=?',[$actionId,$r['scopeId'],$r['id']]);
                if(!$staged||$staged['batch_id']!==$payload['batchId']||$staged['record_proof_hash']!==$entry['recordProofHash']||$staged['side']!==$side)throw new NativeError('crypto_relocation_record_immutable',409);
                $sourceId=$staged['source_wire_id'];
                if($sourceId===null){
                    if($r['type']!=='scopeMetadata'||$r['deleted'])throw new NativeError('crypto_relocation_metadata_binding',409);
                    if($side==='target'){
                        if(++$metadataCount!==1||$r['expectedRevision']!==0)throw new NativeError('crypto_relocation_metadata_binding',409);
                    }else{
                        if(++$parentMetadataCount!==1||$r['previousRecordHash']!==$plan['parentMetadataProofHash']||$r['expectedRevision']<1||(int)$staged['logical_revision']!==$r['expectedRevision']+1)throw new NativeError('crypto_relocation_parent_metadata',409);
                    }
                }else{
                    if(!isset($sources[$sourceId]))throw new NativeError('crypto_relocation_record_binding',409);
                    $d=$sources[$sourceId];$coverage=&$sourceCoverage;if($side==='target')$coverage=&$targetCoverage;
                    if(isset($coverage[$sourceId]))throw new NativeError('crypto_relocation_duplicate',409);$coverage[$sourceId]=true;unset($coverage);
                    if($r['type']!==$d['type']||$r['domain']!==$d['domain']||
                        ($side==='source'&&(!$r['deleted']||$r['id']!==$d['wireId']||$r['expectedRevision']!==$d['revision']||$r['previousRecordHash']!==$d['recordProofHash']))||
                        ($side==='target'&&($r['expectedRevision']!==0||$r['deleted']!==$d['deleted']))||
                        (int)$staged['logical_revision']!==$d['logicalRevision']+($side==='source'?1:0))throw new NativeError('crypto_relocation_source_changed',409);
                    if(!in_array($r['type'],['taskDerivationIntent','taskDerivationResolution'],true)&&$r['metadata']['identity']['canonicalId']!==$d['id'])throw new NativeError('crypto_relocation_identity_changed',409);
                    if($side==='target'&&isset($r['metadata']['reminderState'])){
                        $sourceRow=$this->one('SELECT authorization FROM familyhub_crypto_records WHERE scope_id=? AND id=?',[$plan['sourceScopeId'],$sourceId]);
                        $sourceProof=json_decode($sourceRow['authorization'],true,34,JSON_THROW_ON_ERROR)['recordProof'];
                        if($this->hash($sourceProof)!==$d['recordProofHash'])throw new NativeError('project_sharing_preview_changed',409);
                        [$sourceBody]=NativeCryptoCodec::decode($sourceProof);
                        $original=$sourceBody['metadata']['reminderState']??null;
                        if($original===null||NativeCryptoCodec::canonical((object)$original)!==NativeCryptoCodec::canonical((object)$r['metadata']['reminderState'])||isset($r['metadata']['schedulingUse']))throw new NativeError('crypto_relocation_schedule_changed',409);
                        $originalReminderStates[$r['scopeId'].':'.$r['id']]=$original;
                    }

                }
                // A child publication cannot smuggle a raw private parent ref.
                foreach($r['metadata']['references'] as $ref)if($ref['scopeId']!==$r['scopeId'])throw new NativeError('crypto_relocation_private_reference',409);
                foreach($side==='target'?$r['metadata']['blobIds']:[] as $id)$blobIds[$id]=true;
                $all[$r['scopeId'].':'.$r['id']]=$entry;
                $leaves[$side][]=['id'=>$r['id'],'type'=>$r['type'],'domain'=>$r['domain'],'recordProofHash'=>$entry['recordProofHash'],'logicalRevision'=>(int)$staged['logical_revision']];
            }
            $digest=$this->hash($payload['commitment']);foreach(array_keys($sides) as $side)$batches[$side][]=$digest;
            $groups[]=$payload;
        }
        if(count($sourceCoverage)!==count($sources)||count($targetCoverage)!==count($sources)||$metadataCount!==1||$parentMetadataCount!==1||count($groups)>2*NativeCryptoProjectRelocationCodecV2::MAX_RECORDS+1)throw new NativeError('crypto_relocation_stage_incomplete',409);
        $stored=(int)$this->one('SELECT COUNT(*) AS n FROM familyhub_crypto_project_relocation_staged_v2 WHERE action_id=?',[$actionId])['n'];
        if($stored!==count($all))throw new NativeError('crypto_relocation_stage_incomplete',409);
        foreach(['source','target'] as $side){usort($leaves[$side],fn($a,$b)=>strcmp($a['id'],$b['id']));sort($batches[$side],SORT_STRING);}
        return $verified+['groups'=>$groups,'entries'=>$all,'leaves'=>$leaves,'batchDigests'=>$batches,'blobIds'=>array_keys($blobIds),'originalReminderStates'=>$originalReminderStates];
    }

    /** SQL-only immutable copy after target activation in the SAME final TX.
     * Source objects are retained for their signed historical record proofs. */
    public function installBlobs($prepared,$actor)
    {
        if(!$this->transactionActive())throw new NativeError('crypto_relocation_transaction',409);
        $action=$prepared['plan']['action_id'];$scope=$prepared['body']['targetScopeId'];$required=array_fill_keys($prepared['blobIds'],true);
        $bytes=0;$count=0;
        foreach($this->many('SELECT id,descriptor FROM familyhub_crypto_project_relocation_blobs_v2 WHERE action_id=? ORDER BY id',[$action]) as $item){
            $d=json_decode($item['descriptor'],true,34,JSON_THROW_ON_ERROR);
            if(!isset($required[$item['id']])||$d['scope_id']!==$scope||$d['id']!==$item['id']||$d['owner_account_id']!==$actor['user']['account_id']||(int)$d['complete']!==1||(int)$d['received']!==(int)$d['size'])throw new NativeError('crypto_relocation_blob_incomplete',409);
            $bytes+=(int)$d['size'];$count++;
            $h=hash_init('sha256');$offset=0;
            foreach($this->many('SELECT chunk_offset,data FROM familyhub_crypto_project_relocation_blob_chunks_v2 WHERE action_id=? AND blob_id=? ORDER BY chunk_offset',[$action,$item['id']]) as $chunk){
                $data=NativeCryptoCodec::base64($chunk['data'],NativeCryptoStorage::CHUNK);
                if((int)$chunk['chunk_offset']!==$offset||!strlen($data)||$offset+strlen($data)>(int)$d['size']||$offset+strlen($data)<(int)$d['size']&&strlen($data)!==NativeCryptoStorage::CHUNK)throw new NativeError('crypto_blob_incomplete',409);
                hash_update($h,$data);$offset+=strlen($data);
                $this->change('INSERT INTO familyhub_crypto_blob_chunks_v2 VALUES(?,?,?,?)',[$scope,$item['id'],$chunk['chunk_offset'],$chunk['data']]);
            }
            if($offset!==(int)$d['size']||hash_final($h)!==$d['sha256'])throw new NativeError('crypto_blob_integrity',409);
            $this->insertBlobRow('familyhub_crypto_blobs_v2',$d);unset($required[$item['id']]);
        }
        if($required)throw new NativeError('crypto_blob_incomplete',409);
        $scopeBytes=defined('FAMILYHUB_CRYPTO_MAX_SCOPE_BYTES')?FAMILYHUB_CRYPTO_MAX_SCOPE_BYTES:536870912;
        $scopeObjects=defined('FAMILYHUB_CRYPTO_MAX_SCOPE_OBJECTS')?FAMILYHUB_CRYPTO_MAX_SCOPE_OBJECTS:1000;
        $accountBytes=defined('FAMILYHUB_CRYPTO_MAX_ACCOUNT_BYTES')?FAMILYHUB_CRYPTO_MAX_ACCOUNT_BYTES:2147483648;
        $accountObjects=defined('FAMILYHUB_CRYPTO_MAX_ACCOUNT_OBJECTS')?FAMILYHUB_CRYPTO_MAX_ACCOUNT_OBJECTS:10000;
        foreach([$scopeBytes,$scopeObjects,$accountBytes,$accountObjects] as $limit)if(!is_int($limit)||$limit<1||$limit>9007199254740991)throw new NativeError('crypto_storage_budget_unavailable',503);
        $usage=$this->one('SELECT COUNT(*) AS n,COALESCE(SUM(size),0) AS bytes FROM familyhub_crypto_blobs_v2 WHERE owner_account_id=? AND complete>=0',[$actor['user']['account_id']]);
        if($bytes>$scopeBytes||$count>$scopeObjects||(int)$usage['n']>$accountObjects||(int)$usage['bytes']>$accountBytes)throw new NativeError('crypto_storage_quota',409);
    }
}
