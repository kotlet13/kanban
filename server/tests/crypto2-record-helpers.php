<?php
/** Shared synthetic signed-record builder, including exact dependency CAS bindings. */
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoCodec;
function proof2($body,$prefix,$key) {
    $raw=NativeCryptoCodec::canonical((object)$body);
    return ['commandBase64'=>base64_encode($raw),'signatureBase64'=>base64_encode(sodium_crypto_sign_detached($prefix.$raw,$key['sign']))];
}
function row2($sid,$head,$u,$key,$id=null,$type='task',$revision=0,$previous=null,$refs=[],$unique=[],$deleted=false,$blobIds=[]) {
    $domain=(new \Kanboard\Plugin\FamilyHub\Model\NativeCryptoRecordProofV2($GLOBALS['container']))->domain($type);
    $canonical=$id??uid();
    if (is_string($canonical) && substr($canonical,14,1)==='8') {
        $stored=q('SELECT metadata FROM familyhub_crypto_records WHERE scope_id=? AND id=?',[$sid,$canonical]);
        if (!$stored) { throw new RuntimeException('Synthetic edit needs its immutable canonical identity'); }
        $canonical=json_decode($stored[0]['metadata'],true)['identity']['canonicalId'];
    }
    $identity=['sourceKind'=>\Kanboard\Plugin\FamilyHub\Model\NativeCryptoRecordAddressV2::sourceKind($type),'canonicalId'=>$canonical];
    $wire=\Kanboard\Plugin\FamilyHub\Model\NativeCryptoRecordAddressV2::derive($u['serverId'],$sid,$domain,$identity['sourceKind'],$canonical);
    return ['version'=>2,'operation'=>'crypto2.record','serverId'=>$u['serverId'],'accountId'=>$u['user']['accountId'],'deviceId'=>$u['device']['id'],'batchId'=>uid(),'operationId'=>uid(),'scopeId'=>$sid,'id'=>$wire,'type'=>$type,'domain'=>$domain,'contentContract'=>$domain==='finance'?3:6,'expectedRevision'=>$revision,'previousRecordHash'=>$previous??str_repeat('0',64),'deleted'=>$deleted,'epoch'=>$head['payload']['epoch'],'accessRevision'=>$head['payload']['accessRevision'],'membershipHeadHash'=>$head['headHash'],'envelopeBase64'=>$deleted?null:base64_encode(random_bytes(96)),'metadata'=>['identity'=>$identity,'references'=>$refs,'referenceVersions'=>[],'uniqueRefs'=>$unique,'blobIds'=>$blobIds]+(!$deleted&&in_array($type,['task','event','financeEntry','personalFinanceEntry'],true)?['reminderState'=>['version'=>1,'dueAtEpoch'=>time()+86400,'closed'=>false,'scheduleRevision'=>uid()]]:[])+(\Kanboard\Plugin\FamilyHub\Model\NativeCryptoRecordProofV2::notifiesType($type)?['notificationState'=>['version'=>1,'kind'=>$deleted?'deleted':($revision?'updated':'created'),'assigneeAccountIds'=>[],'groupTargetId'=>null]]:[])+($type==='project'?['projectState'=>['version'=>1,'archived'=>false]]:[])];
}
function batch2($records,$u,$key,$tableLeases=[]) {
    $batch=uid();$proofs=[];$digests=[];$groups=[];
    $indexed=[];$signed=[];$visiting=[];
    foreach($records as $row){$row['batchId']=$batch;$indexed[$row['scopeId'].':'.$row['id']]=$row;}
    $make=function($id)use(&$make,&$signed,&$visiting,$indexed,$key){
        if(isset($signed[$id]))return $signed[$id];
        if(isset($visiting[$id]))throw new RuntimeException('Synthetic cyclic reference proof');
        $visiting[$id]=true;$row=$indexed[$id];$versions=[];
        foreach($row['metadata']['references'] as $ref){
            $targetId=$ref['scopeId'].':'.$ref['id'];
            if(isset($indexed[$targetId])){$target=$indexed[$targetId];$proof=$make($targetId);$revision=$target['expectedRevision']+1;$domain=$target['domain'];}
            else{$stored=q('SELECT type,revision,authorization FROM familyhub_crypto_records WHERE scope_id=? AND id=?',[$ref['scopeId'],$ref['id']]);$target=$stored[0]??null;$proof=$target?json_decode($target['authorization'],true)['recordProof']:null;$revision=$target?(int)$target['revision']:1;$domain=$target?(new \Kanboard\Plugin\FamilyHub\Model\NativeCryptoRecordProofV2($GLOBALS['container']))->domain($target['type']):'content';}
            $versions[]=['scopeId'=>$ref['scopeId'],'id'=>$ref['id'],'domain'=>$domain,'revision'=>$revision,'recordProofHash'=>$proof?hash('sha256',NativeCryptoCodec::canonical((object)$proof)):str_repeat('0',64)];
        }
        usort($versions,fn($a,$b)=>strcmp($a['scopeId'].':'.$a['domain'].':'.$a['id'],$b['scopeId'].':'.$b['domain'].':'.$b['id']));
        $row['metadata']['referenceVersions']=$row['metadata']['referenceVersions']?:$versions;unset($visiting[$id]);return $signed[$id]=proof2($row,"JivieE2EE/record/v2\n",$key);
    };
    foreach($indexed as $id=>$row){$proof=$make($id);$proofs[]=$proof;$digest=hash('sha256',NativeCryptoCodec::canonical((object)$proof));$digests[]=$digest;$groups[$row['scopeId'].':'.$row['domain']][]=$digest;}
    sort($digests,SORT_STRING);
    $projectionGroups=[];foreach($groups as $groupId=>$hashes){sort($hashes,SORT_STRING);$projectionGroups[]=['token'=>hash('sha256',$batch.':'.$groupId),'recordDigests'=>$hashes];}usort($projectionGroups,fn($a,$b)=>strcmp($a['token'],$b['token']));
    $commitment=proof2(['version'=>2,'operation'=>'crypto2.batchCommitment','serverId'=>$u['serverId'],'accountId'=>$u['user']['accountId'],'deviceId'=>$u['device']['id'],'batchId'=>$batch,'recordDigests'=>$digests,'projectionGroups'=>$projectionGroups],"JivieE2EE/batch/v2\n",$key);
    return content2('crypto2.records.batch',['batchId'=>$batch,'records'=>$proofs,'commitment'=>$commitment]+($tableLeases?['tableLeases'=>$tableLeases]:[]),$u,$key);
}
