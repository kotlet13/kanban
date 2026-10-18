<?php
require __DIR__.'/crypto2-export-integration.php';
$account=$fresh['user']['accountId'];$reference=$certificate['authorDirectoryHeadHash'];
$query=['scopeId'=>$child['id'],'certificateHash'=>$cert['certificateHash'],'accountId'=>$account,'directoryHeadHash'=>$reference,'limit'=>1];
$page=call('crypto2.exports.evidence.directory',$query,$fresh);
ck(count($page['proofs'])===1&&$page['hasMore']&&$page['headHash']===$reference,'historical export identity evidence is bounded and anchored to exact stored prefix');
$different=$query;$different['accountId']=$alice['user']['accountId']===$account?uid():$alice['user']['accountId'];
deny(fn()=>call('crypto2.exports.evidence.directory',$different,$fresh),'permission_revoked','historical certificate cannot become arbitrary account directory oracle');
$wrongScope=$query;$wrongScope['scopeId']=$newId;
deny(fn()=>call('crypto2.exports.evidence.directory',$wrongScope,$fresh),'permission_revoked','historical certificate is confined to its exact target scope');
$policy=q('SELECT enabled FROM familyhub_finance_policy WHERE scope_id=?',[$child['id']])[0];
q('UPDATE familyhub_finance_policy SET enabled=0 WHERE scope_id=?',[$child['id']]);
try {
    ck(call('crypto2.scope.headGet',['scopeId'=>$child['id']],$fresh)['headHash']===$childHead['headHash'],'content access remains available while target finance read is absent');
    deny(fn()=>call('crypto2.exports.evidence.directory',$query,$fresh),'finance_forbidden','content-only reader cannot fetch historical target finance certificate evidence');
} finally {
    q('UPDATE familyhub_finance_policy SET enabled=? WHERE scope_id=?',[$policy['enabled'],$child['id']]);
}
$old=$query;$old['directoryHeadHash']=q('SELECT head_hash FROM familyhub_crypto_directory WHERE account_id=? AND generation=1',[$account])[0]['head_hash'];
deny(fn()=>call('crypto2.exports.evidence.directory',$old,$fresh),'permission_revoked','unreferenced earlier account prefix is not separately queryable');
$login=call('auth.login',['username'=>$alice['username'],'password'=>$alice['password'],'deviceName'=>'Historical export file recovery']);$newKey=keys();$current=call('crypto2.account.status',[],$login);$next=$current['snapshot'];$newEpoch=uid();
foreach($next['devices'] as &$device){if($device['revokedGeneration']===null)$device['revokedGeneration']=$current['generation']+1;}unset($device);
$next['identityEpochId']=$newEpoch;$next['devices'][]=dev2($login,$newKey,$newEpoch,$current['generation']+1);$next=sorted2($next);
call('crypto2.account.recoverEpoch',request2('crypto2.account.recoverEpoch',['newIdentityEpochId'=>$newEpoch,'newDeviceSigningKeyBase64'=>$newKey['signPublic'],'newDeviceEncryptionKeyBase64'=>$newKey['boxPublic']],$login,$root,$next,$current,'root'),$login);
$after=call('crypto2.exports.evidence.directory',$query,$login);
ck($after===$page,'current target reader retains exact historical export prefix after issuer device revocation');
$tail=$query;$tail['directoryHeadHash']=call('crypto2.account.status',[],$login)['headHash'];
deny(fn()=>call('crypto2.exports.evidence.directory',$tail,$login),'permission_revoked','historical evidence cannot expose newer unrelated account log tail');
$cursor=0;$count=0;
do{$part=call('crypto2.exports.evidence.directory',$query+[], $login);$count+=count($part['proofs']);$cursor=$part['nextGeneration'];$query['afterGeneration']=$cursor;}while($part['hasMore']);
ck($count===$page['generation']&&$cursor===$page['generation'],'historical evidence pages stop exactly at referenced generation after recovery');
$outsider=user('export_history_outsider');
deny(fn()=>call('crypto2.exports.evidence.directory',$query,$outsider),'permission_revoked','outsider cannot fetch a stored target export certificate directory');
echo 'Crypto2 historical export evidence integration: '.$checks.' checks PASS'.PHP_EOL;
