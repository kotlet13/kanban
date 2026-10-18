<?php
/** Isolated helper contract only; dispatcher/atomic activation is tested separately. */
require __DIR__.'/crypto2-access-integration.php';
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoLeaveV2;
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoDirectoryV2;
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoCodec;
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoV2Codec;

q('CREATE TABLE IF NOT EXISTS familyhub_crypto_leave_requests_v2(request_hash VARCHAR(64) PRIMARY KEY,scope_id VARCHAR(36) NOT NULL,account_id VARCHAR(36) NOT NULL,device_id VARCHAR(36) NOT NULL,authorization TEXT NOT NULL,state VARCHAR(24) NOT NULL,expires_at BIGINT NOT NULL,intent_hash VARCHAR(64) NULL,result_head_hash VARCHAR(64) NULL)');
function leaveHelper2($u) {
    global $container;
    $helper = new NativeCryptoLeaveV2($container,'Bearer '.$u['token']);
    $actor = (new ReflectionMethod($helper,'actor'))->invoke($helper);
    return [$helper,$actor];
}
function leaveWrite2($op,$p,$u,$key) {
    global $container;
    $proof = content2($op,$p,$u,$key);
    [$command,$bytes,$signature] = NativeCryptoCodec::decode($proof);
    $directory = new NativeCryptoDirectoryV2($container);
    NativeCryptoV2Codec::verify($bytes,$signature,$directory->authorizeContent($command,$directory->current($u['user']['accountId'])));
    [$helper,$actor] = leaveHelper2($u);
    return [$helper->write($op,$p,$actor,$proof,$command),$proof];
}
$sid = $project['id'];
$catalog = array_values(array_filter(call('crypto2.scopes.catalog',[],$external)['scopes'],fn($s)=>$s['id']===$sid))[0];
$p = ['scopeId'=>$sid,'membershipHeadHash'=>$newHeads[$sid]['headHash'],'expectedAccessRevision'=>$catalog['accessRevision'],'authorDirectoryHeadHash'=>$externalState['headHash'],'expiresAtEpoch'=>time()+3600];
$before = q('SELECT * FROM familyhub_members WHERE scope_id=? ORDER BY account_id',[$sid]);
[$requested,$proof] = leaveWrite2('crypto2.access.leaveRequest',$p,$external,$externalKey);
ck($requested['state']==='pending'&&$requested['requestHash']===NativeCryptoV2Codec::hash((object)$proof),'nonmanager viewer may sign a removal request without signing a new head or receiving management authority');
ck(q('SELECT * FROM familyhub_members WHERE scope_id=? ORDER BY account_id',[$sid])===$before,'request alone changes no membership or key authority');
[$helper,$actor] = leaveHelper2($external);
$status = $helper->read('crypto2.access.leaveStatus',['requestHash'=>$requested['requestHash']],$actor);
ck($status['state']==='pending'&&$status['headHash']===null,'own minimal outcome contains no scope roster or ciphertext');
[$manager,$managerActor] = leaveHelper2($bob);
$pending = $manager->read('crypto2.access.leaveRequests',['scopeId'=>$sid,'limit'=>1],$managerActor);
ck(count($pending['requests'])===1&&$pending['requests'][0]['authorization']===$proof,'current real manager discovers exact signed viewer request');
deny(fn()=>$helper->read('crypto2.access.leaveRequests',['scopeId'=>$sid],$actor),'permission_revoked','viewer request never grants manager discovery access');
[$other,$otherActor] = leaveHelper2($ordinary);
deny(fn()=>$other->read('crypto2.access.leaveStatus',['requestHash'=>$requested['requestHash']],$otherActor),'permission_revoked','foreign member cannot read another account minimal leave outcome');
$ownerP=$p;$ownerP['authorDirectoryHeadHash']=$bobState['headHash'];
deny(fn()=>leaveWrite2('crypto2.access.leaveRequest',$ownerP,$bob,$bobKey),'scope_owner_transfer_required','owner must transfer ownership rather than request a fabricated ownerless scope');
$bad=$p;$bad['expiresAtEpoch']=time()+604801;
deny(fn()=>leaveWrite2('crypto2.access.leaveRequest',$bad,$external,$externalKey),'crypto_leave_request_changed','leave request expiry is bounded before storing any pending action');
$bad=$p;$bad['membershipHeadHash']=str_repeat('f',64);
deny(fn()=>leaveWrite2('crypto2.access.leaveRequest',$bad,$external,$externalKey),'crypto_leave_request_changed','request binds exact original authenticated membership head');
$planProof=content2('crypto2.access.prepare',['scopeId'=>$sid,'action'=>['kind'=>'memberRemove','accountId'=>$external['user']['accountId']],'leaveRequestHash'=>$requested['requestHash']],$bob,$bobKey);
$plan=['scope_id'=>$sid,'authorization'=>json_encode($planProof),'intent_hash'=>NativeCryptoV2Codec::hash((object)$planProof)];
$manager->validatePlan($plan);
ck(true,'manager linkage binds exact requester account, scope, source head and live signed request');
leaveWrite2('crypto2.access.leaveCancel',['requestHash'=>$requested['requestHash']],$external,$externalKey);
deny(fn()=>$manager->validatePlan($plan),'crypto_leave_request_changed','requester cancellation invalidates that linked component before final mutation');
ck(q('SELECT * FROM familyhub_members WHERE scope_id=? ORDER BY account_id',[$sid])===$before,'cancel preserves original writable membership and every unrelated member');
[$second] = leaveWrite2('crypto2.access.leaveRequest',$p,$external,$externalKey);
$oldHash=$newHeads[$sid]['headHash'];
q('UPDATE familyhub_scopes SET access_revision=access_revision+1 WHERE id=?',[$sid]);
deny(fn()=>$helper->assertPending($second['requestHash'],$sid,$external['user']['accountId']),'crypto_leave_request_changed','later membership generation requires explicit renewed request and cannot remove a rejoined member');
ck($helper->read('crypto2.access.leaveStatus',['requestHash'=>$second['requestHash']],$actor)['state']==='renewalRequired','stale own request is explicitly renewal-required, never silently re-enqueued');
q('UPDATE familyhub_scopes SET access_revision=access_revision-1 WHERE id=?',[$sid]);
q('UPDATE familyhub_crypto_leave_requests_v2 SET expires_at=0 WHERE request_hash=?',[$second['requestHash']]);
ck($helper->read('crypto2.access.leaveStatus',['requestHash'=>$second['requestHash']],$actor)['state']==='expired','expired request remains an explicit own outcome without automatic renewed consent');
q("UPDATE familyhub_crypto_leave_requests_v2 SET state='applied',intent_hash=?,result_head_hash=? WHERE request_hash=?",[str_repeat('c',64),$oldHash,$second['requestHash']]);
q('UPDATE familyhub_members SET active=0 WHERE scope_id=? AND account_id=?',[$sid,$external['user']['accountId']]);
ck($helper->read('crypto2.access.leaveStatus',['requestHash'=>$second['requestHash']],$actor)['state']==='applied','own minimal terminal outcome remains reachable after losing scope READ');
deny(fn()=>leaveWrite2('crypto2.access.leaveCancel',['requestHash'=>$second['requestHash']],$external,$externalKey),'crypto_leave_already_applied','cancel cannot claim to restore membership after a completed result');
echo 'Crypto2 leave helper integration: '.$checks.' cumulative checks PASS'.PHP_EOL;
