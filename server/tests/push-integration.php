<?php
// Synthetic keys, in-memory HTTP capture, never calls Google or real devices.
require '/var/www/app/app/common.php';
if (!defined('FAMILYHUB_DEVELOPMENT_MODE') || FAMILYHUB_DEVELOPMENT_MODE !== true) { throw new RuntimeException('Development only'); }
use Kanboard\Plugin\FamilyHub\Model\NativeFcmConfig;
use Kanboard\Plugin\FamilyHub\Model\NativeFcmTransport;
use Kanboard\Plugin\FamilyHub\Model\NativePushCrypto;
use Kanboard\Plugin\FamilyHub\Model\NativePushService;
use Kanboard\Plugin\FamilyHub\Model\NativePushQueue;
use Kanboard\Plugin\FamilyHub\Model\NativeNotificationWriter;
use Kanboard\Plugin\FamilyHub\Model\NativeInboxService;
use Kanboard\Plugin\FamilyHub\Model\NativeAuthService;
use Kanboard\Plugin\FamilyHub\Model\NativeError;
$checks=0; $pdo=$container['db']->getConnection(); $prefix='fcm_'.bin2hex(random_bytes(6)); $devices=[];
function uuid() { $h=bin2hex(random_bytes(16));return substr($h,0,8).'-'.substr($h,8,4).'-4'.substr($h,13,3).'-a'.substr($h,17,3).'-'.substr($h,20); }
function check($ok,$description) { global $checks; if (!$ok) { throw new RuntimeException('FAIL: '.$description); } $checks++;echo 'PASS: '.$description.PHP_EOL; }
function rejected($callback,$code) { try { $callback(); } catch (NativeError $e) { return $e->errorCode===$code; } return false; }
function query($sql,$params=[]) { global $pdo; $q=$pdo->prepare($sql);$q->execute($params);$rows=$q->fetchAll(PDO::FETCH_ASSOC);$q->closeCursor();return $rows; }
function change($sql,$params=[]) { global $pdo; $q=$pdo->prepare($sql);$q->execute($params);$q->closeCursor(); }
function register($service,$token,$expected=0,$language='sl') { return $service->execute('push.register',['token'=>$token,'platform'=>'android','language'=>$language,'expectedRevision'=>$expected,'projectId'=>'synthetic-fcm']); }
function emit($scope,$account,$revision,$type='task',$category='tasks',$kind='task.assigned',$group=null) {
    global $pdo,$prefix;
    $pdo->beginTransaction();
    (new NativeNotificationWriter($GLOBALS['container']))->insert($scope,$account,null,$type,uuid(),$revision,$kind,$category,'personal',hash('sha256',$prefix.':'.$revision.':'.$type),$group);
    $pdo->commit();
    return (int)query('SELECT MAX(id) AS id FROM familyhub_inbox WHERE scope_id=?',[$scope])[0]['id'];
}
check(!NativeFcmConfig::configured(),'FCM defaults unavailable without explicit config');
$file=tempnam('/tmp','familyhub-fcm-synthetic-');chmod($file,0600);
define('FAMILYHUB_ENABLE_FCM',true);define('FAMILYHUB_FCM_SERVICE_ACCOUNT_FILE',$file);define('FAMILYHUB_FCM_PROJECT_ID','synthetic-fcm');
define('FAMILYHUB_PUBLIC_ROOT','/var/www');
$key=openssl_pkey_new(['private_key_bits'=>2048,'private_key_type'=>OPENSSL_KEYTYPE_RSA]);openssl_pkey_export($key,$private);
$credentials=['type'=>'service_account','project_id'=>'synthetic-fcm','client_email'=>'synthetic@synthetic-fcm.iam.gserviceaccount.com','token_uri'=>'https://oauth2.googleapis.com/token','private_key'=>$private];
file_put_contents($file,json_encode($credentials));
check(!NativeFcmConfig::configured(),'missing separate encryption key cannot claim configured');
define('FAMILYHUB_PUSH_KEY_BASE64',base64_encode(random_bytes(32)));
try {
    check(NativeFcmConfig::configured(),'offline validates synthetic RSA/config/key without network');
    foreach (['project_id'=>'different-project','token_uri'=>'https://evil.invalid/token','private_key'=>'not a private key'] as $field=>$bad) {
        file_put_contents($file,json_encode(array_merge($credentials,[$field=>$bad])));check(!NativeFcmConfig::configured(),'preflight rejects invalid '.$field.' without exposing value');
    }
    file_put_contents($file,json_encode($credentials));
    $publicFile='/var/www/app/data/'.$prefix.'-synthetic-credential.json';file_put_contents($publicFile,json_encode($credentials));chmod($publicFile,0600);
    unlink($file);symlink($publicFile,$file);check(!NativeFcmConfig::configured(),'preflight rejects credential symlink into configured public root');unlink($file);unlink($publicFile);file_put_contents($file,json_encode($credentials));chmod($file,0600);
    $accounts=[];$sessions=[];
    foreach (['a','b'] as $person) {
        $uid=$container['userModel']->create(['username'=>$prefix.'_'.$person,'password'=>bin2hex(random_bytes(16)),'role'=>'app-user']);
        $sessions[$person]=(new NativeAuthService($container))->issue($container['userModel']->getById($uid),'Synthetic push');$accounts[$person]=$sessions[$person]['user']['accountId'];$devices[]=$sessions[$person]['device']['id'];
    }
    $sessions['a2']=(new NativeAuthService($container))->issue($container['userModel']->getById($sessions['a']['user']['id']),'Second synthetic push');$devices[]=$sessions['a2']['device']['id'];
    $a=new NativePushService($container,'Bearer '.$sessions['a']['token'],$prefix);$b=new NativePushService($container,'Bearer '.$sessions['b']['token'],$prefix);$a2=new NativePushService($container,'Bearer '.$sessions['a2']['token'],$prefix);
    check(rejected(fn()=>(new NativePushService($container))->execute('push.state',[]),'auth_required'),'anonymous cannot register or inspect device');
    check($a->execute('push.state',[])['registration']['revision']===0,'new device has empty registration state');
    check(rejected(fn()=>$a->execute('push.register',['token'=>'synthetic','platform'=>'web','language'=>'sl']),'validation_error'),'unsupported platform rejected');
    check(rejected(fn()=>$a->execute('push.register',['token'=>'has whitespace','platform'=>'ios','language'=>'sl']),'validation_error'),'malformed registration token rejected');
    check(rejected(fn()=>$a->execute('push.register',['token'=>'synthetic','platform'=>'ios','language'=>'sl','projectId'=>'other-project']),'push_project_mismatch'),'wrong SDK project rejected before binding');
    $token1='synthetic-token-'.$prefix;$token2='synthetic-rotated-'.$prefix;
    $registration=register($a,$token1)['registration'];check($registration['registered'] && $registration['revision']===1,'current bearer device registered at revision1');
    check(register($a,$token1)['registration']===$registration,'lost ACK identical active registration succeeds before stale CAS');
    check(rejected(fn()=>register($b,$token1),'push_token_bound'),'same token cannot silently transfer to another account');
    check(rejected(fn()=>register($a2,$token1),'push_token_bound'),'same token cannot silently transfer to another device');
    $row=query('SELECT * FROM familyhub_push_registrations WHERE device_id=?',[$devices[0]])[0];
    check($row['token_hash']===hash('sha256',$token1) && strpos($row['token_cipher'],$token1)===false,'database stores token hash and authenticated ciphertext only');
    $server=(new \Kanboard\Plugin\FamilyHub\Model\NativeService($container))->dispatch('capabilities',[],'',$prefix);
    check($server['features']['externalPush'] && $server['pushProjectId']==='synthetic-fcm','configured capability exposes public project ID');
    $aad=NativePushCrypto::aad($server['serverId'],$row);check(NativePushCrypto::decrypt($row['token_cipher'],$aad)===$token1,'GCM ciphertext reconstructs exact token');
    check(rejected(fn()=>NativePushCrypto::decrypt($row['token_cipher'],$aad.'tampered'),'push_unavailable'),'GCM rejects account/device/revision AAD tampering');
    $scope=uuid();$group=uuid();
    change('INSERT INTO familyhub_scopes(id,kind,name,owner_id,sequence,created_at) VALUES(?,\'household\',\'Synthetic FCM\',?,0,?)',[$scope,$sessions['a']['user']['id'],time()]);
    foreach (['a','b'] as $person) { change('INSERT INTO familyhub_members(scope_id,user_id,account_id,role,active) VALUES(?,?,?,?,1)',[$scope,$sessions[$person]['user']['id'],$accounts[$person],$person==='a'?'owner':'member']); }
    $settings=['inApp'=>false,'email'=>false,'push'=>true,'sound'=>false];
    change('INSERT INTO familyhub_inbox_preferences VALUES(?,?,\'tasks\',?)',[$scope,$accounts['a'],json_encode($settings)]);
    register($a2,'second-device-'.$prefix);
    $ids=[];foreach ([1,2,3] as $revision) { $ids[]=emit($scope,$accounts['a'],$revision,'task','tasks','task.assigned',$group); }
    check(count(query('SELECT * FROM familyhub_push_jobs WHERE inbox_id IN (?,?,?)',$ids))===6,'three immutable events enqueue one job per active device atomically');
    $pdo->beginTransaction();(new NativeNotificationWriter($container))->insert($scope,$accounts['a'],null,'task',uuid(),3,'task.assigned','tasks','personal',hash('sha256',$prefix.':3:task'),$group);$pdo->commit();
    check(count(query('SELECT * FROM familyhub_push_jobs WHERE inbox_id IN (?,?,?)',$ids))===6,'idempotent inbox replay adds no push job');
    $inbox=new NativeInboxService($container,'Bearer '.$sessions['a']['token'],$prefix);
    $page=$inbox->execute('inbox.group',['id'=>$ids[2],'limit'=>2]);$tail=$inbox->execute('inbox.group',['id'=>$ids[2],'beforeId'=>$page['nextBeforeId'],'limit'=>2]);
    check($page['hasMore'] && count($page['items'])===2 && count($tail['items'])===1,'push-only exact group pagination includes all3 targets');
    check($inbox->execute('inbox.sync',['cursor'=>0])['items']===[],'inApp false remains excluded from in-app sync while push queued');
    check(rejected(fn()=>(new NativeInboxService($container,'Bearer '.$sessions['b']['token'],$prefix))->execute('inbox.group',['id'=>$ids[2]]),'permission_revoked'),'other recipient cannot discover group refs');
    emit($scope,$accounts['a'],4,'task','tasks','task.assigned',$group);
    check(count($inbox->execute('inbox.group',['id'=>$ids[2]])['items'])===3,'captured anchor excludes later group event');
    $captured=[];$oauth=0;$mode='accepted';
    $http=function ($url,$headers,$body) use (&$captured,&$oauth,&$mode,$key) {
        if ($url==='https://oauth2.googleapis.com/token') {
            $oauth++;parse_str($body,$form);$jwt=explode('.',$form['assertion']);$decode=fn($x)=>base64_decode(strtr($x,'-_','+/'));
            $claims=json_decode($decode($jwt[1]),true);
            check($claims['aud']==='https://oauth2.googleapis.com/token' && $claims['scope']==='https://www.googleapis.com/auth/firebase.messaging' && $claims['exp']-$claims['iat']===3600 && openssl_verify($jwt[0].'.'.$jwt[1],$decode($jwt[2]),openssl_pkey_get_details($key)['key'],OPENSSL_ALGO_SHA256)===1,'OAuth assertion is valid RS256 with fixed audience/scope/expiry');
            return ['status'=>200,'body'=>json_encode(['access_token'=>'synthetic-oauth','token_type'=>'Bearer','expires_in'=>3600])];
        }
        check($url==='https://fcm.googleapis.com/v1/projects/synthetic-fcm/messages:send','HTTP send uses fixed FCM project endpoint');
        $captured[]=json_decode($body,true)['message'];
        return match ($mode) {
            'accepted'=>['status'=>200,'body'=>'{"name":"projects/synthetic-fcm/messages/synthetic"}'],
            'retry'=>['status'=>429,'body'=>'{}','retryAfter'=>120],
            'unregistered'=>['status'=>404,'body'=>'{"error":{"details":[{"@type":"type.googleapis.com/google.firebase.fcm.v1.FcmError","errorCode":"UNREGISTERED"}]}}'],
            'invalid'=>['status'=>400,'body'=>'{"error":{"details":[{"@type":"type.googleapis.com/google.firebase.fcm.v1.FcmError","errorCode":"INVALID_ARGUMENT"}]}}'],
            'malformed'=>['status'=>200,'body'=>'not JSON'],
            'unauthorized'=>['status'=>401,'body'=>'{}'],
            default=>['status'=>403,'body'=>'{"error":{"details":[{"@type":"type.googleapis.com/google.firebase.fcm.v1.FcmError","errorCode":"SENDER_ID_MISMATCH"}]}}'],
        };
    };
    $transport=new NativeFcmTransport($http);
    $result=(new NativePushQueue($container))->run(20,$transport);
    check($result['accepted']===2 && count($captured)===2 && $result['coalesced']===6,'cron coalesces latest known group once per device');
    check($oauth===1,'short-lived OAuth token reused only in worker memory');
    $message=$captured[0];check($message['notification']['title']==='Jivie','generic FCM title identifies Jivie');check(array_keys($message['data'])===['type','serverId','accountId','notificationId'] && $message['data']['accountId']===$accounts['a'] && $message['data']['type']==='familyhub.inbox.v1','push data contains only strict identity/inbox references');
    check($message['android']['notification']['channel_id']==='familyhub_push_silent_v1' && !isset($message['apns']['payload']['aps']['sound']) && strlen($message['apns']['headers']['apns-collapse-id'])===64,'silent platform channel/APNs respects preference and bounded collapse ID');
    check(strpos(json_encode($message),$scope)===false && strpos(json_encode($message),'amountMinor')===false && strpos(json_encode($message),'task.assigned')===false,'payload leaks no scope/kind/financial content');
    check((new NativePushQueue($container))->run(20,$transport)['accepted']===0,'repeated cron does not resend accepted jobs');
    $old=emit($scope,$accounts['a'],5);register($a,$token2,1,'en');
    check(query('SELECT state FROM familyhub_push_jobs WHERE inbox_id=? AND device_id=?',[$old,$devices[0]])[0]['state']==='cancelled','token rotation cancels old-generation jobs');
    check(rejected(fn()=>register($a,$token1,0),'push_conflict'),'stale retry cannot rotate newer token backwards');
    check(rejected(fn()=>$a->execute('push.unregister',['expectedRevision'=>1]),'push_conflict'),'stale unregister cannot remove newer registration');
    $a->execute('push.unregister',['expectedRevision'=>2]);check(!$a->execute('push.unregister',['expectedRevision'=>2])['registration']['registered'],'lost unregister ACK retry is idempotent while disabled');
    check(register($b,$token2)['registration']['registered'],'explicit unregister permits safe token release/rebind');
    $a2->execute('push.unregister',[]);register($a,'retry-device-'.$prefix,3,'en');
    $mode='retry';$retryId=emit($scope,$accounts['a'],6);$r=(new NativePushQueue($container))->run(20,$transport);
    $job=query('SELECT * FROM familyhub_push_jobs WHERE inbox_id=? AND device_id=?',[$retryId,$devices[0]])[0];check($r['retry']===1 && $job['state']==='pending' && (int)$job['next_attempt']>=time()+110,'FCM transient error persists bounded Retry-After/backoff');
    change('UPDATE familyhub_members SET active=0 WHERE scope_id=? AND account_id=?',[$scope,$accounts['a']]);change('UPDATE familyhub_push_jobs SET next_attempt=0 WHERE inbox_id=?',[$retryId]);$before=count($captured);$r=(new NativePushQueue($container))->run(20,$transport);check($r['cancelled']===1 && count($captured)===$before,'membership revoked before retry prevents transport call');
    check(rejected(fn()=>$inbox->execute('inbox.group',['id'=>$ids[2]]),'permission_revoked'),'revoked membership hides historical group');
    change('UPDATE familyhub_members SET active=1 WHERE scope_id=? AND account_id=?',[$scope,$accounts['a']]);
    $settings['sound']=true;change('UPDATE familyhub_inbox_preferences SET settings=? WHERE scope_id=? AND category=\'tasks\'',[json_encode($settings),$scope]);
    $mode='accepted';emit($scope,$accounts['a'],7);(new NativePushQueue($container))->run(20,$transport);$last=end($captured);check($last['android']['notification']['channel_id']==='familyhub_push_sound_v1' && $last['apns']['payload']['aps']['sound']==='default' && $last['notification']['body']==='You have a new notification.','language and current sound preference determine generic payload');
    $mode='invalid';emit($scope,$accounts['a'],8);(new NativePushQueue($container))->run(20,$transport);check($a->execute('push.state',[])['registration']['registered'],'INVALID_ARGUMENT does not incorrectly erase token');
    $mode='malformed';$malformed=emit($scope,$accounts['a'],9);$r=(new NativePushQueue($container))->run(20,$transport);check($r['retry']===1,'malformed success cannot claim provider acceptance');change('UPDATE familyhub_push_jobs SET state=\'cancelled\' WHERE inbox_id=?',[$malformed]);
    $mode='unregistered';emit($scope,$accounts['a'],10);(new NativePushQueue($container))->run(20,$transport);check(!$a->execute('push.state',[])['registration']['registered'],'UNREGISTERED invalidates only bound current registration');
    register($a,'revoked-device-'.$prefix,5);emit($scope,$accounts['a'],11);(new NativeAuthService($container,'Bearer '.$sessions['a']['token'],$prefix))->execute('auth.revoke',['deviceId'=>$devices[0]]);
    check((int)query('SELECT active FROM familyhub_push_registrations WHERE device_id=?',[$devices[0]])[0]['active']===0 && query('SELECT state FROM familyhub_push_jobs WHERE device_id=? AND state IN (\'pending\',\'processing\')',[$devices[0]])===[],'device revoke atomically disables registration and pending deliveries');
    check(rejected(fn()=>$a->execute('push.state',[]),'device_revoked'),'revoked bearer cannot reregister');
    $job=['token'=>'synthetic-direct','accountId'=>$accounts['b'],'inboxId'=>1,'groupKey'=>'generic','kind'=>'generic','language'=>'sl','platform'=>'ios','sound'=>false,'expiresAt'=>time()+60];$mode='mismatch';check($transport->send($job,$server['serverId'])['status']==='rejected','sender/project mismatch never reports success');
    check((int)query('SELECT version FROM plugin_schema_versions WHERE plugin=\'familyhub\'')[0]['version']>=8,'additive push schema8 or newer recorded');
    $beforeOAuth=$oauth;$mode='unauthorized';check($transport->send($job,$server['serverId'])['status']==='retry','OAuth401 is retryable without provider body exposure');$mode='accepted';$transport->send($job,$server['serverId']);check($oauth===$beforeOAuth+1,'OAuth401 invalidates cached access token for renewal');
    $badOAuth=new NativeFcmTransport(fn($url,$headers,$body)=>['status'=>200,'body'=>'{"access_token":[],"token_type":"Bearer","expires_in":3600}']);check(rejected(fn()=>$badOAuth->send($job,$server['serverId']),'push_unavailable'),'malformed OAuth access token fails closed');
    check(rejected(fn()=>(new NativePushQueue($container))->run(51,$transport),'validation_error'),'cron rejects unbounded batch limit');
    change('INSERT INTO familyhub_inbox_preferences VALUES(?,?,\'tasks\',?)',[$scope,$accounts['b'],json_encode($settings)]);
    $expired=emit($scope,$accounts['b'],20);change('UPDATE familyhub_push_jobs SET expires_at=0 WHERE inbox_id=?',[$expired]);$before=count($captured);check((new NativePushQueue($container))->run(20,$transport)['cancelled']===1 && count($captured)===$before,'expired push job never calls provider');
    $leased=emit($scope,$accounts['b'],21);change('UPDATE familyhub_push_jobs SET state=\'processing\',lease_until=? WHERE inbox_id=?',[time()+120,$leased]);check((new NativePushQueue($container))->run(20,$transport)['examined']===0,'unexpired worker lease prevents competing dispatch');change('UPDATE familyhub_push_jobs SET lease_until=0 WHERE inbox_id=?',[$leased]);check((new NativePushQueue($container))->run(20,$transport)['accepted']===1,'expired worker lease recovers bounded delivery');
    change('INSERT INTO familyhub_finance_policy VALUES(?,1,1,0)',[$scope]);change('INSERT INTO familyhub_finance_grants VALUES(?,?,\'read\')',[$scope,$accounts['b']]);change('INSERT INTO familyhub_inbox_preferences VALUES(?,?,\'finance\',?)',[$scope,$accounts['b'],json_encode($settings)]);
    $financial=emit($scope,$accounts['b'],22,'financeEntry','finance','financeEntry.created');change('UPDATE familyhub_finance_grants SET access_level=\'none\' WHERE scope_id=? AND account_id=?',[$scope,$accounts['b']]);$before=count($captured);check((new NativePushQueue($container))->run(20,$transport)['cancelled']===1 && count($captured)===$before,'revoked financial grant prevents reference delivery');
    check(rejected(fn()=>(new NativeInboxService($container,'Bearer '.$sessions['b']['token'],$prefix))->execute('inbox.group',['id'=>$financial]),'finance_forbidden'),'financial group cannot bypass separate read grant');
    $raceFixture=tempnam('/tmp','familyhub-push-race-');chmod($raceFixture,0600);$raceToken='race-rotated-'.$prefix;
    file_put_contents($raceFixture,json_encode(['credentialFile'=>$file,'encryptionKey'=>FAMILYHUB_PUSH_KEY_BASE64,'bearer'=>$sessions['b']['token'],'ip'=>$prefix.'_race','newToken'=>$raceToken,'expectedRevision'=>1]));
    $raceId=emit($scope,$accounts['b'],25);
    $raceProcess=proc_open([PHP_BINARY,'/familyhub-tests/push-race-child.php',$raceFixture],[0=>['pipe','r'],1=>['pipe','w'],2=>['pipe','w']],$racePipes);
    if (!is_resource($raceProcess)) { throw new RuntimeException('Race child unavailable'); }
    if(trim(fgets($racePipes[1]))!=='ready'){throw new RuntimeException('Race child not ready');}
    $raceTransport=new class($raceProcess,$racePipes) {
        public $process;public $pipes=[];
        public function __construct($process,$pipes) { $this->process=$process;$this->pipes=$pipes; }
        public function send($job,$server) {
            fwrite($this->pipes[0],"go\n");fflush($this->pipes[0]);
            stream_set_blocking($this->pipes[1],false);usleep(150000);
            check(fread($this->pipes[1],8192)==='','device rotation waits while worker holds delivery locks');
            return ['status'=>'accepted','retryAfter'=>0];
        }
    };
    try {
        check((new NativePushQueue($container))->run(20,$raceTransport)['accepted']===1,'in-flight delivery linearizes before device rotation');
        stream_set_blocking($raceTransport->pipes[1],true);stream_set_timeout($raceTransport->pipes[1],5);$child=json_decode(fgets($raceTransport->pipes[1]),true);
        foreach($raceTransport->pipes as $pipe){fclose($pipe);}check(proc_close($raceTransport->process)===0 && $child['registered'] && $child['revision']===2,'waiting rotation completes after worker commit');
        check(query('SELECT state FROM familyhub_push_jobs WHERE inbox_id=?',[$raceId])[0]['state']==='sent' && query('SELECT token_hash FROM familyhub_push_registrations WHERE device_id=?',[$devices[1]])[0]['token_hash']===hash('sha256',$raceToken),'old job remains accepted only for original generation, new binding separate');
    } finally { unlink($raceFixture); }
    emit($scope,$accounts['b'],23);change('UPDATE users SET password=? WHERE id=?',[password_hash(bin2hex(random_bytes(16)),PASSWORD_BCRYPT),$sessions['b']['user']['id']]);$before=count($captured);check((new NativePushQueue($container))->run(20,$transport)['cancelled']===1 && count($captured)===$before && (int)query('SELECT active FROM familyhub_push_registrations WHERE device_id=?',[$devices[1]])[0]['active']===0,'password change invalidates queue and registration before delivery');
    $new=(new NativeAuthService($container))->issue($container['userModel']->getById($sessions['b']['user']['id']),'Synthetic 2FA change');$devices[]=$new['device']['id'];$bs=new NativePushService($container,'Bearer '.$new['token'],$prefix);register($bs,'twofactor-device-'.$prefix);
    emit($scope,$accounts['b'],24);change('UPDATE users SET twofactor_activated=1,twofactor_secret=? WHERE id=?',['SYNTHETICSECRET',$sessions['b']['user']['id']]);$before=count($captured);check((new NativePushQueue($container))->run(20,$transport)['cancelled']===1 && count($captured)===$before,'2FA change invalidates queued device fingerprint');
    echo 'SUCCESS '.$checks.' push checks ('.$pdo->getAttribute(PDO::ATTR_DRIVER_NAME).')'.PHP_EOL;
} finally {
    unlink($file);
    foreach ($devices as $device) { (new NativePushService($container))->revokeDevice($device); }
}
