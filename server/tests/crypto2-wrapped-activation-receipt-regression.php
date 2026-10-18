<?php
/** One disposable wrapped-child activation: receipt recovery is minimal, not current-content authority.
 * Run only with a fresh development database, never against a hosting or device test server.
 */
umask(0077);
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
ck($ready['state']==='keysReady' && $ready['grantManifestHash']===$activation['grantManifestHash'],'real wrapped child activation commits with bound manifest');
$receipt=q('SELECT * FROM familyhub_crypto_receipts WHERE account_id=? AND request_id=?',[$u['user']['accountId'],$command['requestId']])[0];
$lookup=['requestId'=>$command['requestId'],'requestHash'=>$receipt['request_hash']];
$found=call('crypto2.receipt.get',$lookup,$u);
ck($found['response']===$ready && $found['authorization']===$proof,'receipt lookup returns exact wrapped activation without warnings or JSON contamination');
ck(call('crypto2.scope.activate',$proof,$u)===$ready,'exact wrapped activation replay is immutable');
$checker=new ReflectionMethod(NativeCryptoV2Service::class,'minimalLifecycleReceipt');
$service=new NativeCryptoV2Service($container,'Bearer '.$u['token'],$prefix);
$minimal=fn($c,$r)=>$checker->invoke($service,$c,$r);
ck($minimal($command,$receipt),'validated wrapped receipt recognized as minimal');
$mutations=[
    'missing manifest'=>static function(&$c) { [$i]=NativeCryptoCodec::decode($c['payload']['activationProof']);unset($i['payload']['grantManifestHash']);$c['payload']['activationProof']=inner2($i,"JivieE2EE/v2\n",$GLOBALS['key']); },
    'empty manifest'=>static function(&$c) { [$i]=NativeCryptoCodec::decode($c['payload']['activationProof']);$i['payload']['grantManifestHash']='';$c['payload']['activationProof']=inner2($i,"JivieE2EE/v2\n",$GLOBALS['key']); },
    'manifest mismatch'=>static function(&$c) { [$i]=NativeCryptoCodec::decode($c['payload']['activationProof']);$i['payload']['grantManifestHash']=str_repeat('f',64);$c['payload']['activationProof']=inner2($i,"JivieE2EE/v2\n",$GLOBALS['key']); },
    'bundle hash mismatch'=>static function(&$c) { $c['payload']['parentTopologyBatch']['parentScopeId']=uid(); },
    'child mismatch'=>static function(&$c) { $c['payload']['scopeId']=uid(); },
    'nested identity mismatch'=>static function(&$c) { [$i]=NativeCryptoCodec::decode($c['payload']['activationProof']);$i['accountId']=uid();$c['payload']['activationProof']=inner2($i,"JivieE2EE/v2\n",$GLOBALS['key']); },
    'malformed proof'=>static function(&$c) { $c['payload']['activationProof']=[]; },
    'unexpected wrapper field'=>static function(&$c) { $c['payload']['grantManifestHash']=str_repeat('f',64); },
];
foreach($mutations as $label=>$mutate) { $changed=$command;$mutate($changed);ck(!$minimal($changed,$receipt),$label.' cannot bypass current access'); }
$badReceipt=$receipt;$response=$ready;$response['grantManifestHash']='';$badReceipt['response']=json_encode($response,JSON_THROW_ON_ERROR);
ck(!$minimal($command,$badReceipt),'response manifest mismatch is not minimal');
$nullCommand=$command;[$inner]=NativeCryptoCodec::decode($nullCommand['payload']['activationProof']);unset($inner['payload']['grantManifestHash']);$nullCommand['payload']['activationProof']=inner2($inner,"JivieE2EE/v2\n",$key);
$response['grantManifestHash']=null;$badReceipt['response']=json_encode($response,JSON_THROW_ON_ERROR);
ck(!$minimal($nullCommand,$badReceipt),'missing command and null response never compare as a valid manifest');
// Invalid direct receipt identities cannot pass through matching null response values.
[$directCommand]=NativeCryptoCodec::decode($parentProof);
$directReceipt=q('SELECT * FROM familyhub_crypto_receipts WHERE account_id=? AND request_id=?',[$u['user']['accountId'],$directCommand['requestId']])[0];
foreach (['scopeId','headHash'] as $field) foreach (['missing','null'] as $kind) {
    $invalid=$directCommand;$invalidResponse=$parentReady;$invalidResponse[$field]=null;
    if ($kind==='missing') unset($invalid['payload'][$field]); else $invalid['payload'][$field]=null;
    $invalidReceipt=$directReceipt;$invalidReceipt['response']=json_encode($invalidResponse,JSON_THROW_ON_ERROR);
    ck(!$minimal($invalid,$invalidReceipt),$kind.' '.$field.' never passes a matching null response');
}
$outsider=user('outsider');
ck(call('crypto2.receipt.get',$lookup,$outsider)['outcome']==='unknown','another account cannot retrieve the own historical receipt');
// Simulate a later access revocation in this disposable fixture only.
foreach([$parent['id'],$child['id']] as $sid) {
    q('UPDATE familyhub_members SET active=0 WHERE scope_id=?',[$sid]);
    q('UPDATE familyhub_scopes SET owner_id=? WHERE id=?',[$outsider['user']['id'],$sid]);
}
deny(fn()=>call('crypto2.scope.headGet',['scopeId'=>$child['id']],$u),'permission_revoked','historical activation receipt does not reopen current content');
deny(fn()=>call('crypto2.records.batch',batch2([row2($child['id'],$childHead,$u,$key)],$u,$key),$u),'permission_revoked','historical activation receipt cannot authorize a new write');
ck(call('crypto2.receipt.get',$lookup,$u)===$found && call('crypto2.scope.activate',$proof,$u)===$ready,'own exact historical wrapped lookup and replay survive later access revocation');
ck(call('crypto2.scope.activate',$parentProof,$u)===$parentReady,'direct activation historical receipt semantics are preserved');
// A malformed stored response must fall back to ACL, rather than the historical shortcut.
q('UPDATE familyhub_crypto_receipts SET response=? WHERE account_id=? AND request_id=?',[$badReceipt['response'],$u['user']['accountId'],$command['requestId']]);
deny(fn()=>call('crypto2.receipt.get',$lookup,$u),'permission_revoked','nonminimal stored receipt falls back to current access');
foreach (['missing manifest','bundle hash mismatch'] as $label) {
    $invalid=$command;$mutations[$label]($invalid);
    $invalidProof=inner2($invalid,"JivieE2EE/v2\n",$key);
    q('UPDATE familyhub_crypto_receipts SET response=?,authorization=? WHERE account_id=? AND request_id=?',[$receipt['response'],json_encode($invalidProof,JSON_THROW_ON_ERROR),$u['user']['accountId'],$command['requestId']]);
    deny(fn()=>call('crypto2.receipt.get',$lookup,$u),'permission_revoked',$label.' stored proof falls back to current access');
}
q('UPDATE familyhub_crypto_receipts SET authorization=? WHERE account_id=? AND request_id=?',[$receipt['authorization'],$u['user']['accountId'],$command['requestId']]);
q('UPDATE familyhub_crypto_receipts SET response=? WHERE account_id=? AND request_id=?',[$receipt['response'],$u['user']['accountId'],$command['requestId']]);
ck(q('SELECT * FROM familyhub_crypto_receipts WHERE account_id=? AND request_id=?',[$u['user']['accountId'],$command['requestId']])[0]===$receipt,'lookup and exact replay leave the original stored receipt byte unchanged');
echo 'Wrapped activation receipt regression: '.$checks.' checks PASS'.PHP_EOL;
