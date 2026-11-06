<?php
/** Distinct follow-up controls; the successful fifty-control entrypoint is not run. */
define('TASK_REMINDER_RECIPIENTS_FIXTURE_ONLY',true);
require __DIR__.'/crypto2-task-reminder-recipients-20261105.php';
use Kanboard\Plugin\FamilyHub\Model\NativeDatabase;
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoNotificationV2 as Notifications;

[$sid]=sharedScope($owner,$recipient);
$task=taskRecord($sid,$owner,[$recipient['user']['account_id']]);$r=putReminder($task,$owner);
fire($task,[$owner['user']['account_id'],$recipient['user']['account_id']],'new link fixture delivers both recipients');
$notice=notices($task)[0];
foreach(['r2a:bad:1','r2a:'.$r['id'].':01','r2a:'.$r['id'].':0','r2a:'.$r['id'].':2','r2a:'.uid().':1','r2a:'.$r['id'].':1:extra'] as $key) {
    $forged=$notice;$forged['event_key']=$key;
    ck(!$notifications->deliveryVisible($forged),'malformed, missing or non-current linked event is denied');
}
foreach(['scope_id','target_id','target_type'] as $field) {
    $forged=$notice;$forged[$field]=$field==='target_type'?'event':uid();
    ck(!$notifications->deliveryVisible($forged),'linked event cannot cross '.$field);
}
$old=notices($task);
$updated=putReminder($task,$owner,false,['id'=>$r['id'],'expectedRevision'=>1,'remindAt'=>gmdate('Y-m-d\TH:i:s\Z',time()+7200)]);
ck(!array_key_exists('recipientPolicy',$updated)&&!$notifications->deliveryVisible($old[0])&&!$notifications->deliveryVisible($old[1]),'explicit shared-to-own edit hides prior fanout generation without expanding future own intent');
ck((int)sql('SELECT visibility_revision FROM familyhub_inbox_state WHERE account_id=?',[$recipient['user']['account_id']])[0]['visibility_revision']===1,'shared edit invalidates cached peer inbox exactly once');

// Inline project metadata uses the accepted-record seam. The production graph
// traversal, scope-wide bounded invalidation and subsequent worker gate are real.
$project=uid();$projectMetadata=['references'=>[],'projectState'=>['version'=>1,'archived'=>false]];
$proof=signCommand('synthetic.project',['scopeId'=>$sid,'id'=>$project,'metadata'=>$projectMetadata],$owner);
sql('INSERT INTO familyhub_crypto_records VALUES(?,?,?,1,0,100,1,?,?,?)',[$sid,$project,'project',base64_encode(random_bytes(96)),json_encode($projectMetadata),json_encode(['recordProof'=>$proof])]);
$child=taskRecord($sid,$owner,[$recipient['user']['account_id']]);
$child['metadata']['references']=[['scopeId'=>$sid,'id'=>$project]];
$child=taskRecord($sid,$owner,[$recipient['user']['account_id']],'task',$child);
putReminder($child,$owner);fire($child,[$owner['user']['account_id'],$recipient['user']['account_id']],'inline project fixture delivers before archive');
$old=notices($child);$before=(int)sql('SELECT visibility_revision FROM familyhub_inbox_state WHERE account_id=?',[$recipient['user']['account_id']])[0]['visibility_revision'];
$closedMetadata=$projectMetadata;$closedMetadata['projectState']['archived']=true;
sql('UPDATE familyhub_crypto_records SET metadata=?,revision=2 WHERE scope_id=? AND id=?',[json_encode($closedMetadata),$sid,$project]);
$transaction=new ReflectionMethod(NativeDatabase::class,'transaction');
$transaction->invoke($notifications,fn()=>$notifications->changed(['scopeId'=>$sid,'id'=>$project,'type'=>'project','deleted'=>false,'expectedRevision'=>1,'metadata'=>$closedMetadata],['metadata'=>json_encode($projectMetadata),'deleted'=>0]));
ck((int)sql('SELECT visibility_revision FROM familyhub_inbox_state WHERE account_id=?',[$recipient['user']['account_id']])[0]['visibility_revision']===$before+1,'inline archive invalidates cached shared notices behind inbox cursor');
ck(!$notifications->deliveryVisible($old[0])&&!$notifications->deliveryVisible($old[1]),'inline archive denies existing shared due references for both recipients');
$peer=array_values(array_filter($old,fn($n)=>$n['recipient_account_id']===$recipient['user']['account_id']))[0];
$capture=new class {public $sent=[];public function send($job,$server){$this->sent[]=$job;return ['status'=>'accepted'];}};
ck(deliverNotice($peer,$recipient,$capture)['status']==='cancelled'&&$capture->sent===[],'inline archive cancels peer queued push before capture transport');
denied(fn()=>$notifications->read('crypto2.inbox.open',['id'=>(int)$peer['id']],$recipient),'permission_revoked','inline archived task cannot open from shared reminder');

echo json_encode(['status'=>'pass','checks'=>$checks,'fixture'=>'distinct linked-event and inline-project controls',
    'limitations'=>'No old successful controls rerun, no HTTP/provider/device proof']).PHP_EOL;
