<?php
require '/var/www/app/app/common.php';
if(!defined('FAMILYHUB_DEVELOPMENT_MODE')||FAMILYHUB_DEVELOPMENT_MODE!==true){throw new RuntimeException('Development only');}
$name='financial_http_'.bin2hex(random_bytes(12));$password=bin2hex(random_bytes(20));
$container['userModel']->create(['username'=>$name,'password'=>$password,'role'=>'app-user']);
echo json_encode(['synthetic'=>true,'username'=>$name,'password'=>$password],JSON_THROW_ON_ERROR);
