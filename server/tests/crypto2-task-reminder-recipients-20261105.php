<?php
/** New isolated SQL + real signature/policy/worker controls. No historical test
 * entrypoint, persistent database, HTTP, SMTP, OAuth or FCM request is invoked. */
require __DIR__.'/crypto5-invitation-preauthorization-memory-fixture.php';
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoNotificationV2 as Notifications;
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoCodec as Codec;
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoRecordAddressV2 as Address;
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoSchedulingUseV2 as Uses;
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoLifecycleV2 as Lifecycle;
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoDirectoryV2 as Directory;
use Kanboard\Plugin\FamilyHub\Model\NativePushCrypto;
use Kanboard\Plugin\FamilyHub\Model\NativePushWorker;
use Kanboard\Plugin\FamilyHub\Model\NativeDeliveryService;
use Kanboard\Plugin\FamilyHub\Schema\RecordPolicySchema;
use Kanboard\Plugin\FamilyHub\Schema\PushSchema;
use Kanboard\Plugin\FamilyHub\Schema\CollaborationSchema;

RecordPolicySchema::create($pdo, false);
$third=person(3,'synthetic_third');
$pdo->exec("CREATE TABLE familyhub_inbox(id INTEGER PRIMARY KEY AUTOINCREMENT,event_key VARCHAR(64),recipient_account_id TEXT,scope_id TEXT,category TEXT,kind TEXT,audience TEXT,actor_account_id TEXT,target_type TEXT,target_id TEXT,target_revision INTEGER,group_key TEXT,created_at TEXT,read_at TEXT,revision INTEGER DEFAULT 1,sequence INTEGER,in_app INTEGER,UNIQUE(event_key,recipient_account_id));
 CREATE TABLE familyhub_inbox_state(account_id TEXT PRIMARY KEY,sequence INTEGER DEFAULT 0,visibility_revision INTEGER DEFAULT 0,configuration_revision INTEGER DEFAULT 0);
 CREATE TABLE familyhub_inbox_preferences(scope_id TEXT,account_id TEXT,category TEXT,settings TEXT,PRIMARY KEY(scope_id,account_id,category));
 CREATE TABLE familyhub_devices(id TEXT PRIMARY KEY,user_id INTEGER,account_id TEXT,revoked_at INTEGER,expires_at INTEGER,credentials_hash TEXT);
 ALTER TABLE users ADD COLUMN password TEXT DEFAULT 'synthetic';
 ALTER TABLE users ADD COLUMN twofactor_activated INTEGER DEFAULT 0;
 ALTER TABLE users ADD COLUMN twofactor_secret TEXT DEFAULT '';
 ALTER TABLE users ADD COLUMN is_ldap_user INTEGER DEFAULT 0;
 ALTER TABLE users ADD COLUMN disable_login_form INTEGER DEFAULT 0;");
PushSchema::create($pdo, false);
$pdo->exec('ALTER TABLE familyhub_push_registrations ADD COLUMN notification_format INTEGER DEFAULT 2');
CollaborationSchema::createDelivery($pdo, false);
$notifications = new class($container) extends Notifications {
    public $deliveryScopeHook = null;
    public $deliveryScopeCalls = 0;
    public function lockDeliveryScope($sid) {
        $scope=parent::lockDeliveryScope($sid);
        $this->deliveryScopeCalls++;
        if ($this->deliveryScopeHook !== null) { ($this->deliveryScopeHook)($sid); }
        return $scope;
    }
    public function command($operation, $payload, $actor, $proof) {
        [$command] = Codec::decode($proof);
        // The API signature dispatcher is outside this fixture. Verify the
        // genuine device signature here before exercising the real write.
        [$decoded,$bytes,$signature] = Codec::decode($proof);
        \Kanboard\Plugin\FamilyHub\Model\NativeCryptoV2Codec::verify($bytes,$signature,$actor['snapshot']['devices'][0]['signingKeyBase64']);
        if (Codec::canonical((object)$decoded['payload']) !== Codec::canonical((object)$payload) || $decoded['operation'] !== $operation) { throw new RuntimeException('Synthetic command binding'); }
        return $this->transaction(fn() => $this->write($operation,$payload,$actor,$proof,$command));
    }
};

// Entirely synthetic ephemeral credential file only enables queue admission.
// Every actual worker send below uses an injected capture transport.
$credentialFile = tempnam(sys_get_temp_dir(), 'jivie-task-reminder-');
$rsa = openssl_pkey_new(['private_key_bits'=>2048,'private_key_type'=>OPENSSL_KEYTYPE_RSA]);
openssl_pkey_export($rsa, $syntheticKey);
file_put_contents($credentialFile,json_encode(['type'=>'service_account','project_id'=>'synthetic-reminder',
    'client_email'=>'synthetic@synthetic-reminder.iam.gserviceaccount.com',
    'token_uri'=>'https://oauth2.googleapis.com/token','private_key'=>$syntheticKey],JSON_THROW_ON_ERROR));
chmod($credentialFile,0600);
register_shutdown_function(static function() use($credentialFile) { @unlink($credentialFile); });
define('FAMILYHUB_ENABLE_FCM',true);
define('FAMILYHUB_ENABLE_NATIVE_API',true);
define('FAMILYHUB_FCM_PROJECT_ID','synthetic-reminder');
define('FAMILYHUB_FCM_SERVICE_ACCOUNT_FILE',$credentialFile);
define('FAMILYHUB_PUBLIC_ROOT',realpath(__DIR__.'/..'));
define('FAMILYHUB_PUSH_KEY_BASE64',base64_encode(random_bytes(32)));

function participant($actor,$role) {
    $s=$actor['snapshot'];
    return ['accountId'=>$actor['user']['account_id'],'rootSigningKeyBase64'=>$s['rootSigningKeyBase64'],
        'rootEncryptionKeyBase64'=>$s['rootEncryptionKeyBase64'],'recoveryRootEpochId'=>$s['recoveryRootEpochId'],
        'identityEpochId'=>$s['identityEpochId'],'directoryHeadHash'=>$actor['head'],'deviceSnapshotHash'=>$actor['deviceHash'],
        'role'=>$role,'financeRole'=>'write','manageKeys'=>$role!=='viewer'];
}
function sharedScope($scheduler,$assignee,$activePolicy=false,$schedulerRole='owner') {
    global $owner;
    [$sid,$body,$head]=scopeFixture(3,$owner);
    $members=[];
    foreach([[$owner,'owner'],[$scheduler,$schedulerRole],[$assignee,'member']] as [$actor,$role]) {
        $members[$actor['user']['account_id']]=participant($actor,$role);
        sql('INSERT OR REPLACE INTO familyhub_members VALUES(?,?,?,?,1)',[$sid,$actor['user']['id'],$actor['user']['account_id'],$role]);
    }
    $body['members']=array_values($members);usort($body['members'],fn($a,$b)=>strcmp($a['accountId'],$b['accountId']));
    $body['accessRevision']=0;$body['accessBasis']=[];
    $head=installHead($sid,$body,$owner);
    sql('INSERT INTO familyhub_crypto_scope_origins VALUES(?,?,?,?)',[$sid,$owner['user']['account_id'],json_encode(signCommand('synthetic.origin',['scopeId'=>$sid],$owner)),time()]);
    if($activePolicy)sql('INSERT INTO familyhub_crypto_record_policy_state_v1 VALUES(?,?,1)',[$sid,uid()]);
    return [$sid,$body,$head];
}
function taskRecord($sid,$creator,$assignees,$type='task',$existing=null,$closed=false) {
    global $server;
    $canonical=$existing['metadata']['identity']['canonicalId']??uid();
    $identity=['sourceKind'=>Address::sourceKind($type),'canonicalId'=>$canonical];
    $id=Address::derive($server,$sid,'content',$identity['sourceKind'],$canonical);
    $metadata=$existing['metadata']??['identity'=>$identity,'references'=>[],'referenceVersions'=>[],'uniqueRefs'=>[],'blobIds'=>[],
        'notificationState'=>['version'=>1,'kind'=>'created','assigneeAccountIds'=>[],'groupTargetId'=>null],
        'reminderState'=>['version'=>1,'dueAtEpoch'=>time()+7200,'closed'=>false,'scheduleRevision'=>uid(),'consentGeneration'=>uid()],
        'recordPolicy'=>['version'=>1,'createdByAccountId'=>$creator['user']['account_id'],'operation'=>'create',
            'fieldCommitments'=>['content'=>hash('sha256','content'),'assignment'=>hash('sha256','assignment'),'checked'=>hash('sha256','checked')]]];
    sort($assignees,SORT_STRING);$metadata['notificationState']['assigneeAccountIds']=$assignees;
    $metadata['reminderState']['closed']=$closed;
    $revision=($existing['revision']??0)+1;
    $sequence=(int)sql('SELECT COALESCE(MAX(sequence),0)+1 AS n FROM familyhub_crypto_record_positions WHERE scope_id=?',[$sid])[0]['n'];
    $proof=signCommand('synthetic.record',['scopeId'=>$sid,'id'=>$id,'type'=>$type,'metadata'=>$metadata,'revision'=>$revision],$creator);
    $hash=Uses::proofHash($proof);
    sql('INSERT OR REPLACE INTO familyhub_crypto_records VALUES(?,?,?,?,0,?,1,?,?,?)',[$sid,$id,$type,$revision,$sequence,base64_encode(random_bytes(96)),json_encode($metadata),json_encode(['recordProof'=>$proof])]);
    sql('INSERT OR REPLACE INTO familyhub_crypto_record_positions VALUES(?,?,?,?)',[$sid,$id,'content',$sequence]);
    sql('INSERT OR REPLACE INTO familyhub_crypto_record_history VALUES(?,?,?,?,1,?,?,?,?)',[$sid,$id,$revision,$sequence,'content',$hash,json_encode($proof),'{}']);
    if($existing) {
        global $notifications;
        $new=['scopeId'=>$sid,'id'=>$id,'type'=>$type,'deleted'=>false,'expectedRevision'=>$revision-1,'metadata'=>$metadata];
        $old=['deleted'=>0,'metadata'=>json_encode($existing['metadata'])];
        $method=new ReflectionMethod(\Kanboard\Plugin\FamilyHub\Model\NativeDatabase::class,'transaction');
        $method->invoke($notifications,fn()=>$notifications->changed($new,$old));
    }
    return ['id'=>$id,'scopeId'=>$sid,'revision'=>$revision,'metadata'=>$metadata,'proofHash'=>$hash];
}
function putReminder($task,$actor,$shared=true,$extra=[]) {
    global $notifications;
    $p=['id'=>uid(),'scopeId'=>$task['scopeId'],'targetType'=>'task','targetId'=>$task['id'],
        'targetIdentity'=>$task['metadata']['identity'],'remindAt'=>gmdate('Y-m-d\TH:i:s\Z',time()-1),'expectedRevision'=>0];
    if($shared)$p['recipientPolicy']=Notifications::TASK_RECIPIENT_POLICY;
    $p=array_replace($p,$extra);$proof=signCommand('crypto2.reminders.put',$p,$actor);
    return $notifications->command('crypto2.reminders.put',$p,$actor,$proof)['reminder'];
}
function notices($task) { return sql("SELECT * FROM familyhub_inbox WHERE scope_id=? AND target_id=? AND kind='crypto2.reminder.due' ORDER BY recipient_account_id",[$task['scopeId'],$task['id']]); }
function recipients($task) { return array_column(notices($task),'recipient_account_id'); }
function fire($task,$expected,$label) {
    global $notifications;
    $counts=$notifications->runDue(500);sort($expected,SORT_STRING);
    ck(recipients($task)===$expected && $counts['delivered']===1,$label);
}
function preference($sid,$actor,$push,$inApp=true,$email=false) {
    sql('INSERT OR REPLACE INTO familyhub_inbox_preferences VALUES(?,?,?,?)',[$sid,$actor['user']['account_id'],'reminders',json_encode(['inApp'=>$inApp,'sound'=>false,'push'=>$push,'email'=>$email])]);
}
function registration($actor) {
    global $server;
    $account=$actor['user']['account_id'];$device=$actor['device']['id'];$token='synthetic-'.$device;
    $fingerprint=hash('sha256',json_encode(['synthetic',0,''],JSON_THROW_ON_ERROR));
    sql('INSERT OR REPLACE INTO familyhub_devices VALUES(?,?,?,NULL,?,?)',[$device,$actor['user']['id'],$account,time()+86400,$fingerprint]);
    $r=['account_id'=>$account,'device_id'=>$device,'revision'=>1];
    sql("INSERT OR REPLACE INTO familyhub_push_registrations VALUES(?,?,?,?,?,'ios','en',1,1,?,2)",[$device,$account,hash('sha256',$token),NativePushCrypto::encrypt($token,NativePushCrypto::aad($server,$r)),FAMILYHUB_FCM_PROJECT_ID,time()]);
}
function deliverNotice($notice,$actor,$capture) {
    global $container;
    $lease=bin2hex(random_bytes(16));
    sql("UPDATE familyhub_push_jobs SET state='processing',attempts=1,lease_token=?,lease_until=? WHERE inbox_id=? AND device_id=?",[$lease,time()+120,$notice['id'],$actor['device']['id']]);
    return (new NativePushWorker($container))->deliver(['device_id'=>$actor['device']['id'],'inbox_id'=>$notice['id'],'registration_revision'=>1],$lease,$capture,microtime(true)+60);
}

registration($owner);registration($recipient);registration($third);
if (!defined('TASK_REMINDER_RECIPIENTS_FIXTURE_ONLY')) {
[$sid]=$scope=sharedScope($owner,$recipient);
$task=taskRecord($sid,$owner,[$recipient['user']['account_id']]);
$legacy=putReminder($task,$owner,false);
ck(!array_key_exists('recipientPolicy',$legacy),'old signed put and wire remain own-only with absent policy');
fire($task,[$owner['user']['account_id']],'legacy reminder still inserts only scheduler inbox');
ck(notices($task)[0]['event_key']===hash('sha256','crypto2-reminder:'.$legacy['id'].':1'),'legacy event key stays byte-identical');

$task=taskRecord($sid,$owner,[$recipient['user']['account_id']]);$both=putReminder($task,$owner);
ck($both['recipientPolicy']===Notifications::TASK_RECIPIENT_POLICY,'new response echoes signed recipient policy');
denied(fn()=>$notifications->command('crypto2.reminders.cancel',['id'=>$both['id'],'scopeId'=>$sid,'expectedRevision'=>1],$recipient,signCommand('crypto2.reminders.cancel',['id'=>$both['id'],'scopeId'=>$sid,'expectedRevision'=>1],$recipient)),'permission_revoked','peer cannot cancel scheduler-owned reminder');
$listed=$notifications->read('crypto2.reminders.list',['scopeId'=>$sid],$owner)['reminders'];
ck(count(array_filter($listed,fn($r)=>$r['id']===$both['id']&&$r['recipientPolicy']===Notifications::TASK_RECIPIENT_POLICY))===1&&$notifications->read('crypto2.reminders.list',['scopeId'=>$sid],$recipient)['reminders']===[],'only scheduler owns, lists and controls shared reminder');
fire($task,[$owner['user']['account_id'],$recipient['user']['account_id']],'new policy delivers two generic recipient-specific inbox references');
ck(count(sql('SELECT * FROM familyhub_push_jobs WHERE inbox_id IN (?,?)',array_column(notices($task),'id')))===2,'each registered recipient receives its own push job');
$notifications->runDue(500);ck(count(notices($task))===2,'repeat due discovery does not duplicate accepted fanout');
foreach(notices($task) as $notice)ck($notifications->deliveryVisible($notice),'new fanout inbox is currently authorized');
ck(count(array_filter(notices($task),fn($n)=>$n['actor_account_id']===$owner['user']['account_id']))===2,'new shared due carries scheduler actor for independent peer projection');

$task=taskRecord($sid,$owner,[$owner['user']['account_id']]);putReminder($task,$owner);fire($task,[$owner['user']['account_id']],'scheduler also assigned receives exactly one inbox');
$task=taskRecord($sid,$owner,[]);putReminder($task,$owner);fire($task,[$owner['user']['account_id']],'unassigned task retains scheduler reminder');

$task=taskRecord($sid,$owner,[$recipient['user']['account_id']]);
foreach([null,'anyone',true,[$recipient['user']['account_id']]] as $invalid)denied(fn()=>putReminder($task,$owner,true,['recipientPolicy'=>$invalid]),'validation_error','malformed or unknown recipient policy rejected');
denied(fn()=>putReminder($task,$owner,true,['recipientAccountIds'=>[$third['user']['account_id']]]),'validation_error','client cannot supply arbitrary recipients');
$event=taskRecord($sid,$owner,[],'event');denied(fn()=>putReminder($event,$owner,true,['targetType'=>'event']),'validation_error','shared task policy rejected for event target');

preference($sid,$recipient,false);
$task=taskRecord($sid,$owner,[$recipient['user']['account_id']]);putReminder($task,$owner);fire($task,[$owner['user']['account_id'],$recipient['user']['account_id']],'recipient push off preserves permitted in-app reminder');
$peer=array_values(array_filter(notices($task),fn($r)=>$r['recipient_account_id']===$recipient['user']['account_id']))[0];
ck(sql('SELECT * FROM familyhub_push_jobs WHERE inbox_id=?',[$peer['id']])===[],'recipient push preference prevents peer queue admission');
preference($sid,$recipient,false,false);
$task=taskRecord($sid,$owner,[$recipient['user']['account_id']]);putReminder($task,$owner);fire($task,[$owner['user']['account_id']],'recipient all channels off creates no peer inbox or queue');preference($sid,$recipient,true);

$task=taskRecord($sid,$owner,[$recipient['user']['account_id']]);putReminder($task,$owner);$task=taskRecord($sid,$owner,[$third['user']['account_id']],'task',$task);
// Third is signed current member before reassignment; no client recipient list.
$body=$scope[1];$body['members'][]=participant($third,'member');usort($body['members'],fn($a,$b)=>strcmp($a['accountId'],$b['accountId']));
sql("INSERT INTO familyhub_members VALUES(?,?,?,'member',1)",[$sid,$third['user']['id'],$third['user']['account_id']]);installHead($sid,$body,$owner);
fire($task,[$owner['user']['account_id'],$third['user']['account_id']],'reassignment before due selects only current signed assignee');

$task=taskRecord($sid,$owner,[$recipient['user']['account_id']]);$r=putReminder($task,$owner);fire($task,[$owner['user']['account_id'],$recipient['user']['account_id']],'post-enqueue fixture starts with both inboxes');
$notices=notices($task);$peer=array_values(array_filter($notices,fn($n)=>$n['recipient_account_id']===$recipient['user']['account_id']))[0];$own=array_values(array_filter($notices,fn($n)=>$n['recipient_account_id']===$owner['user']['account_id']))[0];
$task=taskRecord($sid,$owner,[],'task',$task);
ck((int)sql('SELECT visibility_revision FROM familyhub_inbox_state WHERE account_id=?',[$recipient['user']['account_id']])[0]['visibility_revision']>0,'late reassignment advances peer inbox visibility for cached removal');
$capture=new class { public $sent=[];public function send($job,$server){$this->sent[]=$job;return ['status'=>'accepted'];} };
ck(deliverNotice($peer,$recipient,$capture)['status']==='cancelled'&&$capture->sent===[],'reassignment after enqueue cancels peer worker without sending');
ck(deliverNotice($own,$owner,$capture)['status']==='accepted'&&count($capture->sent)===1,'same reassignment still permits scheduler own push');
denied(fn()=>$notifications->read('crypto2.inbox.open',['id'=>(int)$peer['id']],$recipient),'permission_revoked','obsolete assignee cannot open old reminder');
denied(fn()=>$notifications->read('crypto2.inbox.group',['id'=>(int)$peer['id']],$recipient),'permission_revoked','obsolete assignee cannot resolve old reminder group');
preference($sid,$recipient,true,true,true);$lease=bin2hex(random_bytes(16));
sql("INSERT INTO familyhub_deliveries VALUES(?,'processing',1,?,?,?, ?,NULL)",[$peer['id'],time(),time()+3600,$lease,time()+120]);
$mail=new class {public $sent=[];public function send($email,$id,$account){$this->sent[]=$id;}};
$method=new ReflectionMethod(NativeDeliveryService::class,'deliver');
ck($method->invoke(new NativeDeliveryService($container),(int)$peer['id'],$lease,$mail,microtime(true)+90)==='cancelled'&&$mail->sent===[],'obsolete assignee email also cancelled without transport');preference($sid,$recipient,true);

$task=taskRecord($sid,$owner,[$recipient['user']['account_id']]);$r=putReminder($task,$owner);fire($task,[$owner['user']['account_id'],$recipient['user']['account_id']],'completion fixture starts with both inboxes');
$old=notices($task);$task=taskRecord($sid,$owner,[$recipient['user']['account_id']],'task',$task,true);
ck(!$notifications->deliveryVisible($old[0])&&!$notifications->deliveryVisible($old[1]),'completion suppresses all queued shared deliveries and opens');
$completedPeer=array_values(array_filter($old,fn($n)=>$n['recipient_account_id']===$recipient['user']['account_id']))[0];
$completionCapture=new class {public $sent=[];public function send($job,$server){$this->sent[]=$job;return ['status'=>'accepted'];}};
ck(deliverNotice($completedPeer,$recipient,$completionCapture)['status']==='cancelled'&&$completionCapture->sent===[],'completion after enqueue cancels peer push with no transport');
denied(fn()=>$notifications->read('crypto2.inbox.open',['id'=>(int)$completedPeer['id']],$recipient),'permission_revoked','completed target cannot be opened from shared due event');
denied(fn()=>$notifications->read('crypto2.inbox.group',['id'=>(int)$completedPeer['id']],$recipient),'permission_revoked','completed target cannot resolve shared due group');

$task=taskRecord($sid,$owner,[$recipient['user']['account_id']]);$r=putReminder($task,$owner);fire($task,[$owner['user']['account_id'],$recipient['user']['account_id']],'cancellation fixture starts with both inboxes');$old=notices($task);
$cancel=['id'=>$r['id'],'scopeId'=>$sid,'expectedRevision'=>1];$notifications->command('crypto2.reminders.cancel',$cancel,$owner,signCommand('crypto2.reminders.cancel',$cancel,$owner));
ck(!$notifications->deliveryVisible($old[0])&&!$notifications->deliveryVisible($old[1]),'owner cancellation invalidates exact delivered revision');

$task=taskRecord($sid,$owner,[$recipient['user']['account_id']]);putReminder($task,$owner);sql('UPDATE familyhub_members SET active=0 WHERE scope_id=? AND account_id=?',[$sid,$recipient['user']['account_id']]);fire($task,[$owner['user']['account_id']],'revoked peer excluded before due while scheduler remains');sql('UPDATE familyhub_members SET active=1 WHERE scope_id=? AND account_id=?',[$sid,$recipient['user']['account_id']]);
$task=taskRecord($sid,$owner,[$recipient['user']['account_id']]);putReminder($task,$owner);fire($task,[$owner['user']['account_id'],$recipient['user']['account_id']],'revocation fixture starts with both inboxes');$old=notices($task);
sql('UPDATE familyhub_members SET active=0 WHERE scope_id=? AND account_id=?',[$sid,$recipient['user']['account_id']]);
foreach($old as $notice)ck($notifications->deliveryVisible($notice)===($notice['recipient_account_id']===$owner['user']['account_id']),'revocation after enqueue hides peer while scheduler remains');
sql('UPDATE familyhub_members SET active=1 WHERE scope_id=? AND account_id=?',[$sid,$recipient['user']['account_id']]);

[$policySid]=sharedScope($third,$recipient,true,'viewer');
$task=taskRecord($policySid,$owner,[$recipient['user']['account_id']]);
denied(fn()=>putReminder($task,$third),'record_edit_forbidden','unrelated policy viewer cannot broadcast task reminders');
putReminder($task,$third,false);fire($task,[$third['user']['account_id']],'same policy viewer retains historical self-only scheduling');
$task=taskRecord($policySid,$owner,[$third['user']['account_id'],$recipient['user']['account_id']]);putReminder($task,$third);$task=taskRecord($policySid,$owner,[$recipient['user']['account_id']],'task',$task);
fire($task,[$third['user']['account_id']],'scheduler edit loss before due falls back to own reminder');
$task=taskRecord($policySid,$owner,[$third['user']['account_id'],$recipient['user']['account_id']]);putReminder($task,$third);fire($task,[$third['user']['account_id'],$recipient['user']['account_id']],'current assigned policy viewer may explicitly schedule peers');
$old=notices($task);$task=taskRecord($policySid,$owner,[$recipient['user']['account_id']],'task',$task);
foreach($old as $notice)ck($notifications->deliveryVisible($notice)===($notice['recipient_account_id']===$third['user']['account_id']),'scheduler edit loss after enqueue preserves only own delivery');

// Genuine valid signed relative consent + companion, not a bypass of the
// pre-existing account event/consent guards. This is a distinct task/use.
[$relativeSid,$relativeBody,$relativeHead]=sharedScope($owner,$recipient);
$relativeTask=taskRecord($relativeSid,$owner,[$recipient['user']['account_id']]);
$current=(new Directory($container))->current($owner['user']['account_id']);
$snapshot=json_decode($current['snapshot'],true,34,JSON_THROW_ON_ERROR);
$reminderId=uid();$request=uid();$due=$relativeTask['metadata']['reminderState']['dueAtEpoch'];
$use=['version'=>2,'operation'=>'crypto2.scheduling.use','serverId'=>$server,'scopeId'=>$relativeSid,
    'targetId'=>$relativeTask['id'],'targetType'=>'task','domain'=>'content','useId'=>uid(),
    'sourceScheduleRevision'=>$relativeTask['metadata']['reminderState']['scheduleRevision'],'schedulePutId'=>$reminderId,
    'consentGeneration'=>$relativeTask['metadata']['reminderState']['consentGeneration'],
    'scopeLifecycleHash'=>(new Lifecycle($container))->closingHash($relativeSid),'projectBarrier'=>null,
    'expiresAtEpoch'=>null,'mode'=>'relative','membershipHeadHash'=>$relativeHead,'accessRevision'=>0,
    'targetRevision'=>1,'targetRecordProofHash'=>$relativeTask['proofHash'],'accountId'=>$owner['user']['account_id'],
    'deviceId'=>$owner['device']['id'],'authorDirectoryHeadHash'=>$current['head_hash']];
$bytes=Codec::canonical((object)$use);$useProof=['commandBase64'=>base64_encode($bytes),
    'signatureBase64'=>base64_encode(sodium_crypto_sign_detached(Uses::DOMAIN.$bytes,$owner['secret']))];
$token=hash('sha256',"JivieScheduleUse/v2\n".Codec::canonical((object)['serverId'=>$server,
    'accountId'=>$owner['user']['account_id'],'scopeId'=>$relativeSid,'targetId'=>$relativeTask['id'],'useId'=>$use['useId']]));
$event=signCommand('crypto2.account.scheduleUse',['expectedGeneration'=>(int)$current['generation'],
    'previousHeadHash'=>$current['head_hash'],'identityEpochId'=>$snapshot['identityEpochId'],
    'resultingSnapshotHash'=>$current['snapshot_hash'],'useToken'=>$token,'useProofHash'=>Uses::proofHash($useProof),'active'=>true],$owner);
[$eventBody]=Codec::decode($event);$eventBody['requestId']=$request;$eventBytes=Codec::canonical((object)$eventBody);
$event=['commandBase64'=>base64_encode($eventBytes),'signatureBase64'=>base64_encode(sodium_crypto_sign_detached("JivieE2EE/v2\n".$eventBytes,$owner['secret']))];
$p=['id'=>$reminderId,'scopeId'=>$relativeSid,'targetType'=>'task','targetId'=>$relativeTask['id'],
    'targetIdentity'=>$relativeTask['metadata']['identity'],'expectedRevision'=>0,
    'recipientPolicy'=>Notifications::TASK_RECIPIENT_POLICY,'remindAt'=>gmdate('Y-m-d\TH:i:s\Z',$due-3600),
    'scheduleMode'=>'deadline','offsetMinutes'=>60,'targetDueAtEpoch'=>$due,'targetRevision'=>1,
    'targetRecordProofHash'=>$relativeTask['proofHash'],'useProof'=>$useProof,'accountEventProof'=>$event];
$proof=signCommand('crypto2.reminders.put',$p,$owner);[$outer]=Codec::decode($proof);$outer['requestId']=$request;
$bytes=Codec::canonical((object)$outer);$proof=['commandBase64'=>base64_encode($bytes),'signatureBase64'=>base64_encode(sodium_crypto_sign_detached("JivieE2EE/v2\n".$bytes,$owner['secret']))];
$relative=$notifications->command('crypto2.reminders.put',$p,$owner,$proof)['reminder'];
ck($relative['recipientPolicy']===Notifications::TASK_RECIPIENT_POLICY&&$relative['scheduleMode']==='deadline'&&$relative['offsetMinutes']===60&&$relative['schedulingUse']['active']===true,'valid relative reminder retains exact consent companion and shared policy');
// Move the distinct target deadline naturally into the due window through the
// production changed projection, preserving the same signed consent barriers.
$relativeTask['metadata']['reminderState']['dueAtEpoch']=time()+3599;
$relativeTask['metadata']['reminderState']['scheduleRevision']=uid();
$relativeTask=taskRecord($relativeSid,$owner,[$recipient['user']['account_id']],'task',$relativeTask);
fire($relativeTask,[$owner['user']['account_id'],$recipient['user']['account_id']],'valid relative reminder fanout follows existing deadline projection');

echo json_encode(['status'=>'pass','checks'=>$checks,'fixture'=>'new isolated real SQL/signatures/policy/queue workers',
    'limitations'=>'Signature-dispatch/auth HTTP and provider/device delivery are separate; test task history is inserted at the accepted-record seam']).PHP_EOL;
}
