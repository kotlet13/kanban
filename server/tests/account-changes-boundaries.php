<?php
/** Additional new controls only; does not rerun the metadata PASS set. */
require __DIR__.'/account-changes-fixture.php';
use Kanboard\Plugin\FamilyHub\Model\NativeAccountChanges;
use Kanboard\Plugin\FamilyHub\Model\NativeService;
if (!in_array('--dispatch-only', $argv, true)) {
sql("UPDATE familyhub_scopes SET kind='organization' WHERE id=?",[id(3)]);
sql("INSERT INTO familyhub_scopes(id,kind,name,owner_id,sequence,created_at,access_policy_version,parent_scope_id) VALUES(?,'project','PRIVATE_CHILD_SENTINEL',1,0,1,3,?)",[id(6),id(3)]);
$before=$probe(null);
ck(array_column($before['scopes'],'scopeId')===[id(3),id(4),id(6)],'version3 inherited child is discovered without direct child membership');
$current=$before['cursor'];sql('INSERT INTO familyhub_moderation_blocks(scope_id,account_id,created_at) VALUES(?,?,1)',[id(3),id(1)]);
$blocked=$probe($current);ck(array_column($probe(null)['scopes'],'scopeId')===[id(4)]&&$blocked['accountDomains']===['access'],'blocked parent hides inherited child and creates access hint');
sql('DELETE FROM familyhub_moderation_blocks');sql('INSERT INTO familyhub_members VALUES(?,?,?,?,1)',[id(6),1,id(1),'viewer']);
$current=$probe(null)['cursor'];sql('UPDATE familyhub_members SET active=0 WHERE scope_id=? AND account_id=?',[id(3),id(1)]);
ck(array_column($probe(null)['scopes'],'scopeId')===[id(4),id(6)]&&$probe($current)['accountDomains']===['access'],'direct child survives parent membership removal without private parent hint');
sql('UPDATE familyhub_members SET active=1 WHERE scope_id=? AND account_id=?',[id(3),id(1)]);
$current=$probe(null)['cursor'];
sql('INSERT INTO familyhub_crypto_lifecycle_log_v2 VALUES(?,1,?,?,?,?,?,?,?)',[id(3),str_repeat('a',64),str_repeat('0',64),'archive',1,0,str_repeat('b',64),'PROOF_SENTINEL']);
$lifecycle=$probe($current);ck($lifecycle['scopes']===[['scopeId'=>id(3),'domains'=>['access']],['scopeId'=>id(6),'domains'=>['access']]],'parent lifecycle revision invalidates parent and child access only');
$current=$probe(null)['cursor'];sql('INSERT INTO familyhub_crypto_directory_state VALUES(?,1,?,?,?,?,?)',[id(1),str_repeat('a',64),'SNAPSHOT_SENTINEL',str_repeat('b',64),str_repeat('c',64),id(99)]);
$directory=$probe($current);ck($directory['accountDomains']===['directory','access']&&count($directory['scopes'])===3,'initial own semantic directory state wakes directory and access without reading snapshot proofs');
$current=$probe(null)['cursor'];sql('UPDATE familyhub_crypto_directory_state SET generation=2 WHERE account_id=?',[id(1)]);
ck($probe($current)['changed'],'a later directory version arriving during apply remains visible to an older cursor');
sql('UPDATE familyhub_scopes SET access_policy_version=1,parent_scope_id=NULL WHERE id=?',[id(4)]);
$current=$probe(null)['cursor'];sql('UPDATE familyhub_finance_policy SET sequence=sequence+1 WHERE scope_id=?',[id(4)]);
ck(!$probe($current)['changed'],'finance activity without finance grant is absent from hints');
sql("INSERT INTO familyhub_finance_grants VALUES(?,?,'read')",[id(4),id(1)]);$allowed=$probe($current);
ck($allowed['scopes']===[['scopeId'=>id(4),'domains'=>['access','finance']]],'explicit finance grant changes access and exposes finance progress');
$current=$allowed['cursor'];sql('UPDATE familyhub_finance_policy SET sequence=sequence+1 WHERE scope_id=?',[id(4)]);
ck($probe($current)['scopes']===[['scopeId'=>id(4),'domains'=>['finance']]],'separately granted legacy finance progress stays finance only');
sql('UPDATE familyhub_devices SET expires_at=1 WHERE id=?',[id(101)]);deny(fn()=> $probe(null),'device_revoked','expired device cannot observe account metadata');
sql('UPDATE familyhub_devices SET expires_at=? WHERE id=?',[time()+3600,id(101)]);sql('UPDATE users SET is_active=0 WHERE id=1');deny(fn()=> $probe(null),'device_revoked','disabled account cannot observe hints');
sql('UPDATE users SET is_active=1 WHERE id=1');
}
$api=new NativeService(['db'=>$db]);$route=$api->dispatch('account.changes',['cursor'=>null],bearer(1),'synthetic-route');
ck($route['version']===1&&$route['accountId']===id(1),'public native dispatcher routes through authenticated metadata endpoint');
deny(fn()=> $api->dispatch('account.changes',['cursor'=>null],'','synthetic-route'),'auth_required','native dispatch rejects missing bearer before hints');
echo json_encode(['test'=>'account-changes-boundaries','status'=>'pass','checks'=>$checks,'fixture'=>'isolated-memory-sqlite','http'=>false,'proofVerification'=>false]).PHP_EOL;
