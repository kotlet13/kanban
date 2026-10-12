<?php
// Private synthetic credentials for the opt-in Dart/HTTP test; never a live host.
require '/var/www/app/app/common.php';
if (session_status()===PHP_SESSION_ACTIVE) { session_abort(); }
if (!defined('FAMILYHUB_DEVELOPMENT_MODE') || FAMILYHUB_DEVELOPMENT_MODE!==true ||
    !defined('FAMILYHUB_DEVELOPMENT_ENVIRONMENT') || FAMILYHUB_DEVELOPMENT_ENVIRONMENT!==true) {
    throw new RuntimeException('Synthetic development fixture required');
}
$pdo=$container['db']->getConnection();
$statement=$pdo->query("SELECT version FROM plugin_schema_versions WHERE plugin='familyhub'");
if ((int)$statement->fetchColumn()!==16) { throw new RuntimeException('Moderation schema16 required'); }
$prefix='moderation_http_'.bin2hex(random_bytes(5));
$fixture=['synthetic'=>true];
foreach (['owner','member','outsider'] as $role) {
    $username=$prefix.'_'.$role;$password=bin2hex(random_bytes(16));
    $id=$container['userModel']->create(['username'=>$username,'password'=>$password,'role'=>'app-user','name'=>'Synthetic '.$role]);
    if (!$id) { throw new RuntimeException('Synthetic account creation failed'); }
    $fixture[$role]=['username'=>$username,'password'=>$password];
}
echo json_encode($fixture,JSON_THROW_ON_ERROR);
