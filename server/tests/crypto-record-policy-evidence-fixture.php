<?php
/** New routing/privacy/page bounds; signed proof verification belongs to clients. */
require __DIR__.'/account-changes-fixture.php';
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoRecordPolicyV1;
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoCodec;
$service=new NativeCryptoRecordPolicyV1(['db'=>$db]);
$actor=['user'=>['id'=>2,'account_id'=>id(2)],'device'=>['id'=>id(102)]];
sql('INSERT INTO familyhub_members VALUES(?,?,?,?,1)',[id(3),2,id(2),'viewer']);sql('UPDATE familyhub_scopes SET access_policy_version=1 WHERE id=?',[id(3)]);
$head=str_repeat('a',64);$proof=json_encode(['fixture'=>'owner signature is independently verified by client']);
foreach([80,81] as $n)sql('INSERT INTO familyhub_crypto_record_policy_baselines_v1(scope_id,baseline_id,membership_head_hash,access_revision,content_sequence,finance_sequence,account_id,device_id,prepare_authorization,activation_authorization,baseline_count,baseline_root) VALUES(?,?,?,0,0,0,?,?,?,?,0,?)',[id(3),id($n),$head,id(1),id(101),$proof,$n===80?$proof:null,str_repeat('b',64)]);
sql('INSERT INTO familyhub_crypto_record_policy_state_v1 VALUES(?,?,1)',[id(3),id(80)]);
$f=['content'=>str_repeat('c',64),'assignment'=>str_repeat('d',64),'checked'=>str_repeat('e',64)];
foreach([8=>'financeEntry',10=>'task'] as $n=>$type){
    $entry=['id'=>id($n),'domain'=>$n===8?'finance':'content','type'=>$type,'recordProofHash'=>str_repeat('f',64),'createdByAccountId'=>id(1),'fieldCommitments'=>$f,'policyEnvelopeBase64'=>base64_encode(str_repeat('E',48))];
    sql('INSERT INTO familyhub_crypto_record_policy_entries_v1 VALUES(?,?,?,?,?,?)',[id(3),id(80),id($n),str_repeat('f',64),NativeCryptoCodec::canonical((object)$entry),json_encode(['fixture'=>$n===8?'FINANCE_PRIVATE_SENTINEL':'CONTENT_PUBLIC_SENTINEL'])]);
}
