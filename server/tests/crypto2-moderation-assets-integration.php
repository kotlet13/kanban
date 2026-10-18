<?php
require __DIR__.'/crypto2-moderation-integration.php';

use Kanboard\Plugin\FamilyHub\Model\NativeModerationAdminService;

$idea = row2($newId, $head, $fresh, $freshKeys, null, 'idea');
call('crypto2.records.batch', batch2([$idea], $fresh, $freshKeys), $fresh);
$ideaPreview = call('crypto2.moderation.reportPreview', ['scopeId' => $newId,'targetType' => 'record','targetId' => $idea['id']], $fresh);
$canvas = imagecreatetruecolor(1, 1);
ob_start();
imagepng($canvas);
$png = ob_get_clean();
imagedestroy($canvas);
$descriptor = ['sha256' => hash('sha256', $png),'mime' => 'image/png','size' => strlen($png),'width' => 1,'height' => 1];
$imageStage = uid();
$imageReport = uid();
send2('crypto2.moderation.disclosure.begin', ['stageId' => $imageStage,'reportId' => $imageReport,
    'sourceContext' => $ideaPreview['sourceContext'],'authorDirectoryHeadHash' => $state['headHash'],
    'consentVersion' => 1,'kind' => 'asset','mime' => 'image/png','size' => strlen($png),'sha256' => $descriptor['sha256']], $fresh, $freshKeys);
send2('crypto2.moderation.disclosure.chunk', ['stageId' => $imageStage,'offset' => 0,'dataBase64' => base64_encode($png)], $fresh, $freshKeys);
ck(send2('crypto2.moderation.disclosure.complete', ['stageId' => $imageStage], $fresh, $freshKeys)['complete'], 'selected PNG is validated independently of ordinary encrypted attachment storage');
$polyglot = $png.'<script>not a normalized image</script>';
$badStage = uid();
send2('crypto2.moderation.disclosure.begin', ['stageId' => $badStage,'reportId' => uid(),
    'sourceContext' => $ideaPreview['sourceContext'],'authorDirectoryHeadHash' => $state['headHash'],
    'consentVersion' => 1,'kind' => 'asset','mime' => 'image/png','size' => strlen($polyglot),'sha256' => hash('sha256', $polyglot)], $fresh, $freshKeys);
send2('crypto2.moderation.disclosure.chunk', ['stageId' => $badStage,'offset' => 0,'dataBase64' => base64_encode($polyglot)], $fresh, $freshKeys);
deny(fn() => send2('crypto2.moderation.disclosure.complete', ['stageId' => $badStage], $fresh, $freshKeys), 'asset_integrity', 'explicit report image still rejects appended polyglot bytes before administrator rendering');
$board = ['version' => 2,'id' => $idea['metadata']['identity']['canonicalId'],'title' => 'Selected board','projectId' => null,
    'width' => 640,'height' => 480,'elements' => [[
        'id' => uid(),'kind' => 'image','x' => 10,'y' => 10,'width' => 100,'height' => 100,'rotation' => 0,
        'color' => 4294967295,'strokeWidth' => 1,'text' => '', 'points' => [],'parentImageId' => null,'asset' => $descriptor,'fontSize' => 14,
    ]],'revision' => 1,'createdAt' => '2026-10-17T10:00:00Z','updatedAt' => '2026-10-17T10:00:00Z','archived' => false];
$imagePayload = ['reportId' => $imageReport,'sourceContext' => $ideaPreview['sourceContext'],
    'authorDirectoryHeadHash' => $state['headHash'],'consentVersion' => 1,
    'disclosure' => ['subject' => ['title' => 'Selected board','type' => 'idea'],'evidence' => ['board' => $board,'assets' => [$descriptor]]],
    'assetStageIds' => [$imageStage],'reason' => 'other','details' => 'Synthetic reviewed selected image'];
$missingAsset = $imagePayload;
$missingAsset['assetStageIds'] = [];
deny(fn() => send2('crypto2.moderation.report', $missingAsset, $fresh, $freshKeys), 'crypto_report_assets_changed', 'report cannot silently omit a selected displayed image');
$imageRequest = content2('crypto2.moderation.report', $imagePayload, $fresh, $freshKeys);
$imageReceipt = call('crypto2.moderation.report', $imageRequest, $fresh);
ck($imageReceipt['reportId'] === $imageReport, 'signed report atomically retains its exact reviewed image and board');
$adminId = $container['userModel']->create(['username' => $prefix.'_moderator','password' => bin2hex(random_bytes(20)),'role' => 'app-admin']);
$admin = new NativeModerationAdminService($container);
ck($admin->asset($adminId, $imageReport, $descriptor['sha256'])['bytes'] === $png, 'administrator can fetch only the selected retained full image');
deny(fn() => $admin->asset($fresh['user']['id'], $imageReport, $descriptor['sha256']), 'permission_revoked', 'native reporter bearer cannot gain web administrator asset privileges');
deny(fn() => $admin->asset($adminId, $imageReport, str_repeat('a', 64)), 'report_target_unavailable', 'administrator cannot use report asset route for an unselected source image');
ck($admin->board($adminId, $imageReport)['mime'] === 'image/png', 'administrator renders the bounded disclosed board with its selected image');
$review = $admin->review($adminId, ['reportId' => $imageReport,'reviewRevision' => 0,'targetRevision' => 1,'action' => 'resolved','note' => 'Reviewed selected evidence']);
ck($review['status'] === 'resolved', 'administrator can resolve already disclosed encrypted-source report without a plaintext scope bypass');

echo 'Crypto2 moderation selected assets integration: '.$checks.' checks PASS'.PHP_EOL;
