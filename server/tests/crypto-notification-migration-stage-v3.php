<?php
require __DIR__.'/crypto2-scope-integration.php';
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoMigrationNotificationStageV3 as Stage;
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoMigrationNotificationV3 as Cert;
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoV2Codec;
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoCodec;

function signedNotification3($body,$key,$domain="JivieE2EE/notificationTransform/v3\n") {
    $bytes=NativeCryptoCodec::canonical((object)$body);
    return ['commandBase64'=>base64_encode($bytes),'signatureBase64'=>base64_encode(sodium_crypto_sign_detached($domain.$bytes,$key['sign']))];
}
function outerNotification3($op,$p,$u,$key) {
    return signedNotification3(['version'=>2,'operation'=>$op,'requestId'=>uid(),'serverId'=>$u['serverId'],
        'accountId'=>$u['user']['accountId'],'deviceId'=>$u['device']['id'],'signer'=>'device','payload'=>$p],$key,"JivieE2EE/v2\n");
}
function typedNotification3($row) {
    return (object)array_map(fn($v)=>['type'=>$v===null?'null':'text','valueBase64'=>$v===null?null:base64_encode((string)$v)],$row);
}
$state=call('crypto2.account.status',[],$fresh);
$account=$fresh['user']['accountId'];$sid=$space['id'];$mig=uid();$cap=uid();$rootHash=hash('sha256',random_bytes(32));
$context=['version'=>3,'serverId'=>$fresh['serverId'],'migrationId'=>$mig,'captureId'=>$cap,'accountId'=>$account,'sourceInventoryRoot'=>$rootHash];
$actor=['user'=>['id'=>$fresh['user']['id'],'account_id'=>$account],'device'=>['id'=>$fresh['device']['id']]];
$stage=new Stage($container);
q('INSERT INTO familyhub_crypto_captures_v3(migration_id,account_id,capture_id,key_id,state,inventory_root,source_count,authorization) VALUES(?,?,?,?,?,?,?,?)',[$mig,$account,$cap,uid(),'sealed',$rootHash,3,'{}']);
q('DELETE FROM familyhub_inbox_state WHERE account_id=?',[$account]);
q('INSERT INTO familyhub_inbox_state(account_id,sequence,visibility_revision) VALUES(?,17,2)',[$account]);
$reminder=uid();$target=uid();$epoch=time()-500;
q('INSERT INTO familyhub_reminders(id,scope_id,account_id,target_type,target_id,target_fingerprint,remind_at,remind_epoch,revision,state,schedule_mode,offset_minutes) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)',[$reminder,$sid,$account,'task',$target,str_repeat('a',64),gmdate('Y-m-d\TH:i:s\Z',$epoch),$epoch,4,'cancelled','absolute',null]);
$sourceRows=[
    ['table'=>'familyhub_inbox_state','row'=>['account_id'=>$account,'sequence'=>'17','visibility_revision'=>'2'],'kind'=>'inboxState','canonical'=>['sequence'=>17,'visibilityRevision'=>2]],
    ['table'=>'familyhub_reminders','row'=>q('SELECT * FROM familyhub_reminders WHERE id=?',[$reminder])[0],'kind'=>'reminder','canonical'=>[
        'id'=>$reminder,'scopeId'=>$sid,'targetType'=>'task','canonicalTargetId'=>$target,
        'targetId'=>\Kanboard\Plugin\FamilyHub\Model\NativeCryptoRecordAddressV2::derive($fresh['serverId'],$sid,'content','records',$target),
        'domain'=>'content','targetRevision'=>0,'targetRecordProofHash'=>null,'scheduleRevision'=>uid(),'consentGeneration'=>null,
        'scopeLifecycleHash'=>null,'projectBarrier'=>null,'remindAt'=>gmdate('Y-m-d\TH:i:s\Z',$epoch),
        'remindEpoch'=>$epoch,'revision'=>4,'state'=>'cancelled','scheduleMode'=>'absolute','offsetMinutes'=>null]],
];
$inboxIds=[];
foreach (['membership','task'] as $i=>$type) {
    $canonicalId=$type==='membership'?$account:uid();
    q('INSERT INTO familyhub_inbox(event_key,recipient_account_id,scope_id,category,kind,audience,actor_account_id,target_type,target_id,target_revision,group_key,created_at,read_at,revision,sequence,in_app) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',[
        hash('sha256',random_bytes(32)),$account,$sid,'tasks',$type==='membership'?'member.joined':'task.updated','scope',null,$type,$canonicalId,1,'scope',gmdate('Y-m-d\TH:i:s\Z'),$i===0?gmdate('Y-m-d\TH:i:s\Z'):null,3,10+$i,1]);
    $inboxId=(int)$pdo->lastInsertId();$inboxIds[]=$inboxId;
    $raw=q('SELECT * FROM familyhub_inbox WHERE id=?',[$inboxId])[0];
    $sourceRows[]=['table'=>'familyhub_inbox','row'=>$raw,'kind'=>'inbox','canonical'=>[
        'rowKind'=>'inbox','id'=>$inboxId,'eventKey'=>$raw['event_key'],'scopeId'=>$sid,'category'=>'tasks',
        'kind'=>'crypto2.'.$raw['kind'],'audience'=>'scope','actorAccountId'=>null,'targetType'=>$type,
        'canonicalTargetId'=>$canonicalId,'targetId'=>$type==='membership'?$canonicalId:
            \Kanboard\Plugin\FamilyHub\Model\NativeCryptoRecordAddressV2::derive($fresh['serverId'],$sid,'content','records',$canonicalId),
        'targetRevision'=>1,'groupKey'=>'scope','createdAt'=>$raw['created_at'],'readAt'=>$raw['read_at'],
        'revision'=>3,'sequence'=>10+$i,'inApp'=>true]];
    q('INSERT INTO familyhub_deliveries(inbox_id,state,attempts,next_attempt,expires_at,lease_token,lease_until,sent_at) VALUES(?,?,?,?,?,?,?,?)',[
        $inboxId,$i===0?'sent':'processing',2,time(),time()+500, $i===0?null:str_repeat('e',32),$i===0?null:time()+100,$i===0?time()-50:null]);
    $job=q('SELECT * FROM familyhub_deliveries WHERE inbox_id=?',[$inboxId])[0];
    $sourceRows[]=['table'=>'familyhub_deliveries','row'=>$job,'kind'=>'inbox','canonical'=>[
        'rowKind'=>'delivery','inboxId'=>$inboxId,'state'=>$job['state'],'attempts'=>2,'nextAttempt'=>(int)$job['next_attempt'],
        'expiresAt'=>(int)$job['expires_at'],'leaseToken'=>$job['lease_token'],'leaseUntil'=>$job['lease_until']===null?null:(int)$job['lease_until'],
        'sentAt'=>$job['sent_at']===null?null:(int)$job['sent_at']]];
}
$jobsBefore=q('SELECT * FROM familyhub_deliveries WHERE inbox_id IN (?,?) ORDER BY inbox_id',$inboxIds);
$due=time()+5000;$canonicalTask=uid();$wireTask=\Kanboard\Plugin\FamilyHub\Model\NativeCryptoRecordAddressV2::derive($fresh['serverId'],$sid,'content','records',$canonicalTask);
$taskPayload=['title'=>'Synthetic private deadline','isCompleted'=>false,'dueAt'=>gmdate('Y-m-d\TH:i:s\Z',$due)];
q('INSERT INTO familyhub_records(scope_id,id,type,revision,deleted,payload,sequence,updated_at,created_by,updated_by,contract_version) VALUES(?,?,?,?,?,?,?,?,?,?,?)',[$sid,$canonicalTask,'task',8,0,json_encode($taskPayload),1,gmdate('Y-m-d\TH:i:s\Z'),$account,$account,6]);
$currentHead=call('crypto2.scope.headGet',['scopeId'=>$sid],$fresh);$scheduleRevision=uid();$consentGeneration=uid();$targetProofHash=hash('sha256',random_bytes(32));
$targetRecord=['scopeId'=>$sid,'id'=>$wireTask,'type'=>'task','domain'=>'content','membershipHeadHash'=>$currentHead['headHash'],
    'accessRevision'=>$currentHead['payload']['accessRevision'],'expectedRevision'=>0,'deleted'=>false,
    'metadata'=>['references'=>[],'referenceVersions'=>[],'reminderState'=>['version'=>1,'dueAtEpoch'=>null,'closed'=>false,'scheduleRevision'=>$scheduleRevision,'consentGeneration'=>$consentGeneration]]];
$relativeIds=[];
foreach(['pending','delivered'] as $originalState){
    $rid=uid();$relativeIds[]=$rid;$when=$originalState==='pending'?$due-600:time()-100;
    $fingerprint=hash('sha256',json_encode([$taskPayload['dueAt'],null,null,null]));
    q('INSERT INTO familyhub_reminders(id,scope_id,account_id,target_type,target_id,target_fingerprint,remind_at,remind_epoch,revision,state,schedule_mode,offset_minutes) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)',[
        $rid,$sid,$account,'task',$canonicalTask,$fingerprint,gmdate('Y-m-d\TH:i:s\Z',$when),$when,2,$originalState,'deadline',10]);
    $sourceRows[]=['table'=>'familyhub_reminders','row'=>q('SELECT * FROM familyhub_reminders WHERE id=?',[$rid])[0],'kind'=>'reminder','use'=>true,'canonical'=>[
        'id'=>$rid,'scopeId'=>$sid,'targetType'=>'task','canonicalTargetId'=>$canonicalTask,'targetId'=>$wireTask,'domain'=>'content',
        'targetRevision'=>1,'targetRecordProofHash'=>$targetProofHash,'scheduleRevision'=>$scheduleRevision,'consentGeneration'=>$consentGeneration,
        'scopeLifecycleHash'=>(new \Kanboard\Plugin\FamilyHub\Model\NativeCryptoLifecycleV2($container))->closingHash($sid),'projectBarrier'=>null,
        'remindAt'=>gmdate('Y-m-d\TH:i:s\Z',$when),'remindEpoch'=>$when,'revision'=>2,'state'=>$originalState,'scheduleMode'=>'deadline','offsetMinutes'=>10]];
}
$entries=[];$items=[];
foreach($sourceRows as $i=>$source){
    $id=uid();$binding=['bindingId'=>$id,'scopeId'=>null,'domain'=>'private','sourceCommitment'=>hash('sha256',random_bytes(32))];
    $entry=['context'=>['version'=>3,'serverId'=>$fresh['serverId'],'migrationId'=>$mig,'captureId'=>$cap,'accountId'=>$account,'scopeId'=>null,'domain'=>'private','sourceTable'=>$source['table'],'sourceId'=>'row:'.$i],
        'binding'=>$binding,'typedRow'=>typedNotification3($source['row'])];
    $entries[$id]=$entry;
    $body=$context+['operation'=>'crypto2.migration.notificationTransform','deviceId'=>$fresh['device']['id'],
        'bindingId'=>$id,'kind'=>$source['kind'],'canonical'=>$source['canonical'],
        'authorDirectoryHeadHash'=>$state['headHash'],'useAuthorization'=>null];
    if(!empty($source['use'])){
        $c=$source['canonical'];$use=['version'=>3,'operation'=>'crypto2.migration.schedulingUse','serverId'=>$fresh['serverId'],
            'scopeId'=>$sid,'targetId'=>$wireTask,'targetType'=>'task','domain'=>'content','useId'=>uid(),
            'sourceScheduleRevision'=>$scheduleRevision,'schedulePutId'=>$c['id'],'consentGeneration'=>$consentGeneration,
            'scopeLifecycleHash'=>$c['scopeLifecycleHash'],'projectBarrier'=>null,'expiresAtEpoch'=>null,'mode'=>'relative',
            'membershipHeadHash'=>$currentHead['headHash'],'accessRevision'=>$targetRecord['accessRevision'],
            'targetRevision'=>1,'targetRecordProofHash'=>$targetProofHash,'accountId'=>$account,'deviceId'=>$fresh['device']['id'],
            'authorDirectoryHeadHash'=>$state['headHash'],'migrationId'=>$mig,'captureId'=>$cap,'sourceInventoryRoot'=>$rootHash,
            'bindingId'=>$id,'originalState'=>$c['state']];
        $body['useAuthorization']=signedNotification3($use,$freshKeys,"JivieE2EE/migrationSchedulingUse/v3\n");
    }
    $items[$id]=['authorization' =>signedNotification3($body,$freshKeys),'previousTransformHash'=>null];
}
ksort($entries,SORT_STRING);ksort($items,SORT_STRING);
$resolve=function($m,$c,$b,$a)use(&$entries,$mig,$cap,$account){if($m!==$mig||$c!==$cap||$a['user']['account_id']!==$account||!isset($entries[$b]))throw new RuntimeException('bad test resolver');return $entries[$b];};
$iterate=function($m,$c,$r,$a,$tables)use(&$entries,$rootHash){if($r!==$rootHash)throw new RuntimeException('bad test root');foreach($entries as $entry){if(in_array($entry['context']['sourceTable'],$tables,true))yield array_intersect_key($entry,array_flip(['context','binding']));}};
$targetRead=function($m,$s,$w,$h,$a)use($wireTask,$targetProofHash,$targetRecord){
    if($w!==$wireTask||$h!==$targetProofHash)throw new RuntimeException('wrong target');return ['record'=>$targetRecord];};
$p=['migrationId'=>$mig,'captureId'=>$cap,'sourceInventoryRoot'=>$rootHash,'transforms'=>array_values($items)];
$proof=outerNotification3('crypto2.migration.notifications.stage',$p,$fresh,$freshKeys);[$command]=NativeCryptoCodec::decode($proof);
$pdo->beginTransaction();
$bad=$p;$bad['transforms'][0]['authorization']['signatureBase64']=base64_encode(str_repeat("\0",64));
$badProof=outerNotification3('crypto2.migration.notifications.stage',$bad,$fresh,$freshKeys);[$badCommand]=NativeCryptoCodec::decode($badProof);
deny(fn()=>$stage->stage($bad,$actor,$badProof,$badCommand,$resolve,$targetRead),'crypto_signature_invalid','stage rejects wrong own transform signer before any scheduler effect');
$expired=$p;
foreach($expired['transforms'] as &$item){[$b]=NativeCryptoCodec::decode($item['authorization']);if($b['useAuthorization']!==null&&$b['canonical']['state']==='pending'){
    [$u]=NativeCryptoCodec::decode($b['useAuthorization']);$u['expiresAtEpoch']=time()-1;
    $b['useAuthorization']=signedNotification3($u,$freshKeys,"JivieE2EE/migrationSchedulingUse/v3\n");
    $item['authorization']=signedNotification3($b,$freshKeys);break;}}unset($item);
$xp=outerNotification3('crypto2.migration.notifications.stage',$expired,$fresh,$freshKeys);[$xc]=NativeCryptoCodec::decode($xp);
// The outer boundary owns rollback on failure, including earlier page rows.
$pdo->exec('SAVEPOINT expire_stage');
deny(fn()=>$stage->stage($expired,$actor,$xp,$xc,$resolve,$targetRead),'crypto_notification_migration_use_target','intentional expired pending date permission cannot activate');
$pdo->exec('ROLLBACK TO SAVEPOINT expire_stage');$pdo->exec('RELEASE SAVEPOINT expire_stage');
$staged=$stage->stage($p,$actor,$proof,$command,$resolve,$targetRead);
ck(count($staged['leaves'])===count($sourceRows) && q('SELECT id FROM familyhub_crypto_reminders_v2 WHERE id=?',[$reminder])===[],'staged transforms leave live reminders untouched');
$duplicate=$p;$duplicate['transforms'][]=$duplicate['transforms'][0];$dp=outerNotification3('crypto2.migration.notifications.stage',$duplicate,$fresh,$freshKeys);[$dc]=NativeCryptoCodec::decode($dp);
deny(fn()=>$stage->stage($duplicate,$actor,$dp,$dc,$resolve,$targetRead),'crypto_notification_migration_duplicate','duplicate binding cannot count twice');
$coverage=$stage->stagedCoverage($mig,$cap,$rootHash,$actor,$iterate);
ck($coverage['transformCount']===count($sourceRows) && $coverage['sourceCounts']['inbox']===4 && $coverage['sourceCounts']['reminder']===3 && $coverage['sourceCounts']['inboxState']===1,'complete own source coverage counts exact binding kinds');
$missing=function($m,$c,$r,$a,$tables)use($iterate){foreach($iterate($m,$c,$r,$a,$tables) as $e)yield $e;yield ['binding'=>['bindingId'=>uid(),'scopeId'=>null,'domain'=>'private','sourceCommitment'=>str_repeat('b',64)],'context'=>['sourceTable'=>'familyhub_inbox_state']];};
// Missing/extra coverage is tested with a real additional immutable source.
$extraId='ffffffff-ffff-4fff-afff-ffffffffffff';$entries[$extraId]=['binding'=>['bindingId'=>$extraId,'scopeId'=>null,'domain'=>'private','sourceCommitment'=>str_repeat('b',64)],'context'=>['sourceTable'=>'familyhub_inbox_state']];ksort($entries);
deny(fn()=>$stage->stagedCoverage($mig,$cap,$rootHash,$actor,$iterate),'crypto_notification_migration_incomplete','omitted eligible source blocks complete selection');unset($entries[$extraId]);
$digests=array_column($staged['leaves'],'bindingId');$leafHashes=array_map(fn($l)=>Cert::leafDigest($l),$staged['leaves']);sort($leafHashes,SORT_STRING);
$header=$context+['archiveManifestHash'=>str_repeat('c',64),'coldParityProofHash'=>str_repeat('d',64),'authorDirectoryHeadHash'=>$state['headHash'],
    'transformCount'=>count($sourceRows),'sourceCounts'=>$coverage['sourceCounts'],'transformRoot'=>str_repeat('0',64)];
$header['transformRoot']=Cert::transformRoot($header,$leafHashes);
$certProof=outerNotification3('crypto2.migration.notifications.certify',['header'=>$header],$fresh,$freshKeys);[$certCommand]=NativeCryptoCodec::decode($certProof);
deny(fn()=>$stage->certify(['header'=>$header],$actor,$certProof,$certCommand,$iterate,fn()=>false),'crypto_notification_migration_cold_parity','certificate requires actual finalized cold proof callback');
$cert=$stage->certify(['header'=>$header],$actor,$certProof,$certCommand,$iterate,fn()=>true);
$pdo->commit();
$eventProof=request2('crypto2.account.migrationAttest',['migrationId'=>$mig,'scopeToken'=>Cert::scopeToken($header),'domain'=>'content','attestationHash'=>$cert['certificateHash']],$fresh,$freshKeys,$state['snapshot'],$state);
$event=call('crypto2.account.migrationAttest',$eventProof,$fresh);
$pdo->beginTransaction();
$stage->anchor(['migrationId'=>$mig,'captureId'=>$cap,'sourceInventoryRoot'=>$rootHash,'certificateHash'=>$cert['certificateHash'],
    'eventHeadHash'=>$event['headHash'],'eventCommandHash'=>hash('sha256',base64_decode($eventProof['commandBase64']))],$actor);
$anchored=$stage->coverage($mig,$cap,$rootHash,$actor,$iterate);
$oneBinding=array_key_first($items);$storedLeaf=q('SELECT leaf_hash FROM familyhub_crypto_notification_transforms_v3 WHERE migration_id=? AND binding_id=?',[$mig,$oneBinding])[0]['leaf_hash'];
q('UPDATE familyhub_crypto_notification_transforms_v3 SET leaf_hash=? WHERE migration_id=? AND binding_id=?',[str_repeat('0',64),$mig,$oneBinding]);
deny(fn()=>$stage->coverage($mig,$cap,$rootHash,$actor,$iterate),'crypto_notification_migration_selection_changed','anchored certificate recomputes exact signed full transform stream instead of trusting SQL selection root');
q('UPDATE familyhub_crypto_notification_transforms_v3 SET leaf_hash=? WHERE migration_id=? AND binding_id=?',[$storedLeaf,$mig,$oneBinding]);

ck($anchored['state']==='anchored','exact own directory inclusion authenticates certificate without historical snapshot cache');
$apply=$stage->prepareInstall($anchored,$actor,$iterate,$resolve,$targetRead);
q('UPDATE familyhub_inbox_state SET sequence=21,visibility_revision=5 WHERE account_id=?',[$account]);
$result=$apply();
ck($result['state']==='installed' && q('SELECT state FROM familyhub_reminders WHERE id=?',[$reminder])[0]['state']==='migrated','final install disables old worker while preserving original cancelled canonical intent');
$installed=q('SELECT * FROM familyhub_crypto_reminders_v2 WHERE id=?',[$reminder])[0];
ck($installed['state']==='cancelled' && (int)$installed['revision']===4 && (int)$installed['remind_epoch']===$epoch,'cancelled old time/revision remain exact and cannot redeliver');
ck(q('SELECT sequence,visibility_revision FROM familyhub_inbox_state WHERE account_id=?',[$account])===[['sequence'=>'21','visibility_revision'=>'5']] || q('SELECT sequence,visibility_revision FROM familyhub_inbox_state WHERE account_id=?',[$account])===[['sequence'=>21,'visibility_revision'=>5]],'unrelated global counter advances survive baseline install');
deny($apply,'crypto_notification_migration_install_used','prepared final plan is one-shot');
$pdo->rollBack();
ck(q('SELECT id FROM familyhub_crypto_reminders_v2 WHERE id=?',[$reminder])===[] && q('SELECT state FROM familyhub_reminders WHERE id=?',[$reminder])[0]['state']==='cancelled','outer final failure rolls back canonical row and old worker marker atomically');
$pdo->beginTransaction();
$stage->anchor(['migrationId'=>$mig,'captureId'=>$cap,'sourceInventoryRoot'=>$rootHash,'certificateHash'=>$cert['certificateHash'],'eventHeadHash'=>$event['headHash'],'eventCommandHash'=>hash('sha256',base64_decode($eventProof['commandBase64']))],$actor);
$again=$stage->prepareInstall($anchored,$actor,$iterate,$resolve,$targetRead);$again();$pdo->commit();
$listed=call('crypto2.inbox.list',['scopeId'=>$sid],$fresh)['items'];
$selected=array_values(array_filter($listed,fn($v)=>in_array($v['id'],$inboxIds,true)));
ck(count($selected)===2,'installed membership and missing-target inbox rows remain reachable through actual V2 dispatch');
$membership=call('crypto2.inbox.open',['id'=>$inboxIds[0]],$fresh);
$missing=call('crypto2.inbox.open',['id'=>$inboxIds[1]],$fresh);
ck($membership['item']['targetIdentity']===['sourceKind'=>'membership','canonicalId'=>$account] &&
    $membership['item']['readAt']!==null && $membership['record']===null,'membership routes to account identity without fictional content record and preserves read state');
ck($missing['item']['targetIdentity']['canonicalId']===$sourceRows[4]['canonical']['canonicalTargetId'] &&
    $missing['record']===null,'retained absent target uses canonical routing hint only and returns no invented content');
ck(q('SELECT * FROM familyhub_deliveries WHERE inbox_id IN (?,?) ORDER BY inbox_id',$inboxIds)===$jobsBefore,'sent and processing job state/lease/attempts remain byte exact without resend');
$relative=q('SELECT * FROM familyhub_crypto_reminders_v2 WHERE id=?',[$relativeIds[0]])[0];
$delivered=q('SELECT * FROM familyhub_crypto_reminders_v2 WHERE id=?',[$relativeIds[1]])[0];
$uses=new \Kanboard\Plugin\FamilyHub\Model\NativeCryptoSchedulingUseV2($container);
$priorUse=$uses->forReminder($account,$relativeIds[0]);[$u]=NativeCryptoCodec::decode($priorUse['authorization']);
ck($relative['state']==='pending'&&$delivered['state']==='delivered'&&$u['expiresAtEpoch']===null,'indefinite pending and delivered relative consents preserve exact state without invented expiry or redelivery');
$useHash=NativeCryptoV2Codec::hash((object)$priorUse['authorization']);
// This helper-only install has no final scoped publication/control. Positive
// recipient evidence is covered by the existing migrated-use HTTP representative.
deny(fn()=>call('crypto2.scheduling.migrationEvidence',['scopeId'=>$sid,'targetId'=>$wireTask,'useProofHash'=>$useHash],$fresh),'crypto_notification_migration_provenance_pending','installed stage alone cannot expose migrated use evidence');
$latest=call('crypto2.account.status',[],$fresh);$requestId=uid();
$useToken=hash('sha256',"JivieScheduleUse/v2\n".NativeCryptoCodec::canonical((object)array_intersect_key($u,array_flip(['serverId','accountId','scopeId','targetId','useId']))));
$cancelEvent=request2('crypto2.account.scheduleUse',['useToken'=>$useToken,'useProofHash'=>$useHash,'active'=>false],$fresh,$freshKeys,$latest['snapshot'],$latest);
[$eventBody]=NativeCryptoCodec::decode($cancelEvent);$eventBody['requestId']=$requestId;$cancelEvent=signedNotification3($eventBody,$freshKeys,"JivieE2EE/v2\n");
$cancelProof=content2('crypto2.reminders.cancel',['scopeId'=>$sid,'id'=>$relativeIds[0],'expectedRevision'=>2,'accountEventProof'=>$cancelEvent],$fresh,$freshKeys,$requestId);
$cancel=call('crypto2.reminders.cancel',$cancelProof,$fresh);
ck($cancel['reminder']['state']==='cancelled'&&!$uses->forReminder($account,$relativeIds[0])['active'],'ordinary current own cancel supersedes exact migration baseline with nested account event');
ck(call('crypto2.reminders.cancel',$cancelProof,$fresh)===$cancel,'lost cancellation ACK replays exact response without appending another event');
$recordAttempt=$targetRecord;$recordAttempt['metadata']['schedulingUse']=['authorization'=>$priorUse['authorization'],'directoryHeadHash'=>$latest['headHash'],'eventCommandHash'=>$priorUse['eventCommandHash']];
deny(fn()=>$uses->validateMetadata($recordAttempt),'crypto_scheduling_use_revoked','old migration use cannot authorize date disclosure after observed own cancellation');
echo 'Notification migration stage3: '.$checks.' checks PASS'.PHP_EOL;
