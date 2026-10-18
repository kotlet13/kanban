<?php
require __DIR__.'/crypto2-integration.php';
$state=call('crypto2.account.status',[],$fresh);
$payload=['migrationId'=>uid(),'scopeToken'=>hash('sha256','synthetic opaque scope'),'domain'=>'finance','attestationHash'=>hash('sha256','exact synthetic finalized certificate')];
$event=request2('crypto2.account.migrationAttest',$payload,$fresh,$freshKeys,$state['snapshot'],$state);
$ack=call('crypto2.account.migrationAttest',$event,$fresh);
ck($ack['generation']===$state['generation']+1&&$ack['snapshotHash']===$state['snapshotHash']&&$ack['deviceSnapshotHash']===$state['deviceSnapshotHash'],'migration event appends exact signed certificate commitment without changing account/key authority');
ck(call('crypto2.account.migrationAttest',$event,$fresh)===$ack,'migration attestation lost ACK preserves exact immutable log position');
$page=call('crypto2.account.directory',['afterGeneration'=>$state['generation'],'limit'=>1],$fresh);
ck($page['entries'][0]['authorization']===$event&&$page['entries'][0]['headHash']===$ack['headHash'],'cold bounded directory prefix contains exact certificate inclusion proof');
$state=call('crypto2.account.status',[],$fresh);
deny(fn()=>call('crypto2.account.migrationAttest',request2('crypto2.account.migrationAttest',$payload,$fresh,$root,$state['snapshot'],$state,'root'),$fresh),'crypto_signer_forbidden','root is not routine migration attestation authority');
$read=call('auth.login',['username'=>$fresh['username']??$alice['username'],'password'=>$fresh['password']??$alice['password'],'deviceName'=>'Read only migration evidence']);$readKey=keys();$next=$state['snapshot'];$next['devices'][]=dev2($read,$readKey,$next['identityEpochId'],$state['generation']+1,false);$next=sorted2($next);$add=request2('crypto2.device.add',['deviceId'=>$read['device']['id'],'signingKeyBase64'=>$readKey['signPublic'],'encryptionKeyBase64'=>$readKey['boxPublic'],'keyringWrite'=>false,'manageDevices'=>false],$fresh,$freshKeys,$next,$state);call('crypto2.device.add',$add,$fresh);$state=call('crypto2.account.status',[],$fresh);
deny(fn()=>call('crypto2.account.migrationAttest',request2('crypto2.account.migrationAttest',$payload,$read,$readKey,$state['snapshot'],$state),$read),'crypto_keyring_forbidden','active read device cannot mint manager migration commitments');
ck(call('crypto2.account.migrationAttest',$event,$fresh)===$ack,'historical exact event ACK survives later unrelated directory authority mutation');
echo 'Crypto2 migration attestation integration: '.$checks.' checks PASS'.PHP_EOL;
