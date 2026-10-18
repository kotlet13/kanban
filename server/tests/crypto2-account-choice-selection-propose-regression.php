<?php
/** One native org/child complete-selection export regression on a fresh opt-in
 * SQLite fixture. Never run against a hosting, phone or manual QA database.
 */
umask(0077);
if (getenv('JIVIE_FRESH_SQLITE_ACCOUNT_CHOICE_REGRESSION')!=='1') throw new RuntimeException('Explicit fresh SQLite regression opt-in required');
$reproStage='bootstrap';
set_exception_handler(static function(Throwable $e) {
    global $reproStage,$pdo,$outCommand;
    $out=['result'=>'FAIL','stage'=>$reproStage,'exceptionClass'=>get_class($e),'file'=>basename($e->getFile()),'line'=>$e->getLine()];
    if ($e instanceof \Kanboard\Plugin\FamilyHub\Model\NativeError) $out['errorCode']=$e->errorCode;
    if (preg_match('/no such column: ([A-Za-z_][A-Za-z0-9_.]*)/',$e->getMessage(),$m)) $out['staticFailure']=['kind'=>'missing_column','column'=>$m[1]];
    $out['sourceTrace']=[];foreach($e->getTrace() as $f){if(isset($f['file'],$f['line']) && str_contains($f['file'],'/FamilyHub/')){$out['sourceTrace'][]=['file'=>basename($f['file']),'line'=>$f['line']];if(count($out['sourceTrace'])>=5)break;}}
    if ($reproStage==='real_dispatch_exports_propose' && isset($pdo,$outCommand)) {$query=$pdo->prepare('SELECT COUNT(*) FROM familyhub_crypto_receipts WHERE request_id=?');$query->execute([$outCommand['requestId']]);$out['proposalReceiptCount']=(int)$query->fetchColumn();$out['offerCount']=(int)$pdo->query('SELECT COUNT(*) FROM familyhub_crypto_export_offers_v2')->fetchColumn();}
    if (preg_match('/SQLSTATE\[([A-Z0-9]+)\]/',$e->getMessage(),$m)) $out['sqlState']=$m[1];
    if (preg_match('/Call to undefined method ([A-Za-z_\\\\][A-Za-z0-9_\\\\]*)::([A-Za-z_][A-Za-z0-9_]*)\(\)/',$e->getMessage(),$m)) $out['staticFailure']=['kind'=>'undefined_method','class'=>$m[1],'method'=>$m[2]];
    echo json_encode($out,JSON_THROW_ON_ERROR),PHP_EOL;exit(1);
});

require '/var/www/app/app/common.php';
if (session_status()===PHP_SESSION_ACTIVE) session_abort();
if (!defined('FAMILYHUB_DEVELOPMENT_MODE') || FAMILYHUB_DEVELOPMENT_MODE!==true) throw new RuntimeException('Synthetic only');
use Kanboard\Plugin\FamilyHub\Model\NativeService;
use Kanboard\Plugin\FamilyHub\Model\NativeError;
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoCodec;
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoV2Codec;
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoV2Service;
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoReservedRecordV2;
use Kanboard\Plugin\FamilyHub\Schema\CryptoSchema;
$pdo=$container['db']->getConnection();
if ($pdo->getAttribute(PDO::ATTR_DRIVER_NAME)!=='sqlite') throw new RuntimeException('Disposable SQLite only');
foreach (['familyhub_accounts','familyhub_scopes','familyhub_crypto_receipts'] as $table) {
    $exists=$pdo->prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?");$exists->execute([$table]);
    if ($exists->fetchColumn()!==false && (int)$pdo->query('SELECT COUNT(*) FROM '.$table)->fetchColumn()!==0) throw new RuntimeException('Fresh empty accounts/scopes/receipts required before crypto schema creation');
}
CryptoSchema::create($pdo,false);
if ((int)$pdo->query('SELECT count(*) FROM familyhub_crypto_receipts')->fetchColumn()!==0) throw new RuntimeException('Fresh isolated database required');
$api=new NativeService($container);$prefix='wrapped_receipt_'.bin2hex(random_bytes(6));$checks=0;
set_error_handler(static function($severity,$message,$file,$line) { throw new ErrorException($message,0,$severity,$file,$line); });
function ck($v,$label){global $checks;if(!$v){throw new RuntimeException('FAIL: '.$label);}$checks++;echo 'PASS: '.$label.PHP_EOL;}
function q($sql,$p=[]){global $pdo;$s=$pdo->prepare($sql);$s->execute($p);$r=$s->fetchAll(PDO::FETCH_ASSOC);$s->closeCursor();return $r;}
function uid(){$h=bin2hex(random_bytes(16));return substr($h,0,8).'-'.substr($h,8,4).'-4'.substr($h,13,3).'-a'.substr($h,17,3).'-'.substr($h,20);}
function deny($callback,$code,$label){try{$callback();$pass=false;}catch(NativeError $e){$pass=$e->errorCode===$code;if(!$pass){throw new RuntimeException($label.': expected '.$code.' got '.$e->errorCode);}}ck($pass,$label);}
function keys(){ $s=sodium_crypto_sign_keypair();$b=sodium_crypto_box_keypair();return ['sign'=>sodium_crypto_sign_secretkey($s),'signPublic'=>base64_encode(sodium_crypto_sign_publickey($s)),'boxPublic'=>base64_encode(sodium_crypto_box_publickey($b))];}
function user($suffix,$verified=true){global $container,$prefix;$password=bin2hex(random_bytes(20));$username=$prefix.'_'.$suffix;$container['userModel']->create(['username'=>$username,'password'=>$password,'role'=>'app-user']);$u=call('auth.login',['username'=>$username,'password'=>$password,'deviceName'=>'Crypto synthetic']);$u['username']=$username;$u['password']=$password;q('INSERT INTO familyhub_email_identities(account_id,email,verified_at,revision) VALUES(?,?,?,1)',[$u['user']['accountId'],$username.'@capture.invalid',$verified?time():null]);call('moderation.acceptPolicy',['policyVersion'=>1],$u);return $u;}
function h2($s){return hash('sha256',NativeCryptoCodec::canonical((object)$s));}
function request2($op,$p,$u,$key,$snapshot,$current=null,$signer='device'){
    $p+=['expectedGeneration'=>$current['generation']??0,'previousHeadHash'=>$current['headHash']??str_repeat('0',64),'identityEpochId'=>$current['snapshot']['identityEpochId']??$snapshot['identityEpochId'],'resultingSnapshotHash'=>h2($snapshot)];
    $c=['version'=>2,'operation'=>$op,'requestId'=>uid(),'serverId'=>$u['serverId'],'accountId'=>$u['user']['accountId'],'deviceId'=>$u['device']['id'],'signer'=>$signer,'payload'=>$p];$raw=NativeCryptoCodec::canonical((object)$c);return ['commandBase64'=>base64_encode($raw),'signatureBase64'=>base64_encode(sodium_crypto_sign_detached("JivieE2EE/v2\n".$raw,$key['sign']))];
}
function dev2($u,$key,$epoch,$gen=1,$caps=true){return ['deviceId'=>$u['device']['id'],'signingKeyBase64'=>$key['signPublic'],'encryptionKeyBase64'=>$key['boxPublic'],'keyringWrite'=>$caps,'manageDevices'=>$caps,'addedGeneration'=>$gen,'revokedGeneration'=>null,'identityEpochId'=>$epoch];}
function call($op,$p=[],$u=null) {
    global $api,$prefix;
    ob_start();
    try {
        $result=$api->dispatch($op,$p,$u?'Bearer '.$u['token']:'',$prefix);
        if (ob_get_contents()!=='') throw new RuntimeException('Unexpected response contamination');
        $json=json_encode($result,JSON_THROW_ON_ERROR);
        json_decode($json,true,512,JSON_THROW_ON_ERROR);
        return $result;
    } finally { ob_end_clean(); }
}
function inner2($body,$domain,$key) {
    $raw=NativeCryptoCodec::canonical((object)$body);
    return ['commandBase64'=>base64_encode($raw),'signatureBase64'=>base64_encode(sodium_crypto_sign_detached($domain.$raw,$key['sign']))];
}
function financeCard2($core,$u,$key,$authorHead) {
    unset($core['financeKeyProposalProof'],$core['contentKeyProposalProof']);
    return inner2(['version'=>2,'operation'=>'crypto2.scope.financeKeyProposal','serverId'=>$u['serverId'],'scopeId'=>$core['scopeId'],'epoch'=>$core['epoch'],'previousHeadHash'=>$core['previousHeadHash'],'proposalContextHash'=>hash('sha256',"JivieScopeHeadCore/v2\n".NativeCryptoCodec::canonical((object)$core)),'keyId'=>$core['keyIds']['finance'],'keyCommitment'=>$core['keyCommitments']['finance'],'accountId'=>$u['user']['accountId'],'deviceId'=>$u['device']['id'],'authorDirectoryHeadHash'=>$authorHead],"JivieE2EE/financeKeyProposal/v2\n",$key);
}
function content2($op, $p, $u, $key, $id=null) {
    $id=$id??uid();
    if (in_array($op,['crypto2.scope.create','crypto2.scope.ensurePersonal'],true) && !isset($p['originProof'])) {
        $kind=$op==='crypto2.scope.ensurePersonal'?'personal':$p['kind'];
        $reference=call('crypto2.account.status',[],$u)['headHash'];
        $parentToken=isset($p['parentScopeId'])?(new \Kanboard\Plugin\FamilyHub\Model\NativeCryptoLifecycleV2($GLOBALS['container']))->parentToken($p['id'],$p['parentScopeId']):null;
        $p['originProof']=inner2(['version'=>2,'operation'=>'crypto2.scope.origin','serverId'=>$u['serverId'],'scopeId'=>$p['id'],'kind'=>$kind,'accessPolicyVersion'=>$kind==='personal'?1:3,'parentScopeToken'=>$parentToken,'requestId'=>$id,'accountId'=>$u['user']['accountId'],'deviceId'=>$u['device']['id'],'authorDirectoryHeadHash'=>$reference],"JivieE2EE/scopeOrigin/v2\n",$key);
    }
    if ($op==='crypto2.scope.headPut' && $p['keyIds']['finance']!==null && $p['financeKeyProposalProof']===null) {
        $p['financeKeyProposalProof']=financeCard2($p,$u,$key,$p['authorDirectoryHeadHash']);
    }
    if ($op==='crypto2.scope.activate' && !isset($p['activationProof']) && !isset($p['financeGrantManifestProof'])) {
        $h=call('crypto2.scope.headGet',['scopeId'=>$p['scopeId'],'headHash'=>$p['headHash']],$u);
        if ($h['payload']['keyIds']['finance']!==null) {
            $root=call('crypto2.grants.manifest',['scopeId'=>$p['scopeId'],'headHash'=>$p['headHash']],$u)['domains']['finance'];
            $p['financeGrantManifestProof']=inner2(['version'=>2,'operation'=>'crypto2.scope.financeGrantManifest','serverId'=>$u['serverId'],'scopeId'=>$p['scopeId'],'headHash'=>$p['headHash'],'financeManifestHash'=>$root,'accountId'=>$u['user']['accountId'],'deviceId'=>$u['device']['id'],'authorDirectoryHeadHash'=>$p['authorDirectoryHeadHash']],"JivieE2EE/financeGrantManifest/v2\n",$key);
        }
    }
    $c=['version'=>2,'operation'=>$op,'requestId'=>$id??uid(),'serverId'=>$u['serverId'],'accountId'=>$u['user']['accountId'],'deviceId'=>$u['device']['id'],'signer'=>'device','payload'=>$p];
    $raw=NativeCryptoCodec::canonical((object)$c);
    return ['commandBase64'=>base64_encode($raw),'signatureBase64'=>base64_encode(sodium_crypto_sign_detached("JivieE2EE/v2\n".$raw,$key['sign']))];
}
function send2($op,$p,$u,$key) { return call($op,content2($op,$p,$u,$key),$u); }
function candidate2($scope,$state,$epoch=1,$old=null,$closures=null) {
    $snap=$state['snapshot'];
    return ['financePolicyIntentProof'=>null,'previousLifecycleHash'=>$epoch===1?null:(new \Kanboard\Plugin\FamilyHub\Model\NativeCryptoLifecycleV2($GLOBALS['container']))->closingHash($scope['id']),'initialLifecycleHash'=>q('SELECT initial_hash FROM familyhub_crypto_lifecycle_baselines_v2 WHERE scope_id=?',[$scope['id']])[0]['initial_hash'],'scopeId'=>$scope['id'],'epoch'=>$epoch,'previousHeadHash'=>$old??str_repeat('0',64),'authorDirectoryHeadHash'=>$state['headHash'],'expectedAccessRevision'=>$scope['accessRevision'],'accessBasis'=>[['scopeToken'=>hash('sha256',"JivieScopeAccessBasis/v2\n".$state['snapshot']['serverId'].':'.$scope['id'].':'.$scope['id']),'accessRevision'=>(int)q('SELECT access_revision FROM familyhub_scopes WHERE id=?',[$scope['id']])[0]['access_revision']]],'accessRevision'=>$scope['accessRevision'],'members'=>[['accountId'=>$snap['accountId'],'rootSigningKeyBase64'=>$snap['rootSigningKeyBase64'],'rootEncryptionKeyBase64'=>$snap['rootEncryptionKeyBase64'],'recoveryRootEpochId'=>$snap['recoveryRootEpochId'],'identityEpochId'=>$snap['identityEpochId'],'directoryHeadHash'=>$state['headHash'],'deviceSnapshotHash'=>$state['deviceSnapshotHash'],'role'=>'owner','financeRole'=>'write','manageKeys'=>true]],'membershipIntents'=>[],'closures'=>$closures??['content'=>null,'finance'=>null],'keyCommitments'=>['content'=>hash('sha256',"JivieScopeKey/v2\n".random_bytes(32)),'finance'=>hash('sha256',"JivieScopeKey/v2\n".random_bytes(32))],'keyIds'=>['content'=>uid(),'finance'=>uid()],'contentKeyProposalProof'=>null,'financeKeyProposalProof'=>null];
}
function grants2($head,$sources,$u,$key,$root,$epoch) {
    foreach(['content','finance'] as $domain) foreach($sources as $source) {
        $r=[['recipientKind'=>'device','recipientId'=>$u['device']['id'],'publicKeyBase64'=>$key['boxPublic'],'sealedEnvelopeBase64'=>base64_encode(sodium_crypto_box_seal('Synthetic domain key',base64_decode($key['boxPublic'])))],['recipientKind'=>'recovery','recipientId'=>$epoch,'publicKeyBase64'=>$root['boxPublic'],'sealedEnvelopeBase64'=>base64_encode(sodium_crypto_box_seal('Synthetic domain key',base64_decode($root['boxPublic'])))]];
        send2('crypto2.grants.put',['scopeId'=>$head['scopeId'],'headHash'=>$head['headHash'],'keySourceHeadHash'=>$source['headHash'],'keyId'=>$source['payload']['keyIds'][$domain],'accountId'=>$u['user']['accountId'],'domain'=>$domain,'epoch'=>$source['payload']['epoch'],'expectedGeneration'=>0,'recipients'=>$r],$u,$key);
    }
}
require __DIR__.'/crypto2-record-helpers.php';
$u=user('owner');$root=keys();$key=keys();$epoch=uid();$cipher=base64_encode(random_bytes(96));
$snapshot=['version'=>2,'serverId'=>$u['serverId'],'accountId'=>$u['user']['accountId'],'rootSigningKeyBase64'=>$root['signPublic'],'rootEncryptionKeyBase64'=>$root['boxPublic'],'recoveryRootCiphertextHash'=>hash('sha256',base64_decode($cipher)),'recoveryRootEpochId'=>$epoch,'identityEpochId'=>$epoch,'devices'=>[dev2($u,$key,$epoch)],'keyringEntries'=>[]];
call('crypto2.account.initialize',request2('crypto2.account.initialize',['rootSigningKeyBase64'=>$root['signPublic'],'rootEncryptionKeyBase64'=>$root['boxPublic'],'deviceSigningKeyBase64'=>$key['signPublic'],'deviceEncryptionKeyBase64'=>$key['boxPublic'],'keyringCiphertextBase64'=>$cipher],$u,$root,$snapshot,null,'root'),$u);
$state=call('crypto2.account.status',[],$u);
function proposal($scope,$state,$u,$key,$root,$epoch) {
    $body=candidate2($scope,$state);$body['accessBasis']=$scope['accessBasis'];
    $pending=send2('crypto2.scope.headPut',$body,$u,$key);
    $head=call('crypto2.scope.headGet',['scopeId'=>$scope['id'],'headHash'=>$pending['headHash']],$u);
    grants2($head,[$head],$u,$key,$root,$epoch);
    return [$head,['scopeId'=>$scope['id'],'headHash'=>$head['headHash'],'grantManifestHash'=>call('crypto2.grants.manifest',['scopeId'=>$scope['id'],'headHash'=>$head['headHash']],$u)['grantManifestHash'],'authorDirectoryHeadHash'=>$state['headHash']]];
}
$reproStage='native_parent_and_child_setup';
$parent=send2('crypto2.scope.create',['id'=>uid(),'kind'=>'organization'],$u,$key)['scope'];
[$parentHead,$parentActivation]=proposal($parent,$state,$u,$key,$root,$epoch);
$parentProof=content2('crypto2.scope.activate',$parentActivation,$u,$key);
$parentReady=call('crypto2.scope.activate',$parentProof,$u);
$canonical=NativeCryptoReservedRecordV2::derive($u['serverId'],$parent['id'],'scopeMetadata');
$metadata=row2($parent['id'],$parentHead,$u,$key,$canonical,'scopeMetadata');
$ack=call('crypto2.records.batch',batch2([$metadata],$u,$key),$u);
$previous=$ack['records'][0]['recordProofHash'];
$child=send2('crypto2.scope.create',['id'=>uid(),'kind'=>'project','parentScopeId'=>$parent['id'],'expectedParentAccessRevision'=>$parent['accessRevision'],'expectedParentAccessBasis'=>$parent['accessBasis']],$u,$key)['scope'];
[$childHead,$activation]=proposal($child,$state,$u,$key,$root,$epoch);
$next=row2($parent['id'],$parentHead,$u,$key,$canonical,'scopeMetadata',1,$previous);
$bundle=['parentScopeId'=>$parent['id'],'childScopeId'=>$child['id'],'authorization'=>batch2([$next],$u,$key)];
$activation['parentTopologyBatchHash']=hash('sha256',"JivieFinanceTopologyCreationBatch/v3\n".NativeCryptoCodec::canonical((object)$bundle));
$wrapper=['scopeId'=>$child['id'],'headHash'=>$childHead['headHash'],'activationProof'=>content2('crypto2.scope.activate',$activation,$u,$key),'parentTopologyBatch'=>$bundle];
$proof=content2('crypto2.scope.activate',$wrapper,$u,$key);
[$command]=NativeCryptoCodec::decode($proof);
$ready=call('crypto2.scope.activate',$proof,$u);


function selectionProposeRequest($u,$key,$state,$parent,$parentHead,$child,$childHead,$records=[]) {
    $inventory=call('crypto2.domain.inventory',['scopeId'=>$parent['id'],'domain'=>'finance','accessRevision'=>$parentHead['payload']['accessRevision']],$u);
    $descriptors=$inventory['descriptors'];
    if ($inventory['hasMore']) throw new RuntimeException('Bounded fixture inventory only');
    $manifest='';foreach($descriptors as $descriptor) $manifest.=NativeCryptoCodec::canonical((object)$descriptor)."\n";
    $sequence=$inventory['scopeSequence'];
    $checkpointPayload=['scopeId'=>$parent['id'],'domain'=>'finance','epoch'=>$parentHead['payload']['epoch'],'membershipHeadHash'=>$parentHead['headHash'],'accessRevision'=>$parentHead['payload']['accessRevision'],'authorDirectoryHeadHash'=>$state['headHash'],'expectedSequence'=>$sequence,'recordCount'=>count($descriptors),'manifestHash'=>hash('sha256',$manifest),'historyBasis'=>'verifiedCheckpoint'];
    $checkpoint=content2('crypto2.domain.checkpoint',$checkpointPayload,$u,$key);
    call('crypto2.domain.checkpoint',$checkpoint,$u);
    usort($records,static fn($a,$b)=>strcmp($a['id'],$b['id']));
    $context=['version'=>2,'variant'=>'accountChoiceSelection','purpose'=>'financeAccountChoice','serverId'=>$u['serverId'],'sourceScopeId'=>$parent['id'],'sourceHeadHash'=>$parentHead['headHash'],'sourceCheckpoint'=>['proofHash'=>hash('sha256',NativeCryptoCodec::canonical((object)$checkpoint)),'sequence'=>$sequence,'manifestHash'=>hash('sha256',$manifest)],'targetScopeId'=>$child['id'],'targetHeadHash'=>$childHead['headHash'],'selectionCount'=>count($records),'sourceRecordRoot'=>hash('sha256',"JivieFinanceAccountChoiceSource/v2\n".NativeCryptoCodec::canonical($records))];
    $hashContext=$context;unset($hashContext['variant'],$hashContext['purpose'],$hashContext['sourceRecordRoot']);
    $salt=random_bytes(32);
    // Empty choices reproduce the actual native request. Nonempty guards use a
    // synthetic opaque selection hash: the server never receives these values.
    $selectionHash=hash('sha256',"JivieFinanceAccountChoiceSelectionRoot/v2\n".NativeCryptoCodec::canonical((object)$hashContext).chr(10).$salt.NativeCryptoCodec::canonical([]));
    sodium_memzero($salt);
    $inner=inner2($context+['operation'=>'crypto2.exports.offer','selectionHash'=>$selectionHash,'accountId'=>$u['user']['accountId'],'deviceId'=>$u['device']['id'],'authorDirectoryHeadHash'=>$state['headHash'],'deviceSnapshotHash'=>$state['deviceSnapshotHash']],"JivieE2EE/exportOffer/v2\n",$key);
    return content2('crypto2.exports.propose',['variant'=>'accountChoiceSelection','selectionProof'=>$inner],$u,$key);
}
function receiptFor($proof,$u) {
    [$command]=NativeCryptoCodec::decode($proof);
    return call('crypto2.receipt.get',['requestId'=>$command['requestId'],'requestHash'=>hash('sha256',base64_decode($proof['commandBase64'],true))],$u);
}
$reproStage='empty_parent_finance_checkpoint';
ck((int)q("SELECT COUNT(*) n FROM familyhub_crypto_records r JOIN familyhub_crypto_record_positions p ON p.scope_id=r.scope_id AND p.id=r.id WHERE r.scope_id=? AND p.domain='finance'",[$parent['id']])[0]['n']===0,'native parent finance starts empty');
$empty=selectionProposeRequest($u,$key,$state,$parent,$parentHead,$child,$childHead);
[$outCommand]=NativeCryptoCodec::decode($empty);
$reproStage='real_dispatch_exports_propose';
$result=call('crypto2.exports.propose',$empty,$u);
ck(isset($result['offerHash']) && count(q('SELECT hash FROM familyhub_crypto_export_offers_v2'))===1,'empty native selection creates one offer');
$receipt=receiptFor($empty,$u);
ck($receipt['status']===200 && $receipt['response']===$result,'empty proposal has real successful receipt');
ck(call('crypto2.exports.propose',$empty,$u)===$result && count(q('SELECT hash FROM familyhub_crypto_export_offers_v2'))===1,'exact proposal retry retains one immutable offer and response');
$reproStage='nonempty_scope_filter';
$source=row2($parent['id'],$parentHead,$u,$key,null,'financeAccount');
$sourceAck=call('crypto2.records.batch',batch2([$source],$u,$key),$u)['records'][0];
$foreign=row2($child['id'],$childHead,$u,$key,null,'financeAccount');
call('crypto2.records.batch',batch2([$foreign],$u,$key),$u);
$one=selectionProposeRequest($u,$key,$state,$parent,$parentHead,$child,$childHead,[['id'=>$source['id'],'recordProofHash'=>$sourceAck['recordProofHash']]]);
$oneResult=call('crypto2.exports.propose',$one,$u);
[$oneCommand]=NativeCryptoCodec::decode($one);
$freshSameSelection=fn()=>content2('crypto2.exports.propose',$oneCommand['payload'],$u,$key);
ck(isset($oneResult['offerHash']) && receiptFor($one,$u)['status']===200,'nonempty parent selection excludes child account and parent content metadata');
$reproStage='missing_position';
$position=q('SELECT * FROM familyhub_crypto_record_positions WHERE scope_id=? AND id=?',[$parent['id'],$source['id']])[0];
q('DELETE FROM familyhub_crypto_record_positions WHERE scope_id=? AND id=?',[$parent['id'],$source['id']]);
deny(fn()=>call('crypto2.exports.propose',$freshSameSelection(),$u),'crypto_account_choices_source_set_changed','missing source position cannot silently omit a live account');
q('INSERT INTO familyhub_crypto_record_positions(scope_id,id,domain,sequence) VALUES(?,?,?,?)',[$child['id'],$source['id'],'finance',999]);
deny(fn()=>call('crypto2.exports.propose',$freshSameSelection(),$u),'crypto_account_choices_source_set_changed','same record id position in another scope cannot bind parent account');
q('DELETE FROM familyhub_crypto_record_positions WHERE scope_id=? AND id=?',[$child['id'],$source['id']]);
q('INSERT INTO familyhub_crypto_record_positions(scope_id,id,domain,sequence) VALUES(?,?,?,?)',[$parent['id'],$source['id'],'content',999]);
deny(fn()=>call('crypto2.exports.propose',$freshSameSelection(),$u),'crypto_account_choices_source_set_changed','wrong domain position cannot silently omit a live account');
q('UPDATE familyhub_crypto_record_positions SET domain=?,sequence=? WHERE scope_id=? AND id=?',[$position['domain'],$position['sequence'],$parent['id'],$source['id']]);
ck(call('crypto2.exports.propose',$one,$u)===$oneResult,'restoring exact position permits unchanged historical request replay');
echo json_encode(['result'=>'PASS','stage'=>'complete','checks'=>$checks,'realDispatch'=>true,'emptyAndNonempty'=>true,'freshDisposableSQLite'=>true],JSON_THROW_ON_ERROR),PHP_EOL;
