<?php
/** Synthetic component policy transition; no deployment or mail delivery. */
require __DIR__.'/crypto2-access-integration.php';

use Kanboard\Plugin\FamilyHub\Model\NativeCryptoV2Codec;

function policyInvitation2($scopeId, $head, $recipient, $accept = false)
{
    global $bob, $bobKey, $bobState;
    $scope = array_values(array_filter(call('crypto2.scopes.catalog', [], $bob)['scopes'], fn($s) => $s['id'] === $scopeId))[0];
    $resolved = call('crypto2.invitations.resolve', ['scopeId' => $scopeId, 'recipient' => $recipient['username']], $bob)['recipient'];
    $payload = [
        'scopeId' => $scopeId,
        'invitationId' => uid(),
        'recipient' => $resolved,
        'role' => 'member',
        'expiresAt' => time() + 3600,
        'language' => 'en',
        'expectedAccessRevision' => $scope['accessRevision'],
        'membershipHeadHash' => $head['headHash'],
        'authorDirectoryHeadHash' => $bobState['headHash'],
        'tokenHash' => hash('sha256', 'fhi4_'.bin2hex(random_bytes(32))),
    ];
    $proof = content2('crypto2.invitations.create', $payload, $bob, $bobKey);
    $created = call('crypto2.invitations.create', $proof, $bob);
    $result = ['id' => $payload['invitationId'], 'creation' => $proof, 'created' => $created];
    if ($accept) {
        [$root, $key, $state] = initializeMember2($recipient);
        $acceptance = content2('crypto2.invitations.accept', [
            'scopeId' => $scopeId,
            'invitationId' => $payload['invitationId'],
            'tokenHash' => $payload['tokenHash'],
            'creatorProofHash' => $created['invitation']['creatorProofHash'],
            'role' => 'member',
            'expiresAt' => $payload['expiresAt'],
            'membershipHeadHash' => $head['headHash'],
            'authorDirectoryHeadHash' => $state['headHash'],
        ], $recipient, $key);
        $result['acceptance'] = $acceptance;
        $result['accepted'] = call('crypto2.invitations.accept', $acceptance, $recipient);
    }
    return $result;
}

$acceptedRecipient = user('policy_accepted');
$pendingRecipient = user('policy_pending');
$acceptedInvite = policyInvitation2($project['id'], $newHeads[$project['id']], $acceptedRecipient, true);
$pendingInvite = policyInvitation2($organization['id'], $newHeads[$organization['id']], $pendingRecipient);
$catalog = array_values(array_filter(call('crypto2.scopes.catalog', [], $bob)['scopes'], fn($s) => $s['id'] === $organization['id']))[0];
$request = content2('crypto2.access.prepare', [
    'scopeId' => $organization['id'],
    'membershipHeadHash' => $newHeads[$organization['id']]['headHash'],
    'expectedAccessRevision' => $catalog['accessRevision'],
    'authorDirectoryHeadHash' => $bobState['headHash'],
    'action' => ['kind' => 'accessPolicy', 'targetVersion' => 3],
], $bob, $bobKey);
$policyIntent = call('crypto2.access.prepare', $request, $bob);
ck($policyIntent['affectedCount'] === 2 && call('crypto2.access.prepare', $request, $bob) === $policyIntent, 'policy3 prepare retains the complete parent/child component and original exact receipt');
ck(q('SELECT access_policy_version FROM familyhub_scopes WHERE id=?', [$organization['id']])[0]['access_policy_version'] == 2, 'policy preview simulation does not change live SQL policy');
ck(q('SELECT state FROM familyhub_crypto_invitations_v2 WHERE id=?', [$acceptedInvite['id']])[0]['state'] === 'accepted', 'policy preview preserves accepted pending-key invitation before activation');
$commit = content2('crypto2.access.activate', ['intentHash' => $policyIntent['intentHash'], 'affectedCount' => 2, 'affectedHash' => $policyIntent['affectedHash']], $bob, $bobKey);
deny(fn() => call('crypto2.access.activate', $commit, $bob), 'crypto_access_approval_required', 'policy migration cannot partially apply without every child approval');

$lateRecipient=user('policy_late');
$lateInvite=policyInvitation2($project['id'],$newHeads[$project['id']],$lateRecipient);
$changedCommit=content2('crypto2.access.activate',['intentHash'=>$policyIntent['intentHash'],'affectedCount'=>2,'affectedHash'=>$policyIntent['affectedHash']],$bob,$bobKey);
deny(fn()=>call('crypto2.access.activate',$changedCommit,$bob),'crypto_access_consequences_changed','new child invitation cannot be silently cancelled under an old reviewed consequence snapshot');
ck(q('SELECT state FROM familyhub_crypto_invitations_v2 WHERE id=?',[$lateInvite['id']])[0]['state']==='pending','failed consequence CAS leaves new invitation and old access unchanged');
$lateCatalog=array_values(array_filter(call('crypto2.scopes.catalog',[],$bob)['scopes'],fn($s)=>$s['id']===$project['id']))[0];
send2('crypto2.invitations.revoke',['scopeId'=>$project['id'],'invitationId'=>$lateInvite['id'],'membershipHeadHash'=>$newHeads[$project['id']]['headHash'],'expectedAccessRevision'=>$lateCatalog['accessRevision'],'authorDirectoryHeadHash'=>$bobState['headHash']],$bob,$bobKey);

$policyHeads = [];
foreach ($newHeads as $scopeId => $source) {
    $pending = call('crypto2.access.pending', ['scopeId' => $scopeId], $bob)['intents'][0];
    $ownConsequences=call('crypto2.access.invitationConsequences',['scopeId'=>$scopeId,'intentHash'=>$policyIntent['intentHash']],$bob);
    ck($ownConsequences['invitationConsequences']===$pending['future']['invitationConsequences']&&count($ownConsequences['entries'])===1,'each manager reviews exact own invitation count and authorized ID stream before signing');
    $scope = array_values(array_filter(call('crypto2.scopes.catalog', [], $bob)['scopes'], fn($s) => $s['id'] === $scopeId))[0];
    $body = candidate2($scope, $bobState, 3, $source['headHash'], ['content' => hash('sha256', ''), 'finance' => hash('sha256', '')]);
    $body['accessBasis'] = $pending['accessBasis'];
    $body['accessRevision'] = $pending['future']['accessRevision'];
    $body['members'] = accessMembers2($pending['future']['members'], $actors);
    $body['accessIntentProof'] = inner2([
        'version' => 2,
        'operation' => 'crypto2.access.scopeConsent',
        'serverId' => $bob['serverId'],
        'scopeId' => $scopeId,
        'intentHash' => $policyIntent['intentHash'],
        'affectedCount' => 2,
        'affectedHash' => $policyIntent['affectedHash'],
        'previousHeadHash' => $source['headHash'],
        'expectedAccessRevision' => $pending['expectedAccessRevision'],
        'accessBasis' => $pending['accessBasis'],
        'resultingAccessRevision' => $body['accessRevision'],
        'resultingDescriptor' => $pending['future']['descriptor'],
        'resultingFinancePolicy' => $pending['future']['financePolicy'],
        'invitationConsequences' => $pending['future']['invitationConsequences'],
        'membersHash' => NativeCryptoV2Codec::hash($body['members']),
        'accountId' => $bob['user']['accountId'],
        'deviceId' => $bob['device']['id'],
        'authorDirectoryHeadHash' => $bobState['headHash'],
    ], "JivieE2EE/accessScopeConsent/v2\n", $bobKey);
    ck($pending['future']['descriptor']['accessPolicyVersion'] === 3, 'each own scope consent authenticates resulting policy descriptor');
    $put = send2('crypto2.scope.headPut', $body, $bob, $bobKey);
    $next = call('crypto2.scope.headGet', ['scopeId' => $scopeId, 'headHash' => $put['headHash']], $bob);
    $policyHeads[$scopeId] = $next;
    foreach (['content', 'finance'] as $domain) {
        close2($scopeId, $next['headHash'], $source, $domain, $bobState, 0, $bob, $bobKey);
    }
    foreach ($body['members'] as $member) {
        [$actor, $key, $root, $state] = $actors[$member['accountId']];
        accessGrants2($next, [$sourceHeads[$scopeId], $source, $next], $actor, $key, $root, $state, $bob, $bobKey);
    }
    $manifest = call('crypto2.grants.manifest', ['scopeId' => $scopeId, 'headHash' => $next['headHash']], $bob);
    $activation = content2('crypto2.scope.activate', [
        'scopeId' => $scopeId,
        'headHash' => $next['headHash'],
        'grantManifestHash' => $manifest['grantManifestHash'],
        'authorDirectoryHeadHash' => $bobState['headHash'],
        'accessIntentHash' => $policyIntent['intentHash'],
        'affectedCount' => 2,
        'affectedHash' => $policyIntent['affectedHash'],
    ], $bob, $bobKey);
    send2('crypto2.access.approve', ['intentHash' => $policyIntent['intentHash'], 'scopeId' => $scopeId, 'activationProof' => $activation], $bob, $bobKey);
}
ck(q('SELECT state FROM familyhub_crypto_invitations_v2 WHERE id=?', [$pendingInvite['id']])[0]['state'] === 'pending', 'even complete staged approvals cannot cancel invitations before atomic commit');
$commit = content2('crypto2.access.activate', ['intentHash' => $policyIntent['intentHash'], 'affectedCount' => 2, 'affectedHash' => $policyIntent['affectedHash']], $bob, $bobKey);
$applied = call('crypto2.access.activate', $commit, $bob);
ck($applied['state'] === 'applied' && call('crypto2.access.activate', $commit, $bob) === $applied, 'policy3 applies every head and SQL policy once with exact lost-ACK replay');
foreach ($policyHeads as $scopeId => $head) {
    ck(q('SELECT access_policy_version FROM familyhub_scopes WHERE id=?', [$scopeId])[0]['access_policy_version'] == 3 && call('crypto2.scope.headGet', ['scopeId' => $scopeId], $bob)['headHash'] === $head['headHash'], 'policy3 parent/child descriptor matches atomically activated head');
}
ck(q('SELECT state FROM familyhub_crypto_invitations_v2 WHERE id=?', [$pendingInvite['id']])[0]['state'] === 'revoked' && q('SELECT state FROM familyhub_crypto_invitations_v2 WHERE id=?', [$acceptedInvite['id']])[0]['state'] === 'revoked', 'policy3 revokes both pending and accepted-unconsumed invitations');
ck(q('SELECT state FROM familyhub_crypto_invitation_acceptances_v2 WHERE invitation_id=?', [$acceptedInvite['id']])[0]['state'] === 'revoked', 'policy3 removes pending capability without admitting a ghost SQL member');
ck(q('SELECT account_id FROM familyhub_members WHERE scope_id=? AND account_id=? AND active=1', [$project['id'], $acceptedRecipient['user']['accountId']]) === [], 'revoked accepted recipient never receives active project membership');
ck(call('crypto2.invitations.accept', $acceptedInvite['acceptance'], $acceptedRecipient) === $acceptedInvite['accepted'], 'immutable old acceptance ACK survives the policy cancellation without restoring authority');
ck(call('crypto2.invitations.create', $acceptedInvite['creation'], $bob) === $acceptedInvite['created'], 'immutable creator ACK remains byte exact after policy3 cancellation');

echo 'Crypto2 access policy integration: '.$checks.' checks PASS'.PHP_EOL;
