<?php
/** Synthetic PDO/ACL/typed-export tests. Never run against hosted user data. */
umask(0077);
require '/var/www/app/app/common.php';
if (session_status() === PHP_SESSION_ACTIVE) { session_abort(); }
if (!defined('FAMILYHUB_DEVELOPMENT_MODE') || FAMILYHUB_DEVELOPMENT_MODE !== true) {
    throw new RuntimeException('Synthetic only');
}
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoMigrationV2;
use Kanboard\Plugin\FamilyHub\Model\NativeService;
use Kanboard\Plugin\FamilyHub\Model\NativeError;
use Kanboard\Plugin\FamilyHub\Schema\CryptoSchema;

// Production signature/replay validation belongs to NativeCryptoV2Service;
// this fixture exposes only its inherited authenticated transaction boundary.
class MigrationFixtureV2 extends NativeCryptoMigrationV2
{
    public function invoke($operation, $params, $write = false)
    {
        return $this->transaction(function () use ($operation, $params, $write) {
            $actor = $this->actor();
            return $write ? $this->write($operation, $params, $actor, ['syntheticProof' => true])
                : $this->read($operation, $params, $actor);
        }, true);
    }
}
$pdo = $container['db']->getConnection();
CryptoSchema::create($pdo, $pdo->getAttribute(PDO::ATTR_DRIVER_NAME) === 'mysql');
$api = new NativeService($container);
$prefix = 'migration_'.bin2hex(random_bytes(6));
$checks = 0;
function checkMigration($condition, $label) {
    global $checks;
    if (!$condition) { throw new RuntimeException('FAIL: '.$label); }
    $checks++;
    echo 'PASS: '.$label.PHP_EOL;
}
function migrationQuery($sql, $params = []) {
    global $pdo;
    $statement = $pdo->prepare($sql); $statement->execute($params);
    $rows = $statement->fetchAll(PDO::FETCH_ASSOC); $statement->closeCursor();
    return $rows;
}
function migrationId() {
    $hex = bin2hex(random_bytes(16));
    return substr($hex,0,8).'-'.substr($hex,8,4).'-4'.substr($hex,13,3).'-a'.substr($hex,17,3).'-'.substr($hex,20);
}
function migrationUser($suffix) {
    global $container, $prefix, $api;
    $username = $prefix.'_'.$suffix; $password = bin2hex(random_bytes(20));
    $container['userModel']->create(['username'=>$username,'password'=>$password,'role'=>'app-user']);
    return $api->dispatch('auth.login',['username'=>$username,'password'=>$password,'deviceName'=>'Synthetic migration'], '', $prefix);
}
function migrationModel($user) {
    global $container, $prefix;
    return new MigrationFixtureV2($container, 'Bearer '.$user['token'], $prefix);
}
function migrationDenied($callback, $code, $label) {
    try { $callback(); $valid=false; }
    catch (NativeError $error) {
        $valid=$error->errorCode===$code;
        if (!$valid) { throw new RuntimeException($label.': expected '.$code.' got '.$error->errorCode); }
    }
    checkMigration($valid,$label);
}
$owner = migrationUser('owner');
$other = migrationUser('other');
$ownerId=$owner['user']['id']; $account=$owner['user']['accountId'];
$otherId=$other['user']['id']; $otherAccount=$other['user']['accountId'];
$numericProject=$container['projectModel']->create(['name'=>$prefix.'_kanboard','owner_id'=>$ownerId]);
checkMigration(is_int($numericProject)&&$numericProject>0,'separate numeric Kanboard project created for no-cross-touch regression');
$numericInvitation=bin2hex(random_bytes(16));
migrationQuery('INSERT INTO familyhub_project_invitations(id,project_id,creator_id,recipient_id,request_id,token_hash,created_at,expires_at) VALUES(?,?,?,?,?,?,?,?)',[$numericInvitation,$numericProject,$ownerId,$otherId,bin2hex(random_bytes(16)),hash('sha256',random_bytes(32)),time(),time()+3600]);
$numericInvitationBefore=migrationQuery('SELECT * FROM familyhub_project_invitations WHERE id=?',[$numericInvitation]);
$scope=migrationId(); $task=migrationId();
migrationQuery('INSERT INTO familyhub_scopes(id,kind,name,owner_id,sequence,created_at,access_policy_version) VALUES(?,?,?,?,1,?,1)',[$scope,'household','PRIVATE_MIGRATION_NAME',$ownerId,time()]);
migrationQuery('INSERT INTO familyhub_members(scope_id,user_id,account_id,role,active) VALUES(?,?,?,?,1)',[$scope,$ownerId,$account,'owner']);
migrationQuery('INSERT INTO familyhub_members(scope_id,user_id,account_id,role,active) VALUES(?,?,?,?,1)',[$scope,$otherId,$otherAccount,'member']);
migrationQuery('INSERT INTO familyhub_finance_policy(scope_id,enabled,revision,sequence) VALUES(?,0,0,0)',[$scope]);
migrationQuery('INSERT INTO familyhub_records(scope_id,id,type,revision,deleted,payload,sequence,updated_at,contract_version) VALUES(?,?,?,1,0,?,1,?,6)',[$scope,$task,'task','{"title":"PRIVATE_TASK","unknown":{"unicode":"Čebelica"}}',gmdate('c')]);
$legacy=migrationId();
migrationQuery('INSERT INTO familyhub_operations VALUES(?,?,?,?,?,200)',[$scope,$otherId,$legacy,str_repeat('a',64),'{"private":"OTHER_RECEIPT"}']);
$model=migrationModel($owner); $otherModel=migrationModel($other);
$found=$model->invoke('crypto2.migration.discover',['scopeId'=>$scope]);
checkMigration($found['ownedScopeIds']===[$scope]&&$found['pendingOwnerCount']===1,'opaque discovery retains historical actor contributor');
checkMigration(!str_contains(json_encode($found),'PRIVATE_')&&!str_contains(json_encode($found),$otherAccount),'discovery returns no private titles or contributor identities');
$prepared=$model->invoke('crypto2.migration.prepare',['componentId'=>$found['componentId'],'componentHash'=>$found['componentHash'],'scopeIds'=>[$scope]],true);
$mid=$prepared['migrationId'];
$own=$model->invoke('crypto2.migration.inventory',['migrationId'=>$mid]);
checkMigration($own['inventory']['tables']->{'familyhub_operations:private'}['rows']===0,'scope owner archive excludes other actor receipt');
checkMigration(!isset($own['inventory']['tables']->{'familyhub_project_invitations:private'}),'numeric Kanboard invitation never becomes native UUID component source');
$ownerFence=$model->invoke('crypto2.migration.fence',['migrationId'=>$mid,'inventoryHash'=>$own['inventoryHash']],true);
checkMigration($ownerFence['state']==='preparing','one owner cannot fence a whole foreign/private contribution');
migrationDenied(fn()=>$model->invoke('crypto2.migration.exportPage',['migrationId'=>$mid,'table'=>'familyhub_records','domain'=>'content','cursor'=>0,'limit'=>20]),'crypto_migration_not_fenced','raw export requires actual global fence');
$joined=$otherModel->invoke('crypto2.migration.prepare',['componentId'=>$found['componentId'],'componentHash'=>$found['componentHash'],'scopeIds'=>[]],true);
$otherInventory=$otherModel->invoke('crypto2.migration.inventory',['migrationId'=>$mid]);
$ready=$otherModel->invoke('crypto2.migration.fence',['migrationId'=>$mid,'inventoryHash'=>$otherInventory['inventoryHash']],true);
checkMigration($ready['state']==='fenced','all private contributors consent before global fence');
$page=$model->invoke('crypto2.migration.exportPage',['migrationId'=>$mid,'table'=>'familyhub_records','domain'=>'content','cursor'=>0,'limit'=>20]);
checkMigration(base64_decode($page['rows'][0]->payload['valueBase64'])==='{"title":"PRIVATE_TASK","unknown":{"unicode":"Čebelica"}}','typed raw export preserves exact unknown JSON bytes');
checkMigration($page['rows'][0]->revision['type']==='integer'||str_starts_with(strtolower($page['rows'][0]->revision['type']),'bigint'),'raw cells retain SQL type');
migrationDenied(fn()=>$otherModel->invoke('crypto2.migration.exportPage',['migrationId'=>$mid,'table'=>'familyhub_records','domain'=>'content','cursor'=>0,'limit'=>20]),'crypto_migration_export_forbidden','private contributor does not inherit owner content archive');
$lookup=$otherModel->invoke('crypto2.legacy.lookup',['scopeId'=>$scope,'legacyId'=>$legacy,'finance'=>false,'requestHash'=>str_repeat('a',64)]);
checkMigration($lookup['outcome']==='applied'&&$lookup['storedRequestHash']===str_repeat('a',64)&&!str_contains(json_encode($lookup),'OTHER_RECEIPT'),'old receipt exposes only actor-bound immutable hash/outcome');
// Retiring old plaintext response cannot turn an applied lost-ACK into absence.
migrationQuery('DELETE FROM familyhub_operations WHERE scope_id=? AND user_id=? AND id=?',[$scope,$otherId,$legacy]);
$retiredLookup=$otherModel->invoke('crypto2.legacy.lookup',['scopeId'=>$scope,'legacyId'=>$legacy,'finance'=>false,'requestHash'=>str_repeat('a',64)]);
checkMigration($retiredLookup['outcome']==='applied'&&$retiredLookup['status']===200,'retirement retains authoritative applied outcome after old plaintext receipt removal');
migrationDenied(fn()=>$otherModel->invoke('crypto2.legacy.reserveReplacement',['scopeId'=>$scope,'legacyId'=>$legacy,'finance'=>false,'requestHash'=>str_repeat('a',64),'replacementId'=>migrationId()],true),'crypto_legacy_outcome_unresolved','retired applied financial/content effect cannot receive replacement operation');
// Restore synthetic source for remaining unchanged-component assertions.
migrationQuery('INSERT INTO familyhub_operations VALUES(?,?,?,?,?,200)',[$scope,$otherId,$legacy,str_repeat('a',64),'{"private":"OTHER_RECEIPT"}']);
$missing=migrationId();
$lookup=$otherModel->invoke('crypto2.legacy.lookup',['scopeId'=>$scope,'legacyId'=>$missing,'finance'=>false]);
checkMigration($lookup['outcome']==='notApplied','absence becomes conclusive only after global write fence');
$replacement=migrationId();
$reserved=$otherModel->invoke('crypto2.legacy.reserveReplacement',['scopeId'=>$scope,'legacyId'=>$missing,'finance'=>false,'requestHash'=>str_repeat('b',64),'replacementId'=>$replacement],true);
checkMigration($reserved['outcome']==='reserved','unknown prior operation has one durable domain-specific replacement binding');
migrationDenied(fn()=>$otherModel->invoke('crypto2.legacy.reserveReplacement',['scopeId'=>$scope,'legacyId'=>$missing,'finance'=>false,'requestHash'=>str_repeat('b',64),'replacementId'=>migrationId()],true),'idempotency_mismatch','replacement cannot be regenerated after a lost ACK');
// Membership loss leaves the private receipt and pending contribution intact.
migrationQuery('UPDATE familyhub_members SET active=0 WHERE scope_id=? AND account_id=?',[$scope,$otherAccount]);
$status=$otherModel->invoke('crypto2.migration.status',['migrationId'=>$mid]);
checkMigration($status['ownState']==='unavailable'&&$status['scopeIds']===[],'revoked private contributor remains explicit pending without inaccessible scope IDs');
migrationDenied(fn()=>$otherModel->invoke('crypto2.migration.exportPage',['migrationId'=>$mid,'table'=>'familyhub_operations','domain'=>'private','cursor'=>0,'limit'=>20]),'crypto_migration_contributor_unavailable','revocation never grants private archive through owner authority');
checkMigration(count(migrationQuery('SELECT * FROM familyhub_operations WHERE scope_id=? AND id=?',[$scope,$legacy]))===1,'revoked historical raw receipt remains preserved');
// New component: finance audit/event history exists without a current expense.
$financial=migrationId(); $private=migrationId(); $event=migrationId();
foreach ([[$financial,'household',$ownerId,$account],[$private,'personal',$otherId,$otherAccount]] as $row) {
    migrationQuery('INSERT INTO familyhub_scopes(id,kind,name,owner_id,sequence,created_at,access_policy_version) VALUES(?,?,?,?,0,?,1)',[$row[0],$row[1],'SYNTHETIC_COMPONENT',$row[2],time()]);
    migrationQuery('INSERT INTO familyhub_members(scope_id,user_id,account_id,role,active) VALUES(?,?,?,?,1)',[$row[0],$row[2],$row[3],'owner']);
    migrationQuery('INSERT INTO familyhub_finance_policy(scope_id,enabled,revision,sequence) VALUES(?,1,1,0)',[$row[0]]);
}
migrationQuery('INSERT INTO familyhub_personal_scopes VALUES(?,?)',[$otherAccount,$private]);
migrationQuery('INSERT INTO familyhub_members(scope_id,user_id,account_id,role,active) VALUES(?,?,?,?,1)',[$financial,$otherId,$otherAccount,'member']);
migrationQuery('INSERT INTO familyhub_finance_grants VALUES(?,?,?)',[$financial,$otherAccount,'read']);
migrationQuery('INSERT INTO familyhub_finance_grants VALUES(?,?,?)',[$private,$otherAccount,'write']);
migrationQuery('INSERT INTO familyhub_finance_audit VALUES(?,?,1,?,?,NULL,?,?)',[$financial,migrationId(),$otherAccount,gmdate('c'),'{"amountMinor":100}',migrationId()]);
migrationQuery('INSERT INTO familyhub_payment_events VALUES(?,?,?,?,1,?)',[$financial,$event,migrationId(),$otherAccount,'{"payerAccountId":"'.$otherAccount.'","amountMinor":100}']);
$component=$model->invoke('crypto2.migration.discover',['scopeId'=>$financial]);
checkMigration($component['ownedScopeIds']===[$financial]&&$component['pendingOwnerCount']===1,'finance audit/event-only history retains separate authorized contributor');
checkMigration(!in_array($private,$component['visibleScopeIds'],true)&&!str_contains(json_encode($component),$private),'global component includes private payer without disclosing its ID');
$preparedFinance=$model->invoke('crypto2.migration.prepare',['componentId'=>$component['componentId'],'componentHash'=>$component['componentHash'],'scopeIds'=>[$financial]],true);
$financeInventory=$model->invoke('crypto2.migration.inventory',['migrationId'=>$preparedFinance['migrationId']]);
checkMigration(!isset($financeInventory['inventory']['tables']->{'familyhub_finance_audit:finance'}),'scope owner without finance permission receives no audit archive');
migrationDenied(fn()=>$model->invoke('crypto2.legacy.lookup',['scopeId'=>$financial,'legacyId'=>migrationId(),'finance'=>true]),'finance_forbidden','migration receipt helper does not bypass separate finance ACL');
// Receipt participation is independent of the one shared finance materializer.
// Both authorized readers can own immutable old operations without producing
// conflicting ciphertext for the same shared source row.
foreach (['write', 'none'] as $ownerFinanceGrant) {
    $sharedFinance=migrationId();
    migrationQuery('INSERT INTO familyhub_scopes(id,kind,name,owner_id,sequence,created_at,access_policy_version) VALUES(?,?,?,?,0,?,1)',[$sharedFinance,'household','MATERIALIZER_TEST',$ownerId,time()]);
    foreach ([[$ownerId,$account,'owner'],[$otherId,$otherAccount,'member']] as $member) {
        migrationQuery('INSERT INTO familyhub_members(scope_id,user_id,account_id,role,active) VALUES(?,?,?,?,1)',[$sharedFinance,...$member]);
    }
    migrationQuery('INSERT INTO familyhub_finance_policy(scope_id,enabled,revision,sequence) VALUES(?,1,1,0)',[$sharedFinance]);
    migrationQuery('INSERT INTO familyhub_finance_grants VALUES(?,?,?)',[$sharedFinance,$account,$ownerFinanceGrant]);
    migrationQuery('INSERT INTO familyhub_finance_grants VALUES(?,?,?)',[$sharedFinance,$otherAccount,'read']);
    migrationQuery('INSERT INTO familyhub_finance_audit VALUES(?,?,1,?,?,NULL,?,?)',[$sharedFinance,migrationId(),$otherAccount,gmdate('c'),'{"amountMinor":123}',migrationId()]);
    migrationQuery('INSERT INTO familyhub_finance_operations VALUES(?,?,?,?,?,200)',[$sharedFinance,$otherAccount,migrationId(),str_repeat('d',64),'{"old":"reader-finance-ack"}']);
    if ($ownerFinanceGrant==='write') {
        migrationQuery('INSERT INTO familyhub_finance_operations VALUES(?,?,?,?,?,200)',[$sharedFinance,$account,migrationId(),str_repeat('e',64),'{"old":"owner-finance-ack"}']);
    } else {
        migrationQuery('INSERT INTO familyhub_operations VALUES(?,?,?,?,?,200)',[$sharedFinance,$ownerId,migrationId(),str_repeat('f',64),'{"old":"owner-content-ack"}']);
    }
    $discovery=$model->invoke('crypto2.migration.discover',['scopeId'=>$sharedFinance]);
    $start=$model->invoke('crypto2.migration.prepare',['componentId'=>$discovery['componentId'],'componentHash'=>$discovery['componentHash'],'scopeIds'=>[$sharedFinance]],true);
    $otherModel->invoke('crypto2.migration.prepare',['componentId'=>$discovery['componentId'],'componentHash'=>$discovery['componentHash'],'scopeIds'=>[]],true);
    $ownerTables=$model->invoke('crypto2.migration.inventory',['migrationId'=>$start['migrationId']])['inventory']['tables'];
    $readerTables=$otherModel->invoke('crypto2.migration.inventory',['migrationId'=>$start['migrationId']])['inventory']['tables'];
    $ownerMaterializes=isset($ownerTables->{'familyhub_finance_audit:finance'});
    $readerMaterializes=isset($readerTables->{'familyhub_finance_audit:finance'});
    checkMigration(isset($ownerTables->{'familyhub_finance_policy:content'}) && $ownerTables->{'familyhub_finance_policy:content'}['rows']===1,'owner CONTENT captures exact enabled policy metadata even with finance NONE');
    checkMigration($ownerTables->{'familyhub_finance_grants:content'}['rows']===2,'owner CONTENT retains every finance ACL grant without ledger access');
    checkMigration(!isset($ownerTables->{'familyhub_finance_policy:finance'}) && !isset($readerTables->{'familyhub_finance_policy:finance'}) && !isset($readerTables->{'familyhub_finance_grants:finance'}),'ACL metadata is never duplicated into materializer finance selection');
    checkMigration($ownerMaterializes!==$readerMaterializes,'exactly one finance materializer despite independent receipt portions (owner '.$ownerFinanceGrant.')');
    checkMigration($ownerMaterializes===($ownerFinanceGrant==='write'),'eligible owner preferred, otherwise READ contributor materializes captured finance');
    checkMigration($readerTables->{'familyhub_finance_operations:private'}['rows']===1,'nonowner reader retains own exact finance receipt independently of materializer');
    checkMigration(!isset($readerTables->{'familyhub_records:content'}),'finance receipt reader receives no owner content archive');
    checkMigration(($ownerFinanceGrant==='write' ? $ownerTables->{'familyhub_finance_operations:private'}['rows'] : $ownerTables->{'familyhub_operations:private'}['rows'])===1,'owner private receipt coverage survives finance materializer assignment');
}
// Disabled finance still has an authorization baseline, including NONE grants.
$disabledScope=migrationId();
migrationQuery('INSERT INTO familyhub_scopes(id,kind,name,owner_id,sequence,created_at,access_policy_version) VALUES(?,?,?,?,0,?,1)',[$disabledScope,'household','DISABLED_POLICY_BASELINE',$ownerId,time()]);
migrationQuery('INSERT INTO familyhub_members(scope_id,user_id,account_id,role,active) VALUES(?,?,?,?,1)',[$disabledScope,$ownerId,$account,'owner']);
migrationQuery('INSERT INTO familyhub_finance_policy(scope_id,enabled,revision,sequence) VALUES(?,0,7,13)',[$disabledScope]);
migrationQuery('INSERT INTO familyhub_finance_grants VALUES(?,?,?)',[$disabledScope,$account,'none']);
$disabledDiscovery=$model->invoke('crypto2.migration.discover',['scopeId'=>$disabledScope]);
$disabledMigration=$model->invoke('crypto2.migration.prepare',['componentId'=>$disabledDiscovery['componentId'],'componentHash'=>$disabledDiscovery['componentHash'],'scopeIds'=>[$disabledScope]],true);
$disabledTables=$model->invoke('crypto2.migration.inventory',['migrationId'=>$disabledMigration['migrationId']])['inventory']['tables'];
checkMigration($disabledTables->{'familyhub_finance_policy:content'}['rows']===1 && $disabledTables->{'familyhub_finance_grants:content'}['rows']===1,'disabled revision7 policy and NONE grant remain owner-content captured');
checkMigration(!isset($disabledTables->{'familyhub_finance_records:finance'}),'disabled finance does not create ledger selection from ACL metadata');
// A formerly supported large source payload is paged by exact byte cells.
$largeScope=migrationId(); $largeRecord=migrationId();
migrationQuery('INSERT INTO familyhub_scopes(id,kind,name,owner_id,sequence,created_at,access_policy_version) VALUES(?,?,?,?,1,?,1)',[$largeScope,'household','LARGE_MIGRATION',$ownerId,time()]);
migrationQuery('INSERT INTO familyhub_members(scope_id,user_id,account_id,role,active) VALUES(?,?,?,?,1)',[$largeScope,$ownerId,$account,'owner']);
migrationQuery('INSERT INTO familyhub_finance_policy(scope_id,enabled,revision,sequence) VALUES(?,0,0,0)',[$largeScope]);
$largePayload=json_encode(['title'=>str_repeat('x',1048500),'unknown'=>'preserved'],JSON_THROW_ON_ERROR);
migrationQuery('INSERT INTO familyhub_records(scope_id,id,type,revision,deleted,payload,sequence,updated_at,contract_version) VALUES(?,?,?,1,0,?,1,?,6)',[$largeScope,$largeRecord,'idea',$largePayload,gmdate('c')]);
$largeDiscovery=$model->invoke('crypto2.migration.discover',['scopeId'=>$largeScope]);
$largePrepare=$model->invoke('crypto2.migration.prepare',['componentId'=>$largeDiscovery['componentId'],'componentHash'=>$largeDiscovery['componentHash'],'scopeIds'=>[$largeScope]],true);
$largeMid=$largePrepare['migrationId'];
$largeInventory=$model->invoke('crypto2.migration.inventory',['migrationId'=>$largeMid]);
$model->invoke('crypto2.migration.fence',['migrationId'=>$largeMid,'inventoryHash'=>$largeInventory['inventoryHash']],true);
$largePage=$model->invoke('crypto2.migration.exportPage',['migrationId'=>$largeMid,'table'=>'familyhub_records','domain'=>'content','cursor'=>0,'limit'=>20]);
checkMigration(isset($largePage['rows'][0]->payload['external'])&&strlen(json_encode($largePage))<32768,'large legacy row uses a bounded exact-byte cell reference');
$recovered=''; $offset=0;
do {
    $chunk=$model->invoke('crypto2.migration.exportCell',['migrationId'=>$largeMid,'table'=>'familyhub_records','domain'=>'content','cursor'=>0,'column'=>'payload','offset'=>$offset,'limit'=>196608]);
    $recovered.=base64_decode($chunk['dataBase64']); $offset=$chunk['nextOffset'];
} while ($offset<$chunk['size']);
checkMigration($recovered===$largePayload&&hash('sha256',$recovered)===$chunk['sha256'],'large raw source preserves exact bytes across resumable bounded chunks');
// Abort before any remote archive, then extend legacy history and fence again.
$aborted=$model->invoke('crypto2.migration.abort',['migrationId'=>$largeMid],true);
checkMigration($aborted['legacyPreserved']===true,'unpublished one-account abort preserves source and prior receipt index');
$newLegacy=migrationId();
for($n=0;$n<130;$n++) {
    $request=$n===129?$newLegacy:migrationId();
    migrationQuery('INSERT INTO familyhub_operations VALUES(?,?,?,?,?,200)',[$largeScope,$ownerId,$request,str_repeat('c',64),'{"status":"applied-after-abort"}']);
}
$retryDiscovery=$model->invoke('crypto2.migration.discover',['scopeId'=>$largeScope]);
$retryPrepared=$model->invoke('crypto2.migration.prepare',['componentId'=>$retryDiscovery['componentId'],'componentHash'=>$retryDiscovery['componentHash'],'scopeIds'=>[$largeScope]],true);
$largeMid=$retryPrepared['migrationId'];
$largeInventory=$model->invoke('crypto2.migration.inventory',['migrationId'=>$largeMid]);
$model->invoke('crypto2.migration.fence',['migrationId'=>$largeMid,'inventoryHash'=>$largeInventory['inventoryHash']],true);
$retryLookup=$model->invoke('crypto2.legacy.lookup',['scopeId'=>$largeScope,'legacyId'=>$newLegacy,'finance'=>false,'requestHash'=>str_repeat('c',64)]);
checkMigration($retryLookup['outcome']==='applied','new fence extends immutable receipt outcomes after abort and legitimate legacy writes');
$indexed=migrationQuery("SELECT COUNT(*) AS n FROM familyhub_crypto_legacy_index_v2 WHERE scope_id=? AND kind='records'",[$largeScope]);
checkMigration((int)$indexed[0]['n']===130,'bounded keyset receipt pages cross 128-row boundary without omissions');
// Private archive transport has resumable immutable chunks and a full hash gate.
$archive=migrationId(); $cipher=random_bytes(400123);
$description=base64_encode(NativeCryptoMigrationV2::inventoryCanonical((object)['version'=>2,'keyId'=>migrationId(),'cipherManifestHash'=>hash('sha256','ordered-segments'),'index'=>0]));
$begin=['migrationId'=>$largeMid,'id'=>$archive,'size'=>strlen($cipher),'sha256'=>hash('sha256',$cipher),'manifestBase64'=>$description];
$started=$model->invoke('crypto2.migration.archiveBegin',$begin,true);
checkMigration($started['received']===0&&!$started['complete'],'account-private ciphertext archive starts without claiming restore proof');
migrationDenied(fn()=>$model->invoke('crypto2.migration.archiveComplete',['migrationId'=>$largeMid,'id'=>$archive],true),'crypto_migration_archive_incomplete','incomplete archive cannot pass whole-cipher hash gate');
$first=base64_encode(substr($cipher,0,196608));
$model->invoke('crypto2.migration.archiveChunk',['migrationId'=>$largeMid,'id'=>$archive,'offset'=>0,'dataBase64'=>$first],true);
$replayed=$model->invoke('crypto2.migration.archiveChunk',['migrationId'=>$largeMid,'id'=>$archive,'offset'=>0,'dataBase64'=>$first],true);
checkMigration($replayed['received']===196608,'lost chunk ACK resumes without duplicating bytes');
migrationDenied(fn()=>$model->invoke('crypto2.migration.archiveChunk',['migrationId'=>$largeMid,'id'=>$archive,'offset'=>0,'dataBase64'=>base64_encode(str_repeat('x',196608))],true),'idempotency_mismatch','archive chunk offset cannot be rewritten');
for($offset=196608;$offset<strlen($cipher);$offset+=196608) {
    $model->invoke('crypto2.migration.archiveChunk',['migrationId'=>$largeMid,'id'=>$archive,'offset'=>$offset,'dataBase64'=>base64_encode(substr($cipher,$offset,196608))],true);
}
$complete=$model->invoke('crypto2.migration.archiveComplete',['migrationId'=>$largeMid,'id'=>$archive],true);
checkMigration($complete['complete']&&$complete['sha256']===hash('sha256',$cipher),'archive completion verifies every stored chunk and exact SHA256');
$download='';$offset=0;
do {
    $chunk=$model->invoke('crypto2.migration.archiveGet',['migrationId'=>$largeMid,'id'=>$archive,'offset'=>$offset]);
    $download.=base64_decode($chunk['dataBase64']);$offset=$chunk['nextOffset'];
} while($offset<$chunk['size']);
checkMigration($download===$cipher,'fresh archive downloader reassembles exact durable ciphertext');
migrationDenied(fn()=>$otherModel->invoke('crypto2.migration.archiveGet',['migrationId'=>$largeMid,'id'=>$archive,'offset'=>0]),'crypto_migration_missing','another account cannot obtain archive even with exact migration/blob IDs');
$quota=$begin;$quota['id']=migrationId();$quota['size']=23068672;
migrationDenied(fn()=>$model->invoke('crypto2.migration.archiveBegin',$quota,true),'crypto_migration_archive_quota','archive ID churn consumes source-derived total quota');
// Original plan §11.4: an unchanged prepublication source can reopen without
// deleting its uploaded archive or resetting any charged source quota.
$beforeArchive=migrationQuery('SELECT * FROM familyhub_crypto_migration_archives_v2 WHERE migration_id=?',[$largeMid]);
$beforeChunks=migrationQuery('SELECT * FROM familyhub_crypto_migration_archive_chunks_v2 WHERE migration_id=? ORDER BY chunk_offset',[$largeMid]);
migrationQuery('UPDATE familyhub_scopes SET sequence=sequence+1 WHERE id=?',[$largeScope]);
migrationDenied(fn()=>$model->invoke('crypto2.migration.abort',['migrationId'=>$largeMid],true),'crypto_migration_component_changed','changed authoritative generation cannot be reopened');
migrationQuery('UPDATE familyhub_scopes SET sequence=sequence-1 WHERE id=?',[$largeScope]);
$aborted=$model->invoke('crypto2.migration.abort',['migrationId'=>$largeMid],true);
checkMigration($aborted['state']==='aborted'&&$aborted['legacyPreserved']===true,'unchanged one-account generation safely reopens before final publication');
checkMigration(migrationQuery('SELECT * FROM familyhub_crypto_migration_archives_v2 WHERE migration_id=?',[$largeMid])===$beforeArchive&&migrationQuery('SELECT * FROM familyhub_crypto_migration_archive_chunks_v2 WHERE migration_id=? ORDER BY chunk_offset',[$largeMid])===$beforeChunks,'safe abort preserves every original archive row, ciphertext chunk and charged size');
checkMigration(migrationQuery('SELECT payload FROM familyhub_records WHERE scope_id=? AND id=?',[$largeScope,$largeRecord])[0]['payload']===$largePayload,'safe abort keeps exact large authoritative source');
// Restore membership for subsequent fixtures, then unknown schema fails closed.
migrationQuery('UPDATE familyhub_members SET active=1 WHERE scope_id=? AND account_id=?',[$scope,$otherAccount]);
migrationQuery('ALTER TABLE familyhub_records ADD COLUMN '.$prefix.'_unknown TEXT DEFAULT NULL');
try {
    migrationDenied(fn()=>$model->invoke('crypto2.migration.discover',['scopeId'=>$scope]),'crypto_migration_schema_unsupported','unknown source column blocks cutover without dropping it');
} finally {
    migrationQuery('ALTER TABLE familyhub_records DROP COLUMN '.$prefix.'_unknown');
}
checkMigration(migrationQuery('SELECT * FROM familyhub_project_invitations WHERE id=?',[$numericInvitation])===$numericInvitationBefore,'native capture/fence/archive/abort leaves numeric Kanboard invitation byte-exact');
echo 'Crypto2 migration integration: '.$checks.' checks PASS'.PHP_EOL;
