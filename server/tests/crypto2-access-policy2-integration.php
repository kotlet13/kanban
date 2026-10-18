<?php
/** Closed legacy organization1 -> policy2 action, using real crypto activation. */
require __DIR__.'/crypto2-access-integration.php';

use Kanboard\Plugin\FamilyHub\Model\NativeCryptoV2Codec;

$legacyOrganization = scope($bob, 'organization', 1);
$scopeId = $legacyOrganization['id'];
q('INSERT INTO familyhub_members(scope_id,user_id,account_id,role,active) VALUES(?,?,?,?,1)', [$scopeId, $ordinary['user']['id'], $ordinary['user']['accountId'], 'member']);
$insert = $pdo->getAttribute(PDO::ATTR_DRIVER_NAME) === 'sqlite' ? 'INSERT OR IGNORE' : 'INSERT IGNORE';
q($insert.' INTO familyhub_finance_policy(scope_id,enabled,revision,sequence) VALUES(?,1,0,0)', [$scopeId]);
q('UPDATE familyhub_finance_policy SET enabled=1 WHERE scope_id=?', [$scopeId]);
q("INSERT INTO familyhub_finance_grants(scope_id,account_id,access_level) VALUES(?,?,'write')", [$scopeId, $bob['user']['accountId']]);
$initial = accessInitial2($scopeId, $bob, $bobKey, $bobState, $actors);
$synthetic = uid();
q('INSERT INTO familyhub_crypto_migrations_v2 VALUES(?,?,?,?,?,?,?,?,?)', [$synthetic, uid(), hash('sha256', 'synthetic policy2 component'), json_encode([$scopeId]), hash('sha256', 'synthetic participants'), 'committed', hash('sha256', 'synthetic challenge'), time(), time()]);
q("UPDATE familyhub_crypto_scopes SET state='active',migration_id=? WHERE scope_id=?", [$synthetic, $scopeId]);
$scope = array_values(array_filter(call('crypto2.scopes.catalog', [], $bob)['scopes'], fn($s) => $s['id'] === $scopeId))[0];
$beforeMember = array_values(array_filter($scope['members'], fn($m) => $m['accountId'] === $ordinary['user']['accountId']))[0];
ck($beforeMember['financeRole'] === 'none', 'legacy policy1 member has no finance authority without an explicit grant');
$payload = [
    'scopeId' => $scopeId,
    'membershipHeadHash' => $initial['headHash'],
    'expectedAccessRevision' => $scope['accessRevision'],
    'authorDirectoryHeadHash' => $ordinaryState['headHash'],
    'action' => ['kind' => 'accessPolicy', 'targetVersion' => 2],
];
deny(fn() => send2('crypto2.access.prepare', $payload, $ordinary, $ordinaryKey), 'permission_revoked', 'ordinary member cannot opt the organization into policy2');
$payload['authorDirectoryHeadHash'] = $bobState['headHash'];
$intent = send2('crypto2.access.prepare', $payload, $bob, $bobKey);
$pending = call('crypto2.access.pending', ['scopeId' => $scopeId], $bob)['intents'][0];
$futureMember = array_values(array_filter($pending['future']['members'], fn($m) => $m['accountId'] === $ordinary['user']['accountId']))[0];
ck($futureMember['financeRole'] === 'none' && $pending['future']['descriptor']['accessPolicyVersion'] === 2, 'policy2 resolver preserves ordinary organization members without a finance grant');
ck(q('SELECT access_policy_version FROM familyhub_scopes WHERE id=?', [$scopeId])[0]['access_policy_version'] == 1, 'policy2 preview does not grant finance access early');
$body = candidate2($scope, $bobState, 2, $initial['headHash'], ['content' => hash('sha256', ''), 'finance' => hash('sha256', '')]);
$body['accessBasis'] = $pending['accessBasis'];
$body['accessRevision'] = $pending['future']['accessRevision'];
$body['members'] = accessMembers2($pending['future']['members'], $actors);
$body['accessIntentProof'] = inner2([
    'version' => 2,
    'operation' => 'crypto2.access.scopeConsent',
    'serverId' => $bob['serverId'],
    'scopeId' => $scopeId,
    'intentHash' => $intent['intentHash'],
    'affectedCount' => 1,
    'affectedHash' => $intent['affectedHash'],
    'previousHeadHash' => $initial['headHash'],
    'expectedAccessRevision' => $pending['expectedAccessRevision'],
    'accessBasis' => $pending['accessBasis'],
    'resultingAccessRevision' => $body['accessRevision'],
    'resultingDescriptor' => $pending['future']['descriptor'],
        'resultingFinancePolicy' => $pending['future']['financePolicy'],
    'membersHash' => NativeCryptoV2Codec::hash($body['members']),
    'accountId' => $bob['user']['accountId'],
    'deviceId' => $bob['device']['id'],
    'authorDirectoryHeadHash' => $bobState['headHash'],
], "JivieE2EE/accessScopeConsent/v2\n", $bobKey);
$put = send2('crypto2.scope.headPut', $body, $bob, $bobKey);
$next = call('crypto2.scope.headGet', ['scopeId' => $scopeId, 'headHash' => $put['headHash']], $bob);
foreach (['content', 'finance'] as $domain) {
    close2($scopeId, $next['headHash'], $initial, $domain, $bobState, 0, $bob, $bobKey);
}
foreach ($body['members'] as $member) {
    [$actor, $key, $root, $state] = $actors[$member['accountId']];
    accessGrants2($next, [$initial, $next], $actor, $key, $root, $state, $bob, $bobKey);
}
$manifest = call('crypto2.grants.manifest', ['scopeId' => $scopeId, 'headHash' => $next['headHash']], $bob);
$activation = content2('crypto2.scope.activate', [
    'scopeId' => $scopeId,
    'headHash' => $next['headHash'],
    'grantManifestHash' => $manifest['grantManifestHash'],
    'authorDirectoryHeadHash' => $bobState['headHash'],
    'accessIntentHash' => $intent['intentHash'],
    'affectedCount' => 1,
    'affectedHash' => $intent['affectedHash'],
], $bob, $bobKey);
send2('crypto2.access.approve', ['intentHash' => $intent['intentHash'], 'scopeId' => $scopeId, 'activationProof' => $activation], $bob, $bobKey);
$commit = content2('crypto2.access.activate', ['intentHash' => $intent['intentHash'], 'affectedCount' => 1, 'affectedHash' => $intent['affectedHash']], $bob, $bobKey);
$applied = call('crypto2.access.activate', $commit, $bob);
ck($applied['state'] === 'applied' && call('crypto2.access.activate', $commit, $bob) === $applied, 'policy2 SQL and fresh head commit once with exact replay');
ck(q('SELECT access_policy_version FROM familyhub_scopes WHERE id=?', [$scopeId])[0]['access_policy_version'] == 2, 'legacy organization becomes exact requested policy2');
ck(q('SELECT access_level FROM familyhub_finance_grants WHERE scope_id=? AND account_id=?', [$scopeId, $bob['user']['accountId']])[0]['access_level'] === 'write', 'policy2 retains existing owner grant without overwriting it');
$current = call('crypto2.scope.headGet', ['scopeId' => $scopeId], $ordinary);
$member = array_values(array_filter($current['payload']['members'], fn($m) => $m['accountId'] === $ordinary['user']['accountId']))[0];
ck($member['financeRole'] === 'none', 'activated policy2 head does not widen ordinary organization finance authority');
deny(fn() => send2('crypto2.access.prepare', $payload, $bob, $bobKey), 'crypto_access_changed', 'old policy migration base cannot be reused with a fresh request nonce');

echo 'Crypto2 access policy2 integration: '.$checks.' checks PASS'.PHP_EOL;
