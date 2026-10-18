<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** Management consent deletes active scope transport, never fabricates record
 * edits. The public retained witness discloses only its own scoped leaf. */
class NativeCryptoScopeDeletionAuthorityV2 extends NativeDatabase
{
    protected $cryptoAccess=true;
    private function digest($value){NativeCryptoScopeDeletionCodecV2::digest($value);return $value;}
    private function same($a,$b){return NativeCryptoCodec::canonical($a)===NativeCryptoCodec::canonical($b);}
    private function proof($p,$domain,$key){[$b,$bytes,$sig]=NativeCryptoCodec::decode($p);NativeCryptoV2Codec::verify($bytes,$sig,$key,$domain);return $b;}
    private function descriptor($scope,$head){return ['scopeId'=>$scope['id'],'headHash'=>$head['head_hash'],'accessRevision'=>(int)$scope['effective_access_revision'],'lifecycleHash'=>(new NativeCryptoLifecycleV2($this->container))->closingHash($scope['id'])];}

    private function graph($root,$actor)
    {
        $scopesApi=new NativeCryptoScopeV2($this->container,$this->bearer,$this->ip);
        $rootScope=$this->scope($root,$actor['user']['id'],false,true);
        if($rootScope['kind']==='personal'){throw new NativeError('permission_revoked',403);}
        $rootHead=$scopesApi->current($root);$scopesApi->manager($rootHead,$rootScope,$actor);
        $pending=[$root];$scopes=[];$descriptors=[];$frames=[];$members=[];$blocks=[];$counts=['spaces'=>0,'projects'=>0,'tasks'=>0,'events'=>0,'ideas'=>0,'photos'=>0,'tables'=>0,'attachments'=>0,'finance'=>0,'other'=>0];
        while($pending){
            $id=array_shift($pending);if(isset($scopes[$id])){continue;}
            if(count($scopes)>=NativeCryptoScopeDeletionCodecV2::MAX_SCOPES){throw new NativeError('crypto_scope_deletion_graph_limit',409);}
            $raw=$this->one('SELECT * FROM familyhub_scopes WHERE id=?'.$this->lockSuffix(),[$id]);
            if(!$raw||$raw['deleted_at']!==null){throw new NativeError('scope_deletion_preview_changed',409);}
            // Discovery of an inaccessible/foreign child is a blocker only.
            // Stop before reading its signed roster, records, blobs or counts.
            if((int)$raw['owner_id']!==(int)$rootScope['owner_id']){
                return ['scopes'=>[],'members'=>[],'descriptors'=>[],'graphRoot'=>null,'graphCount'=>0,'counts'=>array_fill_keys(array_keys($counts),0),'blockers'=>[['code'=>'child_owner_transfer_required']],'canDelete'=>false,'incomplete'=>true];
            }
            try{$scope=$this->scope($id,$actor['user']['id'],false,true);$head=$scopesApi->current($id);if(!$head)throw new NativeError('crypto_scope_head_missing',409);$scopesApi->manager($head,$scope,$actor);}
            catch(NativeError $e){if(!in_array($e->errorCode,['permission_revoked','crypto_scope_management_forbidden'],true)){throw $e;}return ['scopes'=>[],'members'=>[],'descriptors'=>[],'graphRoot'=>null,'graphCount'=>0,'counts'=>array_fill_keys(array_keys($counts),0),'blockers'=>[['code'=>'child_owner_transfer_required']],'canDelete'=>false,'incomplete'=>true];}
            $body=$scopesApi->body($head);
            $scopes[$id]=$scope;$members[$id]=array_column($body['members'],'accountId');$descriptors[$id]=$this->descriptor($scope,$head);$counts['spaces']++;
            $recordHash=hash_init('sha256');hash_update($recordHash,"JivieScopeDeletionRecords/v2\n");$recordCount=0;
            foreach($this->iterate('SELECT id,type,revision,deleted,authorization FROM familyhub_crypto_records WHERE scope_id=? ORDER BY id',[$id]) as $r){
                $proof=json_decode($r['authorization'],true,34,JSON_THROW_ON_ERROR);$proofHash=NativeCryptoV2Codec::hash((object)$proof['recordProof']);
                hash_update($recordHash,NativeCryptoCodec::canonical((object)['id'=>$r['id'],'revision'=>(int)$r['revision'],'deleted'=>(bool)$r['deleted'],'proofHash'=>$proofHash])."\n");$recordCount++;
                if(!(int)$r['deleted']){$key=['project'=>'projects','task'=>'tasks','event'=>'events','idea'=>'ideas','organizationTable'=>'tables','attachment'=>'attachments','financeAccount'=>'finance','financeEntry'=>'finance','personalFinanceAccount'=>'finance','personalFinanceEntry'=>'finance','paymentEvent'=>'finance','paymentProjection'=>'finance','cashMovement'=>'finance'][$r['type']]??'other';$counts[$key]++;}
            }
            $blobHash=hash_init('sha256');hash_update($blobHash,"JivieScopeDeletionBlobs/v2\n");$blobCount=0;
            foreach($this->iterate('SELECT id,sha256,size,received,complete FROM familyhub_crypto_blobs_v2 WHERE scope_id=? ORDER BY id',[$id]) as $b){hash_update($blobHash,NativeCryptoCodec::canonical((object)['id'=>$b['id'],'sha256'=>$b['sha256'],'size'=>(int)$b['size'],'received'=>(int)$b['received'],'complete'=>(bool)$b['complete']])."\n");$blobCount++;}
            $frames[$id]=['scope'=>$descriptors[$id],'recordCount'=>$recordCount,'recordRoot'=>hash_final($recordHash),'blobCount'=>$blobCount,'blobRoot'=>hash_final($blobHash)];
            foreach($this->many('SELECT id FROM familyhub_scopes WHERE deleted_at IS NULL AND (parent_scope_id=? OR organization_id=?) ORDER BY id',[$id,$id]) as $child){$pending[]=$child['id'];}
        }
        ksort($scopes,SORT_STRING);ksort($frames,SORT_STRING);ksort($descriptors,SORT_STRING);
        $ids=array_fill_keys(array_keys($scopes),true);
        // Both immutable historical edges and current edges are relevant. No
        // source/target IDs from these private checks are returned in blockers.
        foreach($this->iterate('SELECT scope_id,metadata FROM familyhub_crypto_records ORDER BY scope_id,id') as $r){foreach(json_decode($r['metadata'],true,34,JSON_THROW_ON_ERROR)['references']??[] as $ref){if(isset($ids[$r['scope_id']])!==isset($ids[$ref['scopeId']])){$blocks[]=['code'=>'cross_scope_finance_dependency'];}}}
        foreach($this->iterate('SELECT scope_id,record_proof FROM familyhub_crypto_record_history ORDER BY scope_id,id,revision') as $r){[$b]=NativeCryptoCodec::decode(json_decode($r['record_proof'],true,34,JSON_THROW_ON_ERROR));foreach($b['metadata']['references']??[] as $ref){if(isset($ids[$r['scope_id']])!==isset($ids[$ref['scopeId']])){$blocks[]=['code'=>'cross_scope_finance_dependency'];}}}
        foreach($this->iterate('SELECT DISTINCT o.source_scope_id,o.target_scope_id FROM familyhub_crypto_export_offers_v2 o JOIN familyhub_crypto_export_certificates_v2 c ON c.offer_hash=o.hash') as $r){if(isset($ids[$r['source_scope_id']])!==isset($ids[$r['target_scope_id']])){$blocks[]=['code'=>'cross_scope_payment_dependency'];}}
        foreach($this->iterate('SELECT scope_id,source_scope_id FROM familyhub_payment_projections') as $r){if(isset($ids[$r['scope_id']])!==isset($ids[$r['source_scope_id']]))$blocks[]=['code'=>'cross_scope_payment_dependency'];}
        foreach($this->iterate("SELECT scope_id,payload FROM familyhub_finance_records WHERE deleted=0 AND type='financeEntry'") as $r){$raw=json_decode($r['payload'],true,34,JSON_THROW_ON_ERROR);$accountScope=$raw['accountScopeId']??$r['scope_id'];if(isset($ids[$r['scope_id']])!==isset($ids[$accountScope]))$blocks[]=['code'=>'cross_scope_finance_dependency'];}
        $unique=[];foreach($blocks as $b){$unique[$b['code']]=$b;}$blocks=array_values($unique);
        $rootHash=hash('sha256',"JivieScopeDeletionGraph/v2\n".NativeCryptoCodec::canonical(array_values($frames)));
        return ['scopes'=>$scopes,'members'=>$members,'descriptors'=>array_values($descriptors),'graphRoot'=>$rootHash,'graphCount'=>count($scopes),'counts'=>$counts,'blockers'=>$blocks,'canDelete'=>!$blocks];
    }

    public function preview($p,$actor)
    {
        $this->fields($p,['scopeId']);$sid=$this->uuid($p['scopeId']);$g=$this->graph($sid,$actor);
        // Private graph contexts are returned only when all portions can be
        // independently reviewed by the deleting manager.
        return ['scopeId'=>$sid,'projectId'=>null,'scopeContexts'=>$g['canDelete']?$g['descriptors']:[],
            'graphRoot'=>$g['graphRoot'],'graphCount'=>$g['graphCount'],'counts'=>$g['counts'],'canDelete'=>$g['canDelete'],'blockers'=>$g['blockers'],
            'retention'=>NativeCryptoScopeDeletionCodecV2::retention(),'incomplete'=>$g['incomplete']??false,'name'=>'Encrypted scope','previewHash'=>$g['graphRoot']??hash('sha256',"JivieScopeDeletionBlocked/v2\n".$sid)];
    }

    public function delete($p,$actor,$outerProof,$outer)
    {
        $this->fields($p,['certificateProof','headerProof','scopeProofs','accountEventProof','authorDirectoryHeadHash'],['parentTopology']);
        $directory=new NativeCryptoDirectoryV2($this->container);$current=$directory->current($actor['user']['account_id']);
        if(!$current||$p['authorDirectoryHeadHash']!==$current['head_hash']){throw new NativeError('crypto_member_directory_changed',409);}
        $snapshot=json_decode($current['snapshot'],true,34,JSON_THROW_ON_ERROR);$device=$directory->device($snapshot,$actor['device']['id']);
        if(!$device||$device['revokedGeneration']!==null||!$device['keyringWrite']){throw new NativeError('crypto_keyring_forbidden',403);}
        $key=$device['signingKeyBase64'];$c=$this->proof($p['certificateProof'],NativeCryptoScopeDeletionCodecV2::CERTIFICATE,$key);NativeCryptoScopeDeletionCodecV2::certificate($c);
        foreach(['requestId','serverId'] as $f){if($c[$f]!==$outer[$f]){throw new NativeError('crypto_scope_deletion_context');}}
        if($c['actorAccountId']!==$actor['user']['account_id']||$c['actorDeviceId']!==$actor['device']['id']){throw new NativeError('crypto_scope_deletion_context');}
        $g=$this->graph($c['rootScopeId'],$actor);
        if(!$g['canDelete']){throw new NativeError('scope_deletion_blocked',409,['blockers'=>$g['blockers']]);}
        if(!$this->same($c['scopes'],$g['descriptors'])||$c['graphRoot']!==$g['graphRoot']||$c['graphCount']!==$g['graphCount']){throw new NativeError('scope_deletion_preview_changed',409);}
        $h=$this->proof($p['headerProof'],NativeCryptoScopeDeletionCodecV2::HEADER,$key);NativeCryptoScopeDeletionCodecV2::header($h);
        $base=['version'=>2,'serverId'=>$outer['serverId'],'requestId'=>$outer['requestId'],'actorAccountId'=>$actor['user']['account_id'],'actorDeviceId'=>$actor['device']['id'],'authorDirectoryHeadHash'=>$current['head_hash'],'privateCertificateHash'=>NativeCryptoScopeDeletionCodecV2::hash($p['certificateProof']),'rootToken'=>NativeCryptoScopeDeletionCodecV2::rootToken($c),'graphRoot'=>$g['graphRoot'],'graphCount'=>$g['graphCount'],'retention'=>NativeCryptoScopeDeletionCodecV2::retention()];
        $root=$this->one('SELECT kind,parent_scope_id FROM familyhub_scopes WHERE id=?',[$c['rootScopeId']]);
        $parent=$root&&$root['kind']==='project'?$root['parent_scope_id']:null;
        $hasParent=$parent!==null&&!isset($g['scopes'][$parent]);
        if($hasParent!==array_key_exists('parentTopology',$p)||$hasParent!==array_key_exists('parentTopologyHash',$c)||$hasParent!==array_key_exists('parentTopologyHash',$h))throw new NativeError('crypto_scope_deletion_topology_required',409);
        if($hasParent){
            $hash=NativeCryptoV2Codec::hash((object)$p['parentTopology']);
            if($c['parentTopologyHash']!==$hash||$h['parentTopologyHash']!==$hash)throw new NativeError('crypto_scope_deletion_topology_binding',409);
            $base['parentTopologyHash']=$hash;
            $records=(new NativeCryptoRecordProofV2($this->container))->parseBatch($p['parentTopology'],$outer,$key);
            if(count($records)!==1)throw new NativeError('crypto_scope_deletion_topology_binding',409);
            $record=$records[0]['record'];
            $parentApi=new NativeCryptoScopeV2($this->container,$this->bearer,$this->ip);
            $parentScope=$this->scope($parent,$actor['user']['id'],true);$parentHead=$parentApi->current($parent);
            $parentApi->manager($parentHead,$parentScope,$actor);
            $parentApi->author($parent,$parentHead['head_hash'],(int)$parentHead['epoch'],(int)$parentScope['effective_access_revision'],$actor,'content',true);
            $reserved=hash('sha256',"JivieReservedRecord/v2\n".$this->serverId().':'.$parent.':scopeMetadata');
            $canonical=substr($reserved,0,8).'-'.substr($reserved,8,4).'-4'.substr($reserved,13,3).'-a'.substr($reserved,17,3).'-'.substr($reserved,20,12);
            $wire=NativeCryptoRecordAddressV2::derive($this->serverId(),$parent,'content','scope_metadata',$canonical);
            if($record['scopeId']!==$parent||$record['id']!==$wire||$record['type']!=='scopeMetadata'||$record['domain']!=='content'||$record['deleted']||$record['operationId']!==$outer['requestId']||$record['membershipHeadHash']!==$parentHead['head_hash']||isset($record['metadata']['migrationOrigin'])||isset($record['metadata']['projectRelocation'])||isset($record['metadata']['inlineDeletion']))throw new NativeError('crypto_scope_deletion_topology_binding',409);
        }
        foreach($base as $k=>$v){if(!$this->same($h[$k],$v)){throw new NativeError('crypto_scope_deletion_context');}}
        if(!is_array($p['scopeProofs'])||!array_is_list($p['scopeProofs'])||count($p['scopeProofs'])!==$g['graphCount']){throw new NativeError('crypto_scope_deletion_count');}
        $context=NativeCryptoScopeDeletionCodecV2::headerContext($h);$leaves=[];$digests=[];$previous=null;
        foreach($p['scopeProofs'] as $proof){$leaf=$this->proof($proof,NativeCryptoScopeDeletionCodecV2::LEAF,$key);NativeCryptoScopeDeletionCodecV2::leaf($leaf);$sid=$leaf['scopeId'];
            if($previous!==null&&strcmp($previous,$sid)>=0||!isset($g['scopes'][$sid])||$leaf['headerContextHash']!==$context||$leaf['serverId']!==$outer['serverId']||$leaf['requestId']!==$outer['requestId']){throw new NativeError('crypto_scope_deletion_context');}
            $desc=array_values(array_filter($g['descriptors'],fn($d)=>$d['scopeId']===$sid))[0];foreach($desc as $k=>$v){if($leaf[$k]!==$v){throw new NativeError('crypto_scope_deletion_context');}}
            $previous=$sid;$leaves[$sid]=$proof;$digests[]=NativeCryptoScopeDeletionCodecV2::hash($proof);
        }
        sort($digests,SORT_STRING);if(NativeCryptoScopeDeletionCodecV2::leafRoot($h,$digests)!==$h['scopeLeafRoot']){throw new NativeError('crypto_scope_deletion_inclusion');}
        if($hasParent){
            // The ordinary record validator supplies exact predecessor/CAS,
            // manager WRITE and signature checks inside this same transaction.
            (new NativeCryptoStorageV2($this->container,$this->bearer,$this->ip))->write('crypto2.records.batch',$p['parentTopology'],$actor,$outerProof,$outer,$key);
        }
        [$event,$eventBytes,$eventSig]=NativeCryptoCodec::decode($p['accountEventProof']);$headerHash=NativeCryptoScopeDeletionCodecV2::hash($p['headerProof']);
        if(($event['operation']??null)!=='crypto2.account.scopeDeletion'||($event['version']??null)!==2||($event['signer']??null)!=='device'||($event['accountId']??null)!==$actor['user']['account_id']||($event['deviceId']??null)!==$actor['device']['id']||($event['serverId']??null)!==$outer['serverId']||($event['requestId']??null)!==$outer['requestId']||($event['payload']['scopeToken']??null)!==$h['rootToken']||($event['payload']['certificateHash']??null)!==$headerHash){throw new NativeError('crypto_scope_deletion_event_binding');}
        $eventKey=$directory->authorize($event,$current);NativeCryptoV2Codec::verify($eventBytes,$eventSig,$eventKey);$next=$directory->reduce($event,$current);$entry=$directory->append($event,$p['accountEventProof'],$next);
        $this->change('UPDATE familyhub_crypto_accounts SET generation=?,generation_certificate=?,updated_at=? WHERE account_id=?',[$entry['generation'],json_encode($p['accountEventProof'],JSON_THROW_ON_ERROR),time(),$actor['user']['account_id']]);
        $legacyCleanupPending=false;$cleanupPending=false;
        foreach($g['scopes'] as $sid=>$scope){
            $scopesApi=new NativeCryptoScopeV2($this->container,$this->bearer,$this->ip);
            $head=$scopesApi->current($sid);
            $headWire=$scopesApi->read('crypto2.scope.headGet',['scopeId'=>$sid],$actor);
            $bundle=['headerProof'=>$p['headerProof'],'leafProof'=>$leaves[$sid],'leafDigests'=>$digests,'eventHeadHash'=>$entry['headHash'],'eventCommandHash'=>hash('sha256',$eventBytes),'membershipHead'=>$headWire,'privateCertificateProof'=>$sid===$c['rootScopeId']?$p['certificateProof']:null];
            $this->change('INSERT INTO familyhub_crypto_scope_deletions_v2(scope_id,root_scope_id,certificate_hash,authorization,event_authorization,actor_account_id,retained_members,created_at) VALUES(?,?,?,?,?,?,?,?)',[$sid,$c['rootScopeId'],$headerHash,json_encode($bundle,JSON_THROW_ON_ERROR),json_encode($p['accountEventProof'],JSON_THROW_ON_ERROR),$actor['user']['account_id'],json_encode($g['members'][$sid],JSON_THROW_ON_ERROR),time()]);
            $cleanup=new NativeCryptoScopeDeletionV2($this->container);
            $legacyCleanupPending=$cleanup->retainedLegacySources($sid)||$legacyCleanupPending;
            $cleanup->eraseActiveData($sid,true);
            $cleanupPending=$cleanup->cleanupPending($sid)||$cleanupPending;
            $this->change('UPDATE familyhub_members SET active=0 WHERE scope_id=?',[$sid]);
            $this->change("UPDATE familyhub_crypto_invitations_v2 SET state='revoked' WHERE scope_id=? AND state IN ('pending','accepted')",[$sid]);
            $this->change("UPDATE familyhub_crypto_invitation_mail_v2 SET state='cancelled',token_cipher=NULL,lease_token=NULL WHERE invitation_id IN (SELECT id FROM familyhub_crypto_invitations_v2 WHERE scope_id=?) AND state<>'accepted'",[$sid]);
            $this->change('DELETE FROM familyhub_push_jobs WHERE inbox_id IN (SELECT id FROM familyhub_inbox WHERE scope_id=?)',[$sid]);
            $this->change('DELETE FROM familyhub_deliveries WHERE inbox_id IN (SELECT id FROM familyhub_inbox WHERE scope_id=?)',[$sid]);
            $this->change('DELETE FROM familyhub_inbox WHERE scope_id=?',[$sid]);
        }
        return ['deleted'=>true,'scopeId'=>$c['rootScopeId'],'projectId'=>null,'deletedScopeIds'=>array_keys($g['scopes']),'records'=>[],'financeRecords'=>[],'cleanupPending'=>$cleanupPending,'legacyCleanupPending'=>$legacyCleanupPending,'certificateHash'=>$headerHash,'headerProof'=>$p['headerProof'],'eventAuthorization'=>$p['accountEventProof'],'eventHeadHash'=>$entry['headHash'],'eventCommandHash'=>hash('sha256',$eventBytes)];
    }

    private function retained($sid,$actor)
    {
        $row=$this->one('SELECT * FROM familyhub_crypto_scope_deletions_v2 WHERE scope_id=?',[$sid]);
        if(!$row||!in_array($actor['user']['account_id'],json_decode($row['retained_members'],true,34,JSON_THROW_ON_ERROR),true)){throw new NativeError('permission_revoked',403);}return $row;
    }
    public function status($p,$actor)
    {
        $this->fields($p,['scopeId']);$row=$this->retained($this->uuid($p['scopeId']),$actor);$b=json_decode($row['authorization'],true,34,JSON_THROW_ON_ERROR);
        return ['scopeId'=>$row['scope_id'],'legacyCleanupPending'=>(new NativeCryptoScopeDeletionV2($this->container))->retainedLegacySources($row['scope_id']),'cleanupPending'=>(new NativeCryptoScopeDeletionV2($this->container))->cleanupPending($row['scope_id']),'certificateHash'=>$row['certificate_hash'],'headerProof'=>$b['headerProof'],'leafProof'=>$b['leafProof'],'leafDigests'=>$b['leafDigests'],'eventAuthorization'=>json_decode($row['event_authorization'],true,34,JSON_THROW_ON_ERROR),'eventHeadHash'=>$b['eventHeadHash'],'eventCommandHash'=>$b['eventCommandHash'],'membershipHead'=>$b['membershipHead']];
    }
    public function head($p,$actor)
    {
        $this->fields($p,['scopeId'],['headHash']);$sid=$this->uuid($p['scopeId']);
        $row=$this->retained($sid,$actor);$bundle=json_decode($row['authorization'],true,34,JSON_THROW_ON_ERROR);
        $wire=$bundle['membershipHead'];$hash=$p['headHash']??$wire['headHash'];$this->digest($hash);
        if($hash===$wire['headHash'])return $wire;
        $scopes=new NativeCryptoScopeV2($this->container);
        $head=$scopes->head($sid,$wire['headHash']);
        while($head){$body=$scopes->body($head);if($body['previousHeadHash']===NativeCryptoDirectoryV2::ZERO)break;$head=$scopes->head($sid,$body['previousHeadHash']);if($head['head_hash']!==$hash)continue;
            $baseline=(new NativeCryptoLifecycleV2($this->container))->initialBaseline($sid);
            $out=$baseline+['scopeId'=>$sid,'headHash'=>$hash,'state'=>$head['state'],'payload'=>$scopes->body($head),'authorization'=>json_decode($head['authorization'],true,34,JSON_THROW_ON_ERROR),'activationAuthorization'=>json_decode($head['activation_authorization'],true,34,JSON_THROW_ON_ERROR)];
            foreach(['finance'=>'financeGrantManifestProof','content'=>'contentGrantManifestProof'] as $d=>$field){$m=$this->one('SELECT authorization FROM familyhub_crypto_'.$d.'_manifests WHERE scope_id=? AND head_hash=?',[$sid,$hash]);$out[$field]=$m?json_decode($m['authorization'],true,34,JSON_THROW_ON_ERROR):null;}
            $a=$this->one('SELECT authorization FROM familyhub_crypto_owner_acceptances WHERE scope_id=? AND head_hash=?',[$sid,$hash]);$out['ownerAcceptanceProof']=$a?json_decode($a['authorization'],true,34,JSON_THROW_ON_ERROR):null;return $out;
        }
        throw new NativeError('permission_revoked',403);
    }

    public function directory($p,$actor)
    {
        $this->fields($p,['scopeId','accountId','directoryHeadHash'],['afterGeneration','limit']);
        $sid=$this->uuid($p['scopeId']);$target=$this->uuid($p['accountId']);$hash=$this->digest($p['directoryHeadHash']);
        $row=$this->retained($sid,$actor);$bundle=json_decode($row['authorization'],true,34,JSON_THROW_ON_ERROR);
        $refs=[];$add=function($proof)use(&$refs,$target){if(!$proof)return;[$c]=NativeCryptoCodec::decode($proof);if(($c['accountId']??$c['actorAccountId']??null)===$target){$h=$c['payload']['authorDirectoryHeadHash']??$c['authorDirectoryHeadHash']??null;if($h!==null)$refs[]=$h;}};
        if($target===$row['actor_account_id']){$refs[]=$bundle['eventHeadHash'];$add($bundle['headerProof']);}
        $scopes=new NativeCryptoScopeV2($this->container);$head=$scopes->head($sid,$bundle['membershipHead']['headHash']);
        while($head){$body=$scopes->body($head);foreach($body['members'] as $member){if($member['accountId']===$target)$refs[]=$member['directoryHeadHash'];}
            $add(json_decode($head['authorization'],true,34,JSON_THROW_ON_ERROR));$add(json_decode($head['activation_authorization'],true,34,JSON_THROW_ON_ERROR));
            foreach($this->many('SELECT authorization FROM familyhub_crypto_closures WHERE scope_id=? AND candidate_head_hash=?',[$sid,$head['head_hash']]) as $r)$add(json_decode($r['authorization'],true,34,JSON_THROW_ON_ERROR));
            foreach($this->many('SELECT authorization FROM familyhub_crypto_lifecycle_delegations_v2 WHERE scope_id=? AND head_hash=? AND parent_account_id=?',[$sid,$head['head_hash'],$target]) as $r){[$d]=NativeCryptoCodec::decode(json_decode($r['authorization'],true,34,JSON_THROW_ON_ERROR));$refs[]=$d['payload']['parentDirectoryHeadHash'];}
            foreach($this->many('SELECT authorization FROM familyhub_crypto_lifecycle_log_v2 WHERE scope_id=? AND membership_head_hash=?',[$sid,$head['head_hash']]) as $r){$proof=json_decode($r['authorization'],true,34,JSON_THROW_ON_ERROR);[$c]=NativeCryptoCodec::decode($proof);if(($c['operation']??null)==='crypto2.scope.archive'){$a=$this->one('SELECT authorization FROM familyhub_crypto_lifecycle_actions_v2 WHERE scope_id=? AND id=?',[$sid,$c['payload']['parentActionId']]);if(!$a)throw new NativeError('crypto_lifecycle_log_unavailable',503);$proof=json_decode($a['authorization'],true,34,JSON_THROW_ON_ERROR);}$add($proof);}
            $refs=array_merge($refs,(new NativeCryptoMigrationStructureContextV3($this->container))->directoryReferences($sid,$head['head_hash'],$target));
            if($body['previousHeadHash']===NativeCryptoDirectoryV2::ZERO)break;$head=$scopes->head($sid,$body['previousHeadHash']);
        }
        $add($bundle['membershipHead']['originAuthorization']);
        [$origin]=NativeCryptoCodec::decode($bundle['membershipHead']['originAuthorization']);
        if(($origin['accountId']??null)===$target)$refs[]=$bundle['membershipHead']['originAuthorDirectoryHeadHash'];
        if(!in_array($hash,$refs,true))throw new NativeError('permission_revoked',403);
        $h=$this->one('SELECT generation,head_hash,snapshot_hash,device_snapshot_hash,identity_epoch_id FROM familyhub_crypto_directory WHERE account_id=? AND head_hash=?',[$target,$hash]);if(!$h)throw new NativeError('crypto_directory_head_missing',404);
        $after=$p['afterGeneration']??0;$limit=$p['limit']??20;if(!is_int($after)||$after<0||$after>(int)$h['generation']||!is_int($limit)||$limit<1||$limit>20)throw new NativeError('invalid_cursor');
        $rows=$this->many('SELECT generation,head_hash,previous_head_hash,command_hash,authorization FROM familyhub_crypto_directory WHERE account_id=? AND generation>? AND generation<=? ORDER BY generation LIMIT '.($limit+1),[$target,$after,(int)$h['generation']]);$entries=[];$bytes=0;
        foreach($rows as $r){$e=['generation'=>(int)$r['generation'],'headHash'=>$r['head_hash'],'previousHeadHash'=>$r['previous_head_hash'],'commandHash'=>$r['command_hash'],'authorization'=>json_decode($r['authorization'],true,34,JSON_THROW_ON_ERROR)];$n=strlen(json_encode($e,JSON_THROW_ON_ERROR));if(count($entries)===$limit||$entries&&$bytes+$n>1250000)break;$entries[]=$e;$bytes+=$n;}
        return ['serverId'=>$this->serverId(),'accountId'=>$target,'generation'=>(int)$h['generation'],'headHash'=>$h['head_hash'],'snapshotHash'=>$h['snapshot_hash'],'deviceSnapshotHash'=>$h['device_snapshot_hash'],'identityEpochId'=>$h['identity_epoch_id'],'entries'=>$entries,'hasMore'=>count($rows)>count($entries),'nextGeneration'=>$entries?end($entries)['generation']:$after];
    }

}
