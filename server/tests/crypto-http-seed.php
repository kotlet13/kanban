<?php
/** Emits only newly generated synthetic fixture credentials; redirect to a private local file. */
umask(0077);
require '/var/www/app/app/common.php';
if(session_status()===PHP_SESSION_ACTIVE){session_abort();}
if(!defined('FAMILYHUB_DEVELOPMENT_MODE')||FAMILYHUB_DEVELOPMENT_MODE!==true){throw new RuntimeException('Synthetic only');}
$pdo=$container['db']->getConnection();
\Kanboard\Plugin\FamilyHub\Schema\CryptoSchema::create($pdo,$pdo->getAttribute(PDO::ATTR_DRIVER_NAME)==='mysql');
$service=new \Kanboard\Plugin\FamilyHub\Model\NativeService($container);$prefix='crypto_http_'.bin2hex(random_bytes(6));$out=[];
$transferOnly=getenv('FAMILYHUB_CRYPTO_HTTP_TRANSFER_ONLY')==='1';
$financeOnly=getenv('FAMILYHUB_CRYPTO_HTTP_FINANCE_ONLY')==='1';
foreach($transferOnly?['oldOwner','newOwner','financeContributor']:($financeOnly?['financeOwner','financeMember']:['owner','other']) as $kind){
    $username=$prefix.'_'.$kind;$password=bin2hex(random_bytes(20));$id=$container['userModel']->create(['username'=>$username,'password'=>$password,'role'=>'app-user','name'=>'Synthetic '.$kind]);
    $session=$service->dispatch('auth.login',['username'=>$username,'password'=>$password,'deviceName'=>'Synthetic crypto HTTP'],'',$prefix);
    $email=$username.'@capture.invalid';$q=$pdo->prepare('INSERT INTO familyhub_email_identities(account_id,email,verified_at,revision) VALUES(?,?,?,1)');$q->execute([$session['user']['accountId'],$email,time()]);
    $service->dispatch('moderation.acceptPolicy',['policyVersion'=>1],'Bearer '.$session['token'],$prefix);
    $out[$kind]=['username'=>$username,'password'=>$password,'session'=>$session];
}
$fixture=['synthetic'=>true,'serverUrl'=>'http://127.0.0.1:18785','serverId'=>reset($out)['session']['serverId'],'accounts'=>$out];
if($financeOnly||$transferOnly){
    $owner=$out[$transferOnly?'oldOwner':'financeOwner']['session'];$member=$out[$transferOnly?'financeContributor':'financeMember']['session'];
    $h=bin2hex(random_bytes(16));$scopeId=substr($h,0,8).'-'.substr($h,8,4).'-4'.substr($h,13,3).'-a'.substr($h,17,3).'-'.substr($h,20);
    $h=bin2hex(random_bytes(16));$requestId=substr($h,0,8).'-'.substr($h,8,4).'-4'.substr($h,13,3).'-a'.substr($h,17,3).'-'.substr($h,20);
    $scope=$service->dispatch('scopes.create',['id'=>$scopeId,'kind'=>'household','name'=>'Synthetic two-party finance','requestId'=>$requestId,'accessPolicyVersion'=>1],'Bearer '.$owner['token'],$prefix)['scope'];
    $q=$pdo->prepare('INSERT INTO familyhub_members(scope_id,user_id,account_id,role,active) VALUES(?,?,?,?,1)');$q->execute([$scopeId,$member['user']['id'],$member['user']['accountId'],'member']);
    if($transferOnly){$successor=$out['newOwner']['session'];$q=$pdo->prepare('INSERT INTO familyhub_members(scope_id,user_id,account_id,role,active) VALUES(?,?,?,?,1)');$q->execute([$scopeId,$successor['user']['id'],$successor['user']['accountId'],'member']);}
    $q=$pdo->prepare('INSERT INTO familyhub_finance_policy(scope_id,enabled,revision,sequence) VALUES(?,1,1,0)');$q->execute([$scopeId]);
    $q=$pdo->prepare('INSERT INTO familyhub_finance_grants(scope_id,account_id,access_level) VALUES(?,?,?)');$q->execute([$scopeId,$member['user']['accountId'],'read']);
    $q=$pdo->prepare('UPDATE familyhub_scopes SET access_revision=1 WHERE id=?');$q->execute([$scopeId]);
    // Explicit synthetic staging only: no legacy migration or source retirement is claimed.
    $q=$pdo->prepare('INSERT INTO familyhub_crypto_scopes(scope_id,epoch,sequence,access_revision,state) VALUES(?,1,0,1,?)');$q->execute([$scopeId,'staged']);
    if($transferOnly){$q=$pdo->prepare('INSERT INTO familyhub_crypto_scope_origins VALUES(?,?,?,?)');$q->execute([$scopeId,$owner['user']['accountId'],json_encode(['syntheticFixture'=>true,'purpose'=>'three-party-transfer']),time()]);}
    $scope['accessRevision']=1;$fixture[$transferOnly?'transferScope':'financeScope']=$scope;
}
echo json_encode($fixture,JSON_THROW_ON_ERROR).PHP_EOL;
