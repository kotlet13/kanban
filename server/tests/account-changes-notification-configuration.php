<?php
/** New account configuration wake controls, no prior PASS suites are included. */
require __DIR__.'/account-changes-fixture.php';
define('DATA_DIR','/tmp/jivie-account-changes-fixture');
use Kanboard\Plugin\FamilyHub\Model\NativeInboxService;
use Kanboard\Plugin\FamilyHub\Model\NativeReminderService;
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoNotificationV2;
use Kanboard\Plugin\FamilyHub\Model\NativeNotificationWriter;
sql("UPDATE familyhub_scopes SET kind='organization',access_policy_version=1 WHERE id=?",[id(4)]);
$inbox=new NativeInboxService(['db'=>$db],bearer(1),'synthetic-config');
$reminders=new NativeReminderService(['db'=>$db],bearer(1),'synthetic-config');
$preferences=['scopeId'=>id(4),'category'=>'tasks','settings'=>['inApp'=>true,'sound'=>false,'push'=>false,'email'=>false],'requestId'=>id(150)];
$current=$probe(null)['cursor'];$inbox->execute('inbox.preferences.set',$preferences);$changed=$probe($current);
ck($changed['accountDomains']===['inbox']&&$changed['scopes']===[],'preference command creates account configuration hint without content or finance');
$current=$changed['cursor'];$inbox->execute('inbox.preferences.set',$preferences);
ck(!$probe($current)['changed'],'exact preference receipt retry creates no new configuration progress');
$inbox->execute('inbox.preferences.get',['scopeId'=>id(4)]);
ck(!$probe($current)['changed'],'reading preferences has no invalidation side effect');
sql("INSERT INTO familyhub_reminders(id,scope_id,account_id,target_type,target_id,target_fingerprint,remind_at,remind_epoch,revision,state) VALUES(?,?,?,'task',?,?,'2026-10-24T00:00:00Z',1,1,'pending')",[id(51),id(4),id(1),id(52),str_repeat('a',64)]);
$cancel=['id'=>id(51),'scopeId'=>id(4),'expectedRevision'=>1,'requestId'=>id(151)];
$reminders->execute('reminders.cancel',$cancel);$changed=$probe($current);
ck($changed['accountDomains']===['inbox']&&$changed['scopes']===[],'personal reminder cancellation wakes configuration on other devices');
$current=$changed['cursor'];$reminders->execute('reminders.cancel',$cancel);
ck(!$probe($current)['changed'],'exact cancellation retry leaves account progress unchanged');
class AtomicConfigWriter extends NativeNotificationWriter {public function forTarget($scope,$target){return $this->transaction(fn()=> $this->configurationForScope($scope,$target));}}
sql("UPDATE familyhub_reminders SET state='pending' WHERE id=?",[id(51)]);
$writer=new AtomicConfigWriter(['db'=>$db]);$writer->forTarget(id(4),id(52));$changed=$probe($current);
ck($changed['accountDomains']===['inbox'],'bulk lifecycle targeting preserves recipient account configuration progress');
$current=$changed['cursor'];$writer->forTarget(id(4),id(99));
ck(!$probe($current)['changed'],'unaffected lifecycle target does not create configuration work');
// Exercise crypto preference mutation directly under the same native transaction
// as its signed dispatcher. This seam is metadata routing, not signature proof.
class AtomicCryptoConfig extends NativeCryptoNotificationV2 {public function preferences($p){return $this->transaction(fn()=> $this->write('crypto2.inbox.preferences.set',$p,$this->actor(false),[],null,null));}}
$crypto=new AtomicCryptoConfig(['db'=>$db],bearer(1),'synthetic-config');$cp=$preferences;unset($cp['requestId']);$cp['settings']['sound']=true;
$crypto->preferences($cp);$changed=$probe($current);
ck($changed['accountDomains']===['inbox']&&$changed['scopes']===[],'crypto preference mutation uses the same durable configuration counter');
$current=$changed['cursor'];$service->queries=[];$probe($current);
ck(!preg_match('/familyhub_(inbox_preferences|reminders|crypto_reminders_v2)\b/',implode("\n",$service->queries)),'unchanged probe never inventories reminder or preference payloads');
echo json_encode(['test'=>'account-changes-notification-configuration','status'=>'pass','checks'=>$checks,'fixture'=>'isolated-memory-sqlite','http'=>false,'proofVerification'=>false]).PHP_EOL;
