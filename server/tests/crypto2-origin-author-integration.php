<?php
require __DIR__.'/crypto2-creation-integration.php';
$initial=call('crypto2.scope.lifecycle.baseline',['scopeId'=>$child['id']],$fresh);
[$publicOrigin]=\Kanboard\Plugin\FamilyHub\Model\NativeCryptoCodec::decode($initial['originAuthorization']);
ck($publicOrigin['operation']==='crypto2.scope.origin'&&!isset($publicOrigin['payload'])&&!str_contains(json_encode($publicOrigin),$newId),'child public origin contains only opaque parent token, never private outer parent scope ID');
$uninitialized=send2('crypto2.scope.create',['id'=>uid(),'kind'=>'organization'],$fresh,$freshKeys)['scope'];
$approver=call('crypto2.account.status',[],$fresh);
$newDevice=call('auth.login',['username'=>$alice['username'],'password'=>$alice['password'],'deviceName'=>'Origin approved second']);
$newKeys=keys();$next=$approver['snapshot'];$next['devices'][]=dev2($newDevice,$newKeys,$next['identityEpochId'],$approver['generation']+1);$next=sorted2($next);
$add=request2('crypto2.device.add',['deviceId'=>$newDevice['device']['id'],'signingKeyBase64'=>$newKeys['signPublic'],'encryptionKeyBase64'=>$newKeys['boxPublic'],'keyringWrite'=>true,'manageDevices'=>true],$fresh,$freshKeys,$next,$approver);
call('crypto2.device.add',$add,$fresh);
$latest=call('crypto2.account.status',[],$newDevice);
$badGenesis=candidate2($uninitialized,$latest);
deny(fn()=>send2('crypto2.scope.headPut',$badGenesis,$newDevice,$newKeys),'crypto_scope_origin_author_mismatch','approved second device cannot substitute for exact original genesis creator');
ck(count(q('SELECT head_hash FROM familyhub_crypto_scope_heads WHERE scope_id=?',[$uninitialized['id']]))===0,'rejected genesis substitution persists no head/key reservations');
$goodGenesis=candidate2($uninitialized,$latest);
ck(send2('crypto2.scope.headPut',$goodGenesis,$fresh,$freshKeys)['state']==='pendingKeys','original active creator can finish genesis after harmless approved device directory growth');
echo 'Crypto2 origin author integration: '.$checks.' checks PASS'.PHP_EOL;
