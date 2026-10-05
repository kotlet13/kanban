<?php
// Executed only inside the isolated compose container. Creates synthetic users/projects.
require '/var/www/app/app/common.php';
use Kanboard\Core\Security\Role;

if (! defined('FAMILYHUB_DEVELOPMENT_ENVIRONMENT') || FAMILYHUB_DEVELOPMENT_ENVIRONMENT !== true) {
    throw new RuntimeException('Synthetic tests require the isolated development configuration');
}

$checks = 0;
function check($condition, $description)
{
    global $checks;
    if (! $condition) {
        throw new RuntimeException('FAIL: '.$description);
    }
    $checks++;
    echo 'PASS: '.$description.PHP_EOL;
}
function rpc($username, $password, $method, array $params = array())
{
    $ch = curl_init('http://127.0.0.1/jsonrpc.php');
    curl_setopt_array($ch, array(CURLOPT_POST => true, CURLOPT_RETURNTRANSFER => true, CURLOPT_USERPWD => $username.':'.$password, CURLOPT_HTTPHEADER => array('Content-Type: application/json'), CURLOPT_POSTFIELDS => json_encode(array('jsonrpc' => '2.0', 'id' => 1, 'method' => $method, 'params' => $params))));
    $result = curl_exec($ch);
    if ($result === false) {
        throw new RuntimeException('HTTP request failed');
    }
    curl_close($ch);
    $decoded = json_decode($result, true);
    if (! is_array($decoded)) {
        throw new RuntimeException('Unexpected API response');
    }
    return $decoded;
}
function result($response)
{
    if (! array_key_exists('result', $response)) {
        throw new RuntimeException('Unexpected API error: '.($response['error']['message'] ?? 'unknown'));
    }
    return $response['result'];
}
function denied($response) { return isset($response['error']); }
function invite($project, $recipient, $suffix)
{
    global $names, $password;
    return result(rpc($names['owner'], $password, 'familyHubCreateProjectInvitation', array('project_id' => $project, 'recipient_username' => $recipient, 'request_id' => 'integration_request_'.$suffix)));
}

$prefix = 'fh_'.bin2hex(random_bytes(4)).'_';
$password = bin2hex(random_bytes(18));
$names = array();
$ids = array();
foreach (array('owner', 'recipient', 'outsider', 'viewer', 'administrator', 'twofactor') as $name) {
    $names[$name] = $prefix.$name;
    $ids[$name] = $container['userModel']->create(array('username' => $names[$name], 'password' => $password, 'role' => $name === 'administrator' ? Role::APP_ADMIN : Role::APP_USER));
    check($ids[$name] > 0, 'synthetic '.$name.' created');
}
$project = $container['projectModel']->create(array('name' => $prefix.'Shared project'), $ids['owner'], true);
$container['projectUserRoleModel']->addUser($project, $ids['viewer'], Role::PROJECT_VIEWER);
check($project > 0, 'synthetic project created');
$capabilities = result(rpc($names['owner'], $password, 'familyHubGetCapabilities'));
check($capabilities['contract_version'] === 1 && $capabilities['features']['project_invitations'] === true && $capabilities['features']['finance_acl'] === false, 'versioned capabilities accurately report supported features');
check($capabilities['actor']['user_id'] == $ids['owner'], 'capabilities use authenticated user identity');
check(denied(rpc($names['owner'], 'wrong-password', 'familyHubGetCapabilities')), 'invalid password rejected');
check(denied(rpc('', '', 'familyHubGetCapabilities')), 'anonymous caller rejected');
$globalToken = $container['configModel']->get('api_token');
check(denied(rpc('jsonrpc', $globalToken, 'familyHubGetCapabilities')), 'global jsonrpc identity rejected');
foreach (array('viewer', 'outsider', 'administrator') as $name) {
    check(denied(rpc($names[$name], $password, 'familyHubCreateProjectInvitation', array('project_id' => $project, 'recipient_username' => $names['recipient'], 'request_id' => 'unauthorized_request_'.$name))), $name.' cannot invite without project manager role');
}
$invitation = invite($project, $names['recipient'], 'first');
check($invitation['token_available'] && strlen($invitation['token']) === 64, 'manager creates random expiring token');
$statement = $container['db']->getConnection()->prepare('SELECT token_hash FROM familyhub_project_invitations WHERE id = ?');
$statement->execute(array($invitation['invitation_id']));
$storedHash = $statement->fetchColumn();
$statement->closeCursor();
check($storedHash === hash('sha256', $invitation['token']) && $storedHash !== $invitation['token'], 'only token hash stored');
$replay = invite($project, $names['recipient'], 'first');
check($replay['invitation_id'] === $invitation['invitation_id'] && $replay['token'] === null, 'create replay does not duplicate invitation or disclose token again');
check(denied(rpc($names['owner'], $password, 'familyHubCreateProjectInvitation', array('project_id' => $project, 'recipient_username' => $names['outsider'], 'request_id' => 'integration_request_first'))), 'request id cannot change recipient');
check(denied(rpc($names['outsider'], $password, 'familyHubPreviewProjectInvitation', array('token' => $invitation['token']))), 'wrong recipient cannot preview');
check(denied(rpc($names['outsider'], $password, 'familyHubAcceptProjectInvitation', array('token' => $invitation['token']))), 'wrong recipient cannot accept');
check(result(rpc($names['recipient'], $password, 'familyHubPreviewProjectInvitation', array('token' => $invitation['token'])))['project_id'] === $project, 'recipient previews intended project');
$accept = result(rpc($names['recipient'], $password, 'familyHubAcceptProjectInvitation', array('token' => $invitation['token'])));
check($accept['accepted'] && ! $accept['replayed'], 'recipient accepts invitation');
check($container['projectUserRoleModel']->getUserRole($project, $ids['recipient']) === Role::PROJECT_MEMBER, 'accept grants project member role');
check(result(rpc($names['recipient'], $password, 'familyHubAcceptProjectInvitation', array('token' => $invitation['token'])))['replayed'], 'accept replay is idempotent');
$container['projectUserRoleModel']->removeUser($project, $ids['recipient']);
check(denied(rpc($names['recipient'], $password, 'familyHubAcceptProjectInvitation', array('token' => $invitation['token']))), 'accepted token cannot recreate revoked membership');
check($container['projectUserRoleModel']->getUserRole($project, $ids['recipient']) === '', 'removed member stays removed');
$revocable = invite($project, $names['recipient'], 'revoked');
check(denied(rpc($names['outsider'], $password, 'familyHubRevokeProjectInvitation', array('invitation_id' => $revocable['invitation_id']))), 'outsider cannot revoke');
check(result(rpc($names['owner'], $password, 'familyHubRevokeProjectInvitation', array('invitation_id' => $revocable['invitation_id'])))['revoked'], 'manager revokes pending invitation');
check(result(rpc($names['owner'], $password, 'familyHubRevokeProjectInvitation', array('invitation_id' => $revocable['invitation_id'])))['revoked'], 'revoke replay is idempotent');
check(denied(rpc($names['recipient'], $password, 'familyHubAcceptProjectInvitation', array('token' => $revocable['token']))), 'revoked token cannot be consumed');
$expired = invite($project, $names['recipient'], 'expired');
$container['db']->table('familyhub_project_invitations')->eq('id', $expired['invitation_id'])->update(array('expires_at' => time()-1));
check(denied(rpc($names['recipient'], $password, 'familyHubAcceptProjectInvitation', array('token' => $expired['token']))), 'expired token rejected');
$demoted = invite($project, $names['recipient'], 'demoted');
$container['projectUserRoleModel']->changeUserRole($project, $ids['owner'], Role::PROJECT_MEMBER);
check(denied(rpc($names['recipient'], $password, 'familyHubAcceptProjectInvitation', array('token' => $demoted['token']))), 'invitation invalid when creator loses manager role');
$container['projectUserRoleModel']->changeUserRole($project, $ids['owner'], Role::PROJECT_MANAGER);

// Group access is considered separately from direct project membership.
$group = $container['groupModel']->create($prefix.'group');
$container['groupMemberModel']->addUser($group, $ids['recipient']);
$container['projectGroupRoleModel']->addGroup($project, $group, Role::PROJECT_VIEWER);
$groupInvitation = invite($project, $names['recipient'], 'group_viewer');
result(rpc($names['recipient'], $password, 'familyHubAcceptProjectInvitation', array('token' => $groupInvitation['token'])));
check($container['projectUserRoleModel']->getUserRole($project, $ids['recipient']) === Role::PROJECT_VIEWER, 'accept preserves existing group viewer role');
$container['groupMemberModel']->removeUser($group, $ids['recipient']);
check(denied(rpc($names['recipient'], $password, 'familyHubAcceptProjectInvitation', array('token' => $groupInvitation['token']))), 'replay cannot restore removed group access');
$container['groupMemberModel']->addUser($group, $ids['owner']);
$container['projectGroupRoleModel']->changeGroupRole($project, $group, Role::PROJECT_MANAGER);
$container['projectUserRoleModel']->removeUser($project, $ids['owner']);
$groupOwnerInvitation = invite($project, $names['recipient'], 'group_manager');
check($groupOwnerInvitation['token_available'], 'current group project manager can invite');
$container['groupMemberModel']->removeUser($group, $ids['owner']);
check(denied(rpc($names['recipient'], $password, 'familyHubAcceptProjectInvitation', array('token' => $groupOwnerInvitation['token']))), 'lost group manager role invalidates pending invitation');
$container['projectUserRoleModel']->addUser($project, $ids['owner'], Role::PROJECT_MANAGER);

// Simulate storage failure after token consume: the grant and consume must roll back together.
$rollback = invite($project, $names['recipient'], 'rollback');
$pdo = $container['db']->getConnection();
$trigger = 'fh_test_'.bin2hex(random_bytes(4));
if (DB_DRIVER === 'sqlite') {
    $pdo->exec("CREATE TRIGGER $trigger BEFORE INSERT ON project_has_users WHEN NEW.project_id = $project AND NEW.user_id = ".$ids['recipient']." BEGIN SELECT RAISE(ABORT, 'synthetic storage failure'); END");
} else {
    $pdo->exec("CREATE TRIGGER $trigger BEFORE INSERT ON project_has_users FOR EACH ROW BEGIN IF NEW.project_id = $project AND NEW.user_id = ".$ids['recipient']." THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'synthetic storage failure'; END IF; END");
}
try {
    check(denied(rpc($names['recipient'], $password, 'familyHubAcceptProjectInvitation', array('token' => $rollback['token']))), 'membership storage failure rejects acceptance');
    $row = $container['db']->table('familyhub_project_invitations')->eq('id', $rollback['invitation_id'])->findOne();
    check($row['accepted_at'] === null && $container['projectUserRoleModel']->getUserRole($project, $ids['recipient']) === '', 'failed membership grant rolls back token consumption');
} finally {
    $pdo->exec("DROP TRIGGER $trigger");
}
check(result(rpc($names['recipient'], $password, 'familyHubAcceptProjectInvitation', array('token' => $rollback['token'])))['accepted'], 'same token can succeed after transient storage failure');
$container['projectUserRoleModel']->removeUser($project, $ids['recipient']);

// Real concurrent HTTP requests, served by separate PHP-FPM workers.
function parallelRpc(array $calls)
{
    $multi = curl_multi_init();
    $handles = array();
    foreach ($calls as $call) {
        $ch = curl_init('http://127.0.0.1/jsonrpc.php');
        curl_setopt_array($ch, array(CURLOPT_POST => true, CURLOPT_RETURNTRANSFER => true, CURLOPT_USERPWD => $call[0].':'.$call[1], CURLOPT_HTTPHEADER => array('Content-Type: application/json'), CURLOPT_POSTFIELDS => json_encode(array('jsonrpc' => '2.0', 'id' => 1, 'method' => $call[2], 'params' => $call[3]))));
        $handles[] = $ch;
        curl_multi_add_handle($multi, $ch);
    }
    do {
        curl_multi_exec($multi, $running);
        if ($running) { curl_multi_select($multi, 1); }
    } while ($running);
    $results = array();
    foreach ($handles as $ch) {
        $results[] = json_decode(curl_multi_getcontent($ch), true);
        curl_multi_remove_handle($multi, $ch);
        curl_close($ch);
    }
    curl_multi_close($multi);
    return $results;
}
for ($i = 0; $i < 12; $i++) {
    $race = invite($project, $names['recipient'], 'race_'.$i);
    $responses = parallelRpc(array(
        array($names['recipient'], $password, 'familyHubAcceptProjectInvitation', array('token' => $race['token'])),
        array($names['owner'], $password, 'familyHubRevokeProjectInvitation', array('invitation_id' => $race['invitation_id'])),
    ));
    $row = $container['db']->table('familyhub_project_invitations')->eq('id', $race['invitation_id'])->findOne();
    check(($row['accepted_at'] === null) !== ($row['revoked_at'] === null), 'accept/revoke race '.$i.' has exactly one durable outcome');
    check(! isset($responses[1]['result']) || $row['revoked_at'] !== null, 'revoke race '.$i.' never reports false success');
    check(! isset($responses[0]['result']) || $row['accepted_at'] !== null, 'accept race '.$i.' never reports false success');
    $container['projectUserRoleModel']->removeUser($project, $ids['recipient']);
}
$doubleAccept = invite($project, $names['recipient'], 'double_accept');
parallelRpc(array(
    array($names['recipient'], $password, 'familyHubAcceptProjectInvitation', array('token' => $doubleAccept['token'])),
    array($names['recipient'], $password, 'familyHubAcceptProjectInvitation', array('token' => $doubleAccept['token'])),
));
check($container['db']->table('project_has_users')->eq('project_id', $project)->eq('user_id', $ids['recipient'])->count() === 1, 'parallel accepts create exactly one membership');
$container['projectUserRoleModel']->removeUser($project, $ids['recipient']);

$twofactorToken = bin2hex(random_bytes(24));
$container['db']->table('users')->eq('id', $ids['twofactor'])->update(array('twofactor_activated' => 1, 'api_access_token' => $twofactorToken));
check(denied(rpc($names['twofactor'], $password, 'familyHubGetCapabilities')), '2FA user password does not bypass upstream 2FA');
check(result(rpc($names['twofactor'], $twofactorToken, 'familyHubGetCapabilities'))['actor']['user_id'] == $ids['twofactor'], 'existing personal API token works for 2FA user');
$container['db']->table('users')->eq('id', $ids['outsider'])->update(array('is_active' => 0));
check(denied(rpc($names['outsider'], $password, 'familyHubGetCapabilities')), 'deactivated user rejected');
check((int) $container['db']->table('plugin_schema_versions')->eq('plugin', 'familyhub')->findOneColumn('version') === 9, 'plugin schema migration version recorded');
echo 'Completed '.$checks.' integration checks; synthetic fixtures remain only in local dev volume.'.PHP_EOL;
