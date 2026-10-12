<?php
// Seed membership only for uniquely named synthetic moderation HTTP accounts.
require '/var/www/app/app/common.php';
if (session_status()===PHP_SESSION_ACTIVE) { session_abort(); }
if (!defined('FAMILYHUB_DEVELOPMENT_MODE') || FAMILYHUB_DEVELOPMENT_MODE!==true ||
    !defined('FAMILYHUB_DEVELOPMENT_ENVIRONMENT') || FAMILYHUB_DEVELOPMENT_ENVIRONMENT!==true || $argc!==3) {
    throw new RuntimeException('Synthetic development fixture required');
}
foreach ([$argv[1],$argv[2]] as $id) {
    if (!preg_match('/^[a-f0-9-]{36}$/D',$id)) { throw new RuntimeException('Synthetic UUID required'); }
}
$pdo=$container['db']->getConnection();
$q=$pdo->prepare('SELECT s.kind,s.access_policy_version,u.username FROM familyhub_scopes s JOIN users u ON u.id=s.owner_id WHERE s.id=?');$q->execute([$argv[1]]);$scope=$q->fetch(PDO::FETCH_ASSOC);
$q=$pdo->prepare('SELECT u.id,u.username FROM users u JOIN familyhub_accounts a ON a.user_id=u.id WHERE a.account_id=?');$q->execute([$argv[2]]);$member=$q->fetch(PDO::FETCH_ASSOC);
if (!$scope || !$member || $scope['kind']!=='household' || (int)$scope['access_policy_version']!==3 ||
    !preg_match('/^moderation_http_[a-f0-9]{10}_owner$/D',$scope['username']) ||
    !preg_match('/^moderation_http_[a-f0-9]{10}_member$/D',$member['username'])) {
    throw new RuntimeException('Synthetic membership guard failed');
}
$pdo->prepare("INSERT INTO familyhub_members(scope_id,user_id,account_id,role,active) VALUES(?,?,?,'member',1)")->execute([$argv[1],$member['id'],$argv[2]]);
echo "Synthetic membership prepared\n";
