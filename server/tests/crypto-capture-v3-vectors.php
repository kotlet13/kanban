<?php
/** Pure, synthetic cross-language capture3 commitment and sidecar checks. */
require '/var/www/app/app/common.php';
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoCaptureV3;
use Kanboard\Plugin\FamilyHub\Model\NativeError;
$fixture = json_decode(file_get_contents(__DIR__.'/fixtures/e2ee-capture-v3.json'), true, 64, JSON_THROW_ON_ERROR);
$context = $fixture['context'];
$row = json_decode(json_encode($fixture['typedRow'], JSON_THROW_ON_ERROR), false, 64, JSON_THROW_ON_ERROR);
$binding = $fixture['binding'];
$header = array_intersect_key($context, array_flip(['version','serverId','captureId','migrationId','accountId']));
$checks = 0;
$check = function ($ok, $label) use (&$checks) {
    if (!$ok) { throw new RuntimeException('FAIL: '.$label); }
    $checks++;
};
$deny = function ($callback) use ($check) {
    try { $callback(); $ok=false; } catch (NativeError $e) { $ok=true; }
    $check($ok, 'reject invalid candidate');
};
$salt = hash_hmac('sha256', "JivieCaptureSalt/v3\n".\Kanboard\Plugin\FamilyHub\Model\NativeCryptoCodec::canonical((object)$context), base64_decode($fixture['keyBase64']), true);
$check(base64_encode($salt) === $fixture['saltBase64'], 'HMAC salt golden');
$id = substr(hash_hmac('sha256', "JivieCaptureBindingId/v3\n".\Kanboard\Plugin\FamilyHub\Model\NativeCryptoCodec::canonical((object)$context), base64_decode($fixture['keyBase64']), true), 0, 16);
$id[6] = chr((ord($id[6]) & 15) | 64);
$id[8] = chr((ord($id[8]) & 63) | 128);
$hex = bin2hex($id);
$uuid = substr($hex,0,8).'-'.substr($hex,8,4).'-'.substr($hex,12,4).'-'.substr($hex,16,4).'-'.substr($hex,20);
$check($uuid === $fixture['bindingId'], 'separate HMAC binding ID golden');
$check(NativeCryptoCaptureV3::sourceCommitment($context,$salt,$row) === $binding['sourceCommitment'], 'source golden');
$check(NativeCryptoCaptureV3::inventoryRoot($header+['sourceCount'=>1],[$binding]) === $fixture['inventoryRoot'], 'inventory golden');
$check(NativeCryptoCaptureV3::inventoryRoot($header+['sourceCount'=>0],[]) === $fixture['emptyInventoryRoot'], 'empty inventory golden');
$secret = ['bindingId'=>$binding['bindingId'],'sourceTable'=>$context['sourceTable'],'sourceId'=>$context['sourceId'],'saltBase64'=>$fixture['saltBase64']];
$verified=NativeCryptoCaptureV3::verifyBindings($header,[$binding],[$secret],fn($c)=>$row);
$check(count($verified)===1 && !str_contains(json_encode($verified),$fixture['saltBase64']), 'sidecar never returned');
$deny(fn()=>NativeCryptoCaptureV3::verifyBindings($header,[$binding],[],fn($c)=>$row));
$deny(fn()=>NativeCryptoCaptureV3::verifyBindings($header,[$binding],[$secret,$secret],fn($c)=>$row));
$deny(fn()=>NativeCryptoCaptureV3::verifyBindings($header,[$binding],[$secret+['rawHash'=>'forbidden']],fn($c)=>$row));
$deny(fn()=>NativeCryptoCaptureV3::verifyBindings($header,[$binding],[$secret],fn($c)=>(object)['changed'=>true]));
$deny(fn()=>NativeCryptoCaptureV3::inventoryRoot($header+['sourceCount'=>2],[$binding]));
$deny(fn()=>NativeCryptoCaptureV3::inventoryRoot($header+['sourceCount'=>2],[$binding,$binding]));
$deny(fn()=>NativeCryptoCaptureV3::context(array_replace($context,['version'=>2])));
sodium_memzero($salt);
echo 'capture3 vectors PASS '.$checks.PHP_EOL;
