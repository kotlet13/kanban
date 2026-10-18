<?php
/** Synthetic discovery/lease regression only; all transports are in-memory. */
define('FAMILYHUB_SMTP_HOST','127.0.0.1');
define('FAMILYHUB_SMTP_PORT',25252);
define('FAMILYHUB_SMTP_ENCRYPTION','none');
define('FAMILYHUB_SMTP_ALLOW_LOCAL_PLAINTEXT',true);
define('FAMILYHUB_SMTP_FROM','sender@capture.invalid');
require '/var/www/app/app/common.php';
if (!defined('FAMILYHUB_DEVELOPMENT_MODE') || FAMILYHUB_DEVELOPMENT_MODE!==true) throw new RuntimeException('Development only');
use Kanboard\Plugin\FamilyHub\Model\NativeAuthService;
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoFence;
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoNotificationV2;
use Kanboard\Plugin\FamilyHub\Model\NativeDeliveryService;
use Kanboard\Plugin\FamilyHub\Model\NativePushCrypto;
use Kanboard\Plugin\FamilyHub\Model\NativePushQueue;
use Kanboard\Plugin\FamilyHub\Model\NativePushWorker;
use Kanboard\Plugin\FamilyHub\Model\NativeReminderService;
use Kanboard\Plugin\FamilyHub\Schema\CryptoSchema;
$pdo=$container['db']->getConnection();
CryptoSchema::create($pdo,$pdo->getAttribute(PDO::ATTR_DRIVER_NAME)!=='sqlite');
$checks=0;$scopes=[];$uid=null;$file=tempnam('/tmp','worker-fairness-');chmod($file,0600);
function workerUuid(){ $h=bin2hex(random_bytes(16));return substr($h,0,8).'-'.substr($h,8,4).'-4'.substr($h,13,3).'-a'.substr($h,17,3).'-'.substr($h,20); }
function workerQ($sql,$args=[]){global $pdo;$q=$pdo->prepare($sql);$q->execute($args);$rows=$q->fetchAll(PDO::FETCH_ASSOC);$q->closeCursor();return $rows;}
function workerCheck($condition,$message){global $checks;if(!$condition)throw new RuntimeException('FAIL: '.$message);$checks++;echo 'PASS: '.$message.PHP_EOL;}
function workerScope($state=null,$parent=null,$origin=false){
    global $scopes,$uid,$account;$id=workerUuid();$scopes[]=$id;
    workerQ("INSERT INTO familyhub_scopes(id,kind,name,owner_id,sequence,created_at,parent_scope_id) VALUES(?,'household','Synthetic worker',?,0,?,?)",[$id,$uid,time(),$parent]);
    workerQ("INSERT INTO familyhub_members(scope_id,user_id,account_id,role,active) VALUES(?,?,?,'owner',1)",[$id,$uid,$account]);
    workerQ("INSERT INTO familyhub_inbox_preferences(scope_id,account_id,category,settings) VALUES(?,?,'tasks',?)",[$id,$account,json_encode(['inApp'=>true,'push'=>true,'email'=>true,'sound'=>false])]);
    if($state!==null)workerQ('INSERT INTO familyhub_crypto_scopes(scope_id,epoch,sequence,access_revision,state) VALUES(?,1,0,1,?)',[$id,$state]);
    if($origin)workerQ("INSERT INTO familyhub_crypto_scope_origins(scope_id,account_id,authorization,created_at) VALUES(?,?,'{}',?)",[$id,$account,time()]);
    return $id;
}
function workerInbox($sid,$next,$state='pending'){
    global $pdo,$account,$device,$tokenHash;
    workerQ("INSERT INTO familyhub_inbox(event_key,recipient_account_id,scope_id,category,kind,audience,actor_account_id,target_type,target_id,target_revision,group_key,created_at,read_at,revision,sequence,in_app) VALUES(?,?,?,'tasks','task.assigned','personal',NULL,'task',?,1,?, ?,NULL,1,1,1)",[hash('sha256',random_bytes(32)),$account,$sid,workerUuid(),workerUuid(),gmdate('Y-m-d\TH:i:s\Z')]);
    $id=(int)$pdo->lastInsertId();$lease=bin2hex(random_bytes(16));
    workerQ('INSERT INTO familyhub_deliveries(inbox_id,state,attempts,next_attempt,expires_at,lease_token,lease_until) VALUES(?,?,?,?,?,?,?)',[$id,$state,2,$next,time()+3600,$state==='processing'?$lease:null,$state==='processing'?0:null]);
    workerQ('INSERT INTO familyhub_push_jobs(inbox_id,device_id,registration_revision,token_hash,state,attempts,next_attempt,expires_at,lease_token,lease_until) VALUES(?,?,1,?,?,?,?,?,?,?)',[$id,$device,$tokenHash,$state,2,$next,time()+3600,$state==='processing'?$lease:null,$state==='processing'?0:null]);
    return [$id,$lease];
}
class FencingDeliveryFairness extends NativeDeliveryService {
    public $fenceScope;
    protected function transaction(callable $callback,$global=false){if($this->fenceScope){workerQ("UPDATE familyhub_crypto_scopes SET state='fenced' WHERE scope_id=?",[$this->fenceScope]);$this->fenceScope=null;}return parent::transaction($callback,$global);}
}
class FencingPushFairness extends NativePushQueue {
    public $fenceScope;
    protected function transaction(callable $callback,$global=false){if($this->fenceScope){workerQ("UPDATE familyhub_crypto_scopes SET state='fenced' WHERE scope_id=?",[$this->fenceScope]);$this->fenceScope=null;}return parent::transaction($callback,$global);}
}
try {
    $uid=$container['userModel']->create(['username'=>'worker_fairness_'.bin2hex(random_bytes(6)),'password'=>bin2hex(random_bytes(16)),'email'=>'worker@capture.invalid','role'=>'app-user']);
    $session=(new NativeAuthService($container))->issue($container['userModel']->getById($uid),'Synthetic fairness');
    $account=$session['user']['accountId'];$device=$session['device']['id'];
    define('FAMILYHUB_ENABLE_FCM',true);define('FAMILYHUB_FCM_SERVICE_ACCOUNT_FILE',$file);define('FAMILYHUB_FCM_PROJECT_ID','synthetic-fairness');define('FAMILYHUB_PUBLIC_ROOT','/var/www');define('FAMILYHUB_PUSH_KEY_BASE64',base64_encode(random_bytes(32)));
    $key=openssl_pkey_new(['private_key_bits'=>2048,'private_key_type'=>OPENSSL_KEYTYPE_RSA]);openssl_pkey_export($key,$private);
    file_put_contents($file,json_encode(['type'=>'service_account','project_id'=>FAMILYHUB_FCM_PROJECT_ID,'client_email'=>'synthetic@synthetic-fairness.iam.gserviceaccount.com','token_uri'=>'https://oauth2.googleapis.com/token','private_key'=>$private]));
    $token='synthetic-'.bin2hex(random_bytes(12));$tokenHash=hash('sha256',$token);$reg=['account_id'=>$account,'device_id'=>$device,'revision'=>1];
    $cipher=NativePushCrypto::encrypt($token,NativePushCrypto::aad($session['serverId'],$reg));
    workerQ("INSERT INTO familyhub_push_registrations(device_id,account_id,token_hash,token_cipher,project_id,platform,language,revision,active,updated_at,notification_format) VALUES(?,?,?,?,?,'android','en',1,1,?,2)",[$device,$account,$tokenHash,$cipher,FAMILYHUB_FCM_PROJECT_ID,time()]);
    $fenced=workerScope('fenced');$verified=workerScope('verified');$parent=workerScope('fenced');$child=workerScope(null,$parent);$active=workerScope(null,null,true);$live=workerScope('preparing');
    $blocked=[];
    foreach([$fenced,$verified,$child,$active] as $i=>$sid){[$id,$lease]=workerInbox($sid,-100000-$i,$i%2?'processing':'pending');$blocked[]=[$id,$lease];}
    [$liveId]=workerInbox($live,-99990);
    $beforeMail=workerQ('SELECT * FROM familyhub_deliveries WHERE inbox_id IN ('.implode(',',array_fill(0,count($blocked),'?')).') ORDER BY inbox_id',array_column($blocked,0));
    $beforePush=workerQ('SELECT * FROM familyhub_push_jobs WHERE inbox_id IN ('.implode(',',array_fill(0,count($blocked),'?')).') ORDER BY inbox_id',array_column($blocked,0));
    $mail=new class{public $messages=[];function send($recipient,$id,$account){$this->messages[]=$id;return ['accepted'=>true];}};
    $push=new class{public $messages=[];function send($job,$server){$this->messages[]=$job['inboxId'];return ['status'=>'accepted'];}};
    $r=(new NativeDeliveryService($container))->run(1,$mail);
    workerCheck($r['accepted']===1 && $mail->messages===[$liveId],'mail LIMIT skips fenced/verified/parent-fenced/retired-legacy candidates');
    $r=(new NativePushQueue($container))->run(1,$push);
    workerCheck($r['accepted']===1 && $push->messages===[$liveId],'push LIMIT reaches unrelated eligible job behind frozen candidates');
    workerCheck(workerQ('SELECT * FROM familyhub_deliveries WHERE inbox_id IN ('.implode(',',array_fill(0,count($blocked),'?')).') ORDER BY inbox_id',array_column($blocked,0))===$beforeMail,'frozen mail pending and processing source bytes unchanged');
    workerCheck(workerQ('SELECT * FROM familyhub_push_jobs WHERE inbox_id IN ('.implode(',',array_fill(0,count($blocked),'?')).') ORDER BY inbox_id',array_column($blocked,0))===$beforePush,'frozen push pending and processing source bytes unchanged');
    $method=new ReflectionMethod(NativeDeliveryService::class,'deliver');
    [$id,$lease]=$blocked[1];$mailBefore=count($mail->messages);$pushBefore=count($push->messages);
    workerCheck($method->invoke(new NativeDeliveryService($container),$id,$lease,$mail,microtime(true)+90)==='retry','mail leased before fence defers without cancellation');
    $r=(new NativePushWorker($container))->deliver(['device_id'=>$device,'inbox_id'=>$id,'registration_revision'=>1],$lease,$push,microtime(true)+60);
    workerCheck($r['status']==='retry' && count($mail->messages)===$mailBefore && count($push->messages)===$pushBefore,'push leased before fence defers without transport');
    workerCheck(workerQ('SELECT * FROM familyhub_deliveries WHERE inbox_id IN ('.implode(',',array_fill(0,count($blocked),'?')).') ORDER BY inbox_id',array_column($blocked,0))===$beforeMail && workerQ('SELECT * FROM familyhub_push_jobs WHERE inbox_id IN ('.implode(',',array_fill(0,count($blocked),'?')).') ORDER BY inbox_id',array_column($blocked,0))===$beforePush,'deferred leased jobs retain exact original attempts/tokens/deadlines');
    [$raceId]=workerInbox($live,-99980);$before=workerQ('SELECT * FROM familyhub_deliveries WHERE inbox_id=?',[$raceId]);
    $race=new FencingDeliveryFairness($container);$race->fenceScope=$live;$race->run(1,$mail);
    workerCheck(workerQ('SELECT * FROM familyhub_deliveries WHERE inbox_id=?',[$raceId])===$before,'fence after mail discovery prevents attempt/lease mutation');
    workerQ("UPDATE familyhub_crypto_scopes SET state='preparing' WHERE scope_id=?",[$live]);$before=workerQ('SELECT * FROM familyhub_push_jobs WHERE inbox_id=?',[$raceId]);
    $race=new FencingPushFairness($container);$race->fenceScope=$live;$race->run(1,$push);
    workerCheck(workerQ('SELECT * FROM familyhub_push_jobs WHERE inbox_id=?',[$raceId])===$before,'fence after push discovery prevents attempt/lease mutation');
    workerQ("UPDATE familyhub_crypto_scopes SET state='preparing' WHERE scope_id=?",[$live]);
    $reminders=[];
    foreach([$fenced,$verified,$child,$active,$live] as $i=>$sid){$id=workerUuid();$reminders[]=$id;workerQ("INSERT INTO familyhub_reminders(id,scope_id,account_id,target_type,target_id,target_fingerprint,remind_at,remind_epoch,revision,state,schedule_mode) VALUES(?,?,?,'task',?,?,?, ?,4,'pending','absolute')",[$id,$sid,$account,workerUuid(),str_repeat('a',64),gmdate('Y-m-d\TH:i:s\Z',1),-100000+$i]);}
    $frozenReminderRows=workerQ('SELECT * FROM familyhub_reminders WHERE id IN (?,?,?,?) ORDER BY id',array_slice($reminders,0,4));
    $r=(new NativeReminderService($container))->runDue(1);
    workerCheck($r['examined']===1 && workerQ('SELECT state FROM familyhub_reminders WHERE id=?',[$reminders[4]])[0]['state']==='cancelled','legacy reminder LIMIT skips frozen prefix and processes eligible target independently');
    workerCheck(workerQ('SELECT * FROM familyhub_reminders WHERE id IN (?,?,?,?) ORDER BY id',array_slice($reminders,0,4))===$frozenReminderRows,'legacy frozen reminder exact revision/state/time preserved');
    $cryptoIds=[];
    foreach([$fenced,$active] as $i=>$sid){$id=workerUuid();$cryptoIds[]=$id;workerQ("INSERT INTO familyhub_crypto_reminders_v2(id,scope_id,account_id,target_type,target_id,domain,target_revision,schedule_revision,remind_at,remind_epoch,revision,state,schedule_mode,authorization) VALUES(?,?,?,'task',?,'content',1,?,?,?,4,'pending','absolute','{}')",[$id,$sid,$account,workerUuid(),workerUuid(),gmdate('Y-m-d\TH:i:s\Z',1),-100000+$i]);}
    $before=workerQ('SELECT * FROM familyhub_crypto_reminders_v2 WHERE id=?',[$cryptoIds[0]]);
    $r=(new NativeCryptoNotificationV2($container))->runDue(1);
    workerCheck($r['examined']===1 && workerQ('SELECT state FROM familyhub_crypto_reminders_v2 WHERE id=?',[$cryptoIds[1]])[0]['state']==='cancelled','crypto reminder discovery skips inert staged source and allows exact new origin');
    workerCheck(workerQ('SELECT * FROM familyhub_crypto_reminders_v2 WHERE id=?',[$cryptoIds[0]])===$before,'inert crypto reminder candidate remains unchanged');
    echo 'Crypto worker fence fairness: '.$checks.' checks PASS'.PHP_EOL;
} finally {
    if($scopes){$marks=implode(',',array_fill(0,count($scopes),'?'));$ids=workerQ('SELECT id FROM familyhub_inbox WHERE scope_id IN ('.$marks.')',$scopes);foreach($ids as $id){workerQ('DELETE FROM familyhub_push_jobs WHERE inbox_id=?',[$id['id']]);workerQ('DELETE FROM familyhub_deliveries WHERE inbox_id=?',[$id['id']]);}foreach(['familyhub_inbox','familyhub_inbox_preferences','familyhub_reminders','familyhub_crypto_reminders_v2','familyhub_crypto_scope_origins','familyhub_crypto_scopes','familyhub_members'] as $table){workerQ('DELETE FROM '.$table.' WHERE scope_id IN ('.$marks.')',$scopes);}workerQ('DELETE FROM familyhub_scopes WHERE id IN ('.$marks.')',$scopes);}
    if($uid!==null){workerQ('DELETE FROM familyhub_accounts WHERE user_id=?',[$uid]);workerQ('DELETE FROM users WHERE id=?',[$uid]);}
    if(is_file($file))unlink($file);
}
