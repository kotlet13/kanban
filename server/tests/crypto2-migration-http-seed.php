<?php
/** Creates only synthetic loopback data; redirect credentials to a private file. */
umask(0077);
require '/var/www/app/app/common.php';
if (session_status() === PHP_SESSION_ACTIVE) session_abort();
if (!defined('FAMILYHUB_DEVELOPMENT_MODE') || FAMILYHUB_DEVELOPMENT_MODE !== true) throw new RuntimeException('Synthetic only');
use Kanboard\Plugin\FamilyHub\Model\NativeService;
use Kanboard\Plugin\FamilyHub\Schema\CryptoSchema;
$pdo = $container['db']->getConnection();
CryptoSchema::create($pdo,$pdo->getAttribute(PDO::ATTR_DRIVER_NAME)==='mysql');
$api = new NativeService($container);
function seedMigrationId() {
    $h=bin2hex(random_bytes(16));return substr($h,0,8).'-'.substr($h,8,4).'-4'.substr($h,13,3).'-a'.substr($h,17,3).'-'.substr($h,20);
}
function seedMigrationSql($sql,$params=[]) {
    global $pdo;$s=$pdo->prepare($sql);$s->execute($params);$s->closeCursor();
}
$username='archive_'.bin2hex(random_bytes(10));$password=bin2hex(random_bytes(20));
$container['userModel']->create(['username'=>$username,'password'=>$password,'role'=>'app-user']);
$session=$api->dispatch('auth.login',['username'=>$username,'password'=>$password,'deviceName'=>'Synthetic archive'], '', $username);
$account=$session['user']['accountId'];$uid=$session['user']['id'];
seedMigrationSql('INSERT INTO familyhub_email_identities(account_id,email,verified_at,revision) VALUES(?,?,?,1)',[$account,$username.'@capture.invalid',time()]);
$api->dispatch('moderation.acceptPolicy',['policyVersion'=>1],'Bearer '.$session['token'],$username);
$scope=seedMigrationId();$task=seedMigrationId();$deleted=seedMigrationId();$receipt=seedMigrationId();$attachment=seedMigrationId();
$ledger=seedMigrationId();$expense=seedMigrationId();
seedMigrationSql('INSERT INTO familyhub_scopes(id,kind,name,owner_id,sequence,created_at,access_policy_version) VALUES(?,?,?,?,51,?,1)',[$scope,'household','SYNTHETIC_ARCHIVE_SOURCE',$uid,time()]);
seedMigrationSql('INSERT INTO familyhub_members VALUES(?,?,?,?,1)',[$scope,$uid,$account,'owner']);
seedMigrationSql('INSERT INTO familyhub_finance_policy(scope_id,enabled,revision,sequence,required_contract_version) VALUES(?,1,4,2,3)',[$scope]);
seedMigrationSql('INSERT INTO familyhub_finance_grants VALUES(?,?,?)',[$scope,$account,'write']);
$payload=json_encode([
    'title'=>'PRIVATE_COLD_SOURCE','notes'=>'','projectId'=>null,'dueAt'=>'2026-10-17T00:00:00.000Z','isCompleted'=>true,
    'createdAt'=>'2026-10-17T00:00:00.000Z','updatedAt'=>'2026-10-17T00:00:00.000Z',
    'startAt'=>null,'endAt'=>null,'assigneeAccountIds'=>[],
    'phaseId'=>null,'estimateMinutes'=>null,'availabilityMinutes'=>null,'availabilityPeriod'=>null,
    'timer'=>['elapsedSeconds'=>0,'runningSince'=>null,'runId'=>null],
    'assigneePersonId'=>null,'subjectPersonIds'=>[],
    'unknownExtension'=>['nested'=>[1,true,null,'Čebelica',0.1,-0.0]],
],JSON_THROW_ON_ERROR|JSON_UNESCAPED_UNICODE);
if (getenv('JIVIE_CAPTURE_TEST_LARGE_RECORD') === '1') {
    $large = json_decode($payload,true,128,JSON_THROW_ON_ERROR);
    $large['unknownExtension']['largePreservedField'] = str_repeat('Z',110000);
    $payload = json_encode($large,JSON_THROW_ON_ERROR|JSON_UNESCAPED_UNICODE);
}
seedMigrationSql('INSERT INTO familyhub_records(scope_id,id,type,revision,deleted,payload,sequence,updated_at,contract_version) VALUES(?,?,?,50,0,?,50,?,6)',[$scope,$task,'task',$payload,gmdate('c')]);
seedMigrationSql('INSERT INTO familyhub_records(scope_id,id,type,revision,deleted,payload,sequence,updated_at,contract_version) VALUES(?,?,?,7,1,NULL,51,?,6)',[$scope,$deleted,'task',gmdate('c')]);
$extraRecords=(int)(getenv('JIVIE_CAPTURE_TEST_EXTRA_RECORDS')?:0);
if($extraRecords<0||$extraRecords>1100)throw new RuntimeException('Synthetic capacity bound');
$extraSampleId=null;$extraSamplePayload=null;
for($n=0;$n<$extraRecords;$n++){
    $extraSampleId=seedMigrationId();
    $extraSamplePayload=json_encode(['title'=>'PRIVATE_SYNTHETIC_LIST_'.$n,'createdAt'=>'2026-10-17T00:00:00.000Z','updatedAt'=>'2026-10-17T00:00:00.000Z','future'=>['number'=>0.1,'ordinal'=>$n]],JSON_THROW_ON_ERROR);
    seedMigrationSql('INSERT INTO familyhub_records(scope_id,id,type,revision,deleted,payload,sequence,updated_at,contract_version) VALUES(?,?,?,3,0,?,?,?,6)',[$scope,$extraSampleId,'shoppingList',$extraSamplePayload,52+$n,gmdate('c')]);
}
if($extraRecords)seedMigrationSql('UPDATE familyhub_scopes SET sequence=? WHERE id=?',[51+$extraRecords,$scope]);
seedMigrationSql('INSERT INTO familyhub_operations VALUES(?,?,?,?,?,200)',[$scope,$uid,$receipt,str_repeat('a',64),'{"status":"accepted-before-lost-ack"}']);
$date='2026-10-17T00:00:00.000Z';
$legacyTaskMismatch = getenv('JIVIE_CAPTURE_TEST_MISMATCH') === '1';
$planned = $legacyTaskMismatch ? '2026-10-16T00:00:00.000Z' : $date;
$accountPayload=json_encode(['createdAt'=>$date,'updatedAt'=>$date,'name'=>'PRIVATE_CAPTURED_LEDGER','currency'=>'EUR',
    'openingBalanceMinor'=>7000,'openingBalanceAt'=>null,'archived'=>false,'ownerAccountId'=>null],JSON_THROW_ON_ERROR);
$entryPayload=json_encode(['createdAt'=>$date,'updatedAt'=>$date,'accountId'=>$ledger,'accountScopeId'=>null,'projectId'=>null,
    'kind'=>'expense','status'=>'posted','plannedAt'=>$planned,'paidAt'=>$date,'taskId'=>$task,'ledgerAccountId'=>null,
    'payerPersonId'=>null,'recipientPersonId'=>null,'createdByPersonId'=>null,'recurrenceRuleId'=>null,'occurrenceKey'=>null,
    'amountMinor'=>12345,'currency'=>'EUR','title'=>'PRIVATE_ALREADY_POSTED_COST','notes'=>'','category'=>'',
    'payerAccountId'=>null,'recipientAccountId'=>null,'occurredAt'=>$date,
    'unknownExtension'=>['captured'=>[0.1,'exact']]],JSON_THROW_ON_ERROR);
foreach ([[$ledger,'financeAccount',12,$accountPayload,1],[$expense,'financeEntry',31,$entryPayload,2]] as [$id,$type,$revision,$raw,$sequence]) {
    seedMigrationSql('INSERT INTO familyhub_finance_records(scope_id,id,type,revision,deleted,payload,sequence,updated_at,created_by,updated_by,contract_version) VALUES(?,?,?,?,0,?,?,?,?,?,3)',
        [$scope,$id,$type,$revision,$raw,$sequence,$date,$account,$account]);
}
$auditFixture = getenv('JIVIE_CAPTURE_TEST_AUDIT') === '1';
if ($auditFixture) {
    seedMigrationSql('INSERT INTO familyhub_finance_audit(scope_id,record_id,revision,actor_account_id,changed_at,before_json,after_json,op_id) VALUES(?,?,?,?,?,?,?,?)',
        [$scope,$expense,31,$account,'2020-01-02T03:04:05.123+01:00','{"unknown":{"fraction":0.1,"negativeZero":-0.0}}',$entryPayload,seedMigrationId()]);
}
$bytes=str_repeat('COLD_FILE_SENTINEL_',70000);$sha=hash('sha256',$bytes);
seedMigrationSql('INSERT INTO familyhub_attachments(scope_id,id,target_type,target_id,name,mime,size,sha256,owner_account_id,owner_device_id,received,complete,deleted,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,1,0,?,?)',[$scope,$attachment,'scope',$scope,'PRIVATE_ATTACHMENT.pdf','application/pdf',strlen($bytes),$sha,$account,$session['device']['id'],strlen($bytes),time(),time()]);
$root=DATA_DIR.'/familyhub/attachments';if(!is_dir($root))mkdir($root,0700,true);
file_put_contents($root.'/'.hash('sha256',$scope.':'.$attachment),$bytes);
$ideaFixture=getenv('JIVIE_CAPTURE_TEST_IDEA')==='1';$ideaBoard=null;$ideaSha=null;$ideaBytes=null;$orphan=null;$orphanDraft=null;
if($ideaFixture){
    $ideaBoard=seedMigrationId();$orphan=seedMigrationId();
    $pngChunk=static fn($type,$data)=>pack('N',strlen($data)).$type.$data.pack('N',crc32($type.$data));
    $ideaBytes="\x89PNG\r\n\x1a\n".$pngChunk('IHDR',pack('NNCCCCC',1,1,8,2,0,0,0)).$pngChunk('IDAT',gzcompress("\0\x20\x80\xc0")).$pngChunk('IEND','');$ideaSha=hash('sha256',$ideaBytes);
    $asset=['sha256'=>$ideaSha,'mime'=>'image/png','size'=>strlen($ideaBytes),'width'=>1,'height'=>1];
    $element=static fn($x)=>['id'=>seedMigrationId(),'kind'=>'image','x'=>$x,'y'=>1,'width'=>10,'height'=>10,'rotation'=>0,'color'=>4280693304,'strokeWidth'=>3,'text'=>'','points'=>[],'parentImageId'=>null,'asset'=>$asset];
    $board=['version'=>1,'id'=>$ideaBoard,'title'=>'PRIVATE_IMAGE_BOARD','projectId'=>null,'width'=>1600,'height'=>1200,'elements'=>[$element(0),$element(20)],'revision'=>8,'createdAt'=>$date,'updatedAt'=>$date,'future'=>['fraction'=>0.1]];
    seedMigrationSql('INSERT INTO familyhub_records(scope_id,id,type,revision,deleted,payload,sequence,updated_at,contract_version) VALUES(?,?,?,8,0,?,53,?,6)',[$scope,$ideaBoard,'idea',json_encode($board,JSON_THROW_ON_ERROR),$date]);
    $orphanDraft=$board;$orphanDraft['id']=$orphan;$orphanDraft['title']='PRIVATE_UNSAVED_ORPHAN_DRAFT';$orphanDraft['revision']=0;
    foreach([[$ideaBoard,1],[$orphan,0]] as [$bid,$published]){
        seedMigrationSql('INSERT INTO familyhub_idea_assets(scope_id,board_id,sha256,owner_account_id,mime,size,width,height,received,complete,published,data,created_at,updated_at) VALUES(?,?,?,?,?,?,1,1,?,1,?,NULL,?,?)',[$scope,$bid,$ideaSha,$account,'image/png',strlen($ideaBytes),strlen($ideaBytes),$published,time(),time()]);
        $dir=DATA_DIR.'/familyhub/ideas/'.hash('sha256',$scope.':'.$bid);if(!is_dir($dir))mkdir($dir,0700,true);file_put_contents($dir.'/'.$ideaSha,$ideaBytes);
    }
}
$combinedChoices = getenv('JIVIE_CAPTURE_TEST_CHOICES') === '1';
$parentOwner = null; $childScope = null; $childEntry = null; $childEntryPayload = null;
$sourceActorAccountId = $account;
if ($combinedChoices) {
    if (getenv('JIVIE_CAPTURE_TEST_SHARED') === '1' || getenv('JIVIE_CAPTURE_TEST_INBOX_STATE') === '1') {
        throw new RuntimeException('Combined representative has its own exact two-role fixture');
    }
    $parentOwner = ['session'=>$session,'username'=>$username,'password'=>$password];
    // Existing owner manages both content scopes and the child ledger, but has
    // NONE on the parent ledger. The sole parent READ materializer is not a
    // child member: the handoff must contain only the sanitized selection.
    do { $childScope = seedMigrationId(); } while (strcmp($childScope,$scope)<=0);
    $childEntry = seedMigrationId();
    seedMigrationSql('INSERT INTO familyhub_scopes(id,kind,name,owner_id,parent_scope_id,sequence,created_at,access_policy_version) VALUES(?,?,?,?,?,7,?,1)',
        [$childScope,'project','SYNTHETIC_SPLIT_ROLE_PROJECT',$uid,$scope,time()]);
    seedMigrationSql('INSERT INTO familyhub_members VALUES(?,?,?,?,1)',[$childScope,$uid,$account,'owner']);
    seedMigrationSql('INSERT INTO familyhub_finance_policy(scope_id,enabled,revision,sequence,required_contract_version) VALUES(?,1,4,7,3)',[$childScope]);
    seedMigrationSql('INSERT INTO familyhub_finance_grants VALUES(?,?,?)',[$childScope,$account,'write']);
    $childRaw = json_decode($entryPayload,true,128,JSON_THROW_ON_ERROR);
    $childRaw['accountScopeId']=$scope; $childRaw['taskId']=null;
    $childRaw['amountMinor']=200; $childRaw['title']='PRIVATE_CHILD_LINKED_COST';
    $childEntryPayload=json_encode($childRaw,JSON_THROW_ON_ERROR|JSON_UNESCAPED_UNICODE);
    seedMigrationSql('INSERT INTO familyhub_finance_records(scope_id,id,type,revision,deleted,payload,sequence,updated_at,created_by,updated_by,contract_version) VALUES(?,?,?,5,0,?,7,?,?,?,3)',
        [$childScope,$childEntry,'financeEntry',$childEntryPayload,$date,$account,$account]);
    $username='capture_issuer_'.bin2hex(random_bytes(10)); $password=bin2hex(random_bytes(20));
    $container['userModel']->create(['username'=>$username,'password'=>$password,'role'=>'app-user']);
    $session=$api->dispatch('auth.login',['username'=>$username,'password'=>$password,'deviceName'=>'Synthetic split-role issuer'],'',$username);
    $reader=$session['user']['accountId']; $readerUser=$session['user']['id'];
    seedMigrationSql('INSERT INTO familyhub_email_identities(account_id,email,verified_at,revision) VALUES(?,?,?,1)',[$reader,$username.'@capture.invalid',time()]);
    $api->dispatch('moderation.acceptPolicy',['policyVersion'=>1],'Bearer '.$session['token'],$username);
    seedMigrationSql('INSERT INTO familyhub_members VALUES(?,?,?,?,1)',[$scope,$readerUser,$reader,'member']);
    seedMigrationSql('UPDATE familyhub_finance_grants SET access_level=? WHERE scope_id=? AND account_id=?',['none',$scope,$account]);
    seedMigrationSql('INSERT INTO familyhub_finance_grants VALUES(?,?,?)',[$scope,$reader,'read']);
    $receipt=seedMigrationId();
    seedMigrationSql('INSERT INTO familyhub_operations VALUES(?,?,?,?,?,200)',[$scope,$readerUser,$receipt,str_repeat('a',64),'{"status":"accepted-own-split-role-before-lost-ack"}']);
}
$sharedReadContributor = getenv('JIVIE_CAPTURE_TEST_SHARED') === '1';
if ($sharedReadContributor) {
    // Nonowner source capture: the owner has NONE, this member has READ only.
    // Its private original receipt is not an owner content contribution.
    $username = 'capture_reader_'.bin2hex(random_bytes(10));
    $password = bin2hex(random_bytes(20));
    $container['userModel']->create(['username' => $username, 'password' => $password, 'role' => 'app-user']);
    $session = $api->dispatch('auth.login', ['username' => $username, 'password' => $password,
        'deviceName' => 'Synthetic nonowner capture'], '', $username);
    $reader = $session['user']['accountId'];
    $readerUser = $session['user']['id'];
    seedMigrationSql('INSERT INTO familyhub_email_identities(account_id,email,verified_at,revision) VALUES(?,?,?,1)',
        [$reader, $username.'@capture.invalid', time()]);
    $api->dispatch('moderation.acceptPolicy', ['policyVersion' => 1], 'Bearer '.$session['token'], $username);
    seedMigrationSql('INSERT INTO familyhub_members VALUES(?,?,?,?,1)', [$scope, $readerUser, $reader, 'editor']);
    seedMigrationSql('UPDATE familyhub_finance_grants SET access_level=? WHERE scope_id=? AND account_id=?', ['none', $scope, $account]);
    seedMigrationSql('INSERT INTO familyhub_finance_grants VALUES(?,?,?)', [$scope, $reader, 'read']);
    $receipt = seedMigrationId();
    seedMigrationSql('INSERT INTO familyhub_operations VALUES(?,?,?,?,?,200)',
        [$scope, $readerUser, $receipt, str_repeat('a', 64), '{"status":"accepted-own-shared-before-lost-ack"}']);
}
$counterFixture = getenv('JIVIE_CAPTURE_TEST_INBOX_STATE') === '1';
$otherInboxId = null;
if ($counterFixture) {
    if ($sharedReadContributor) throw new RuntimeException('counter fixture requires independent owner scope');
    $outside=seedMigrationId();
    seedMigrationSql('INSERT INTO familyhub_scopes(id,kind,name,owner_id,sequence,created_at,access_policy_version) VALUES(?,?,?,?,0,?,1)',[$outside,'household','UNRELATED_COUNTER_SCOPE',$uid,time()]);
    seedMigrationSql('INSERT INTO familyhub_members VALUES(?,?,?,?,1)',[$outside,$uid,$account,'owner']);
    seedMigrationSql('INSERT INTO familyhub_inbox_state(account_id,sequence,visibility_revision) VALUES(?,17,4)',[$account]);
    $eventKey=bin2hex(random_bytes(32));
    seedMigrationSql('INSERT INTO familyhub_inbox(event_key,recipient_account_id,scope_id,category,kind,audience,actor_account_id,target_type,target_id,target_revision,group_key,created_at,sequence,in_app) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,17,1)',
        [$eventKey,$account,$outside,'tasks','task.created','scope',$account,'task',seedMigrationId(),1,$outside.':test',gmdate('Y-m-d\TH:i:s\Z')]);
    $q=$pdo->prepare('SELECT id FROM familyhub_inbox WHERE event_key=? AND recipient_account_id=?');$q->execute([$eventKey,$account]);$otherInboxId=(int)$q->fetchColumn();$q->closeCursor();
}
echo json_encode(['synthetic'=>true,'serverUrl'=>'http://127.0.0.1:18785','session'=>$session,'username'=>$username,'password'=>$password,
    'ideaFixture'=>$ideaFixture,'ideaBoardId'=>$ideaBoard,'ideaSha256'=>$ideaSha,'ideaBytes'=>$ideaBytes===null?null:strlen($ideaBytes),'ideaDataBase64'=>$ideaBytes===null?null:base64_encode($ideaBytes),'orphanIdeaBoardId'=>$orphan,'orphanIdeaDraft'=>$orphanDraft,
    'auditFixture'=>$auditFixture,'counterFixture'=>$counterFixture,'otherInboxId'=>$otherInboxId,
    'combinedChoiceFixture'=>$combinedChoices,'parentOwner'=>$parentOwner,'sourceActorAccountId'=>$sourceActorAccountId,
    'childScopeId'=>$childScope,'childEntryId'=>$childEntry,'childEntryPayload'=>$childEntryPayload,
    'sharedReadContributor' => $sharedReadContributor,'legacyTaskMismatch'=>$legacyTaskMismatch,
    'scopeId'=>$scope,'taskId'=>$task,'deletedId'=>$deleted,'legacyId'=>$receipt,'payload'=>$payload,
    'ledgerId'=>$ledger,'expenseId'=>$expense,'accountPayload'=>$accountPayload,'entryPayload'=>$entryPayload,
    'attachmentId'=>$attachment,'fileBytes'=>strlen($bytes),'fileSha256'=>$sha,
    'extraRecords'=>$extraRecords,'extraSampleId'=>$extraSampleId,'extraSamplePayload'=>$extraSamplePayload],JSON_THROW_ON_ERROR).PHP_EOL;
