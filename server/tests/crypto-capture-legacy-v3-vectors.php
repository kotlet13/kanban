<?php
/** Independent Python byte fixture; no live account or user data. */
require '/var/www/app/app/common.php';
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoCaptureLegacyV3 as Legacy;
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoCaptureV3 as Capture;
use Kanboard\Plugin\FamilyHub\Model\NativeError;
$f = json_decode(file_get_contents(__DIR__.'/fixtures/e2ee-capture-legacy-v3.json'), true, 64, JSON_THROW_ON_ERROR);
$checks = 0;
$check = function ($ok) use (&$checks) {
    if (!$ok) throw new RuntimeException('capture legacy golden failed');
    $checks++;
};
$deny = function ($call) use ($check) {
    try { $call(); $ok = false; } catch (NativeError $e) { $ok = true; }
    $check($ok);
};
$check(Legacy::root($f['header'], [$f['descriptor']]) === $f['root']);
$check(Legacy::root(array_replace($f['header'], ['receiptCount' => 0]), []) === $f['emptyRoot']);
$check(Legacy::scopeToken($f['header']) === $f['scopeToken']);
$check(Legacy::selectionHash($f['selectionContext']) === $f['header']['receiptSelectionHash']);
$row = json_decode(json_encode($f['witness']['typedRow']), false, 64, JSON_THROW_ON_ERROR);
$check(Capture::sourceCommitment($f['context'], base64_decode($f['witness']['saltBase64']), $row) === $f['descriptor']['sourceCommitment']);
$deny(fn() => Legacy::root($f['header'], []));
$deny(fn() => Legacy::root(array_replace($f['header'], ['receiptCount' => 2]), [$f['descriptor'], $f['descriptor']]));
$deny(fn() => Legacy::root(array_replace($f['header'], ['domain' => 'finance']), [$f['descriptor']]));
$deny(fn() => Legacy::descriptor(array_replace($f['descriptor'], ['receiptKind' => 'unknown'])));
$deny(fn() => Legacy::descriptor(array_replace($f['descriptor'], ['legacyDeviceId' => $f['context']['accountId']])));
$deny(fn() => Legacy::header(array_replace($f['header'], ['captureVersion' => 2])));
$deny(fn() => Legacy::selectionHash(array_replace($f['selectionContext'], ['receiptSelections' => array_merge($f['selectionContext']['receiptSelections'], $f['selectionContext']['receiptSelections'])])));
echo 'capture legacy vectors PASS '.$checks.PHP_EOL;
