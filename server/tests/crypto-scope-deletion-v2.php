<?php
/** Synthetic signed graph deletion, atomic companion, retained scoped witness. */
require __DIR__.'/crypto2-invitation-integration.php';
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoScopeDeletionCodecV2 as Deletion;
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoCodec;
function deletionSign($value,$domain,$key){$bytes=NativeCryptoCodec::canonical((object)$value);return ['commandBase64'=>base64_encode($bytes),'signatureBase64'=>base64_encode(sodium_crypto_sign_detached($domain.$bytes,$key['sign']))];}
function deletionCommand($op,$payload,$request,$u,$key){$c=['version'=>2,'operation'=>$op,'requestId'=>$request,'serverId'=>$u['serverId'],'accountId'=>$u['user']['accountId'],'deviceId'=>$u['device']['id'],'signer'=>'device','payload'=>$payload];return deletionSign($c,"JivieE2EE/v2\n",$key);}
$hidden=uid();q('INSERT INTO familyhub_scopes(id,kind,name,owner_id,sequence,created_at,access_policy_version,parent_scope_id) VALUES(?,?,?,?,0,?,3,?)',[$hidden,'project','Must not disclose hidden counts',$recipient['user']['id'],time(),$shared['id']]);
$blocked=call('crypto2.scope.deletionPreview',['scopeId'=>$shared['id']],$fresh);
ck(!$blocked['canDelete']&&$blocked['incomplete']&&$blocked['scopeContexts']===[]&&$blocked['graphRoot']===null&&$blocked['graphCount']===0&&array_sum($blocked['counts'])===0,'foreign child blocks before hidden head/record/blob discovery and returns redacted incomplete preview');
q('DELETE FROM familyhub_scopes WHERE id=?',[$hidden]);
$legacyAttachment=uid();$legacyTable=uid();$legacyBoard=uid();$legacySha=hash('sha256','synthetic legacy asset');
q('INSERT INTO familyhub_tables(scope_id,id,title,cells,revision,updated_at,created_by) VALUES(?,?,?,?,1,?,?)',[$shared['id'],$legacyTable,'Legacy table plaintext','{}',time(),$fresh['user']['accountId']]);
q('INSERT INTO familyhub_attachments(scope_id,id,target_type,target_id,name,mime,size,sha256,owner_account_id,owner_device_id,received,complete,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?,?,1,1,?,?)',[$shared['id'],$legacyAttachment,'scope',$shared['id'],'Legacy filename.txt','text/plain',1,hash('sha256','x'),$fresh['user']['accountId'],$fresh['device']['id'],time(),time()]);
q('INSERT INTO familyhub_attachment_chunks VALUES(?,?,0,?)',[$shared['id'],$legacyAttachment,'x']);
q('INSERT INTO familyhub_idea_assets(scope_id,board_id,sha256,owner_account_id,mime,size,width,height,received,complete,published,data,created_at,updated_at) VALUES(?,?,?,?,?,1,1,1,1,1,1,?,?,?)',[$shared['id'],$legacyBoard,$legacySha,$fresh['user']['accountId'],'image/png','legacy bytes',time(),time()]);
q('INSERT INTO familyhub_payment_cash VALUES(?,?,?)',[$shared['id'],uid(),'{"legacy":"plaintext cash"}']);
$sourceBinding=uid();q('INSERT INTO familyhub_crypto_capture_sources_v3(migration_id,account_id,binding_id,scope_id,domain,source_table,source_id,source_commitment,authorization,private_baseline) VALUES(?,?,?,?,?,?,?,?,?,?)',[uid(),$fresh['user']['accountId'],$sourceBinding,$shared['id'],'content','familyhub_records','row:0',hash('sha256','opaque synthetic binding'),'{}','retained pre-cutover source sentinel']);
$preview=call('crypto2.scope.deletionPreview',['scopeId'=>$shared['id']],$fresh);
ck($preview['canDelete']&&$preview['graphCount']===1,'current manager can review exact bounded graph');
$request=uid();$current=call('crypto2.account.status',[],$fresh);
$c=['version'=>2,'serverId'=>$fresh['serverId'],'rootScopeId'=>$shared['id'],'requestId'=>$request,'actorAccountId'=>$fresh['user']['accountId'],'actorDeviceId'=>$fresh['device']['id'],'scopes'=>$preview['scopeContexts'],'graphRoot'=>$preview['graphRoot'],'graphCount'=>$preview['graphCount'],'retention'=>Deletion::retention()];
$cp=deletionSign($c,Deletion::CERTIFICATE,$freshKeys);
$h=['version'=>2,'serverId'=>$fresh['serverId'],'requestId'=>$request,'actorAccountId'=>$fresh['user']['accountId'],'actorDeviceId'=>$fresh['device']['id'],'authorDirectoryHeadHash'=>$current['headHash'],'privateCertificateHash'=>h2($cp),'rootToken'=>Deletion::rootToken($c),'graphRoot'=>$c['graphRoot'],'graphCount'=>$c['graphCount'],'retention'=>Deletion::retention(),'scopeLeafRoot'=>str_repeat('0',64),'scopeLeafCount'=>$c['graphCount']];
$context=Deletion::headerContext($h);$leaves=[];$digests=[];
foreach($c['scopes'] as $d){$leaf=['version'=>2,'serverId'=>$fresh['serverId'],'requestId'=>$request,'headerContextHash'=>$context]+$d;$proof=deletionSign($leaf,Deletion::LEAF,$freshKeys);$leaves[]=$proof;$digests[]=h2($proof);}
sort($digests,SORT_STRING);$h['scopeLeafRoot']=Deletion::leafRoot($h,$digests);$hp=deletionSign($h,Deletion::HEADER,$freshKeys);
$event=request2('crypto2.account.scopeDeletion',['scopeToken'=>$h['rootToken'],'certificateHash'=>h2($hp)],$fresh,$freshKeys,$current['snapshot'],$current);
[$ec]=NativeCryptoCodec::decode($event);$ec['requestId']=$request;$event=deletionSign($ec,"JivieE2EE/v2\n",$freshKeys);
$payload=['certificateProof'=>$cp,'headerProof'=>$hp,'scopeProofs'=>$leaves,'accountEventProof'=>$event,'authorDirectoryHeadHash'=>$current['headHash']];$outer=deletionCommand('crypto2.scope.delete',$payload,$request,$fresh,$freshKeys);
deny(fn()=>call('crypto2.account.scopeDeletion',$event,$fresh),'crypto_companion_only','scope deletion event cannot be independently accepted');
$wrong=$payload;$wrong['scopeProofs']=[];deny(fn()=>call('crypto2.scope.delete',deletionCommand('crypto2.scope.delete',$wrong,uid(),$fresh,$freshKeys),$fresh),'crypto_scope_deletion_context','request context substitution cannot delete or append event');
ck(call('crypto2.account.status',[],$fresh)['headHash']===$current['headHash'],'invalid graph leaves own prefix unchanged');
// Exact head/revision CAS inside the transaction, followed by complete rollback.
q('UPDATE familyhub_scopes SET access_revision=access_revision+1 WHERE id=?',[$shared['id']]);
deny(fn()=>call('crypto2.scope.delete',$outer,$fresh),'scope_deletion_preview_changed','stale reviewed scope revision cannot delete');
q('UPDATE familyhub_scopes SET access_revision=access_revision-1 WHERE id=?',[$shared['id']]);
// Rejected immutable outer cannot be reused as a fresh action. A reviewed new
// request is necessary; recreate only the request context, not any business ID.
$new=uid();$c['requestId']=$new;$cp=deletionSign($c,Deletion::CERTIFICATE,$freshKeys);$h['requestId']=$new;$h['privateCertificateHash']=h2($cp);$h['rootToken']=Deletion::rootToken($c);$h['scopeLeafRoot']=str_repeat('0',64);$context=Deletion::headerContext($h);$leaves=[];$digests=[];foreach($c['scopes'] as $d){$proof=deletionSign(['version'=>2,'serverId'=>$fresh['serverId'],'requestId'=>$new,'headerContextHash'=>$context]+$d,Deletion::LEAF,$freshKeys);$leaves[]=$proof;$digests[]=h2($proof);}sort($digests,SORT_STRING);$h['scopeLeafRoot']=Deletion::leafRoot($h,$digests);$hp=deletionSign($h,Deletion::HEADER,$freshKeys);$ec['requestId']=$new;$ec['payload']['scopeToken']=$h['rootToken'];$ec['payload']['certificateHash']=h2($hp);$event=deletionSign($ec,"JivieE2EE/v2\n",$freshKeys);$payload=['certificateProof'=>$cp,'headerProof'=>$hp,'scopeProofs'=>$leaves,'accountEventProof'=>$event,'authorDirectoryHeadHash'=>$current['headHash']];$outer=deletionCommand('crypto2.scope.delete',$payload,$new,$fresh,$freshKeys);
if($pdo->getAttribute(PDO::ATTR_DRIVER_NAME)==='sqlite'){
 q("CREATE TRIGGER scope_deletion_rollback BEFORE DELETE ON familyhub_members BEGIN SELECT RAISE(ABORT,'synthetic'); END");
 try{call('crypto2.scope.delete',$outer,$fresh);ck(false,'failure injected');}catch(PDOException $e){ck(true,'partial active cleanup failure rolls back deletion event and scope');}
 q('DROP TRIGGER scope_deletion_rollback');
 ck(call('crypto2.account.status',[],$fresh)['headHash']===$current['headHash']&&q('SELECT scope_id FROM familyhub_crypto_scope_deletions_v2 WHERE scope_id=?',[$shared['id']])===[],'failed cleanup leaves no retained-witness success row or account event');
}
$result=call('crypto2.scope.delete',$outer,$fresh);
ck($result['cleanupPending']&&$result['legacyCleanupPending'],'physical cleanup and retained legacy source material are reported separately');
ck(q('SELECT data FROM familyhub_attachment_chunks WHERE scope_id=?',[$shared['id']])===[]&&q('SELECT data FROM familyhub_payment_cash WHERE scope_id=?',[$shared['id']])===[]&&q('SELECT data FROM familyhub_idea_assets WHERE scope_id=?',[$shared['id']])===[],'active legacy chunks, assets and payment payload rows are removed');
ck(q('SELECT name FROM familyhub_attachments WHERE scope_id=?',[$shared['id']])[0]['name']===''&&q('SELECT title FROM familyhub_tables WHERE scope_id=?',[$shared['id']])[0]['title']==='','legacy document routing tombstones retain no filenames or cells');
ck(q('SELECT private_baseline FROM familyhub_crypto_capture_sources_v3 WHERE binding_id=?',[$sourceBinding])[0]['private_baseline']==='retained pre-cutover source sentinel','frozen source bytes remain exact with explicit non-encrypted retention disclosure');
ck($result['deleted']&&$result['eventHeadHash']===call('crypto2.account.status',[],$fresh)['headHash'],'scope deletion and own event commit atomically');
ck(call('crypto2.scope.delete',$outer,$fresh)===$result,'lost deletion ACK returns exact immutable original after active scope removal');
$status=call('crypto2.scope.deletionStatus',['scopeId'=>$shared['id']],$recipient);
ck(!isset($status['rootScopeId'])&&!isset($status['privateCertificateProof'])&&!isset($status['deletedScopeIds'])&&$status['membershipHead']['headHash']===$head2['headHash'],'former member receives own scoped leaf without private graph or sibling IDs');
[$leaf]=NativeCryptoCodec::decode($status['leafProof']);ck($leaf['scopeId']===$shared['id']&&Deletion::leafRoot($h,$status['leafDigests'])===$h['scopeLeafRoot'],'own signed leaf is included in complete ordered opaque stream');
$retainedPrefix=call('crypto2.scope.deletionDirectory',['scopeId'=>$shared['id'],'accountId'=>$fresh['user']['accountId'],'directoryHeadHash'=>$status['eventHeadHash'],'limit'=>20],$recipient);
ck($retainedPrefix['headHash']===$status['eventHeadHash']&&count($retainedPrefix['entries'])>0,'former member can verify only exact deleting actor inclusion prefix');
deny(fn()=>call('crypto2.scope.deletionDirectory',['scopeId'=>$shared['id'],'accountId'=>$fresh['user']['accountId'],'directoryHeadHash'=>str_repeat('f',64),'limit'=>20],$recipient),'permission_revoked','retained directory never grants arbitrary account tail');
echo "Signed scope deletion total $checks\n";
