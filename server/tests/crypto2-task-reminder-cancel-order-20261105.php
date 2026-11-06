<?php
/** Distinct cancellation lock/reload controls; no successful main/project suite reruns. */
define('TASK_REMINDER_RECIPIENTS_FIXTURE_ONLY',true);
require __DIR__.'/crypto2-task-reminder-recipients-20261105.php';
[$sid]=sharedScope($owner,$recipient);
$task=taskRecord($sid,$owner,[$recipient['user']['account_id']]);$r=putReminder($task,$owner);
$cancel=['id'=>$r['id'],'scopeId'=>$sid,'expectedRevision'=>1];
$before=$notifications->deliveryScopeCalls;
// Simulate a newer row becoming visible after a scope-lock wait. The real
// parent lock runs first; the hook mutates only this ephemeral SQLite fixture.
$notifications->deliveryScopeHook=static function($scope) use($r) {
    sql('UPDATE familyhub_crypto_reminders_v2 SET revision=2 WHERE id=?',[$r['id']]);
};
denied(fn()=>$notifications->command('crypto2.reminders.cancel',$cancel,$owner,signCommand('crypto2.reminders.cancel',$cancel,$owner)),'reminder_conflict','shared cancellation reloads after lifecycle lock before checking CAS');
ck($notifications->deliveryScopeCalls===$before+1&&sql('SELECT state,revision FROM familyhub_crypto_reminders_v2 WHERE id=?',[$r['id']])===[['state'=>'pending','revision'=>1]],'post-lock conflict rolls back and preserves original schedule');
$notifications->deliveryScopeHook=null;
$result=$notifications->command('crypto2.reminders.cancel',$cancel,$owner,signCommand('crypto2.reminders.cancel',$cancel,$owner));
ck($result['reminder']['state']==='cancelled'&&$result['reminder']['revision']===2&&$notifications->deliveryScopeCalls===$before+2,'matching shared cancel uses mutex and commits exact next revision');

// Losing scope visibility does not remove the owner's privacy escape.
$task=taskRecord($sid,$owner,[$recipient['user']['account_id']]);$r=putReminder($task,$owner);
sql('UPDATE familyhub_scopes SET archived=1 WHERE id=?',[$sid]);
$cancel=['id'=>$r['id'],'scopeId'=>$sid,'expectedRevision'=>1];
$result=$notifications->command('crypto2.reminders.cancel',$cancel,$owner,signCommand('crypto2.reminders.cancel',$cancel,$owner));
ck($result['reminder']['state']==='cancelled','archived scope still permits existing shared reminder cancellation');
sql('UPDATE familyhub_scopes SET archived=0 WHERE id=?',[$sid]);

$task=taskRecord($sid,$owner,[$recipient['user']['account_id']]);$r=putReminder($task,$owner);
$cancel=['id'=>$r['id'],'scopeId'=>$sid,'expectedRevision'=>1];
$notifications->deliveryScopeHook=static function($scope) use($r,$recipient) {
    sql('UPDATE familyhub_crypto_reminders_v2 SET account_id=? WHERE id=?',[$recipient['user']['account_id'],$r['id']]);
};
denied(fn()=>$notifications->command('crypto2.reminders.cancel',$cancel,$owner,signCommand('crypto2.reminders.cancel',$cancel,$owner)),'permission_revoked','shared cancellation rechecks owner binding after lifecycle wait');
$notifications->deliveryScopeHook=null;
// No live encrypted origin means lockDeliveryScope returns null after locking;
// no worker can deliver, and cancelling retained own intent must still work.
sql('DELETE FROM familyhub_crypto_scope_origins WHERE scope_id=?',[$sid]);
$result=$notifications->command('crypto2.reminders.cancel',$cancel,$owner,signCommand('crypto2.reminders.cancel',$cancel,$owner));
ck($result['reminder']['state']==='cancelled','no eligible delivery scope still permits retained own shared cancellation');
sql('INSERT INTO familyhub_crypto_scope_origins VALUES(?,?,?,?)',[$sid,$owner['user']['account_id'],json_encode(signCommand('synthetic.origin',['scopeId'=>$sid],$owner)),time()]);

$task=taskRecord($sid,$owner,[]);$r=putReminder($task,$owner,false);$before=$notifications->deliveryScopeCalls;
$cancel=['id'=>$r['id'],'scopeId'=>$sid,'expectedRevision'=>1];
$notifications->command('crypto2.reminders.cancel',$cancel,$owner,signCommand('crypto2.reminders.cancel',$cancel,$owner));
ck($notifications->deliveryScopeCalls===$before,'legacy own cancellation retains its exact escape path without new mutex');
echo json_encode(['status'=>'pass','checks'=>$checks,'fixture'=>'distinct shared cancel scope-lock/reload controls',
    'limitations'=>'SQLite lock-order seam, not real MariaDB concurrent send; no earlier successful controls rerun']).PHP_EOL;
