<?php
require __DIR__.'/crypto2-access-integration.php';
require __DIR__.'/crypto2-record-helpers.php';

use Kanboard\Plugin\FamilyHub\Model\NativeCryptoCodec;
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoV2Codec;

$standalone = scope($bob, 'project', 2);
$scopeId = $standalone['id'];
$initial = accessInitial2($scopeId, $bob, $bobKey, $bobState, $actors);
$synthetic = uid();
q('INSERT INTO familyhub_crypto_migrations_v2 VALUES(?,?,?,?,?,?,?,?,?)', [$synthetic, uid(), hash('sha256', 'synthetic project component'), json_encode([$scopeId]), hash('sha256', 'synthetic participants'), 'committed', hash('sha256', 'synthetic challenge'), time(), time()]);
q("UPDATE familyhub_crypto_scopes SET state='active',migration_id=? WHERE scope_id=?", [$synthetic, $scopeId]);
$scope = array_values(array_filter(call('crypto2.scopes.catalog', [], $bob)['scopes'], fn($s) => $s['id'] === $scopeId))[0];
$payload = [
    'scopeId' => $scopeId,
    'membershipHeadHash' => $initial['headHash'],
    'expectedAccessRevision' => $scope['accessRevision'],
    'authorDirectoryHeadHash' => $bobState['headHash'],
    'action' => ['kind' => 'accessPolicy', 'targetVersion' => 3],
];
deny(fn() => send2('crypto2.access.prepare', $payload, $bob, $bobKey), 'project_scope_requires_single_root', 'standalone project policy3 refuses absent canonical project root');
$projectRecord = row2($scopeId, $initial, $bob, $bobKey, null, 'project');
$otherProject = row2($scopeId, $initial, $bob, $bobKey, null, 'project');
$created = call('crypto2.records.batch', batch2([$projectRecord, $otherProject], $bob, $bobKey), $bob);
deny(fn() => send2('crypto2.access.prepare', $payload, $bob, $bobKey), 'project_scope_requires_single_root', 'standalone project policy3 refuses multiple live project roots');
$removeOther = row2($scopeId, $initial, $bob, $bobKey, $otherProject['id'], 'project', 1, $created['records'][1]['recordProofHash'], [], [], true);
call('crypto2.records.batch', batch2([$removeOther], $bob, $bobKey), $bob);
$unrelated = row2($scopeId, $initial, $bob, $bobKey);
$taskAck = call('crypto2.records.batch', batch2([$unrelated], $bob, $bobKey), $bob);
deny(fn() => send2('crypto2.access.prepare', $payload, $bob, $bobKey), 'project_scope_unrelated_content', 'standalone project policy3 refuses a task without signed exact root reference');
$linked = row2($scopeId, $initial, $bob, $bobKey, $unrelated['id'], 'task', 1, $taskAck['records'][0]['recordProofHash'], [['scopeId' => $scopeId, 'id' => $projectRecord['id']]]);
call('crypto2.records.batch', batch2([$linked], $bob, $bobKey), $bob);
$pageTasks = [];
for ($index = 0; $index < 21; $index++) {
    $pageTasks[] = row2($scopeId, $initial, $bob, $bobKey, null, 'task', 0, null, [['scopeId' => $scopeId, 'id' => $projectRecord['id']]]);
}
call('crypto2.records.batch', batch2($pageTasks, $bob, $bobKey), $bob);
$canonical = $projectRecord['metadata']['identity']['canonicalId'];
q('UPDATE familyhub_scopes SET project_root_id=? WHERE id=?', [uid(), $scopeId]);
deny(fn() => send2('crypto2.access.prepare', $payload, $bob, $bobKey), 'project_scope_root_changed', 'standalone project policy3 cannot silently replace an existing canonical root');
q('UPDATE familyhub_scopes SET project_root_id=NULL WHERE id=?', [$scopeId]);
$intent = send2('crypto2.access.prepare', $payload, $bob, $bobKey);
$pending = call('crypto2.access.pending', ['scopeId' => $scopeId], $bob)['intents'][0];
ck(q('SELECT project_root_id FROM familyhub_scopes WHERE id=?', [$scopeId])[0]['project_root_id'] === null, 'project preview validates the encrypted graph without changing live root metadata');
$inventory = call('crypto2.domain.inventory', ['scopeId' => $scopeId, 'domain' => 'content', 'accessRevision' => $scope['accessRevision']], $bob);
$context = hash_init('sha256');
foreach ($inventory['descriptors'] as $descriptor) {
    hash_update($context, NativeCryptoCodec::canonical((object)$descriptor)."\n");
}
$contentHash = hash_final($context);
$body = candidate2($scope, $bobState, 2, $initial['headHash'], ['content' => $contentHash, 'finance' => hash('sha256', '')]);
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
        'invitationConsequences' => $pending['future']['invitationConsequences'],
    'membersHash' => NativeCryptoV2Codec::hash($body['members']),
    'accountId' => $bob['user']['accountId'],
    'deviceId' => $bob['device']['id'],
    'authorDirectoryHeadHash' => $bobState['headHash'],
], "JivieE2EE/accessScopeConsent/v2\n", $bobKey);
$put = send2('crypto2.scope.headPut', $body, $bob, $bobKey);
$next = call('crypto2.scope.headGet', ['scopeId' => $scopeId, 'headHash' => $put['headHash']], $bob);
send2('crypto2.scope.closeDomain', [
    'scopeId' => $scopeId,
    'candidateHeadHash' => $next['headHash'],
    'domain' => 'content',
    'epoch' => 1,
    'membershipHeadHash' => $initial['headHash'],
    'authorDirectoryHeadHash' => $bobState['headHash'],
    'expectedSequence' => $inventory['scopeSequence'],
    'recordCount' => count($inventory['descriptors']),
    'manifestHash' => $contentHash,
    'historyBasis' => 'reviewedRecoveryBaseline',
], $bob, $bobKey);
close2($scopeId, $next['headHash'], $initial, 'finance', $bobState, 0, $bob, $bobKey);
accessGrants2($next, [$initial, $next], $bob, $bobKey, $bobRoot, $bobState, $bob, $bobKey);
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
$applied = send2('crypto2.access.activate', ['intentHash' => $intent['intentHash'], 'affectedCount' => 1, 'affectedHash' => $intent['affectedHash']], $bob, $bobKey);
ck($applied['state'] === 'applied' && q('SELECT project_root_id FROM familyhub_scopes WHERE id=?', [$scopeId])[0]['project_root_id'] === $canonical, 'project policy3 commit preserves original canonical root while storage remains mapped wire UUID');
ck(call('crypto2.scope.headGet', ['scopeId' => $scopeId], $bob)['headHash'] === $next['headHash'], 'exact project graph closure is bound to the activated policy head');
ck(count($inventory['descriptors']) > 20 && count(q('SELECT id FROM familyhub_crypto_closure_records WHERE scope_id=? AND candidate_head_hash=? AND domain=?', [$scopeId, $next['headHash'], 'content'])) === count($inventory['descriptors']), 'nonempty closure crosses keyset page boundary without active MySQL SELECT or omitted descriptors');

echo 'Crypto2 project access policy integration: '.$checks.' checks PASS'.PHP_EOL;
