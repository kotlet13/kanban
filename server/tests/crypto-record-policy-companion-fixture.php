<?php
/** New fixed companion association seam; business admission remains independent. */
require __DIR__.'/account-changes-fixture.php';
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoRecordPolicyV1;
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoReservedRecordV2;
$policy=new NativeCryptoRecordPolicyV1(['db'=>$db]);sql('INSERT INTO familyhub_crypto_record_policy_state_v1 VALUES(?,?,1)',[id(3),id(90)]);
$server=sql('SELECT server_id FROM familyhub_instance')->fetchColumn();$hash=str_repeat('f',64);
$f=['content'=>str_repeat('a',64),'assignment'=>str_repeat('b',64),'checked'=>str_repeat('c',64)];
$task=['serverId'=>$server,'scopeId'=>id(3),'accountId'=>id(2),'deviceId'=>id(102),'batchId'=>id(70),'operationId'=>id(71),'id'=>id(10),'type'=>'task','domain'=>'content','contentContract'=>7,'deleted'=>false,'expectedRevision'=>1,'metadata'=>['identity'=>['canonicalId'=>id(20)],'recordPolicy'=>['version'=>1,'createdByAccountId'=>id(1),'operation'=>'edit','fieldCommitments'=>$f]]];
$intent=$task;$intent['id']=id(30);$intent['type']='taskDerivationIntent';$intent['contentContract']=6;$intent['metadata']=['identity'=>['canonicalId'=>NativeCryptoReservedRecordV2::derive($server,id(3),'taskDerivation:'.id(20))],'recordPolicyCompanion'=>['version'=>1,'taskId'=>id(10),'taskRevision'=>2,'taskProofHash'=>$hash]];
$entries=[['record'=>$task,'recordProofHash'=>$hash]];
