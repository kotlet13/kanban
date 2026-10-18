<?php
/** Real signed request/component routing on disposable SQL; no SMTP or deployment. */
require __DIR__.'/crypto2-access-integration.php';
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoV2Codec;

function leaveApprove2($sid,$source,$intent,$sources) {
    global $bob,$bobState,$bobKey,$actors;
    $pending=array_values(array_filter(call('crypto2.access.pending',['scopeId'=>$sid],$bob)['intents'],fn($r)=>$r['intentHash']===$intent['intentHash']))[0];
    $scope=array_values(array_filter(call('crypto2.scopes.catalog',[],$bob)['scopes'],fn($s)=>$s['id']===$sid))[0];
    $body=candidate2($scope,$bobState,$source['payload']['epoch']+1,$source['headHash'],['content'=>hash('sha256',''),'finance'=>hash('sha256','')]);
    $body['accessBasis']=$pending['accessBasis'];$body['accessRevision']=$pending['future']['accessRevision'];$body['members']=accessMembers2($pending['future']['members'],$actors);
    $body['accessIntentProof']=inner2(['version'=>2,'operation'=>'crypto2.access.scopeConsent','serverId'=>$bob['serverId'],'scopeId'=>$sid,'intentHash'=>$intent['intentHash'],'affectedCount'=>$intent['affectedCount'],'affectedHash'=>$intent['affectedHash'],'previousHeadHash'=>$source['headHash'],'expectedAccessRevision'=>$pending['expectedAccessRevision'],'accessBasis'=>$pending['accessBasis'],'resultingAccessRevision'=>$body['accessRevision'],'resultingDescriptor'=>$pending['future']['descriptor'],'resultingFinancePolicy'=>$pending['future']['financePolicy'],'membersHash'=>NativeCryptoV2Codec::hash($body['members']),'accountId'=>$bob['user']['accountId'],'deviceId'=>$bob['device']['id'],'authorDirectoryHeadHash'=>$bobState['headHash']],"JivieE2EE/accessScopeConsent/v2\n",$bobKey);
    $put=send2('crypto2.scope.headPut',$body,$bob,$bobKey);$head=call('crypto2.scope.headGet',['scopeId'=>$sid,'headHash'=>$put['headHash']],$bob);
    foreach(['content','finance'] as $domain) close2($sid,$head['headHash'],$source,$domain,$bobState,0,$bob,$bobKey);
    foreach($body['members'] as $m){[$u,$k,$r,$st]=$actors[$m['accountId']];accessGrants2($head,[...$sources,$head],$u,$k,$r,$st,$bob,$bobKey);}
    $manifest=call('crypto2.grants.manifest',['scopeId'=>$sid,'headHash'=>$head['headHash']],$bob);
    $inner=content2('crypto2.scope.activate',['scopeId'=>$sid,'headHash'=>$head['headHash'],'grantManifestHash'=>$manifest['grantManifestHash'],'authorDirectoryHeadHash'=>$bobState['headHash'],'accessIntentHash'=>$intent['intentHash'],'affectedCount'=>$intent['affectedCount'],'affectedHash'=>$intent['affectedHash']],$bob,$bobKey);
    send2('crypto2.access.approve',['intentHash'=>$intent['intentHash'],'scopeId'=>$sid,'activationProof'=>$inner],$bob,$bobKey);
    return $head;
}
function leavePrepare2($sid,$source,$requestHash) {
    global $bob,$bobState,$bobKey,$external;
    $catalog=array_values(array_filter(call('crypto2.scopes.catalog',[],$bob)['scopes'],fn($s)=>$s['id']===$sid))[0];
    return send2('crypto2.access.prepare',['scopeId'=>$sid,'membershipHeadHash'=>$source['headHash'],'expectedAccessRevision'=>$catalog['accessRevision'],'authorDirectoryHeadHash'=>$bobState['headHash'],'action'=>['kind'=>'memberRemove','accountId'=>$external['user']['accountId']],'leaveRequestHash'=>$requestHash],$bob,$bobKey);
}
function leaveRequest2($sid,$source) {
    global $external,$externalKey,$externalState;
    $catalog=array_values(array_filter(call('crypto2.scopes.catalog',[],$external)['scopes'],fn($s)=>$s['id']===$sid))[0];
    $proof=content2('crypto2.access.leaveRequest',['scopeId'=>$sid,'membershipHeadHash'=>$source['headHash'],'expectedAccessRevision'=>$catalog['accessRevision'],'authorDirectoryHeadHash'=>$externalState['headHash'],'expiresAtEpoch'=>time()+3600],$external,$externalKey);
    return [call('crypto2.access.leaveRequest',$proof,$external),$proof];
}
$sid=$project['id'];$source=$newHeads[$sid];
[$request,$requestProof]=leaveRequest2($sid,$source);
ck(call('crypto2.access.leaveRequest',$requestProof,$external)===$request,'actual viewer leave request has immutable lost-ACK receipt');
$intent=leavePrepare2($sid,$source,$request['requestHash']);
$prepared=leaveApprove2($sid,$source,$intent,[$childHead,$source]);
$before=q('SELECT * FROM familyhub_members WHERE scope_id=? ORDER BY account_id',[$sid]);
send2('crypto2.access.leaveCancel',['requestHash'=>$request['requestHash']],$external,$externalKey);
deny(fn()=>send2('crypto2.access.activate',['intentHash'=>$intent['intentHash'],'affectedCount'=>1,'affectedHash'=>$intent['affectedHash']],$bob,$bobKey),'crypto_leave_request_changed','cancel racing an already closed and approved manager plan prevents all ACL/head activation effects');
ck(q('SELECT * FROM familyhub_members WHERE scope_id=? ORDER BY account_id',[$sid])===$before&&call('crypto2.scope.headGet',['scopeId'=>$sid],$bob)['headHash']===$source['headHash'],'failed canceled leave preserves exact members and original active head');
$cancel=send2('crypto2.access.cancel',['intentHash'=>$intent['intentHash'],'affectedCount'=>1,'affectedHash'=>$intent['affectedHash']],$bob,$bobKey);
ck($cancel['cleanupRequired']===true,'request cancellation does not erase immutable domain closure or pretend old keys writable');
// Actual legitimate unchanged-membership recovery after the canceled closure.
$catalog=array_values(array_filter(call('crypto2.scopes.catalog',[],$bob)['scopes'],fn($s)=>$s['id']===$sid))[0];
$body=candidate2($catalog,$bobState,3,$source['headHash'],['content'=>hash('sha256',''),'finance'=>hash('sha256','')]);$body['accessBasis']=$catalog['accessBasis'];$body['members']=$source['payload']['members'];
$put=send2('crypto2.scope.headPut',$body,$bob,$bobKey);$cleanup=call('crypto2.scope.headGet',['scopeId'=>$sid,'headHash'=>$put['headHash']],$bob);
foreach(['content','finance'] as $domain) close2($sid,$cleanup['headHash'],$source,$domain,$bobState,0,$bob,$bobKey);
foreach($body['members'] as $m){[$u,$k,$r,$st]=$actors[$m['accountId']];accessGrants2($cleanup,[$childHead,$source,$cleanup],$u,$k,$r,$st,$bob,$bobKey);}
$manifest=call('crypto2.grants.manifest',['scopeId'=>$sid,'headHash'=>$cleanup['headHash']],$bob);
send2('crypto2.scope.activate',['scopeId'=>$sid,'headHash'=>$cleanup['headHash'],'grantManifestHash'=>$manifest['grantManifestHash'],'authorDirectoryHeadHash'=>$bobState['headHash']],$bob,$bobKey);
ck(call('crypto2.scope.headGet',['scopeId'=>$sid],$external)['headHash']===$cleanup['headHash'],'real cleanup successor preserves requester access and unchanged membership');
deny(fn()=>leavePrepare2($sid,$cleanup,$request['requestHash']),'crypto_leave_request_changed','a canceled original request cannot remove a member after later membership generation');
[$renewed,$renewedProof]=leaveRequest2($sid,$cleanup);
$nextIntent=leavePrepare2($sid,$cleanup,$renewed['requestHash']);
$nextHead=leaveApprove2($sid,$cleanup,$nextIntent,[$childHead,$source,$cleanup]);
$activation=content2('crypto2.access.activate',['intentHash'=>$nextIntent['intentHash'],'affectedCount'=>1,'affectedHash'=>$nextIntent['affectedHash']],$bob,$bobKey);
$applied=call('crypto2.access.activate',$activation,$bob);
ck($applied['state']==='applied'&&call('crypto2.access.activate',$activation,$bob)===$applied,'remaining real manager atomically removes viewer with exact final lost-ACK replay');
$status=call('crypto2.access.leaveStatus',['requestHash'=>$renewed['requestHash']],$external);
ck($status['state']==='applied'&&$status['headHash']===$nextHead['headHash']&&$status['intentHash']===$nextIntent['intentHash'],'own minimal leave outcome remains reachable after actual READ loss');
ck(call('crypto2.access.leaveRequest',$renewedProof,$external)===$renewed,'original signed request ACK stays byte exact after removal without requiring scope READ');
deny(fn()=>call('crypto2.scope.headGet',['scopeId'=>$sid],$external),'permission_revoked','minimal own outcome never grants content or head READ after leave');
deny(fn()=>send2('crypto2.access.leaveCancel',['requestHash'=>$renewed['requestHash']],$external,$externalKey),'crypto_leave_already_applied','late cancel cannot undo applied membership or restore old keys');
ck(q('SELECT active FROM familyhub_members WHERE scope_id=? AND account_id=?',[$sid,$external['user']['accountId']])[0]['active']==0,'actual final membership exclusion survives all request and cancel retries');
echo 'Crypto2 leave integration: '.$checks.' cumulative checks PASS'.PHP_EOL;
