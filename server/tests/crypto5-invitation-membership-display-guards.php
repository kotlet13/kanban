<?php
/** NEW current-membership display projection; signed roster authority is unchanged. */
require __DIR__.'/crypto5-invitation-preauthorization-memory-fixture.php';
[$sid,$body,$head]=scopeFixture(3,$owner);
$body['members'][]=['accountId'=>$recipient['user']['account_id'],'rootSigningKeyBase64'=>$recipient['snapshot']['rootSigningKeyBase64'],'rootEncryptionKeyBase64'=>$recipient['snapshot']['rootEncryptionKeyBase64'],'recoveryRootEpochId'=>$recipient['snapshot']['recoveryRootEpochId'],'identityEpochId'=>$recipient['snapshot']['identityEpochId'],'directoryHeadHash'=>$recipient['head'],'deviceSnapshotHash'=>$recipient['deviceHash'],'role'=>'member','financeRole'=>'write','manageKeys'=>true];
sql("INSERT INTO familyhub_members VALUES(?,?,?,'member',0)",[$sid,$recipient['user']['id'],$recipient['user']['account_id']]);$head=installHead($sid,$body,$owner);
$pdo->exec('PRAGMA query_only=ON');$before=(int)$pdo->query('SELECT total_changes()')->fetchColumn();
$wire=$scopes->read('crypto2.scope.headGet',['scopeId'=>$sid,'headHash'=>$head],$owner);
ck($wire['acceptedAccountIds']===[$owner['user']['account_id']]&&count($wire['payload']['members'])===2,'head display excludes pending SQL member while preserving signed authorized roster');
ck((int)$pdo->query('SELECT total_changes()')->fetchColumn()===$before,'accepted member labels are a read-only host projection');$pdo->exec('PRAGMA query_only=OFF');
sql('UPDATE familyhub_members SET active=1 WHERE scope_id=? AND account_id=?',[$sid,$recipient['user']['account_id']]);
$expected=[$owner['user']['account_id'],$recipient['user']['account_id']];sort($expected,SORT_STRING);
$accepted=$scopes->read('crypto2.scope.headGet',['scopeId'=>$sid,'headHash'=>$head],$owner);
ck($accepted['acceptedAccountIds']===$expected&&$accepted['authorization']===$wire['authorization'],'trusted active membership updates labels without replacing signed head authorization');
$foreign=person(3,'synthetic_unlisted');sql("INSERT INTO familyhub_members VALUES(?,?,?,'member',1)",[$sid,$foreign['user']['id'],$foreign['user']['account_id']]);
ck($scopes->read('crypto2.scope.headGet',['scopeId'=>$sid,'headHash'=>$head],$owner)['acceptedAccountIds']===$expected,'current SQL member absent from exact head roster is not projected into that head');
sql('UPDATE familyhub_members SET active=0 WHERE scope_id=? AND account_id=?',[$sid,$recipient['user']['account_id']]);
ck($scopes->read('crypto2.scope.headGet',['scopeId'=>$sid,'headHash'=>$head],$owner)['acceptedAccountIds']===[$owner['user']['account_id']],'revoked or inactive membership does not remain visibly accepted');
sql('UPDATE familyhub_members SET active=1 WHERE scope_id=? AND account_id=?',[$sid,$recipient['user']['account_id']]);
[$child,$childBody]=scopeFixture(3,$owner,'project',$sid);$childBody['members'][]=$body['members'][1];$childHead=installHead($child,$childBody,$owner);
ck($scopes->read('crypto2.scope.headGet',['scopeId'=>$child,'headHash'=>$childHead],$owner)['acceptedAccountIds']===$expected,'policy3 child labels include accepted inherited parent membership');
sql('UPDATE familyhub_members SET active=0 WHERE scope_id=? AND account_id=?',[$sid,$recipient['user']['account_id']]);
ck($scopes->read('crypto2.scope.headGet',['scopeId'=>$child,'headHash'=>$childHead],$owner)['acceptedAccountIds']===[$owner['user']['account_id']],'pending or removed inherited parent membership stays absent from child accepted labels');
echo json_encode(['status'=>'pass','checks'=>$checks,'fixture'=>'new in-memory SQL signed-head display seam','authority'=>'acceptedAccountIds is current host display metadata only; signed payload and key authority unchanged','limitations'=>'No HTTP/native or full invitation run']).PHP_EOL;
