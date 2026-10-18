<?php
/** Synthetic wrapper over the existing single-owner Capture3 fixture. */
umask(0077);
foreach(['JIVIE_CAPTURE_TEST_CHOICES','JIVIE_CAPTURE_TEST_SHARED','JIVIE_CAPTURE_TEST_INBOX_STATE','JIVIE_CAPTURE_TEST_IDEA','JIVIE_CAPTURE_TEST_AUDIT','JIVIE_CAPTURE_TEST_EXTRA_RECORDS'] as $name){
    if(getenv($name)!==false&&getenv($name)!==''&&getenv($name)!=='0')throw new RuntimeException('Use only the agreed base Capture3 fixture');
}
ob_start();require '/familyhub-tests/crypto2-migration-http-seed.php';
$fixture=json_decode(ob_get_clean(),true,128,JSON_THROW_ON_ERROR);
$raw=json_decode($fixture['payload'],true,128,JSON_THROW_ON_ERROR);
$due=time()+172800;$raw['dueAt']=gmdate('Y-m-d\TH:i:s.000\Z',$due);$raw['isCompleted']=false;
$fixture['payload']=json_encode($raw,JSON_THROW_ON_ERROR|JSON_UNESCAPED_UNICODE);
seedMigrationSql('UPDATE familyhub_records SET payload=? WHERE scope_id=? AND id=?',[$fixture['payload'],$fixture['scopeId'],$fixture['taskId']]);
$fixture['legacyTaskMismatch']=true;
$fingerprint=hash('sha256',json_encode([$raw['dueAt'],null,null,null]));
foreach(['pending','delivered'] as $state){
    $id=seedMigrationId();$when=$state==='pending'?$due-3600:time()-100;
    seedMigrationSql('INSERT INTO familyhub_reminders(id,scope_id,account_id,target_type,target_id,target_fingerprint,remind_at,remind_epoch,revision,state,schedule_mode,offset_minutes) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)',[
        $id,$fixture['scopeId'],$fixture['session']['user']['accountId'],'task',$fixture['taskId'],$fingerprint,gmdate('Y-m-d\TH:i:s\Z',$when),$when,2,$state,'deadline',60]);
    $fixture[$state==='pending'?'use3PendingId':'use3DeliveredId']=$id;
}
$fixture['use3GenerationFixture']=true;
echo json_encode($fixture,JSON_THROW_ON_ERROR|JSON_UNESCAPED_UNICODE);
