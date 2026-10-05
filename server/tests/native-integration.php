<?php
// HTTP integration using disposable synthetic accounts only; never production.
require '/var/www/app/app/common.php';
use Otp\Otp;
use Base32\Base32;
if (!defined('FAMILYHUB_DEVELOPMENT_MODE') || FAMILYHUB_DEVELOPMENT_MODE !== true) { throw new RuntimeException('Local development only'); }
$checks = 0; $prefix = 'native_'.bin2hex(random_bytes(4)); $password = bin2hex(random_bytes(14));
$pdo = $container['db']->getConnection(); $sqlite = $pdo->getAttribute(PDO::ATTR_DRIVER_NAME) === 'sqlite';
// Guarded synthetic rate reset only; NEVER remove scopes, records, QA users or volumes.
foreach(['login-ip:', 'register-ip:', 'scopes-ip:', 'invitation-ip:', 'sync-ip:'] as $key) {
    $pdo->prepare('DELETE FROM familyhub_rate_limits WHERE id=?')->execute([hash('sha256',$key.'127.0.0.1')]);
}
function uuid()
{
    $h=bin2hex(random_bytes(16)); return substr($h,0,8).'-'.substr($h,8,4).'-4'.substr($h,13,3).'-a'.substr($h,17,3).'-'.substr($h,20);
}
function check($condition, $description)
{
    global $checks;
    if (!$condition) { throw new RuntimeException('FAIL: '.$description); }
    $checks++; echo 'PASS: '.$description.PHP_EOL;
}
function handle($operation, array $params=[], $token=null, array $headers=[])
{
    $ch=curl_init('http://127.0.0.1/index.php?controller=NativeApiController&action=handle&plugin=FamilyHub');
    $headers[]='Content-Type: application/json'; if ($token) { $headers[]='Authorization: Bearer '.$token; }
    curl_setopt_array($ch,[CURLOPT_POST=>true,CURLOPT_RETURNTRANSFER=>true,CURLOPT_HTTPHEADER=>$headers,CURLOPT_POSTFIELDS=>json_encode(['v'=>1,'op'=>$operation,'params'=>(object)$params])]);
    return $ch;
}
function call($operation,array $params=[],$token=null,array $headers=[])
{
    $ch=handle($operation,$params,$token,$headers); $raw=curl_exec($ch); $status=curl_getinfo($ch,CURLINFO_HTTP_CODE); curl_close($ch);
    $body=json_decode($raw,true); if (!is_array($body)) { throw new RuntimeException('Invalid native HTTP response'); }
    return ['status'=>$status,'body'=>$body];
}
function data($reply)
{
    if ($reply['status']!==200 || !isset($reply['body']['data'])) { throw new RuntimeException('Unexpected native status '.$reply['status'].' code '.($reply['body']['error']['code']??'unknown')); }
    return $reply['body']['data'];
}
function error($reply,$code,$status) { return $reply['status']===$status && ($reply['body']['error']['code']??'')===$code; }
function parallel(array $calls)
{
    $multi=curl_multi_init(); $handles=[];
    foreach($calls as [$op,$params,$token]) { $h=handle($op,$params,$token); $handles[]=$h; curl_multi_add_handle($multi,$h); }
    do { $code=curl_multi_exec($multi,$running); if($running) { curl_multi_select($multi,0.1); } } while($running && $code===CURLM_OK);
    $results=[]; foreach($handles as $h) { $results[]=['status'=>curl_getinfo($h,CURLINFO_HTTP_CODE),'body'=>json_decode(curl_multi_getcontent($h),true)]; curl_multi_remove_handle($multi,$h); curl_close($h); }
    curl_multi_close($multi); return $results;
}
function push($scope,$id,$type,$revision,$payload,$deleted=false,$op=null) { return ['scopeId'=>$scope,'operation'=>['opId'=>$op??uuid(),'recordId'=>$id,'type'=>$type,'expectedRevision'=>$revision,'deleted'=>$deleted,'payload'=>$payload]]; }
$names=[];$ids=[];
foreach(['owner','recipient','outsider','viewer','totp','locked','changed','recycled'] as $name) {
    $names[$name]=$prefix.'_'.$name;
    $ids[$name]=$container['userModel']->create(['username'=>$names[$name],'password'=>$password,'role'=>'app-user','name'=>'Synthetic']);
    check($ids[$name]>0,'synthetic '.$name.' account');
}
$caps=data(call('capabilities')); check($caps['version']===1 && $caps['enabled'] && $caps['features']['totp'] && $caps['features']['finance'] && $caps['features']['inbox'] && !$caps['features']['externalPush'] && !$caps['features']['smtp'],'native capabilities truthful');
check(data(call('capabilities'))['serverId']===$caps['serverId'],'server identity stable');
check(error(call('auth.me'),'auth_required',401),'no web/global authentication implicit');
check(error(call('auth.me',[],null,['Authorization: Basic '.base64_encode('jsonrpc:irrelevant')]),'auth_required',401),'Basic/global key cannot become native identity');
check(error(call('capabilities',[],null,['Origin: https://evil.example']),'origin_not_allowed',403),'foreign browser origin rejected');
check(call('capabilities',[],null,['Origin: http://127.0.0.1:18770'])['status']===200,'explicit development origin accepted');
$sessions=[];
foreach(['owner','recipient','outsider','viewer','changed','recycled'] as $name) {
    $sessions[$name]=data(call('auth.login',['username'=>$names[$name],'password'=>$password,'deviceName'=>'Synthetic device']));
}
$owner=$sessions['owner']['token']; $recipient=$sessions['recipient']['token']; $viewer=$sessions['viewer']['token']; $outsider=$sessions['outsider']['token'];
check($sessions['owner']['serverId']===$caps['serverId'] && strlen($sessions['owner']['user']['accountId'])===36,'session stable server/account identity');
$s=$pdo->prepare('SELECT token_hash FROM familyhub_devices WHERE id=?');$s->execute([$sessions['owner']['device']['id']]);check($s->fetchColumn()===hash('sha256',$owner),'device secret hash only');$s->closeCursor();
check(data(call('auth.me',[],$owner))['user']['accountId']===$sessions['owner']['user']['accountId'],'bearer device identifies own user');
$scope=uuid(); $create=['id'=>$scope,'kind'=>'household','name'=>'Synthetic household','requestId'=>uuid()];
check(data(call('scopes.create',$create,$owner))['scope']['role']==='owner','nonadmin user bootstraps owned household');
check(data(call('scopes.create',$create,$owner))['scope']['id']===$scope,'scope create replay safe');
check(error(call('sync.pull',['scopeId'=>$scope,'cursor'=>0],$outsider),'permission_revoked',403),'foreign scope denied');
check(error(call('scopes.members',['scopeId'=>$scope],$outsider),'permission_revoked',403),'foreign membership listing denied');
$inviteParams=['scopeId'=>$scope,'recipientUsername'=>$names['recipient'],'role'=>'member','requestId'=>uuid()];
$inv=data(call('invitations.create',$inviteParams,$owner));
check(data(call('invitations.create',$inviteParams,$owner))['token']===null,'invitation create retry cannot reveal or regenerate token');
$s=$pdo->prepare('SELECT token_hash FROM familyhub_invitations WHERE id=?');$s->execute([$inv['invitation']['id']]);check($s->fetchColumn()===hash('sha256',$inv['token']),'invitation secret hash only');$s->closeCursor();
check(data(call('invitations.preview',['token'=>$inv['token']]))['registrationAllowed']===false,'existing recipient preview distinct from register');
check(error(call('invitations.accept',['token'=>$inv['token']],$outsider),'invitation_invalid',403),'invitation recipient bound');
check(data(call('invitations.accept',['token'=>$inv['token']],$recipient))['scope']['role']==='member','existing account accepts native scope');
check(data(call('invitations.accept',['token'=>$inv['token']],$recipient))['scope']['role']==='member','accept replay preserves membership');
$viewInv=data(call('invitations.create',['scopeId'=>$scope,'recipientUsername'=>$names['viewer'],'role'=>'viewer','requestId'=>uuid()],$owner));
data(call('invitations.accept',['token'=>$viewInv['token']],$viewer));
$time='2026-10-04T12:00:00.000Z';$list=uuid();$item=uuid();
$listPayload=['title'=>'Synthetic list','createdAt'=>$time,'updatedAt'=>$time];
$listOp=push($scope,$list,'shoppingList',0,$listPayload);
$first=data(call('sync.push',$listOp,$owner)); check($first['record']['revision']===1,'first immutable operation applied');
$retry=data(call('sync.push',$listOp,$owner));check($retry['replayed'] && $retry['cursor']===$first['cursor'],'lost response retry exact idempotence');
$altered=$listOp;$altered['operation']['payload']['title']='Changed';check(error(call('sync.push',$altered,$owner),'idempotency_mismatch',409),'op ID cannot change content');
check(error(call('sync.push',push($scope,uuid(),'shoppingList',0,$listPayload),$viewer),'permission_revoked',403),'viewer cannot write');
check(call('sync.pull',['scopeId'=>$scope,'cursor'=>0],$viewer)['status']===200,'viewer can pull');
check(error(call('invitations.create',['scopeId'=>$scope,'recipientUsername'=>$names['outsider'],'role'=>'member','requestId'=>uuid()],$recipient),'permission_revoked',403),'member cannot invite');
$itemPayload=['listId'=>$list,'title'=>'Synthetic item','quantity'=>'2','isChecked'=>false,'createdAt'=>$time,'updatedAt'=>$time];
check(data(call('sync.push',push($scope,$item,'shoppingItem',0,$itemPayload),$recipient))['record']['revision']===1,'second person adds shopping item');
$editA=$itemPayload;$editA['isChecked']=true;$editB=$itemPayload;$editB['quantity']='3';
$races=parallel([['sync.push',push($scope,$item,'shoppingItem',1,$editA),$owner],['sync.push',push($scope,$item,'shoppingItem',1,$editB),$recipient]]);
$statuses=array_column($races,'status');sort($statuses);check($statuses===[200,409],'concurrent edits produce one winner and explicit conflict');
$conflict=$races[$races[0]['status']===409?0:1];check($conflict['body']['error']['details']['serverRecord']['revision']===2,'conflict returns authorized canonical current record');
$stale=push($scope,$item,'shoppingItem',1,$editA);$bad=call('sync.push',$stale,$owner);check(error($bad,'conflict',409),'stale revision conflict');
check(call('sync.push',$stale,$owner)['body']===$bad['body'],'conflict retry durable outcome');
$blockedDelete=push($scope,$list,'shoppingList',1,null,true);$blocked=call('sync.push',$blockedDelete,$owner);
check(error($blocked,'live_children',422),'parent deletion denied while children live');
check($blocked['body']['error']['details']['serverRecord']['id']===$list,'live-child rejection includes own authorized canonical record');
check(call('sync.push',$blockedDelete,$owner)['body']===$blocked['body'],'domain rejection durable on retry');
$pulled=data(call('sync.pull',['scopeId'=>$scope,'cursor'=>0,'limit'=>1],$recipient));check($pulled['hasMore'] && count($pulled['records'])===1,'pull paginates current records');
$next=data(call('sync.pull',['scopeId'=>$scope,'cursor'=>$pulled['cursor'],'limit'=>1],$recipient));check(!$next['hasMore'] && $next['cursor']===$next['scopeSequence'],'pull cursor includes sequence gaps safely');
check(error(call('sync.pull',['scopeId'=>$scope,'cursor'=>$next['cursor']+1],$owner),'invalid_cursor',422),'future cursor rejected');
data(call('sync.push',push($scope,$item,'shoppingItem',2,null,true),$owner));
check(error(call('sync.push',push($scope,$item,'shoppingItem',3,$itemPayload),$owner),'conflict',409),'tombstone cannot be resurrected');
data(call('sync.push',push($scope,$list,'shoppingList',1,null,true),$owner));
check(error(call('sync.push',push($scope,uuid(),'shoppingItem',0,$itemPayload),$owner),'parent_missing',422),'new child cannot attach deleted parent');
$projectScope=uuid();data(call('scopes.create',['id'=>$projectScope,'kind'=>'project','name'=>'Independent project','requestId'=>uuid()],$owner));
check(error(call('sync.pull',['scopeId'=>$projectScope,'cursor'=>0],$recipient),'permission_revoked',403),'household membership does not inherit project scope');
// Reader waits for an uncommitted scope sequence, then must read freshly
// committed data rather than an identity read's old repeatable-read snapshot.
$cursorRecord=uuid();$cursorFirst=data(call('sync.push',push($projectScope,$cursorRecord,'shoppingList',0,$listPayload),$owner));
if($sqlite){$pdo->exec('BEGIN IMMEDIATE');}else{$pdo->beginTransaction();}
$s=$pdo->prepare('SELECT sequence FROM familyhub_scopes WHERE id=?'.($sqlite?'':' FOR UPDATE'));$s->execute([$projectScope]);$committedSequence=(int)$s->fetchColumn()+1;$s->closeCursor();
$cursorPayload=$listPayload;$cursorPayload['title']='New committed title';
$pdo->prepare('UPDATE familyhub_records SET payload=?,revision=2,sequence=? WHERE scope_id=? AND id=?')->execute([json_encode($cursorPayload),$committedSequence,$projectScope,$cursorRecord]);
$pdo->prepare('UPDATE familyhub_scopes SET sequence=? WHERE id=?')->execute([$committedSequence,$projectScope]);
$multi=curl_multi_init();$waiting=handle('sync.pull',['scopeId'=>$projectScope,'cursor'=>$cursorFirst['cursor']],$owner);curl_multi_add_handle($multi,$waiting);
curl_multi_exec($multi,$running);usleep(250000);curl_multi_exec($multi,$running);
check($running>0,'pull waits while another transaction holds scope lock');
if($sqlite){$pdo->exec('COMMIT');}else{$pdo->commit();}
do{curl_multi_exec($multi,$running);if($running){curl_multi_select($multi,0.1);}}while($running);
$freshPull=json_decode(curl_multi_getcontent($waiting),true);curl_multi_remove_handle($multi,$waiting);curl_close($waiting);curl_multi_close($multi);
check(($freshPull['data']['records'][0]['revision']??null)===2 && $freshPull['data']['cursor']===$committedSequence,'blocked reader sees committed record before advancing cursor');
$registerName=$prefix.'_new';$regInv=data(call('invitations.create',['scopeId'=>$scope,'recipientUsername'=>$registerName,'role'=>'member','requestId'=>uuid()],$owner));
check(data(call('invitations.preview',['token'=>$regInv['token']]))['registrationAllowed'],'new username invite preview supports registration');
$registered=data(call('auth.register',['token'=>$regInv['token'],'username'=>$registerName,'password'=>$password,'displayName'=>'Synthetic new user','deviceName'=>'New device']));
check(data(call('scopes.list',[],$registered['token']))['scopes'][0]['id']===$scope,'invite registration atomically creates session and membership');
check(error(call('auth.register',['token'=>$regInv['token'],'username'=>$registerName,'password'=>$password,'displayName'=>'Synthetic','deviceName'=>'Retry']),'invitation_invalid',404),'registration cannot consume invitation twice');
$expired=data(call('invitations.create',['scopeId'=>$scope,'recipientUsername'=>$names['outsider'],'role'=>'member','requestId'=>uuid()],$owner));
$pdo->prepare('UPDATE familyhub_invitations SET expires_at=? WHERE id=?')->execute([time()-1,$expired['invitation']['id']]);
check(error(call('invitations.accept',['token'=>$expired['token']],$outsider),'invitation_invalid',404),'expired invitation denied');
$revocable=data(call('invitations.create',['scopeId'=>$scope,'recipientUsername'=>$names['outsider'],'role'=>'member','requestId'=>uuid()],$owner));
data(call('invitations.revoke',['scopeId'=>$scope,'invitationId'=>$revocable['invitation']['id'],'requestId'=>uuid()],$owner));
check(error(call('invitations.accept',['token'=>$revocable['token']],$outsider),'invitation_invalid',404),'revoked invitation denied');
data(call('scopes.removeMember',['scopeId'=>$scope,'userId'=>(int)$ids['recipient'],'requestId'=>uuid()],$owner));
check(error(call('sync.pull',['scopeId'=>$scope,'cursor'=>0],$recipient),'permission_revoked',403),'removed member cannot pull');
check(error(call('sync.push',$listOp,$recipient),'permission_revoked',403),'removed member cannot replay operation');
check(error(call('invitations.accept',['token'=>$inv['token']],$recipient),'permission_revoked',403),'accepted token cannot regrant revoked membership');
$secret=\Otp\GoogleAuthenticator::generateRandom();$container['db']->table('users')->eq('id',$ids['totp'])->update(['twofactor_activated'=>1,'twofactor_secret'=>$secret]);
$otp=(new Otp())->totp(Base32::decode($secret));
$login=['username'=>$names['totp'],'password'=>$password,'deviceName'=>'TOTP device'];
check(error(call('auth.login',$login),'two_factor_required',401),'correct password requires configured TOTP');
check(error(call('auth.login',$login+['otp'=>'000000']),'invalid_credentials',401),'invalid TOTP cannot issue device');
$totpSession=data(call('auth.login',$login+['otp'=>$otp]));check(strlen($totpSession['token'])>64,'valid TOTP issues device');
check(error(call('auth.login',$login+['otp'=>$otp]),'invalid_credentials',401),'TOTP time step cannot replay');
$container['db']->table('users')->eq('id',$ids['totp'])->update(['twofactor_secret'=>\Otp\GoogleAuthenticator::generateRandom()]);
check(error(call('auth.me',[],$totpSession['token']),'device_revoked',401),'TOTP secret change invalidates devices');
$container['userModel']->update(['id'=>$ids['changed'],'password'=>bin2hex(random_bytes(14))]);
check(error(call('auth.me',[],$sessions['changed']['token']),'device_revoked',401),'password change invalidates devices');
$newDevice=data(call('auth.login',['username'=>$names['owner'],'password'=>$password,'deviceName'=>'Second device']));
check(count(data(call('auth.devices',[],$owner))['devices'])>=2,'own active devices listed without tokens');
data(call('auth.revoke',['deviceId'=>$newDevice['device']['id']],$owner));
check(error(call('auth.me',[],$newDevice['token']),'device_revoked',401),'device revocation immediately denies reuse');
check(error(call('auth.revoke',['deviceId'=>$sessions['owner']['device']['id']],$outsider),'permission_revoked',403),'cannot revoke other account devices');
for($i=0;$i<8;$i++){call('auth.login',['username'=>$names['locked'],'password'=>'wrong-password','deviceName'=>'Locked']);}
check(error(call('auth.login',['username'=>$names['locked'],'password'=>$password,'deviceName'=>'Locked']),'invalid_credentials',401),'Kanboard account lock honored for correct password');
// Registration failure AFTER user/session insertion must roll back all effects.
$failName=$prefix.'_rollback';$failInv=data(call('invitations.create',['scopeId'=>$scope,'recipientUsername'=>$failName,'role'=>'member','requestId'=>uuid()],$owner));
$trigger='native_fail_'.bin2hex(random_bytes(4));
if($sqlite){$pdo->exec("CREATE TRIGGER $trigger BEFORE INSERT ON familyhub_members WHEN NEW.scope_id='$scope' AND NEW.role='member' BEGIN SELECT RAISE(ABORT,'synthetic failure'); END");}
else{$pdo->exec("CREATE TRIGGER $trigger BEFORE INSERT ON familyhub_members FOR EACH ROW SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='synthetic failure'");}
$failed=call('auth.register',['token'=>$failInv['token'],'username'=>$failName,'password'=>$password,'displayName'=>'Rollback','deviceName'=>'Rollback']);
$pdo->exec("DROP TRIGGER $trigger");
check($failed['status']===500,'synthetic registration persistence failure visible');
check(!$container['userModel']->getByUsername($failName),'failed registration does not leave user');
check(data(call('invitations.preview',['token'=>$failInv['token']]))['registrationAllowed'],'failed registration does not consume invite');
// Every race has a legitimate serial outcome; future requests deny revoked access.
for($i=0;$i<4;$i++){
    $raceInv=data(call('invitations.create',['scopeId'=>$scope,'recipientUsername'=>$names['recipient'],'role'=>'member','requestId'=>uuid()],$owner));
    $out=parallel([['invitations.accept',['token'=>$raceInv['token']],$recipient],['invitations.revoke',['scopeId'=>$scope,'invitationId'=>$raceInv['invitation']['id'],'requestId'=>uuid()],$owner]]);
    check(($out[0]['status']===200 && $out[1]['status']===409)||($out[0]['status']===404 && $out[1]['status']===200),'accept/revoke race has one valid serialized winner');
    if($out[0]['status']===200){data(call('scopes.removeMember',['scopeId'=>$scope,'userId'=>(int)$ids['recipient'],'requestId'=>uuid()],$owner));}
}
$join=data(call('invitations.create',['scopeId'=>$scope,'recipientUsername'=>$names['recipient'],'role'=>'member','requestId'=>uuid()],$owner));data(call('invitations.accept',['token'=>$join['token']],$recipient));
$record=uuid();$out=parallel([['sync.push',push($scope,$record,'shoppingList',0,$listPayload),$recipient],['scopes.removeMember',['scopeId'=>$scope,'userId'=>(int)$ids['recipient'],'requestId'=>uuid()],$owner]]);
check($out[1]['status']===200 && in_array($out[0]['status'],[200,403],true),'remove member/push race respects scope lock');
check(error(call('sync.pull',['scopeId'=>$scope,'cursor'=>0],$recipient),'permission_revoked',403),'race never leaves revoked member access');
// Delete/recreate same numeric core ID must not inherit previous device or scope.
$recycledId=$ids['recycled'];$oldAccount=$sessions['recycled']['user']['accountId'];
$recycledScope=uuid();data(call('scopes.create',['id'=>$recycledScope,'kind'=>'project','name'=>'Recycled identity test','requestId'=>uuid()],$sessions['recycled']['token']));
$pdo->prepare('DELETE FROM users WHERE id=?')->execute([$recycledId]);
$pdo->prepare('INSERT INTO users(id,username,password,role,is_active) VALUES(?,?,?,?,1)')->execute([$recycledId,$names['recycled'],password_hash($password,PASSWORD_BCRYPT),'app-user']);
$fresh=data(call('auth.login',['username'=>$names['recycled'],'password'=>$password,'deviceName'=>'Recreated user']));
check($fresh['user']['accountId']!==$oldAccount,'recycled numeric user has new durable account UUID');
check(error(call('auth.me',[],$sessions['recycled']['token']),'device_revoked',401),'recycled user cannot use former device');
check(error(call('sync.pull',['scopeId'=>$recycledScope,'cursor'=>0],$fresh['token']),'permission_revoked',403),'recycled user cannot inherit former scope');
check((new \Kanboard\Plugin\FamilyHub\Plugin($container))->getPluginVersion()==='0.5.0','packaged plugin version reports native feature');
// Durable rate-limiter test with a dedicated synthetic IP; no real user's limits.
$rateId=hash('sha256','login-ip:192.0.2.123');
$pdo->prepare('DELETE FROM familyhub_rate_limits WHERE id=?')->execute([$rateId]);
$pdo->prepare('INSERT INTO familyhub_rate_limits(id,window_start,attempts) VALUES(?,?,?)')->execute([$rateId,time(),60]);
try{(new \Kanboard\Plugin\FamilyHub\Model\NativeService($container))->dispatch('auth.login',['username'=>$prefix.'_unknown','password'=>$password,'deviceName'=>'Rate test'],'','192.0.2.123');$limited=false;}
catch(\Kanboard\Plugin\FamilyHub\Model\NativeError $e){$limited=$e->status===429 && $e->errorCode==='rate_limited';}
check($limited,'durable IP request budget rejects further login attempts');
$s=$pdo->prepare('SELECT attempts FROM familyhub_rate_limits WHERE id=?');$s->execute([$rateId]);check((int)$s->fetchColumn()===61,'denied login attempt remains counted');$s->closeCursor();
// HTTP preflight never includes cookie credentials or a wildcard origin.
$ch=curl_init('http://127.0.0.1/index.php?controller=NativeApiController&action=handle&plugin=FamilyHub');
curl_setopt_array($ch,[CURLOPT_CUSTOMREQUEST=>'OPTIONS',CURLOPT_RETURNTRANSFER=>true,CURLOPT_HEADER=>true,CURLOPT_HTTPHEADER=>['Origin: http://127.0.0.1:18770','Access-Control-Request-Method: POST','Access-Control-Request-Headers: Authorization, Content-Type']]);
$preflight=curl_exec($ch);$status=curl_getinfo($ch,CURLINFO_HTTP_CODE);curl_close($ch);
check($status===204 && stripos($preflight,'Access-Control-Allow-Origin: http://127.0.0.1:18770')!==false && stripos($preflight,'Access-Control-Allow-Credentials')===false,'strict bearer-only CORS preflight');
// Real project/task CRUD (not merely advertising type flags).
$projectId=uuid();$projectPayload=['title'=>'Synthetic project','description'=>'','area'=>'home','createdAt'=>$time,'updatedAt'=>$time];
check(data(call('sync.push',push($projectScope,$projectId,'project',0,$projectPayload),$owner))['record']['type']==='project','native project record create');
$taskId=uuid();$taskPayload=['title'=>'Synthetic task','notes'=>'','projectId'=>$projectId,'dueAt'=>null,'isCompleted'=>false,'createdAt'=>$time,'updatedAt'=>$time];
check(data(call('sync.push',push($projectScope,$taskId,'task',0,$taskPayload),$owner))['record']['payload']['projectId']===$projectId,'native task has authorized same-scope project');
$taskPayload['isCompleted']=true;check(data(call('sync.push',push($projectScope,$taskId,'task',1,$taskPayload),$owner))['record']['payload']['isCompleted'],'native task completes with revision check');
$crossScope=$taskPayload;check(error(call('sync.push',push($scope,uuid(),'task',0,$crossScope),$owner),'parent_missing',422),'cross-scope project reference cannot bypass membership');
$illegal=$taskPayload;$illegal['financeEntries']=[];check(error(call('sync.push',push($projectScope,$taskId,'task',2,$illegal),$owner),'validation_error',422),'financial or unknown payload fields rejected');
$illegal=$taskPayload;$illegal['notes']=str_repeat('x',4097);check(error(call('sync.push',push($projectScope,$taskId,'task',2,$illegal),$owner),'validation_error',422),'payload text byte limit enforced');
$illegal=$taskPayload;$illegal['createdAt']='2026-10-05T12:00:00.000Z';check(error(call('sync.push',push($projectScope,$taskId,'task',2,$illegal),$owner),'created_at_immutable',422),'record origin time cannot be rewritten');
// Synthetic valid large page, inserted only in this test's own isolated scope.
$largeScope=uuid();data(call('scopes.create',['id'=>$largeScope,'kind'=>'household','name'=>'Synthetic page budget','requestId'=>uuid()],$owner));
if($sqlite){$pdo->exec('BEGIN IMMEDIATE');}else{$pdo->beginTransaction();}
$insert=$pdo->prepare('INSERT INTO familyhub_records(scope_id,id,type,revision,deleted,payload,sequence,updated_at) VALUES(?,?,\'task\',1,0,?,?,?)');
for($i=1;$i<=140;$i++){$p=['title'=>'Page fixture','notes'=>str_repeat('č',2048),'projectId'=>null,'dueAt'=>null,'isCompleted'=>false,'createdAt'=>$time,'updatedAt'=>$time];$insert->execute([$largeScope,uuid(),json_encode($p,JSON_UNESCAPED_UNICODE),$i,$time]);}
$pdo->prepare('UPDATE familyhub_scopes SET sequence=140 WHERE id=?')->execute([$largeScope]);
if($sqlite){$pdo->exec('COMMIT');}else{$pdo->commit();}
$page=data(call('sync.pull',['scopeId'=>$largeScope,'cursor'=>0,'limit'=>500],$owner));
check($page['hasMore'] && count($page['records'])<140 && strlen(json_encode($page['records'],JSON_UNESCAPED_UNICODE))<524288,'pull page byte budget limits large Unicode payloads');
$page2=data(call('sync.pull',['scopeId'=>$largeScope,'cursor'=>$page['cursor'],'limit'=>500],$owner));
check(!$page2['hasMore'] && count($page['records'])+count($page2['records'])===140 && $page2['cursor']===140,'byte pagination preserves every record and final cursor');
$pdo->prepare('UPDATE familyhub_devices SET expires_at=? WHERE id=?')->execute([time()-1,$sessions['outsider']['device']['id']]);
check(error(call('auth.me',[],$outsider),'device_revoked',401),'expired device token denied');
echo 'SUCCESS '.$checks.' checks ('.$pdo->getAttribute(PDO::ATTR_DRIVER_NAME).')'.PHP_EOL;
