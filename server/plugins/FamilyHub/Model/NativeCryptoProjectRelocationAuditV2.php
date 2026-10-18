<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** Manager-attested encrypted audit snapshots. Original signed source history
 * remains private in its original scope; a transformed snapshot never claims
 * to be a new signature by the original historical actor. */
class NativeCryptoProjectRelocationAuditV2 extends NativeDatabase
{
    protected $cryptoAccess=true;
    const DOMAIN="JivieProjectRelocationAudit/v2\n";
    private const MAX_BYTES=33554432;
    private function hash($v){return NativeCryptoProjectRelocationCodecV2::hash($v);}
    private function token($action,$target,$sourceHash)
    {
        return hash('sha256',"JivieProjectRelocationAuditSource/v2\n".NativeCryptoCodec::canonical((object)['version'=>2,'serverId'=>$this->serverId(),'actionId'=>$action,'scopeId'=>$target,'sourceEvidenceHash'=>$sourceHash]));
    }

    private function recordSources($scope,$descriptor,$actor)
    {
        if(NativeCryptoRecordAddressV2::sourceKind($descriptor['type'])!=='finance_records')return [];
        $head=new NativeCryptoScopeV2($this->container,$this->bearer,$this->ip);
        $s=$this->scope($scope,$actor['user']['id'],true,true);$h=$head->current($scope);
        if(!$h)throw new NativeError('crypto_scope_head_missing',409);
        $head->manager($h,$s,$actor);$head->author($scope,$h['head_hash'],(int)$h['epoch'],(int)$s['effective_access_revision'],$actor,'finance');
        $current=$this->one('SELECT authorization,revision,type FROM familyhub_crypto_records WHERE scope_id=? AND id=?',[$scope,$descriptor['wireId']]);
        if(!$current||$current['type']!==$descriptor['type']||(int)$current['revision']!==$descriptor['revision'])throw new NativeError('project_sharing_preview_changed',409);
        $authorization=json_decode($current['authorization'],true,34,JSON_THROW_ON_ERROR);
        if($this->hash($authorization['recordProof'])!==$descriptor['recordProofHash'])throw new NativeError('project_sharing_preview_changed',409);
        $out=[];$expected=$descriptor['recordProofHash'];$revision=$descriptor['revision'];$migrationBaseline=null;
        while($revision>0){
            $row=$this->one("SELECT record_proof,record_proof_hash FROM familyhub_crypto_record_history WHERE scope_id=? AND domain='finance' AND id=? AND revision=?",[$scope,$descriptor['wireId'],$revision]);
            if(!$row||$row['record_proof_hash']!==$expected)throw new NativeError('crypto_record_chain',409);
            $proof=json_decode($row['record_proof'],true,34,JSON_THROW_ON_ERROR);[$body]=NativeCryptoCodec::decode($proof);
            if($this->hash($proof)!==$expected||$body['expectedRevision']!==$revision-1||$body['scopeId']!==$scope||$body['id']!==$descriptor['wireId']||$body['type']!==$descriptor['type'])throw new NativeError('crypto_record_chain',409);
            $baseline=$revision===1&&(isset($body['metadata']['migrationOrigin'])||($body['metadata']['projectRelocation']['side']??null)==='target');
            if($revision===1&&isset($body['metadata']['migrationOrigin']))$migrationBaseline=$body['metadata']['migrationOrigin'];
            if(!$baseline)$out[]=['sourceEvidenceHash'=>$expected,'revisionNamespace'=>'crypto','revision'=>$revision,'sourceWireId'=>$descriptor['wireId']];
            if(count($out)>10000)throw new NativeError('crypto_relocation_capacity',409);
            $expected=$body['previousRecordHash'];$revision--;
        }
        if($expected!==NativeCryptoDirectoryV2::ZERO)throw new NativeError('crypto_record_chain',409);
        if($migrationBaseline!==null){
            $installed=$this->one("SELECT a.migration_id FROM familyhub_crypto_migration_activations_v3 a JOIN familyhub_crypto_scopes s ON s.scope_id=a.scope_id AND s.migration_id=a.migration_id WHERE a.scope_id=? AND a.migration_id=? AND a.state='committed'",[$scope,$migrationBaseline['migrationId']]);
            if(!$installed)throw new NativeError('crypto_migration_audit_provenance_pending',409);
        }
        if($migrationBaseline!==null)foreach((new NativeCryptoMigrationAuditReadV3($this->container,$this->bearer,$this->ip))->committedDescriptors($scope,$descriptor['id'],$actor) as $legacy){
            $out[]=['sourceEvidenceHash'=>$legacy['sourceEvidenceHash'],'revisionNamespace'=>'legacy','revision'=>$legacy['revision'],'sourceWireId'=>$descriptor['wireId']];
            if(count($out)>10000)throw new NativeError('crypto_relocation_capacity',409);
        }
        return $out;
    }

    /** Pre-prepare own manager discovery. Returned hashes are only candidates;
     * the client verifies the matching ordinary/scoped audit stream itself. */
    public function sources($p,$actor)
    {
        $this->fields($p,['scopeId','descriptor'],['afterHash','limit']);
        $scope=$this->uuid($p['scopeId']);NativeCryptoProjectRelocationCodecV2::sourceDescriptor($p['descriptor']);
        $items=$this->recordSources($scope,$p['descriptor'],$actor);
        usort($items,fn($a,$b)=>strcmp($a['sourceEvidenceHash'],$b['sourceEvidenceHash']));
        $after=$p['afterHash']??'';if($after!=='')NativeCryptoProjectRelocationCodecV2::digest($after);
        $limit=$p['limit']??50;if(!is_int($limit)||$limit<1||$limit>50)throw new NativeError('validation_error');
        $items=array_values(array_filter($items,fn($v)=>strcmp($v['sourceEvidenceHash'],$after)>0));$more=count($items)>$limit;$items=array_slice($items,0,$limit);
        return ['entries'=>$items,'hasMore'=>$more,'nextAfterHash'=>$items?end($items)['sourceEvidenceHash']:$after];
    }
    private function sourceSet($prepared,$actor)
    {
        $out=[];
        foreach($prepared['descriptors'] as $descriptor){
            foreach($this->recordSources($prepared['body']['sourceScopeId'],$descriptor,$actor) as $entry){
                if(isset($out[$entry['sourceEvidenceHash']])||count($out)>=10000)throw new NativeError('crypto_relocation_capacity',409);
                $out[$entry['sourceEvidenceHash']]=$entry;
            }
        }
        ksort($out,SORT_STRING);
        if(count($out)!==$prepared['body']['sourceAuditCount']||NativeCryptoProjectRelocationCodecV2::digestRoot('audit',array_keys($out),10000)!==$prepared['body']['sourceAuditRoot'])throw new NativeError('project_sharing_preview_changed',409);
        return $out;
    }
    private function snapshot($body,$prepared,$source,$target,$actor)
    {
        $this->fields($body,['version','operation','serverId','scopeId','actionId','planHash','sourceToken','recordId','epoch','membershipHeadHash','accessRevision','blobIds','envelopeBase64','accountId','deviceId','authorDirectoryHeadHash']);
        $expected=['version'=>2,'operation'=>'crypto2.projectRelocation.auditSnapshot','serverId'=>$this->serverId(),
            'scopeId'=>$prepared['body']['targetScopeId'],'actionId'=>$prepared['plan']['action_id'],'planHash'=>$prepared['plan']['plan_hash'],
            'sourceToken'=>$this->token($prepared['plan']['action_id'],$prepared['body']['targetScopeId'],$source['sourceEvidenceHash']),
            'recordId'=>$target['id'],'accountId'=>$actor['user']['account_id'],'deviceId'=>$actor['device']['id']];
        foreach($expected as $field=>$value)if($body[$field]!==$value)throw new NativeError('crypto_relocation_audit_binding',409);
        $targetRecord=$prepared['entries'][$body['scopeId'].':'.$target['id']]['record']??null;
        if(!$targetRecord||$targetRecord['domain']!=='finance'||$body['epoch']!==$targetRecord['epoch']||
            $body['membershipHeadHash']!==$targetRecord['membershipHeadHash']||$body['accessRevision']!==$targetRecord['accessRevision'])throw new NativeError('crypto_relocation_audit_binding',409);
        if(!is_int($body['epoch'])||$body['epoch']<1||!is_int($body['accessRevision'])||$body['accessRevision']<0||!is_array($body['blobIds'])||!array_is_list($body['blobIds'])||count($body['blobIds'])>4)throw new NativeError('validation_error');
        NativeCryptoProjectRelocationCodecV2::digest($body['membershipHeadHash']);
        foreach($body['blobIds'] as $id){
            $this->uuid($id);$blob=$this->one('SELECT descriptor FROM familyhub_crypto_project_relocation_blobs_v2 WHERE action_id=? AND id=?',[$prepared['plan']['action_id'],$id]);
            $blob=$blob?json_decode($blob['descriptor'],true,34,JSON_THROW_ON_ERROR):null;
            if(!$blob||$blob['scope_id']!==$body['scopeId']||$blob['domain']!=='finance'||(int)$blob['complete']!==1||$blob['head_hash']!==$body['membershipHeadHash']||(int)$blob['epoch']!==$body['epoch'])throw new NativeError('crypto_relocation_audit_cipher_pending',409);
        }
        if(count(array_unique($body['blobIds']))!==count($body['blobIds'])||strlen(NativeCryptoCodec::base64($body['envelopeBase64'],196608))<48)throw new NativeError('crypto_relocation_audit_binding',409);
        (new NativeCryptoScopeV2($this->container,$this->bearer,$this->ip))->currentAuthorReference($body['authorDirectoryHeadHash'],$actor);
    }
    public function stage($p,$actor,$proof,$command,$key)
    {
        $this->fields($p,['actionId','planHash','snapshots']);
        if(!is_array($p['snapshots'])||!array_is_list($p['snapshots'])||!$p['snapshots']||count($p['snapshots'])>32)throw new NativeError('validation_error');
        $prepared=(new NativeCryptoProjectRelocationStageV2($this->container,$this->bearer,$this->ip))->prepareInstall($p['actionId'],$p['planHash'],$actor,$command,$key);
        $sources=$this->sourceSet($prepared,$actor);$targets=[];
        foreach($prepared['leaves']['target'] as $leaf){$row=$this->one('SELECT source_wire_id FROM familyhub_crypto_project_relocation_staged_v2 WHERE action_id=? AND scope_id=? AND wire_id=?',[$p['actionId'],$prepared['body']['targetScopeId'],$leaf['id']]);if($row['source_wire_id']!==null)$targets[$row['source_wire_id']]=$leaf;}
        foreach($p['snapshots'] as $item){
            $this->fields($item,['sourceEvidenceHash','authorization']);$source=$sources[$item['sourceEvidenceHash']]??null;
            if(!$source)throw new NativeError('crypto_relocation_audit_source',409);
            [$body,$bytes,$signature]=NativeCryptoCodec::decode($item['authorization']);
            $this->snapshot($body,$prepared,$source,$targets[$source['sourceWireId']],$actor);NativeCryptoV2Codec::verify($bytes,$signature,$key,self::DOMAIN);
            $encoded=json_encode($item['authorization'],JSON_THROW_ON_ERROR);$hash=$this->hash($item['authorization']);
            $old=$this->one('SELECT proof_hash FROM familyhub_crypto_project_relocation_audit_v2 WHERE action_id=? AND source_evidence_hash=?',[$p['actionId'],$item['sourceEvidenceHash']]);
            if($old){if($old['proof_hash']!==$hash)throw new NativeError('crypto_relocation_audit_immutable',409);continue;}
            $usage=$this->one('SELECT COALESCE(SUM(LENGTH(authorization)),0) AS bytes FROM familyhub_crypto_project_relocation_audit_v2 WHERE action_id=?',[$p['actionId']]);
            if((int)$usage['bytes']>self::MAX_BYTES-strlen($encoded))throw new NativeError('crypto_relocation_capacity',409);
            $this->change('INSERT INTO familyhub_crypto_project_relocation_audit_v2(action_id,source_evidence_hash,scope_id,record_id,source_token,proof_hash,authorization,state) VALUES(?,?,?,?,?,?,?,?)',[$p['actionId'],$source['sourceEvidenceHash'],$body['scopeId'],$body['recordId'],$body['sourceToken'],$hash,$encoded,'staged']);
        }
        return ['staged'=>true];
    }

    public function prepareInstall($prepared,$actor,$command,$key)
    {
        $sources=$this->sourceSet($prepared,$actor);$hashes=[];$rows=[];$blobIds=[];
        foreach($this->many('SELECT * FROM familyhub_crypto_project_relocation_audit_v2 WHERE action_id=? ORDER BY source_evidence_hash',[$prepared['plan']['action_id']]) as $row){
            $source=$sources[$row['source_evidence_hash']]??null;if(!$source)throw new NativeError('crypto_relocation_audit_source',409);
            $target=$this->one('SELECT wire_id FROM familyhub_crypto_project_relocation_staged_v2 WHERE action_id=? AND side=? AND source_wire_id=?',[$prepared['plan']['action_id'],'target',$source['sourceWireId']]);
            if(!$target)throw new NativeError('crypto_relocation_audit_source',409);
            $proof=json_decode($row['authorization'],true,34,JSON_THROW_ON_ERROR);[$body,$bytes,$signature]=NativeCryptoCodec::decode($proof);
            $this->snapshot($body,$prepared,$source,['id'=>$target['wire_id']],$actor);
            NativeCryptoV2Codec::verify($bytes,$signature,$key,self::DOMAIN);
            if($this->hash($proof)!==$row['proof_hash'])throw new NativeError('crypto_relocation_audit_immutable',409);
            $hashes[]=$row['proof_hash'];$rows[]=$row;foreach($body['blobIds'] as $id)$blobIds[$id]=true;
        }
        if(count($rows)!==count($sources))throw new NativeError('crypto_relocation_audit_incomplete',409);
        sort($hashes,SORT_STRING);
        return ['root'=>NativeCryptoProjectRelocationCodecV2::digestRoot('audit',$hashes,10000),'count'=>count($rows),'rows'=>$rows,'blobIds'=>array_keys($blobIds)];
    }
    public function install($prepared)
    {
        if(!$this->transactionActive())throw new NativeError('crypto_relocation_transaction',409);
        foreach($prepared['rows'] as $row)$this->change("UPDATE familyhub_crypto_project_relocation_audit_v2 SET state='committed' WHERE action_id=? AND source_evidence_hash=?",[$row['action_id'],$row['source_evidence_hash']]);
    }

    /** Full target-finance stream proves absence of omitted record snapshots
     * without revealing a foreign scope, original proof body or private plan. */
    public function read($p,$actor)
    {
        $this->fields($p,['scopeId'],['afterHash','limit']);$scope=$this->uuid($p['scopeId']);
        $s=$this->scope($scope,$actor['user']['id']);$api=new NativeCryptoScopeV2($this->container,$this->bearer,$this->ip);$head=$api->current($scope);
        if(!$head)throw new NativeError('crypto_scope_head_missing',409);
        $api->author($scope,$head['head_hash'],(int)$head['epoch'],(int)$s['effective_access_revision'],$actor,'finance',false);
        $publication=$this->one("SELECT * FROM familyhub_crypto_project_relocation_publications_v2 WHERE scope_id=? AND side='target'",[$scope]);
        if(!$publication)return ['scopeId'=>$scope,'publication'=>null,'proofs'=>[],'hasMore'=>false,'nextAfterHash'=>null];
        $after=$p['afterHash']??'';if($after!=='')NativeCryptoProjectRelocationCodecV2::digest($after);
        $limit=$p['limit']??20;if(!is_int($limit)||$limit<1||$limit>20)throw new NativeError('validation_error');
        $rows=$this->many("SELECT proof_hash,authorization FROM familyhub_crypto_project_relocation_audit_v2 WHERE action_id=? AND scope_id=? AND state='committed' AND proof_hash>? ORDER BY proof_hash LIMIT ".($limit+1),[$publication['action_id'],$scope,$after]);
        $more=count($rows)>$limit;$proofs=[];$size=0;
        foreach(array_slice($rows,0,$limit) as $row){
            if($size+strlen($row['authorization'])>1048576){$more=true;break;}
            $proof=json_decode($row['authorization'],true,34,JSON_THROW_ON_ERROR);
            if($this->hash($proof)!==$row['proof_hash'])throw new NativeError('crypto_relocation_audit_immutable',409);
            $proofs[]=$proof;$size+=strlen($row['authorization']);$after=$row['proof_hash'];
        }
        return ['scopeId'=>$scope,'publication'=>json_decode($publication['authorization'],true,34,JSON_THROW_ON_ERROR),
            'eventAuthorization'=>json_decode($publication['event_authorization'],true,34,JSON_THROW_ON_ERROR),
            'eventHeadHash'=>$publication['event_head_hash'],'eventCommandHash'=>$publication['event_command_hash'],
            'otherPublicationHash'=>$publication['other_publication_hash'],'proofs'=>$proofs,'hasMore'=>$more,'nextAfterHash'=>$after];
    }
}
