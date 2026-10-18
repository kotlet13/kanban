<?php
/** Standalone deterministic interoperability vector, no database or live credentials. */
$models=is_dir('/var/www/app/plugins/FamilyHub')?'/var/www/app/plugins/FamilyHub/Model':__DIR__.'/../plugins/FamilyHub/Model';
require $models.'/NativeError.php';
require $models.'/NativeCryptoCodec.php';
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoCodec;
use Kanboard\Plugin\FamilyHub\Model\NativeError;
$seed=hex2bin('9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60');
$key=sodium_crypto_sign_seed_keypair($seed);
$command=(object)['version'=>1,'operation'=>'crypto.test.vector','requestId'=>'00000000-0000-4000-8000-000000000001','serverId'=>'00000000-0000-4000-8000-000000000002','accountId'=>'00000000-0000-4000-8000-000000000003','deviceId'=>'00000000-0000-4000-8000-000000000004','signer'=>'device','payload'=>(object)['text'=>"Šifriranje / 👋\u{2028}",'flag'=>false,'count'=>1,'empty'=>(object)[],'list'=>[]]];
$bytes=NativeCryptoCodec::canonical($command);$signature=sodium_crypto_sign_detached(NativeCryptoCodec::DOMAIN.$bytes,sodium_crypto_sign_secretkey($key));
$vector=['purpose'=>'Public synthetic interoperability vector; RFC8032 test seed, never a real account key','seedBase64'=>base64_encode($seed),'publicKeyBase64'=>base64_encode(sodium_crypto_sign_publickey($key)),'domainBase64'=>base64_encode(NativeCryptoCodec::DOMAIN),'commandBase64'=>base64_encode($bytes),'signatureBase64'=>base64_encode($signature),'sha256'=>hash('sha256',$bytes)];
if(($argv[1]??'')==='--emit'){echo json_encode($vector,JSON_PRETTY_PRINT|JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES|JSON_THROW_ON_ERROR).PHP_EOL;exit;}
$expected=json_decode(file_get_contents(__DIR__.'/fixtures/e2ee-command-v1.json'),true,34,JSON_THROW_ON_ERROR);if($expected!==$vector){throw new RuntimeException('Cross-language vector changed');}
NativeCryptoCodec::verify($bytes,$signature,$vector['publicKeyBase64']);$checks=1;
foreach(['{"a":1,"a":2}','{"b":1,"a":2}','{"a":1.0}','{"a":9007199254740992}',' {"a":1}'] as $bad){try{NativeCryptoCodec::decode(['commandBase64'=>base64_encode($bad),'signatureBase64'=>base64_encode($signature)]);throw new RuntimeException('Invalid canonical representation accepted');}catch(NativeError $e){if($e->errorCode!=='crypto_invalid_envelope'){throw $e;}$checks++;}}
echo 'Crypto codec: '.$checks.' checks PASS'.PHP_EOL;
