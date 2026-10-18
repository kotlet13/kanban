<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** Final retained scoped evidence. It contains no private source/target pair,
 * original parent proof body, plaintext audit payload or key material.
 * Preparatory plans/nested receipts never qualify as publication evidence. */
class NativeCryptoProjectRelocationPublicationV2 extends NativeDatabase
{
    protected $cryptoAccess=true;
    private function hash($v){return NativeCryptoProjectRelocationCodecV2::hash($v);}
    private function proofJson($v){return NativeCryptoCodec::canonical((object)$v);}

    /** Internal final transaction step, after ALL graph/blob/audit/record
     * validation and installation. Arguments are coordinator-derived complete
     * sets, never a public count or caller-provided inclusion boolean. */
    public function publish($row,$plan,$proofs,$leaves,$batchDigests,$audit,$notifications,$actor,$command,$key,$eventProof)
    {
        if(!$this->transactionActive()||$row['state']!=='committing'||($command['operation']??null)!=='crypto2.projectRelocation.commit'){
            throw new NativeError('crypto_relocation_transaction',409);
        }
        $this->fields($proofs,['source','target']);$this->fields($leaves,['source','target']);$this->fields($batchDigests,['source','target']);
        $directory=new NativeCryptoDirectoryV2($this->container);$own=$directory->current($actor['user']['account_id']);
        $api=new NativeCryptoScopeV2($this->container,$this->bearer,$this->ip);$publications=[];$hashes=[];
        foreach(['source','target'] as $side){
            [$body,$bytes,$signature]=NativeCryptoCodec::decode($proofs[$side]);
            NativeCryptoProjectRelocationCodecV2::publication($body);
            NativeCryptoV2Codec::verify($bytes,$signature,$key,NativeCryptoProjectRelocationCodecV2::PUBLICATION_DOMAIN);
            $scopeId=$plan[$side==='source'?'sourceScopeId':'targetScopeId'];$other=$plan[$side==='source'?'targetScopeId':'sourceScopeId'];
            $scope=$this->scope($scopeId,$actor['user']['id']);$head=$api->current($scopeId);
            if(!$head)throw new NativeError('crypto_relocation_publication_head',409);
            $expected=['version'=>2,'serverId'=>$this->serverId(),'scopeId'=>$scopeId,'side'=>$side,'actionId'=>$row['action_id'],'planHash'=>$row['plan_hash'],'requestId'=>$command['requestId'],'accountId'=>$actor['user']['account_id'],'deviceId'=>$actor['device']['id'],'authorDirectoryHeadHash'=>$own['head_hash'],'membershipHeadHash'=>$head['head_hash'],'accessRevision'=>(int)$scope['effective_access_revision'],'lifecycleHash'=>(new NativeCryptoLifecycleV2($this->container))->closingHash($scopeId),'counterpartToken'=>NativeCryptoProjectRelocationCodecV2::counterpartToken($this->serverId(),$row['action_id'],$scopeId,$other)];
            foreach($expected as $field=>$value)if($body[$field]!==$value)throw new NativeError('crypto_relocation_publication_context',409);
            if($body['proposalProofHash']!==$this->hash(json_decode($head['authorization'],true,34,JSON_THROW_ON_ERROR))||$head['activation_authorization']===null||$body['activationProofHash']!==$this->hash(json_decode($head['activation_authorization'],true,34,JSON_THROW_ON_ERROR)))throw new NativeError('crypto_relocation_activation_binding',409);
            if($side==='source'&&($body['membershipHeadHash']!==$plan['sourceHeadHash']||$body['lifecycleHash']!==$plan['sourceLifecycleHash']))throw new NativeError('project_sharing_preview_changed',409);
            $api->manager($head,$scope,$actor);
            $digests=[];$seen=[];
            foreach($leaves[$side] as $leaf){
                if(isset($seen[$leaf['id']]))throw new NativeError('crypto_relocation_order');
                $seen[$leaf['id']]=true;$digests[]=NativeCryptoProjectRelocationCodecV2::recordLeaf($leaf);
                $saved=$this->one('SELECT authorization,type,revision FROM familyhub_crypto_records WHERE scope_id=? AND id=?',[$scopeId,$leaf['id']]);
                if(!$saved||$saved['type']!==$leaf['type'])throw new NativeError('crypto_relocation_record_binding',409);
                $recordProof=json_decode($saved['authorization'],true,34,JSON_THROW_ON_ERROR)['recordProof'];
                if($this->hash($recordProof)!==$leaf['recordProofHash'])throw new NativeError('crypto_relocation_record_binding',409);
                [$record]=NativeCryptoCodec::decode($recordProof);$tag=$record['metadata']['projectRelocation']??null;
                if(!$tag||$tag['actionId']!==$row['action_id']||$tag['planHash']!==$row['plan_hash']||$tag['side']!==$side)throw new NativeError('crypto_relocation_record_binding',409);
            }
            sort($digests,SORT_STRING);sort($batchDigests[$side],SORT_STRING);
            $count=count($digests);$expectedCount=$plan['sourceGraphCount']+1;
            if($count!==$expectedCount||$body['recordCount']!==$count||$body['recordRoot']!==NativeCryptoProjectRelocationCodecV2::digestRoot('records',$digests)||$body['batchCount']!==count($batchDigests[$side])||$body['batchRoot']!==NativeCryptoProjectRelocationCodecV2::digestRoot('batches',$batchDigests[$side])){
                throw new NativeError('crypto_relocation_publication_inclusion',409);
            }
            $auditRoot=$side==='target'?$audit['root']:NativeCryptoProjectRelocationCodecV2::digestRoot('audit',[]);
            $auditCount=$side==='target'?$audit['count']:0;
            if($body['auditRoot']!==$auditRoot||$body['auditCount']!==$auditCount)throw new NativeError('crypto_relocation_audit_inclusion',409);
            if($body['notificationRoot']!==$notifications['root']||$body['notificationCount']!==$notifications['count'])throw new NativeError('crypto_relocation_notification_inclusion',409);
            $publications[$side]=$body;$hashes[$side]=$this->hash($proofs[$side]);
        }
        $root=NativeCryptoProjectRelocationCodecV2::publicationRoot($hashes['source'],$hashes['target']);
        [$event,$eventBytes,$eventSignature]=NativeCryptoCodec::decode($eventProof);
        $this->fields($event,['version','operation','requestId','serverId','accountId','deviceId','signer','payload']);
        if($event['version']!==2||$event['operation']!=='crypto2.account.projectRelocation'||$event['requestId']!==$command['requestId']||$event['serverId']!==$this->serverId()||$event['accountId']!==$actor['user']['account_id']||$event['deviceId']!==$actor['device']['id']||$event['signer']!=='device'||($event['payload']['actionId']??null)!==$row['action_id']||($event['payload']['publicationRoot']??null)!==$root){
            throw new NativeError('crypto_relocation_event_binding',409);
        }
        NativeCryptoV2Codec::verify($eventBytes,$eventSignature,$directory->authorize($event,$own));
        $next=$directory->reduce($event,$own);$included=$directory->append($event,$eventProof,$next);
        $this->change('UPDATE familyhub_crypto_accounts SET generation=?,generation_certificate=?,updated_at=? WHERE account_id=?',[$included['generation'],json_encode($eventProof,JSON_THROW_ON_ERROR),time(),$actor['user']['account_id']]);
        $eventHash=hash('sha256',$eventBytes);
        foreach(['source','target'] as $side){
            $body=$publications[$side];$other=$side==='source'?'target':'source';
            $this->change('INSERT INTO familyhub_crypto_project_relocation_publications_v2(action_id,scope_id,side,publication_hash,authorization,event_authorization,event_head_hash,event_command_hash,other_publication_hash,account_id) VALUES(?,?,?,?,?,?,?,?,?,?)',[$row['action_id'],$body['scopeId'],$side,$hashes[$side],json_encode($proofs[$side],JSON_THROW_ON_ERROR),json_encode($eventProof,JSON_THROW_ON_ERROR),$included['headHash'],$eventHash,$hashes[$other],$actor['user']['account_id']]);
            foreach($leaves[$side] as $leaf)$this->change('INSERT INTO familyhub_crypto_project_relocation_publication_leaves_v2(action_id,scope_id,id,record_proof_hash,leaf_hash,descriptor) VALUES(?,?,?,?,?,?)',[$row['action_id'],$body['scopeId'],$leaf['id'],$leaf['recordProofHash'],NativeCryptoProjectRelocationCodecV2::recordLeaf($leaf),$this->proofJson($leaf)]);
            foreach($batchDigests[$side] as $digest)$this->change('INSERT INTO familyhub_crypto_project_relocation_publication_batches_v2(action_id,scope_id,batch_hash) VALUES(?,?,?)',[$row['action_id'],$body['scopeId'],$digest]);
        }
        return ['publicationRoot'=>$root,'sourcePublicationHash'=>$hashes['source'],'targetPublicationHash'=>$hashes['target'],'eventHeadHash'=>$included['headHash'],'eventCommandHash'=>$eventHash];
    }

    /** Current scoped READ selects only its own publication and optional own
     * record leaf; other records are opaque sorted digest membership. */
    public function evidence($p,$actor)
    {
        $this->fields($p,['scopeId','actionId'],['recordProofHash','recordBodyHash','id','afterHash','limit']);
        $scope=$this->uuid($p['scopeId']);$this->scope($scope,$actor['user']['id']);$action=$this->uuid($p['actionId']);
        $row=$this->one('SELECT * FROM familyhub_crypto_project_relocation_publications_v2 WHERE scope_id=? AND action_id=?',[$scope,$action]);
        if(!$row)throw new NativeError('crypto_relocation_publication_pending',409);
        $leaf=null;$recordProof=null;$batchProof=null;$digests=[];$batchDigests=[];
        $bodySelector=isset($p['recordBodyHash']);
        if($bodySelector){
            if(isset($p['recordProofHash'])||!isset($p['id']))throw new NativeError('validation_error');
            NativeCryptoRecordAddressV2::wireId($p['id']);NativeCryptoProjectRelocationCodecV2::digest($p['recordBodyHash']);
        }elseif(isset($p['id']))throw new NativeError('validation_error');
        if(isset($p['recordProofHash'])||$bodySelector){
            if(!$bodySelector)NativeCryptoProjectRelocationCodecV2::digest($p['recordProofHash']);
            $leaf=$bodySelector?$this->one('SELECT descriptor FROM familyhub_crypto_project_relocation_publication_leaves_v2 WHERE scope_id=? AND action_id=? AND id=?',[$scope,$action,$p['id']]):$this->one('SELECT descriptor FROM familyhub_crypto_project_relocation_publication_leaves_v2 WHERE scope_id=? AND action_id=? AND record_proof_hash=?',[$scope,$action,$p['recordProofHash']]);
            if(!$leaf)throw new NativeError('crypto_relocation_record_binding',409);
            $leaf=json_decode($leaf['descriptor'],true,34,JSON_THROW_ON_ERROR);
            if($leaf['domain']==='finance')(new NativeFinanceAccess($this->container))->policyForCrypto($scope,$actor['user'],false,true);
            $history=$this->one('SELECT record_proof,batch_commitment FROM familyhub_crypto_record_history WHERE scope_id=? AND domain=? AND record_proof_hash=?',[$scope,$leaf['domain'],$leaf['recordProofHash']]);
            if(!$history)throw new NativeError('crypto_relocation_record_pending',409);
            $recordProof=json_decode($history['record_proof'],true,34,JSON_THROW_ON_ERROR);$batchProof=json_decode($history['batch_commitment'],true,34,JSON_THROW_ON_ERROR);
            if($this->hash($recordProof)!==$leaf['recordProofHash'])throw new NativeError('crypto_relocation_record_binding',409);
            if($bodySelector){[, $recordBytes]=NativeCryptoCodec::decode($recordProof);if(hash('sha256',$recordBytes)!==$p['recordBodyHash'])throw new NativeError('crypto_relocation_record_binding',409);}
        }
        $after=$p['afterHash']??'';if($after!=='')NativeCryptoProjectRelocationCodecV2::digest($after);
        $limit=$p['limit']??32;if(!is_int($limit)||$limit<1||$limit>32)throw new NativeError('validation_error');
        $rows=$this->many('SELECT leaf_hash FROM familyhub_crypto_project_relocation_publication_leaves_v2 WHERE scope_id=? AND action_id=? AND leaf_hash>? ORDER BY leaf_hash LIMIT '.($limit+1),[$scope,$action,$after]);
        $more=count($rows)>$limit;$rows=array_slice($rows,0,$limit);$digests=array_column($rows,'leaf_hash');
        foreach($this->iterate('SELECT batch_hash FROM familyhub_crypto_project_relocation_publication_batches_v2 WHERE scope_id=? AND action_id=? ORDER BY batch_hash',[$scope,$action]) as $batch)$batchDigests[]=$batch['batch_hash'];
        return ['authorization'=>json_decode($row['authorization'],true,34,JSON_THROW_ON_ERROR),'eventAuthorization'=>json_decode($row['event_authorization'],true,34,JSON_THROW_ON_ERROR),'eventHeadHash'=>$row['event_head_hash'],'eventCommandHash'=>$row['event_command_hash'],'otherPublicationHash'=>$row['other_publication_hash'],'descriptor'=>$leaf,'recordProof'=>$recordProof,'batchCommitment'=>$batchProof,'recordDigests'=>$digests,'batchDigests'=>$batchDigests,'hasMore'=>$more,'nextAfterHash'=>$digests?end($digests):$after];
    }

    /** Recover only an exact event already in the caller's OWN signed log.
     * This outcome does not grant scope READ, keys, a floor or new membership. */
    public function own($p,$actor)
    {
        $this->fields($p,['actionId','eventCommandHash','publicationRoot']);$action=$this->uuid($p['actionId']);
        foreach(['eventCommandHash','publicationRoot'] as $field)NativeCryptoProjectRelocationCodecV2::digest($p[$field]);
        $rows=$this->many('SELECT * FROM familyhub_crypto_project_relocation_publications_v2 WHERE action_id=? AND account_id=? ORDER BY side',[$action,$actor['user']['account_id']]);
        if(count($rows)!==2)throw new NativeError('crypto_relocation_publication_pending',409);
        $proofs=[];
        foreach($rows as $row){if($row['event_command_hash']!==$p['eventCommandHash'])throw new NativeError('crypto_relocation_event_binding',409);$proofs[$row['side']]=json_decode($row['authorization'],true,34,JSON_THROW_ON_ERROR);}
        if(NativeCryptoProjectRelocationCodecV2::publicationRoot($this->hash($proofs['source']),$this->hash($proofs['target']))!==$p['publicationRoot'])throw new NativeError('crypto_relocation_event_binding',409);
        $entry=$this->one('SELECT generation,head_hash,authorization FROM familyhub_crypto_directory WHERE account_id=? AND command_hash=?',[$actor['user']['account_id'],$p['eventCommandHash']]);
        if(!$entry)throw new NativeError('crypto_relocation_event_pending',409);
        [$event]=NativeCryptoCodec::decode(json_decode($entry['authorization'],true,34,JSON_THROW_ON_ERROR));
        if($event['operation']!=='crypto2.account.projectRelocation'||$event['payload']['actionId']!==$action||$event['payload']['publicationRoot']!==$p['publicationRoot'])throw new NativeError('crypto_relocation_event_binding',409);
        return ['publications'=>$proofs,'eventAuthorization'=>json_decode($entry['authorization'],true,34,JSON_THROW_ON_ERROR),'eventGeneration'=>(int)$entry['generation'],'eventHeadHash'=>$entry['head_hash'],'eventCommandHash'=>$p['eventCommandHash']];
    }

    public function directoryReferences($scope,$head,$account)
    {
        $out=[];
        foreach($this->iterate('SELECT authorization,event_head_hash FROM familyhub_crypto_project_relocation_publications_v2 WHERE scope_id=? AND account_id=?',[$scope,$account]) as $row){
            [$body]=NativeCryptoCodec::decode(json_decode($row['authorization'],true,34,JSON_THROW_ON_ERROR));
            NativeCryptoProjectRelocationCodecV2::publication($body);
            if($body['scopeId']===$scope&&$body['membershipHeadHash']===$head&&$body['accountId']===$account){$out[]=$body['authorDirectoryHeadHash'];$out[]=$row['event_head_hash'];}
        }
        foreach($this->many("SELECT a.authorization FROM familyhub_crypto_project_relocation_audit_v2 a JOIN familyhub_crypto_project_relocation_publications_v2 p ON p.action_id=a.action_id AND p.scope_id=a.scope_id WHERE a.scope_id=? AND p.side='target' AND a.state='committed' AND p.account_id=?",[$scope,$account]) as $row){
            [$body]=NativeCryptoCodec::decode(json_decode($row['authorization'],true,34,JSON_THROW_ON_ERROR));
            if(($body['membershipHeadHash']??null)===$head&&($body['accountId']??null)===$account)$out[]=$body['authorDirectoryHeadHash'];
        }
        return array_values(array_unique($out));
    }
}
