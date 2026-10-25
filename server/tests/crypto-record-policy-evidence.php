<?php
require __DIR__.'/crypto-record-policy-evidence-fixture.php';
$page=$service->read('crypto2.scope.recordPolicy.baseline',['scopeId'=>id(3),'limit'=>1],$actor);
ck(count($page['records'])===1&&!$page['hasMore']&&$page['nextAfterId']===id(10),'finance filtering precedes pagination and exposes no hidden IDs');
ck(!str_contains(json_encode($page),'FINANCE_PRIVATE_SENTINEL'),'finance stage authorization never leaks through content routing');
$tail=$service->read('crypto2.scope.recordPolicy.baseline',['scopeId'=>id(3),'limit'=>1],$actor);
ck(count($tail['records'])===1&&$tail['records'][0]['entry']['id']===id(10)&&!$tail['hasMore'],'continuation reaches permitted content after filtered finance');
ck($tail['serverId']!==''&&$tail['accountId']===id(2)&&$tail['deviceId']===id(102)&&$tail['activeBaselineId']===id(80),'baseline response binds reader identity and active baseline');
$other=$service->read('crypto2.scope.recordPolicy.baseline',['scopeId'=>id(3),'baselineId'=>id(81)],$actor);
ck(!$other['active']&&$other['activeBaselineId']===id(80)&&$other['baselineId']===id(81),'selected unfinished baseline never claims to be the active baseline');
sql("INSERT INTO familyhub_finance_grants VALUES(?,?,'read')",[id(3),id(2)]);
$full=$service->read('crypto2.scope.recordPolicy.baseline',['scopeId'=>id(3)],$actor);
ck(count($full['records'])===2&&str_contains(json_encode($full),'FINANCE_PRIVATE_SENTINEL'),'separate actual finance grant permits finance baseline evidence');
for($n=20;$n<36;$n++){
    $entry=['id'=>id($n),'domain'=>'content','type'=>'task','recordProofHash'=>str_repeat('f',64),'createdByAccountId'=>id(1),'fieldCommitments'=>$f,'policyEnvelopeBase64'=>base64_encode(str_repeat('E',48))];
    sql('INSERT INTO familyhub_crypto_record_policy_entries_v1 VALUES(?,?,?,?,?,?)',[id(3),id(80),id($n),str_repeat('f',64),NativeCryptoCodec::canonical((object)$entry),json_encode(['fixtureStageProof'=>str_repeat('A',120000)])]);
}
$bounded=$service->read('crypto2.scope.recordPolicy.baseline',['scopeId'=>id(3),'limit'=>32],$actor);
ck(strlen(json_encode($bounded))<1250000&&$bounded['hasMore']&&$bounded['nextAfterId']!==id(35),'large repeated stage evidence uses byte budget and resumable pagination');
deny(fn()=> $service->read('crypto2.scope.recordPolicy.baseline',['scopeId'=>id(3),'limit'=>33],$actor),'invalid_cursor','baseline evidence has explicit bounded entry limit');
sql('UPDATE familyhub_members SET active=0 WHERE scope_id=? AND account_id=?',[id(3),id(2)]);
deny(fn()=> $service->read('crypto2.scope.recordPolicy.baseline',['scopeId'=>id(3)],$actor),'permission_revoked','fresh evidence read obeys actual membership revocation');
echo json_encode(['test'=>'crypto-record-policy-evidence','status'=>'pass','checks'=>$checks,'fixture'=>'isolated-memory-sqlite','http'=>false,'proofVerification'=>false]).PHP_EOL;
