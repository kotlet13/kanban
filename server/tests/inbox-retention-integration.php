<?php
// Real SQL/HTTP plus independent processes, only new disposable test identities.
require '/var/www/app/app/common.php';
if (!defined('FAMILYHUB_DEVELOPMENT_MODE') || FAMILYHUB_DEVELOPMENT_MODE !== true) { throw new RuntimeException('Development only'); }
if (session_status() === PHP_SESSION_ACTIVE) { session_abort(); }
use Kanboard\Plugin\FamilyHub\Model\NativeInboxRetention;
use Kanboard\Plugin\FamilyHub\Model\NativeInboxService;
use Kanboard\Plugin\FamilyHub\Model\NativeNotificationWriter;
$pdo = $container['db']->getConnection(); $checks = 0; $prefix = 'retention_'.bin2hex(random_bytes(4));
function uuid() { $h=bin2hex(random_bytes(16)); return substr($h,0,8).'-'.substr($h,8,4).'-4'.substr($h,13,3).'-a'.substr($h,17,3).'-'.substr($h,20); }
function check($ok,$message) { global $checks; if (!$ok) { throw new RuntimeException('FAIL: '.$message); } $checks++; echo 'PASS: '.$message.PHP_EOL; }
function query($sql,$params=[]) { global $pdo; $q=$pdo->prepare($sql); $q->execute($params); $rows=$q->fetchAll(PDO::FETCH_ASSOC); $q->closeCursor(); return $rows; }
function change($sql,$params=[]) { global $pdo; $q=$pdo->prepare($sql); $q->execute($params); $q->closeCursor(); }
function call($op,$params,$token) { $ch=curl_init('http://127.0.0.1/index.php?controller=NativeApiController&action=handle&plugin=FamilyHub'); curl_setopt_array($ch,[CURLOPT_POST=>true,CURLOPT_RETURNTRANSFER=>true,CURLOPT_HTTPHEADER=>['Content-Type: application/json','Authorization: Bearer '.$token],CURLOPT_POSTFIELDS=>json_encode(['v'=>1,'op'=>$op,'params'=>(object)$params])]); $raw=curl_exec($ch); $status=curl_getinfo($ch,CURLINFO_HTTP_CODE); curl_close($ch); return ['status'=>$status,'body'=>json_decode($raw,true)]; }
function data($r) { if ($r['status']!==200) { throw new RuntimeException('Unexpected HTTP '.$r['status']); } return $r['body']['data']; }
class RetentionProbe extends NativeInboxRetention {
    public function own($limit=500,$now=null,$hook=null) { return $this->transaction(function () use ($limit,$now,$hook) { $count=$this->pruneForUser($this->actor()['user'],$limit,$now); if ($hook) { $hook(); } return $count; }); }
}
class BarrierInbox extends NativeInboxService {
    private $count=0; private $hook;
    public function __construct($container,$token,$ip,$hook) { parent::__construct($container,'Bearer '.$token,$ip); $this->hook=$hook; }
    protected function transaction(callable $callback,$global=false,$snapshot=false) { $this->count++; $hook=$this->count===3 ? $this->hook : null; return parent::transaction(function () use ($callback,$hook) { $result=$callback(); if ($hook) { $hook(); } return $result; },$global,$snapshot); }
}
function child($fixture) {
    $file=tempnam('/tmp','familyhub-retention-'); chmod($file,0600); file_put_contents($file,json_encode($fixture,JSON_THROW_ON_ERROR));
    $process=proc_open([PHP_BINARY,'/familyhub-tests/inbox-retention-child.php',$file],[0=>['pipe','r'],1=>['pipe','w'],2=>['pipe','w']],$pipes);
    stream_set_timeout($pipes[1],10); if (trim(fgets($pipes[1]))!=='ready') { throw new RuntimeException('Child not ready'); }
    return [$process,$pipes,$file];
}
function blocked($child) { fwrite($child[1][0],"go\n"); fflush($child[1][0]); if (trim(fgets($child[1][1]))!=='attempting') { throw new RuntimeException('No child attempt'); } stream_set_blocking($child[1][1],false); usleep(250000); check(fgets($child[1][1])===false,'independent mutation waits for recipient transaction'); stream_set_blocking($child[1][1],true); }
function finish($child) { $line=trim(fgets($child[1][1])); foreach ($child[1] as $pipe) { fclose($pipe); } $exit=proc_close($child[0]); unlink($child[2]); if ($exit!==0) { throw new RuntimeException('Child failed'); } return $line; }
$sessions=[]; $ids=[];
foreach (['owner','recipient','foreign'] as $role) {
    $ids[$role]=$container['userModel']->create(['username'=>$prefix.'_'.$role,'password'=>bin2hex(random_bytes(16)),'role'=>'app-user']);
    $sessions[$role]=(new \Kanboard\Plugin\FamilyHub\Model\NativeAuthService($container))->issue($container['userModel']->getById($ids[$role]),'Synthetic retention');
}
$scope=uuid(); $account=$sessions['recipient']['user']['accountId']; $token=$sessions['recipient']['token']; $bearer='Bearer '.$token;
change('INSERT INTO familyhub_scopes(id,kind,name,owner_id,sequence,created_at) VALUES(?,\'household\',\'Synthetic retention\',?,0,?)',[$scope,$ids['owner'],time()]);
foreach (['owner','recipient'] as $role) { change('INSERT INTO familyhub_members(scope_id,user_id,account_id,role,active) VALUES(?,?,?,?,1)',[$scope,$ids[$role],$sessions[$role]['user']['accountId'],$role==='owner'?'owner':'member']); }
function notification($read=null) {
    global $container,$pdo,$scope,$account;
    $target=uuid(); $pdo->beginTransaction(); (new NativeNotificationWriter($container))->insert($scope,$account,null,'task',$target,1,'task.created','tasks','scope',hash('sha256',$target)); $pdo->commit();
    $id=(int)query('SELECT id FROM familyhub_inbox WHERE scope_id=? AND target_id=?',[$scope,$target])[0]['id'];
    change('UPDATE familyhub_inbox SET read_at=?,created_at=? WHERE id=?',[$read,'2000-01-01T00:00:00Z',$id]); return $id;
}
$now=time(); $cutoff=NativeInboxRetention::cutoff($now);
$unread=notification(); $boundary=notification($cutoff); $older=notification(gmdate('Y-m-d\TH:i:s\Z',$now-7*86400-1)); $recent=notification(gmdate('Y-m-d\TH:i:s\Z',$now-7*86400+3600));
$before=query('SELECT * FROM familyhub_inbox_state WHERE account_id=?',[$account])[0];
// Deliberately still-live delivery jobs, including a crashed worker lease.
foreach ([$boundary,$older] as $id) {
    change('INSERT INTO familyhub_deliveries(inbox_id,state,attempts,next_attempt,expires_at,lease_token,lease_until) VALUES(?,\'processing\',1,0,?,\'synthetic\',?)',[$id,$now+86400,$now-1]);
    change('INSERT INTO familyhub_push_jobs(inbox_id,device_id,registration_revision,token_hash,state,attempts,next_attempt,expires_at) VALUES(?,?,1,?,\'pending\',0,0,?)',[$id,$sessions['recipient']['device']['id'],hash('sha256','synthetic'),$now+86400]);
}
$probe=new RetentionProbe($container,$bearer);
check($probe->own(1,$now)===1,'cleanup limits deletion batch');
check($probe->own(500,$now)===1,'seven-day boundary and older read rows expire');
check(count(query('SELECT id FROM familyhub_inbox WHERE recipient_account_id=?',[$account]))===2,'old unread and recently read rows survive');
check(query('SELECT * FROM familyhub_deliveries WHERE inbox_id IN (?,?)',[$boundary,$older])===[] && query('SELECT * FROM familyhub_push_jobs WHERE inbox_id IN (?,?)',[$boundary,$older])===[],'expiry removes pending and crashed email/push jobs');
$after=query('SELECT * FROM familyhub_inbox_state WHERE account_id=?',[$account])[0];
check((int)$after['visibility_revision']===(int)$before['visibility_revision']+2 && $after['sequence']===$before['sequence'],'deletion advances visibility generation without corrupting cursor');
$reply=call('inbox.sync',['cursor'=>(int)$before['sequence'],'visibilityRevision'=>(int)$before['visibility_revision']],$token);
check($reply['status']===409 && $reply['body']['error']['code']==='visibility_changed','offline old cursor must reset after server deletion');
check(count(data(call('inbox.sync',['cursor'=>0],$token))['items'])===2,'complete backfill keeps old unread and excludes expired read');
check($probe->own(500,$now)===0,'repeated cleanup changes nothing');
$missing=call('inbox.read',['id'=>$older,'read'=>false,'expectedRevision'=>1,'requestId'=>uuid()],$token);
check(call('inbox.open',['id'=>$older],$token)['status']===403 && $missing['status']===404 && $missing['body']['error']['code']==='notification_missing','late unread cannot resurrect an expired row or imply scope revocation');
check(call('sync2.pull',['scopeId'=>$scope,'cursor'=>0],$token)['status']===200,'expired read command leaves current scope access intact');
$wire=data(call('inbox.open',['id'=>$recent],$token))['item']; $request=['id'=>$recent,'read'=>true,'expectedRevision'=>$wire['revision'],'requestId'=>uuid()];
$marked=data(call('inbox.read',$request,$token))['item'];
check($marked===$wire,'new read request on already-read item preserves original timestamp/revision/sequence');
check(data(call('inbox.read',$request,$token))['item']===$marked,'lost read response replays exactly');
$unmarked=data(call('inbox.read',['id'=>$recent,'read'=>false,'expectedRevision'=>$marked['revision'],'requestId'=>uuid()],$token))['item'];
check($unmarked['readAt']===null && $unmarked['revision']===$marked['revision']+1,'unread removes retention deadline');
$reread=data(call('inbox.read',['id'=>$recent,'read'=>true,'expectedRevision'=>$unmarked['revision'],'requestId'=>uuid()],$token))['item'];
check($reread['readAt']>$wire['readAt'] && $reread['revision']===$unmarked['revision']+1,'reading after unread starts a new seven-day interval');
check(call('inbox.read',['id'=>$recent,'read'=>true,'expectedRevision'=>$wire['revision'],'requestId'=>uuid()],$token)['status']===409,'stale revision cannot reset current timestamp');
check(call('inbox.read',['id'=>$unread,'read'=>true,'expectedRevision'=>1,'requestId'=>uuid()],$sessions['foreign']['token'])['status']===403,'foreign recipient cannot start retention');
$race=notification(gmdate('Y-m-d\TH:i:s\Z',time()-10));
$cleanup=child(['action'=>'prune','token'=>$token,'now'=>time()+NativeInboxRetention::READ_RETENTION_SECONDS-5]);
// Advance the cleanup cutoff only after unread has been written while locked.
$service=new BarrierInbox($container,$token,$prefix,function () use ($cleanup,$race) { change('UPDATE familyhub_inbox SET created_at=? WHERE id=?',['1999-01-01T00:00:00Z',$race]); blocked($cleanup); });
$service->execute('inbox.read',['id'=>$race,'read'=>false,'expectedRevision'=>1,'requestId'=>uuid()]);
check(finish($cleanup)==='done:0' && query('SELECT read_at FROM familyhub_inbox WHERE id=?',[$race])[0]['read_at']===null,'committed unread survives cleanup waiting on recipient lock');
$race=notification($cutoff); $late=child(['action'=>'read','token'=>$token,'ip'=>$prefix,'params'=>['id'=>$race,'read'=>false,'expectedRevision'=>1,'requestId'=>uuid()]]);
check($probe->own(500,$now,fn () => blocked($late))===1,'expiry wins while holding recipient state');
check(str_starts_with(finish($late),'done:error:') && query('SELECT id FROM familyhub_inbox WHERE id=?',[$race])===[],'unread waiting behind deletion cannot recreate row');
// Existing reminder cron, even with no due reminder/device traffic.
$cronExpired=notification($cutoff); (new \Kanboard\Plugin\FamilyHub\Model\NativeReminderService($container))->runDue(100);
check(query('SELECT id FROM familyhub_inbox WHERE id=?',[$cronExpired])===[],'existing reminder cron deletes expired notifications without inbox traffic');
// Cleanup must survive a rejected old sync response, rather than rolling back.
$snapshot=data(call('inbox.sync',['cursor'=>0],$token)); $lazy=notification($cutoff);
$reply=call('inbox.sync',['cursor'=>$snapshot['cursor'],'visibilityRevision'=>$snapshot['visibilityRevision']],$token);
check($reply['status']===409 && query('SELECT id FROM familyhub_inbox WHERE id=?',[$lazy])===[],'request cleanup commits even when old cursor is rejected');
// Expired backlog can exceed a bounded cleanup batch; APIs must still hide all.
$backlog=[]; for ($i=0;$i<102;$i++) { $backlog[]=notification($cutoff); }
$anchor=notification(); $group='synthetic-retention-group';
foreach (array_merge($backlog,[$anchor]) as $id) { change('UPDATE familyhub_inbox SET group_key=? WHERE id=?',[$group,$id]); }
$groupPage=data(call('inbox.group',['id'=>$anchor],$token));
check(array_column($groupPage['items'],'id')===[$anchor] && !$groupPage['hasMore'],'group API excludes all expired rows beyond deletion batch');
check(count(query('SELECT id FROM familyhub_inbox WHERE recipient_account_id=? AND read_at=?',[$account,$cutoff]))===2,'request cleanup remains bounded with large expired backlog');
$list=data(call('inbox.list',['scopeId'=>$scope],$token));
check(count(array_intersect(array_column($list['items'],'id'),$backlog))===0,'list API excludes expired backlog');
// Source operations retain their own idempotency independently of inbox rows.
$task=uuid(); $stamp=gmdate('Y-m-d\TH:i:s\Z');
$push=['scopeId'=>$scope,'operation'=>['opId'=>uuid(),'recordId'=>$task,'type'=>'task','expectedRevision'=>0,'deleted'=>false,'payload'=>['title'=>'Synthetic replay','notes'=>'','projectId'=>null,'startAt'=>null,'endAt'=>null,'dueAt'=>null,'isCompleted'=>false,'assigneeAccountIds'=>[],'createdAt'=>$stamp,'updatedAt'=>$stamp]]];
data(call('sync2.push',$push,$sessions['owner']['token']));
$event=query('SELECT id FROM familyhub_inbox WHERE recipient_account_id=? AND target_id=?',[$account,$task])[0];
change('UPDATE familyhub_inbox SET read_at=? WHERE id=?',[$cutoff,$event['id']]); $probe->own(500,$now);
$replay=data(call('sync2.push',$push,$sessions['owner']['token']));
check($replay['replayed'] && query('SELECT id FROM familyhub_inbox WHERE recipient_account_id=? AND target_id=?',[$account,$task])===[],'source record replay cannot recreate expired notification');
$invite=data(call('invitations.create',['scopeId'=>$scope,'recipientUsername'=>$prefix.'_foreign','role'=>'member','requestId'=>uuid()],$sessions['owner']['token']));
data(call('invitations.accept',['token'=>$invite['token']],$sessions['foreign']['token']));
$foreignAccount=$sessions['foreign']['user']['accountId']; $joined=query('SELECT id FROM familyhub_inbox WHERE recipient_account_id=? AND target_type=\'membership\'',[$foreignAccount])[0];
change('UPDATE familyhub_inbox SET read_at=? WHERE id=?',[$cutoff,$joined['id']]);
(new RetentionProbe($container,'Bearer '.$sessions['foreign']['token']))->own(500,$now);
data(call('invitations.accept',['token'=>$invite['token']],$sessions['foreign']['token']));
check(query('SELECT id FROM familyhub_inbox WHERE recipient_account_id=? AND target_type=\'membership\'',[$foreignAccount])===[],'accepted invitation retry cannot recreate expired joined event');
$reminderId=uuid(); data(call('reminders.put',['id'=>$reminderId,'scopeId'=>$scope,'targetType'=>'task','targetId'=>$task,'remindAt'=>$stamp,'expectedRevision'=>0,'requestId'=>uuid()],$token));
$cron=new \Kanboard\Plugin\FamilyHub\Model\NativeReminderService($container); $cron->runDue(100);
$due=query('SELECT id FROM familyhub_inbox WHERE recipient_account_id=? AND kind=\'reminder.due\' AND target_id=?',[$account,$task])[0];
change('UPDATE familyhub_inbox SET read_at=? WHERE id=?',[$cutoff,$due['id']]); $probe->own(500,$now); $cron->runDue(100);
check(query('SELECT id FROM familyhub_inbox WHERE recipient_account_id=? AND kind=\'reminder.due\' AND target_id=?',[$account,$task])===[],'delivered reminder cron retry cannot recreate expired event');
echo 'SUCCESS '.$checks.' retention checks ('.$pdo->getAttribute(PDO::ATTR_DRIVER_NAME).')'.PHP_EOL;
