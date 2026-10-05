<?php
// No FamilyHub login/account creation: this fixture exercises true first enrollment.
require '/var/www/app/app/common.php';
if(session_status()===PHP_SESSION_ACTIVE){session_abort();}
if(!defined('FAMILYHUB_DEVELOPMENT_MODE')||FAMILYHUB_DEVELOPMENT_MODE!==true){throw new RuntimeException('Synthetic only');}
$prefix='account_http_'.bin2hex(random_bytes(5));$password=bin2hex(random_bytes(16));
$admin=$container['userModel']->getByUsername('admin');
$nonadmin=$prefix.'_nonadmin';$container['userModel']->create(['username'=>$nonadmin,'password'=>$password,'role'=>'app-user']);
$code=(new \Kanboard\Plugin\FamilyHub\Model\NativeEnrollmentService($container))->issue($admin['id']);
echo json_encode(['synthetic'=>true,'bootstrap'=>$code,'owner'=>['username'=>$prefix.'_owner','password'=>$password,'displayName'=>'Synthetic owner'],'nonadmin'=>['username'=>$nonadmin,'password'=>$password]],JSON_THROW_ON_ERROR).PHP_EOL;
