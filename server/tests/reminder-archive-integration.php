<?php
require '/var/www/app/app/common.php';
if(session_status()===PHP_SESSION_ACTIVE)session_abort();
if(!defined('FAMILYHUB_DEVELOPMENT_MODE')||FAMILYHUB_DEVELOPMENT_MODE!==true)throw new RuntimeException('Synthetic development only');
use Kanboard\Plugin\FamilyHub\Model\NativeService;
use Kanboard\Plugin\FamilyHub\Model\NativeReminderService;
function uuid(){ $h=bin2hex(random_bytes(16));return substr($h,0,8).'-'.substr($h,8,4).'-4'.substr($h,13,3).'-a'.substr($h,17,3).'-'.substr($h,20); }
function check($v,$m){if(!$v)throw new RuntimeException('FAIL: '.$m);echo 'PASS: '.$m.PHP_EOL;}
$pdo=$container['db']->getConnection();$service=new NativeService($container);$name='archivereminder_'.bin2hex(random_bytes(6));$pw=bin2hex(random_bytes(18));
$id=$container['userModel']->create(['username'=>$name,'password'=>$pw,'role'=>'app-user']);$session=$service->dispatch('auth.login',['username'=>$name,'password'=>$pw,'deviceName'=>'Synthetic archive reminder'],'','synthetic-archive-reminder');$bearer='Bearer '.$session['token'];$account=$session['user']['accountId'];
$org=uuid();$archived=uuid();$active=uuid();$service->dispatch('scopes.create',['id'=>$org,'kind'=>'organization','name'=>'Synthetic reminder org','requestId'=>uuid()],$bearer,'synthetic-archive-reminder');
foreach([$archived,$active]as$scope)$service->dispatch('scopes.create',['id'=>$scope,'kind'=>'project','name'=>'Synthetic reminder project','organizationId'=>$org,'requestId'=>uuid()],$bearer,'synthetic-archive-reminder');
$task=uuid();$stamp=gmdate('Y-m-d\TH:i:s\Z');$payload=['title'=>'Synthetic target','notes'=>'','projectId'=>$active,'dueAt'=>null,'isCompleted'=>false,'startAt'=>null,'endAt'=>null,'assigneeAccountIds'=>[],'phaseId'=>null,'estimateMinutes'=>null,'availabilityMinutes'=>null,'availabilityPeriod'=>null,'timer'=>['elapsedSeconds'=>0,'runningSince'=>null,'runId'=>null],'assigneePersonId'=>null,'subjectPersonIds'=>[],'createdAt'=>$stamp,'updatedAt'=>$stamp];
$service->dispatch('sync3.push',['scopeId'=>$active,'operation'=>['opId'=>uuid(),'recordId'=>$task,'type'=>'task','expectedRevision'=>0,'deleted'=>false,'payload'=>$payload]],$bearer,'synthetic-archive-reminder');
$service->dispatch('scopes.archive',['scopeId'=>$archived,'archived'=>true,'requestId'=>uuid()],$bearer,'synthetic-archive-reminder');
$insert=$pdo->prepare("INSERT INTO familyhub_reminders(id,scope_id,account_id,target_type,target_id,target_fingerprint,remind_at,remind_epoch,revision,state) VALUES(?,?,?,'task',?,?,?, ?,1,'pending')");
$fingerprint=hash('sha256',json_encode([null,null,null,null]));
for($i=0;$i<100;$i++)$insert->execute([uuid(),$archived,$account,$task,$fingerprint,'1970-01-01T00:00:00Z',0]);
$reminder=uuid();$insert->execute([$reminder,$active,$account,$task,$fingerprint,'1970-01-01T00:00:01Z',1]);
// A guarded selection proves this test's active row is globally earliest; do not
// run a global worker against any pre-existing earlier fixture.
$first=$pdo->query("SELECT r.id FROM familyhub_reminders r JOIN familyhub_scopes s ON s.id=r.scope_id WHERE r.state='pending' AND s.archived=0 ORDER BY r.remind_epoch,r.id LIMIT 1")->fetchColumn();
check($first===$reminder,'active test reminder is selected ahead of 100 archived due rows');
$result=(new NativeReminderService($container))->runDue(1);check($result['delivered']===1,'limit-one cron delivers active row without archive starvation');
$q=$pdo->prepare('SELECT COUNT(*) FROM familyhub_inbox WHERE scope_id=?');$q->execute([$archived]);check((int)$q->fetchColumn()===0,'archived rows create no notifications');$q->closeCursor();
$service->dispatch('scopes.archive',['scopeId'=>$archived,'archived'=>false,'requestId'=>uuid()],$bearer,'synthetic-archive-reminder');
$q=$pdo->prepare("SELECT COUNT(*) FROM familyhub_reminders WHERE scope_id=? AND state='pending'");$q->execute([$archived]);check((int)$q->fetchColumn()===0,'restore cancels stale past reminders without sending them');$q->closeCursor();
echo 'PASS: 4 archive reminder checks'.PHP_EOL;
