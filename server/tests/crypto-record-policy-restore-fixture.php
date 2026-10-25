<?php
/** Restore admission over accepted-history SQL; no HTTP/receiver/key proof. */
require __DIR__.'/account-changes-fixture.php';
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoRecordPolicyV1;
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoRecordProofV2;
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoRecordAddressV2;
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoCodec;
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoV2Codec;
sql('INSERT INTO familyhub_crypto_record_policy_state_v1 VALUES(?,?,1)',[id(3),id(90)]);
$policy=new NativeCryptoRecordPolicyV1(['db'=>$db]);$codec=new NativeCryptoRecordProofV2(['db'=>$db]);
$f=['content'=>str_repeat('a',64),'assignment'=>str_repeat('b',64),'checked'=>str_repeat('c',64)];
$basePolicy=['version'=>1,'createdByAccountId'=>id(2),'operation'=>'delete','fieldCommitments'=>$f];
$server=sql('SELECT server_id FROM familyhub_instance')->fetchColumn();
$wire=NativeCryptoRecordAddressV2::derive($server,id(3),'content','records',id(30));
function acceptedRestoreHistory($wire,$type,$deletions){
    $hash=str_repeat('0',64);$hashes=[];$revision=0;
    foreach($deletions as $deleted){
        $record=['scopeId'=>id(3),'id'=>$wire,'type'=>$type,'domain'=>'content','expectedRevision'=>$revision,'previousRecordHash'=>$hash,'deleted'=>$deleted];
        $proof=['commandBase64'=>base64_encode(NativeCryptoCodec::canonical((object)$record)),'signatureBase64'=>base64_encode(str_repeat('S',64))];
        $hash=NativeCryptoV2Codec::hash((object)$proof);$revision++;
        sql('INSERT INTO familyhub_crypto_record_history VALUES(?,?,?,?,?,?,?,?,?)',[id(3),$wire,$revision,$revision,1,'content',$hash,json_encode($proof),'{}']);
        $hashes[$revision]=$hash;
    }
    return $hashes;
}
$hashes=acceptedRestoreHistory($wire,'householdPerson',[false,false,true,true]);
$old=['revision'=>4,'deleted'=>1,'metadata'=>json_encode(['recordPolicy'=>$basePolicy,'notificationState'=>['assigneeAccountIds'=>[id(1)]]])];
$record=['version'=>2,'operation'=>'crypto2.record','serverId'=>$server,'accountId'=>id(2),'deviceId'=>id(102),'batchId'=>id(70),'scopeId'=>id(3),'id'=>$wire,'type'=>'householdPerson','expectedRevision'=>4,'deleted'=>false,'epoch'=>1,'accessRevision'=>0,'membershipHeadHash'=>str_repeat('d',64),'domain'=>'content','contentContract'=>7,'operationId'=>id(71),'previousRecordHash'=>$hashes[4],'envelopeBase64'=>base64_encode(str_repeat('C',48)),
    'metadata'=>['references'=>[],'referenceVersions'=>[],'uniqueRefs'=>[],'blobIds'=>[],'identity'=>['canonicalId'=>id(30),'sourceKind'=>'records'],'recordPolicy'=>array_replace($basePolicy,['operation'=>'restore']),'recordRestore'=>['version'=>1,'tombstoneProofHash'=>$hashes[4],'previousLiveProofHash'=>$hashes[2]]]];
$scope=['id'=>id(3),'role'=>'viewer','kind'=>'organization'];$creator=['user'=>['account_id'=>id(2)]];$other=['user'=>['account_id'=>id(1)]];
