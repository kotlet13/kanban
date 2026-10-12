<?php
// Fresh loopback Dart-client fixture only. Output credentials go to a mode0600 file.
require '/var/www/app/app/common.php';
if (session_status()===PHP_SESSION_ACTIVE) { session_abort(); }
if (!defined('FAMILYHUB_DEVELOPMENT_MODE') || FAMILYHUB_DEVELOPMENT_MODE!==true ||
    !defined('FAMILYHUB_DEVELOPMENT_ENVIRONMENT') || FAMILYHUB_DEVELOPMENT_ENVIRONMENT!==true) {
    throw new RuntimeException('Synthetic development fixture required');
}
$pdo=$container['db']->getConnection();
$q=$pdo->query("SELECT version FROM plugin_schema_versions WHERE plugin='familyhub'");
if ((int)$q->fetchColumn()!==17) { throw new RuntimeException('Ideas schema17 required'); }
if (($argv[1]??'')==='seed' && $argc===2) {
    $prefix='ideas_http_'.bin2hex(random_bytes(5));$fixture=['synthetic'=>true];
    foreach (['owner','member','outsider'] as $role) {
        $username=$prefix.'_'.$role;$password=bin2hex(random_bytes(16));
        if (!$container['userModel']->create(['username'=>$username,'password'=>$password,'role'=>'app-user','name'=>'Synthetic idea '.$role])) {
            throw new RuntimeException('Synthetic account creation failed');
        }
        $fixture[$role]=['username'=>$username,'password'=>$password];
    }
    echo json_encode($fixture,JSON_THROW_ON_ERROR);exit;
}
if (($argv[1]??'')!=='join' || $argc!==4) { throw new RuntimeException('Invalid fixture action'); }
foreach ([$argv[2],$argv[3]] as $id) {
    if (!preg_match('/^[a-f0-9-]{36}$/D',$id)) { throw new RuntimeException('Synthetic UUID required'); }
}
$q=$pdo->prepare('SELECT s.kind,s.access_policy_version,u.username FROM familyhub_scopes s JOIN users u ON u.id=s.owner_id WHERE s.id=?');$q->execute([$argv[2]]);$scope=$q->fetch(PDO::FETCH_ASSOC);
$q=$pdo->prepare('SELECT u.id,u.username FROM users u JOIN familyhub_accounts a ON a.user_id=u.id WHERE a.account_id=?');$q->execute([$argv[3]]);$member=$q->fetch(PDO::FETCH_ASSOC);
if (!$scope || !$member || $scope['kind']!=='household' || (int)$scope['access_policy_version']!==3 ||
    !preg_match('/^(ideas_http_[a-f0-9]{10})_owner$/D',$scope['username'],$match) || $member['username']!==$match[1].'_member') {
    throw new RuntimeException('Synthetic membership guard failed');
}
$q=$pdo->prepare("INSERT INTO familyhub_members(scope_id,user_id,account_id,role,active) VALUES(?,?,?,'member',1)");
$q->execute([$argv[2],$member['id'],$argv[3]]);
echo "Synthetic idea membership prepared\n";
