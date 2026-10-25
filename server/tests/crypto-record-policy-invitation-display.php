<?php
/** New host display hint only. No invitation consent/signature/HTTP claim. */
require __DIR__.'/account-changes-fixture.php';
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoInvitationV2;
$invitation=new NativeCryptoInvitationV2(['db'=>$db]);
$method=new ReflectionMethod(NativeCryptoInvitationV2::class,'previewScopeDisplay');$method->setAccessible(true);
$scope=['id'=>id(3),'kind'=>'project','effective_access_policy_version'=>3];
$old=$method->invoke($invitation,$scope);
ck($old['recordPolicyVersion']===0,'inactive invitation scope display explicitly reports the old policy');
sql('INSERT INTO familyhub_crypto_record_policy_state_v1 VALUES(?,?,1)',[id(3),id(90)]);
$active=$method->invoke($invitation,$scope);
$withoutHint=$active;unset($withoutHint['recordPolicyVersion']);
ck($active['recordPolicyVersion']===1&&$withoutHint===['id'=>id(3),'kind'=>'project','name'=>'Encrypted space','projectFinanceIncluded'=>true],'active display hint preserves all existing invitation scope values');
ck(!isset($active['role'],$active['financeRole'],$active['manageKeys'])&&(int)sql('SELECT policy_version FROM familyhub_crypto_record_policy_state_v1 WHERE scope_id=?',[id(3)])->fetchColumn()===1,'display hint neither assigns signed roles nor mutates policy state');
echo json_encode(['test'=>'crypto-record-policy-invitation-display','status'=>'pass','checks'=>$checks,'fixture'=>'isolated-memory-sqlite','displayHelper'=>true,'http'=>false,'consentOrAuthorityProof'=>false]).PHP_EOL;
