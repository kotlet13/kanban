<?php
require __DIR__.'/crypto2-creation-integration.php';

$target = $record;
$preview = call('crypto2.moderation.reportPreview', ['scopeId' => $newId, 'targetType' => 'record', 'targetId' => $target['id']], $fresh);
ck($preview['sourceContext']['recordProofHash'] !== null && $preview['evidenceTrust'] === 'reporterDisclosed' && !isset($preview['subject'], $preview['evidence']), 'crypto report preview supplies exact source evidence without server-decrypted disclosure');
q('UPDATE familyhub_scopes SET name=? WHERE id=?', ['UNSELECTED_SQL_SENTINEL', $newId]);
$source = $preview['sourceContext'];
$payload = [
    'reportId' => uid(),
    'sourceContext' => $source,
    'authorDirectoryHeadHash' => $state['headHash'],
    'consentVersion' => 1,
    'disclosure' => ['subject' => ['title' => 'Selected title', 'type' => 'task'], 'evidence' => ['title' => 'Selected title', 'notes' => 'Only reviewed text']],
    'reason' => 'other',
    'details' => 'Synthetic disclosure test',
];
// Reporting is a safety escape: neither a new verified-email requirement nor
// shared-upload policy acceptance may prevent reporting currently visible data.
q('DELETE FROM familyhub_policy_acceptances WHERE account_id=?', [$fresh['user']['accountId']]);
q('UPDATE familyhub_email_identities SET verified_at=NULL WHERE account_id=?', [$fresh['user']['accountId']]);
$request = content2('crypto2.moderation.report', $payload, $fresh, $freshKeys);
$receipt = call('crypto2.moderation.report', $request, $fresh);
ck($receipt['reportId'] === $payload['reportId'] && $receipt['status'] === 'submitted', 'unverified reader can submit exact reviewed report without accepting upload policy');
ck(call('crypto2.moderation.report', $request, $fresh) === $receipt, 'report lost ACK retains one immutable exact receipt');
$stored = q('SELECT snapshot,reason,details FROM familyhub_moderation_reports WHERE id=?', [$payload['reportId']])[0];
$snapshot = json_decode($stored['snapshot'], true);
ck($snapshot['evidence'] == $payload['disclosure']['evidence'] && !str_contains($stored['snapshot'], 'UNSELECTED_SQL_SENTINEL') && !str_contains($stored['snapshot'], $target['envelopeBase64']), 'administrator receives only user-selected plaintext and no unrelated SQL data or ciphertext dump');
ck($snapshot['evidenceTrust'] === 'reporterDisclosed' && $snapshot['sourceContext'] == $source, 'stored report clearly distinguishes source signature binding from reporter-disclosed plaintext correctness');
$proof = json_decode(q('SELECT authorization FROM familyhub_crypto_moderation_reports_v2 WHERE report_id=?', [$payload['reportId']])[0]['authorization'], true);
ck($proof === $request, 'report keeps the exact signed disclosure authorization');
q('UPDATE familyhub_email_identities SET verified_at=? WHERE account_id=?', [time(), $fresh['user']['accountId']]);
call('moderation.acceptPolicy', ['policyVersion' => 1], $fresh);
$advance = row2($newId, $head, $fresh, $freshKeys, $target['id'], 'task', 1, $source['recordProofHash']);
call('crypto2.records.batch', batch2([$advance], $fresh, $freshKeys), $fresh);
$stale = $payload;
$stale['reportId'] = uid();
deny(fn() => send2('crypto2.moderation.report', $stale, $fresh, $freshKeys), 'report_preview_changed', 'new report rejects a stale source revision after concurrent encrypted edit');
ck(call('crypto2.moderation.report', $request, $fresh) === $receipt, 'old successful report ACK survives a later target revision without a second disclosure');
ck(count(q('SELECT id FROM familyhub_moderation_reports WHERE reporter_account_id=?', [$fresh['user']['accountId']])) === 1, 'failed source CAS does not create a partial report or authorization');
deny(fn() => call('crypto2.moderation.reportPreview', ['scopeId' => $newId, 'targetType' => 'record', 'targetId' => $target['id']], $outsider), 'permission_revoked', 'report preview cannot inspect a scope outside current authorization');
deny(fn() => call('crypto2.moderation.reportPreview', ['scopeId' => $personal['id'], 'targetType' => 'record', 'targetId' => $target['id']], $fresh), 'personal_not_shareable', 'private personal sync is not silently disclosed through shared reporting');
$userPreview = call('crypto2.moderation.reportPreview', ['scopeId' => $newId, 'targetType' => 'user', 'targetId' => $fresh['user']['accountId']], $fresh);
ck($userPreview['sourceContext']['type'] === 'user' && $userPreview['sourceContext']['recordProofHash'] === null, 'visible member report binds exact scope access revision without inventing a record proof');

echo 'Crypto2 moderation integration: '.$checks.' checks PASS'.PHP_EOL;
