<?php
require __DIR__.'/crypto2-moderation-integration.php';

use Kanboard\Plugin\FamilyHub\Model\NativeCryptoCodec;
use Kanboard\Plugin\FamilyHub\Model\NativeModerationService;
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoMaintenanceLease;

$freshPreview = call('crypto2.moderation.reportPreview', ['scopeId' => $newId,'targetType' => 'record','targetId' => $target['id']], $fresh);
$largeDisclosure = ['subject' => ['title' => 'Selected large report','type' => 'task'],
    'evidence' => ['notes' => str_repeat('LARGE_SELECTED_RETENTION_SENTINEL ', 9000)]];
$bytes = json_encode($largeDisclosure, JSON_THROW_ON_ERROR);
$stageId = uid();
$reportId = uid();
$begin = content2('crypto2.moderation.disclosure.begin', [
    'stageId' => $stageId,'reportId' => $reportId,'sourceContext' => $freshPreview['sourceContext'],
    'authorDirectoryHeadHash' => $state['headHash'],'consentVersion' => 1,
    'kind' => 'snapshot','mime' => 'application/json','size' => strlen($bytes),'sha256' => hash('sha256', $bytes),
], $fresh, $freshKeys);
$begun = call('crypto2.moderation.disclosure.begin', $begin, $fresh);
ck(call('crypto2.moderation.disclosure.begin', $begin, $fresh) === $begun, 'reviewed disclosure staging begin lost ACK preserves original expiry');
deny(fn() => call('crypto2.moderation.disclosure.status', ['stageId' => $stageId], $outsider), 'permission_revoked', 'report staging is private to its explicit reporter');
deny(fn() => send2('crypto2.moderation.disclosure.complete', ['stageId' => $stageId], $fresh, $freshKeys), 'crypto_report_disclosure_incomplete', 'selected snapshot cannot complete with missing bytes');
$first = null;
for ($offset = 0; $offset < strlen($bytes); $offset += 196608) {
    $chunk = content2('crypto2.moderation.disclosure.chunk', ['stageId' => $stageId,'offset' => $offset,
        'dataBase64' => base64_encode(substr($bytes, $offset, 196608))], $fresh, $freshKeys);
    $ack = call('crypto2.moderation.disclosure.chunk', $chunk, $fresh);
    if ($first === null) {
        $first = $chunk;
        ck(call('crypto2.moderation.disclosure.chunk', $chunk, $fresh) === $ack, 'selected snapshot chunk exact retry does not duplicate disclosed bytes');
    }
}
ck(send2('crypto2.moderation.disclosure.complete', ['stageId' => $stageId], $fresh, $freshKeys)['complete'], 'bounded multi-chunk selected snapshot verifies its exact full hash');
$largePayload = $payload;
$largePayload['reportId'] = $reportId;
$largePayload['sourceContext'] = $freshPreview['sourceContext'];
$largePayload['disclosure'] = null;
$largePayload['snapshotStageId'] = $stageId;
$largePayload['assetStageIds'] = [];
$largeRequest = content2('crypto2.moderation.report', $largePayload, $fresh, $freshKeys);
$largeReceipt = call('crypto2.moderation.report', $largeRequest, $fresh);
ck(str_contains(q('SELECT snapshot FROM familyhub_moderation_reports WHERE id=?', [$reportId])[0]['snapshot'], 'LARGE_SELECTED_RETENTION_SENTINEL'), 'administrator snapshot contains exactly the reviewed staged text');
deny(fn() => send2('crypto2.moderation.disclosure.abort', ['stageId' => $stageId], $fresh, $freshKeys), 'crypto_report_evidence_retained', 'included evidence cannot evade report retention through upload abort');
[$largeCommand,$largeRaw] = NativeCryptoCodec::decode($largeRequest);
$digestReceipt = call('crypto2.receipt.get', ['requestId' => $largeCommand['requestId'],'requestHash' => hash('sha256', $largeRaw)], $fresh);
ck($digestReceipt['authorization']['format'] === 'moderationReceiptDigest2' && !isset($digestReceipt['authorization']['commandBase64']), 'generic receipt never retains another plaintext disclosure command copy');

$orphanId = uid();
$orphanBytes = 'ORPHAN_SELECTED_SENTINEL';
$orphanBegin = content2('crypto2.moderation.disclosure.begin', [
    'stageId' => $orphanId,'reportId' => uid(),'sourceContext' => $freshPreview['sourceContext'],
    'authorDirectoryHeadHash' => $state['headHash'],'consentVersion' => 1,
    'kind' => 'snapshot','mime' => 'application/json','size' => strlen($orphanBytes),'sha256' => hash('sha256', $orphanBytes),
], $fresh, $freshKeys);
call('crypto2.moderation.disclosure.begin', $orphanBegin, $fresh);
send2('crypto2.moderation.disclosure.chunk', ['stageId' => $orphanId,'offset' => 0,'dataBase64' => base64_encode($orphanBytes)], $fresh, $freshKeys);
q('UPDATE familyhub_crypto_moderation_stages_v2 SET expires_at=? WHERE id=?', [time() - 1,$orphanId]);
q("UPDATE familyhub_moderation_reports SET status='resolved',resolved_at=? WHERE reporter_account_id=?", [time() - 181 * 86400,$fresh['user']['accountId']]);
q('INSERT INTO familyhub_moderation_audit VALUES(?,?,?,?,?,?,?)', [uid(),$payload['reportId'],$fresh['user']['id'],'resolved','AUDIT_SELECTED_SENTINEL',time() - 181 * 86400,1]);

// Exercise the exact worker retention body under its maintenance/global-lock
// contract, scoped only to this synthetic reporter. Other fixtures are untouched.
$retention = new class($container) extends NativeModerationService {
    public function syntheticAccount($account)
    {
        $lease = NativeCryptoMaintenanceLease::acquire(true);
        return $this->transaction(fn () => $this->purgeReportsInTransaction($account), true);
    }
};
ck($retention->syntheticAccount($fresh['user']['accountId']) === 2, '180-day resolved policy redacts both reviewed report snapshots');
$retained = q('SELECT snapshot,details FROM familyhub_moderation_reports WHERE reporter_account_id=?', [$fresh['user']['accountId']]);
ck(count(array_filter($retained, fn($r) => $r['snapshot'] !== null || $r['details'] !== null)) === 0, 'resolved snapshot and report details no longer remain in active report storage');
ck(q('SELECT stage_id FROM familyhub_crypto_moderation_chunks_v2 WHERE stage_id IN (?,?)', [$stageId,$orphanId]) === [], 'retention removes included disclosure chunks and expired orphan bytes');
$proofRows = q('SELECT authorization FROM familyhub_crypto_moderation_reports_v2 WHERE account_id=?', [$fresh['user']['accountId']]);
ck(count(array_filter($proofRows, fn($r) => isset(json_decode($r['authorization'], true)['commandBase64']))) === 0, 'moderation proof table does not retain expired selected plaintext command bodies');
ck(q('SELECT note FROM familyhub_moderation_audit WHERE report_id=?', [$payload['reportId']])[0]['note'] === '[Retention expired]', 'retention removes copied selected material from administrator audit notes');
ck(call('crypto2.moderation.report', $request, $fresh) === $receipt && call('crypto2.moderation.report', $largeRequest, $fresh) === $largeReceipt, 'exact old report ACKs remain unchanged after active-store redaction');
[$changedBody] = NativeCryptoCodec::decode($request);
$changedBody['payload']['details'] = 'Changed after retention';
deny(fn() => call('crypto2.moderation.report', inner2($changedBody, "JivieE2EE/v2\n", $freshKeys), $fresh), 'idempotency_mismatch', 'changed original body cannot use digest-only receipt after redaction');
ck(call('crypto2.moderation.disclosure.chunk', $first, $fresh)['received'] === 196608, 'old chunk ACK remains exact after its disclosed bytes are removed');

echo 'Crypto2 moderation retention integration: '.$checks.' checks PASS'.PHP_EOL;
