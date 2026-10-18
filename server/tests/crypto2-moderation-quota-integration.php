<?php
require __DIR__.'/crypto2-moderation-integration.php';

use Kanboard\Plugin\FamilyHub\Model\NativeModerationService;
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoMaintenanceLease;

$currentPreview = call('crypto2.moderation.reportPreview', ['scopeId' => $newId,'targetType' => 'record','targetId' => $target['id']], $fresh);
$stageIds = [];
$content = str_repeat(' ', 2097152);
$hash = hash('sha256', $content);
for ($index = 0; $index < 32; $index++) {
    $id = uid();
    $stageIds[] = $id;
    send2('crypto2.moderation.disclosure.begin', [
        'stageId' => $id,'reportId' => uid(),'sourceContext' => $currentPreview['sourceContext'],
        'authorDirectoryHeadHash' => $state['headHash'],'consentVersion' => 1,
        'kind' => 'snapshot','mime' => 'application/json','size' => 2097152,'sha256' => $hash,
    ], $fresh, $freshKeys);
    send2('crypto2.moderation.disclosure.chunk', ['stageId' => $id,'offset' => 0,'dataBase64' => base64_encode(substr($content, 0, 196608))], $fresh, $freshKeys);
}
$next = ['stageId' => uid(),'reportId' => uid(),'sourceContext' => $currentPreview['sourceContext'],
    'authorDirectoryHeadHash' => $state['headHash'],'consentVersion' => 1,
    'kind' => 'snapshot','mime' => 'application/json','size' => 2,'sha256' => hash('sha256', '{}')];
deny(fn() => send2('crypto2.moderation.disclosure.begin', $next, $fresh, $freshKeys), 'crypto_report_staging_limit', 'unfinished disclosure reservations enforce aggregate64MiB even before all bytes arrive');
q('UPDATE familyhub_crypto_moderation_stages_v2 SET expires_at=? WHERE account_id=? AND included=0', [time() - 1,$fresh['user']['accountId']]);
deny(fn() => send2('crypto2.moderation.disclosure.begin', $next, $fresh, $freshKeys), 'crypto_report_staging_limit', 'expiry and new IDs cannot release quota while disclosed orphan bytes remain stored');
$retention = new class($container) extends NativeModerationService {
    public function syntheticAccount($account)
    {
        $lease = NativeCryptoMaintenanceLease::acquire(true);
        return $this->transaction(fn () => $this->purgeReportsInTransaction($account), true);
    }
};
$retention->syntheticAccount($fresh['user']['accountId']);
ck(q('SELECT c.stage_id FROM familyhub_crypto_moderation_chunks_v2 c JOIN familyhub_crypto_moderation_stages_v2 s ON s.id=c.stage_id WHERE s.account_id=?', [$fresh['user']['accountId']]) === [], 'scoped orphan purge actually removes uploaded bytes before releasing their reservation');
ck(send2('crypto2.moderation.disclosure.begin', $next, $fresh, $freshKeys)['received'] === 0, 'fresh explicit upload can use quota only after orphan redaction');

echo 'Crypto2 moderation staging quota integration: '.$checks.' checks PASS'.PHP_EOL;
