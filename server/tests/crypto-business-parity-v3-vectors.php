<?php
require '/var/www/app/app/common.php';
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoMigrationBusinessParityV3 as C;
use Kanboard\Plugin\FamilyHub\Model\NativeError;
$f=json_decode(file_get_contents(__DIR__.'/fixtures/e2ee-business-parity-v3.json'),true,64,JSON_THROW_ON_ERROR);
$n=0;
$check=function($ok)use(&$n){if(!$ok)throw new RuntimeException('parity3 vector');$n++;};
$deny=function($fn)use($check){try{$fn();$ok=false;}catch(NativeError $e){$ok=true;}$check($ok);};
$artifact=$f['canonicalArtifact'];
$check(C::canonicalArtifact($artifact['sourceBinding'])===$artifact['hash']);
foreach (['bindingId'=>'99999999-1111-4111-8111-111111111111','recordProofHash'=>str_repeat('9',64),'scopeId'=>'99999998-1111-4111-8111-111111111111'] as $k=>$v) {
    $check(C::canonicalArtifact(array_replace($artifact['sourceBinding'],[$k=>$v]))!==$artifact['hash']);
}
$deny(fn()=>C::canonicalArtifact($artifact['sourceBinding']+['sourceRowHash'=>str_repeat('0',64)]));
$r=C::compute($f['header'],$f['frames']);
$check($r['hash']===$f['result']['hash']);
foreach ($f['result'] as $k=>$v) $check($r[$k]===$v);
$frames=$f['frames'];
$deny(fn()=>C::compute($f['header'],array_slice($frames,1)));
$deny(fn()=>C::compute($f['header'],array_merge([$frames[1],$frames[0]],array_slice($frames,2))));
$deny(fn()=>C::compute($f['header'],array_merge([$frames[0]],$frames)));
$bad=$frames;$bad[0]['value']['sourceRowHash']=str_repeat('1',64);$deny(fn()=>C::compute($f['header'],$bad));
$bad=$frames;$bad[0]['value']['adapter']='unsupportedCurrentSource';$deny(fn()=>C::compute($f['header'],$bad));
$deny(fn()=>C::compute($f['header'],array_slice($frames,0,-1)));
$deny(fn()=>C::compute(array_replace($f['header'],['accountId'=>'99999999-1111-4111-8111-111111111111']),$frames));
echo 'business parity3 vectors PASS '.$n.PHP_EOL;
