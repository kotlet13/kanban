<?php
/** Emits only newly generated synthetic fixture credentials; redirect to a private local file. */
umask(0077);
require '/var/www/app/app/common.php';
if(session_status()===PHP_SESSION_ACTIVE){session_abort();}
if(!defined('FAMILYHUB_DEVELOPMENT_MODE')||FAMILYHUB_DEVELOPMENT_MODE!==true){throw new RuntimeException('Synthetic only');}
$pdo=$container['db']->getConnection();
\Kanboard\Plugin\FamilyHub\Schema\CryptoSchema::create($pdo,$pdo->getAttribute(PDO::ATTR_DRIVER_NAME)==='mysql');
$service=new \Kanboard\Plugin\FamilyHub\Model\NativeService($container);$prefix='crypto_http_'.bin2hex(random_bytes(6));$out=[];
foreach (['owner','other','recipient'] as $kind) {
    $username=$prefix.'_'.$kind;$password=bin2hex(random_bytes(20));
    $id=$container['userModel']->create(['username'=>$username,'password'=>$password,'role'=>'app-user','name'=>'Synthetic '.$kind]);
    $session=$service->dispatch('auth.login',['username'=>$username,'password'=>$password,'deviceName'=>'Synthetic relocation HTTP'],'',$prefix);
    $q=$pdo->prepare('INSERT INTO familyhub_email_identities(account_id,email,verified_at,revision) VALUES(?,?,?,1)');
    $q->execute([$session['user']['accountId'],$username.'@capture.invalid',time()]);
    $service->dispatch('moderation.acceptPolicy',['policyVersion'=>1],'Bearer '.$session['token'],$prefix);
    $out[$kind]=['username'=>$username,'password'=>$password,'session'=>$session];
}
echo json_encode(['synthetic'=>true,'serverUrl'=>'http://127.0.0.1:18785','serverId'=>$out['owner']['session']['serverId'],'accounts'=>$out],JSON_THROW_ON_ERROR).PHP_EOL;
