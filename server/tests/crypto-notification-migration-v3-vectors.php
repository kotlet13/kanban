<?php
require '/var/www/app/app/common.php';
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoMigrationNotificationV3 as N;
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoCodec;
use Kanboard\Plugin\FamilyHub\Model\NativeError;
$n = 0;
$check = function ($ok) use (&$n) { if (!$ok) throw new RuntimeException('notification migration3 vector'); $n++; };
$deny = function ($fn) use ($check) { try { $fn(); $ok = false; } catch (NativeError $e) { $ok = true; } $check($ok); };
$header = ['version'=>3,'serverId'=>'11111111-1111-4111-8111-111111111111',
    'migrationId'=>'22222222-2222-4222-8222-222222222222',
    'captureId'=>'33333333-3333-4333-8333-333333333333',
    'accountId'=>'44444444-4444-4444-8444-444444444444',
    'sourceInventoryRoot'=>str_repeat('a',64),'archiveManifestHash'=>str_repeat('b',64),
    'coldParityProofHash'=>str_repeat('c',64),'authorDirectoryHeadHash'=>str_repeat('d',64),
    'transformCount'=>2,'sourceCounts'=>['reminder'=>1,'inbox'=>1,'preference'=>0,'inboxState'=>0],
    'transformRoot'=>str_repeat('0',64)];
$leaves = [
    ['bindingId'=>'55555555-5555-4555-8555-555555555555','kind'=>'reminder','transformHash'=>str_repeat('e',64),'useProofHash'=>str_repeat('f',64)],
    ['bindingId'=>'66666666-6666-4666-8666-666666666666','kind'=>'inbox','transformHash'=>str_repeat('1',64),'useProofHash'=>null],
];
$hashes = array_map(fn($leaf)=>N::leafDigest($leaf),$leaves); sort($hashes,SORT_STRING);
$vector = json_decode(file_get_contents(__DIR__.'/fixtures/e2ee-notification-migration-v3.json'),true,34,JSON_THROW_ON_ERROR);
$context = $vector['selectionContext'];
$check(N::selectionRoot($context,2,$vector['leafDigests']) === $vector['selectionRoot']);
$check(N::selectionRoot($context,0,[]) === $vector['emptySelectionRoot']);
$deny(fn()=>N::selectionRoot($context,2,[$vector['leafDigests'][0]]));
$deny(fn()=>N::selectionRoot($context,2,array_reverse($vector['leafDigests'])));
$deny(fn()=>N::selectionRoot($context,2,[$vector['leafDigests'][0],$vector['leafDigests'][0]]));
$check(N::selectionRoot(array_replace($context,['sourceInventoryRoot'=>str_repeat('f',64)]),2,$vector['leafDigests']) !== $vector['selectionRoot']);
$root = N::transformRoot($header,$hashes);
$check(strlen($root)===64 && N::transformRoot(array_replace($header,['transformRoot'=>$root]),$hashes)===$root);
$check(N::scopeToken($header)!==N::scopeToken(array_replace($header,['accountId'=>'77777777-7777-4777-8777-777777777777'])));
$deny(fn()=>N::transformRoot($header,[$hashes[0]]));
$deny(fn()=>N::transformRoot($header,array_reverse($hashes)));
$deny(fn()=>N::transformRoot($header,[$hashes[0],$hashes[0]]));
$deny(fn()=>N::header(array_replace($header,['sourceCounts'=>['reminder'=>1,'inbox'=>0,'preference'=>0,'inboxState'=>0]])));
$deny(fn()=>N::leafDigest(array_replace($leaves[0],['kind'=>'preference'])));
$keys=sodium_crypto_sign_seed_keypair(str_repeat("\x42",32));
$body=['version'=>3,'operation'=>'crypto2.migration.notificationTransform',
    'serverId'=>$header['serverId'],'accountId'=>$header['accountId'],
    'migrationId'=>$header['migrationId'],'captureId'=>$header['captureId'],
    'sourceInventoryRoot'=>$header['sourceInventoryRoot'],'bindingId'=>$leaves[0]['bindingId'],
    'kind'=>'reminder','canonical'=>['state'=>'delivered'],'deviceId'=>'88888888-8888-4888-8888-888888888888',
    'authorDirectoryHeadHash'=>$header['authorDirectoryHeadHash'],'useAuthorization'=>null];
$bytes=NativeCryptoCodec::canonical((object)$body);
$proof=['commandBase64'=>base64_encode($bytes),'signatureBase64'=>base64_encode(sodium_crypto_sign_detached("JivieE2EE/notificationTransform/v3\n".$bytes,sodium_crypto_sign_secretkey($keys)))];
$public=base64_encode(sodium_crypto_sign_publickey($keys));
$resolve=function($account,$directory,$device)use($header,$body,$public){if($account!==$header['accountId']||$directory!==$header['authorDirectoryHeadHash']||$device!==$body['deviceId'])throw new NativeError('crypto_transform_signer');return $public;};
$check(strlen(N::transformHash($proof,$header,$leaves[0]['bindingId'],'reminder',$resolve))===64);
$deny(fn()=>N::transformHash($proof,array_replace($header,['accountId'=>'77777777-7777-4777-8777-777777777777']),$leaves[0]['bindingId'],'reminder',$resolve));
$deny(fn()=>N::transformHash($proof,$header,$leaves[1]['bindingId'],'reminder',$resolve));
$deny(fn()=>N::transformHash($proof,$header,$leaves[0]['bindingId'],'inbox',$resolve));
$bad=$proof; $bad['signatureBase64']=base64_encode(str_repeat("\0",64));
$deny(fn()=>N::transformHash($bad,$header,$leaves[0]['bindingId'],'reminder',$resolve));
$wrongKeys=sodium_crypto_sign_seed_keypair(str_repeat("\x43",32));
$deny(fn()=>N::transformHash($proof,$header,$leaves[0]['bindingId'],'reminder',fn()=>base64_encode(sodium_crypto_sign_publickey($wrongKeys))));
$deny(fn()=>N::transformHash($proof,$header,$leaves[0]['bindingId'],'reminder',function(){throw new NativeError('crypto_transform_revoked');}));
$other=$body;$other['authorDirectoryHeadHash']=str_repeat('2',64);$otherBytes=NativeCryptoCodec::canonical((object)$other);$otherProof=['commandBase64'=>base64_encode($otherBytes),'signatureBase64'=>base64_encode(sodium_crypto_sign_detached("JivieE2EE/notificationTransform/v3\n".$otherBytes,sodium_crypto_sign_secretkey($keys)))];
$deny(fn()=>N::transformHash($otherProof,$header,$leaves[0]['bindingId'],'reminder',$resolve));
echo 'Notification migration3 vectors '.$n.' PASS'.PHP_EOL;
