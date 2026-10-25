<?php
require __DIR__.'/account-changes-semantic-fixture.php';
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoDirectoryV2;
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoV2Codec;
$cursor=$probe(null)['cursor'];
semanticAppend(id(2),'crypto2.account.scopeObserve',['scopeToken'=>str_repeat('a',64),'headHash'=>str_repeat('b',64),'observationHash'=>str_repeat('c',64)]);
ck(!$probe($cursor)['changed'],'peer observation creates no false access hint in shared parent child or private own scope');
$peer=$directory->current(id(2));$next=json_decode($peer['snapshot'],true);$new=semanticDevice(id(222),$next['identityEpochId'],(int)$peer['generation']+1);$next['devices'][]=$new;
semanticAppend(id(2),'crypto2.device.add',array_intersect_key($new,array_flip(['deviceId','signingKeyBase64','encryptionKeyBase64','keyringWrite','manageDevices'])),$next);
$add=$probe($cursor);ck($add['accountDomains']===[]&&$add['scopes']===[['scopeId'=>id(3),'domains'=>['access']],['scopeId'=>id(6),'domains'=>['access']]],'real peer device add changes shared and inherited access without own private scope');$cursor=$add['cursor'];
$peer=$directory->current(id(2));$next=json_decode($peer['snapshot'],true);foreach($next['devices'] as &$d)if($d['deviceId']===id(222))$d['revokedGeneration']=(int)$peer['generation']+1;unset($d);
semanticAppend(id(2),'crypto2.device.revoke',['deviceId'=>id(222)],$next);
$revoke=$probe($cursor);ck($revoke['scopes']===[['scopeId'=>id(3),'domains'=>['access']],['scopeId'=>id(6),'domains'=>['access']]],'real signed peer device revoke retains exact affected access selection');$cursor=$revoke['cursor'];
sql('UPDATE familyhub_members SET active=0 WHERE scope_id=? AND account_id=?',[id(3),id(2)]);$inactive=$probe($cursor);ck($inactive['scopes']===[['scopeId'=>id(3),'domains'=>['access']],['scopeId'=>id(6),'domains'=>['access']]],'membership active change remains a real access hint');$cursor=$inactive['cursor'];
semanticAppend(id(2),'crypto2.account.scopeObserve',['scopeToken'=>str_repeat('a',64),'headHash'=>str_repeat('b',64),'observationHash'=>str_repeat('d',64)]);
ck(!$probe($cursor)['changed'],'retained inactive member observation does not wake access');
sql("UPDATE familyhub_members SET role='viewer' WHERE scope_id=? AND account_id=?",[id(3),id(2)]);ck(count($probe($cursor)['scopes'])===2,'inactive membership role metadata is conservatively preserved');$cursor=$probe(null)['cursor'];
$own=$directory->current(id(1));$next=json_decode($own['snapshot'],true);$entry=['id'=>id(500),'recipientId'=>$next['recoveryRootEpochId'],'recipientKind'=>'recovery','recipientPublicKeyBase64'=>$next['rootEncryptionKeyBase64'],'sealedEnvelopeBase64'=>base64_encode(str_repeat('K',48))];
$next['keyringEntries'][]=['id'=>$entry['id'],'recipientId'=>$entry['recipientId'],'recipientKind'=>'recovery','recipientPublicKeyBase64'=>$entry['recipientPublicKeyBase64'],'envelopeHash'=>hash('sha256',str_repeat('K',48)),'createdGeneration'=>(int)$own['generation']+1,'identityEpochId'=>$next['identityEpochId']];
semanticAppend(id(1),'crypto2.account.keyringEntriesPut',['entries'=>[$entry]],$next);
$keys=$probe($cursor);ck($keys['accountDomains']===['directory','access']&&count($keys['scopes'])===3,'real signed keyring update preserves own directory and semantic access hints');$cursor=$keys['cursor'];
// Root/recovery epoch values are persisted-metadata seams here, not a root
// transition/possession admission test. The real reducer covers the keyring and
// device operations above; full root/rebind algorithms are unchanged source.
foreach(['root-snapshot'=>['snapshot_hash'=>hash('sha256','new-root')],'recovery-epoch'=>['identity_epoch_id'=>id(999)],'device-rebind'=>['device_snapshot_hash'=>hash('sha256','new-device')]] as $kind=>$columns){
    foreach($columns as $column=>$value)sql('UPDATE familyhub_crypto_directory_state SET '.$column.'=? WHERE account_id=?',[$value,id(1)]);
    $expectedDomains=$kind==='device-rebind'?['directory','access']:['access'];
    $reply=$probe($cursor);ck($reply['accountDomains']===$expectedDomains&&count($reply['scopes'])===3,$kind.' persisted semantic metadata changes access even without log-column change');$cursor=$reply['cursor'];
}
sql('UPDATE users SET is_active=0 WHERE id=2');ck(count($probe($cursor)['scopes'])===2,'peer disabled-account metadata remains in member and inherited access stamp');sql('UPDATE users SET is_active=1 WHERE id=2');
$legacy=json_decode(base64_decode(explode('.',$cursor)[0]),true);$legacy['account']['access']=hash('sha256',json_encode(array_keys($legacy['scopes'])));foreach($legacy['scopes'] as &$domains)$domains['access']=hash('sha256','pre-semantic-stamp');unset($domains);
$bytes=base64_encode(json_encode($legacy));$key=hash_hmac('sha256',"JivieAccountChanges/v1\n",base64_decode(FAMILYHUB_ACCOUNT_MAIL_KEY_BASE64),true);$oldCursor=$bytes.'.'.hash_hmac('sha256',$bytes,$key);$upgraded=$probe($oldCursor);
ck(!$upgraded['resetRequired']&&$upgraded['accountDomains']===['access']&&count($upgraded['scopes'])===3,'old authenticated vector remains accepted with conservative one-time access baseline');
ck(!$probe($upgraded['cursor'])['changed'],'upgraded vector converges to stable nochange without schema or journal reset');
$before=sql('SELECT account_id,generation,head_hash,authorization FROM familyhub_crypto_directory ORDER BY account_id,generation')->fetchAll(\PDO::FETCH_ASSOC);$probe($upgraded['cursor']);
ck(sql('SELECT account_id,generation,head_hash,authorization FROM familyhub_crypto_directory ORDER BY account_id,generation')->fetchAll(\PDO::FETCH_ASSOC)===$before,'probing preserves original directory history proof bytes');
sql('UPDATE familyhub_devices SET revoked_at=1 WHERE id=?',[id(101)]);deny(fn()=> $probe($upgraded['cursor']),'device_revoked','current native bearer revocation still fails before hint disclosure');
semanticResult('account-changes-semantic-security');
