<?php
require __DIR__.'/crypto-record-policy-companion-fixture.php';
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoRecordPolicyV1;
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoReservedRecordV2;
ck($policy->companion($intent,$entries),'fixed task intent associates only with its exact same-batch task proof');
deny(fn()=> $policy->companion($intent,[]),'crypto_record_policy_companion','standalone internal record cannot claim a viewer exception');
$bad=$intent;$bad['operationId']=id(72);deny(fn()=> $policy->companion($bad,$entries),'crypto_record_policy_companion','companion cannot substitute another local operation');
$bad=$intent;$bad['metadata']['recordPolicyCompanion']['taskProofHash']=str_repeat('e',64);deny(fn()=> $policy->companion($bad,$entries),'crypto_record_policy_companion','claimed task digest must equal the submitted signed task proof');
$bad=$intent;$bad['metadata']['identity']['canonicalId']=id(99);deny(fn()=> $policy->companion($bad,$entries),'crypto_record_policy_companion','intent reserved identity is derived from the exact task canonical identity');
$bad=$intent;$bad['domain']='finance';$bad['type']='taskDerivationResolution';deny(fn()=> $policy->companion($bad,$entries),'crypto_record_policy_companion','fixed content companion exception never grants finance resolution writes');
$bad=$task;$bad['contentContract']=6;deny(fn()=> $policy->companion($intent,[['record'=>$bad,'recordProofHash'=>$hash]]),'crypto_record_policy_companion','old broad task contract cannot authorize an internal viewer write');
$bad=$intent;$bad['scopeId']=id(4);deny(fn()=> $policy->companion($bad,$entries),'crypto_record_policy_companion','inactive scope receives no new companion protocol claims');
$old=['metadata'=>json_encode(['recordPolicy'=>['version'=>1,'createdByAccountId'=>id(1),'operation'=>'edit','fieldCommitments'=>$f],'notificationState'=>['assigneeAccountIds'=>[]]])];
deny(fn()=> $policy->admit($task,$old,['id'=>id(3),'role'=>'viewer','kind'=>'project'],['user'=>['account_id'=>id(2)]]),'record_edit_forbidden','valid companion structure never replaces independent accepted task authorization');
echo json_encode(['test'=>'crypto-record-policy-companion','status'=>'pass','checks'=>$checks,'fixture'=>'isolated-memory-sqlite','http'=>false,'proofVerification'=>false]).PHP_EOL;
