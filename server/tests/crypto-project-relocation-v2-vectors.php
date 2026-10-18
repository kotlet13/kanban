<?php
require '/var/www/app/app/common.php';
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoProjectRelocationCodecV2 as R;
use Kanboard\Plugin\FamilyHub\Model\NativeError;

$v=json_decode(file_get_contents(__DIR__.'/fixtures/e2ee-project-relocation-v2.json'),true,34,JSON_THROW_ON_ERROR);
$count=0;
$check=function($value)use(&$count){if(!$value)throw new RuntimeException('relocation vector');$count++;};
$deny=function($fn)use($check){try{$fn();$denied=false;}catch(NativeError $e){$denied=true;}$check($denied);};
$check(count($v['descriptors'])===53&&R::graphRoot($v['descriptors'])===$v['root']);
$deny(fn()=>R::graphRoot(array_reverse($v['descriptors'])));
$deny(fn()=>R::graphRoot([$v['descriptors'][0],$v['descriptors'][0]]));
$bad=$v['descriptors'];$bad[0]['logicalRevision']=-1;$deny(fn()=>R::graphRoot($bad));
$bad=$v['descriptors'];$bad[0]['revision']=9007199254740992;$deny(fn()=>R::graphRoot($bad));
$bad=$v['descriptors'];$bad[0]['extra']='unreviewed';$deny(fn()=>R::graphRoot($bad));
$bad=$v['descriptors'];$bad[0]['logicalRevision']++;$check(R::graphRoot($bad)!==$v['root']);
$action='00000000-0000-4000-a000-000000000060';$server='00000000-0000-4000-a000-000000000061';$source='00000000-0000-4000-a000-000000000062';$target='00000000-0000-4000-a000-000000000063';
$sourceToken=R::counterpartToken($server,$action,$source,$target);
$targetToken=R::counterpartToken($server,$action,$target,$source);
$check($sourceToken!==$targetToken);
$check(R::publicationRoot(str_repeat('1',64),str_repeat('2',64))!==R::publicationRoot(str_repeat('2',64),str_repeat('1',64)));
$check(R::digestRoot('audit',[])===hash('sha256',"JivieProjectRelocation/audit/v2\n"));
$deny(fn()=>R::digestRoot('records',[]));
$deny(fn()=>R::digestRoot('audit',[str_repeat('1',64),str_repeat('1',64)]));
$deny(fn()=>R::tag(['version'=>2,'actionId'=>$action,'planHash'=>str_repeat('1',64),'side'=>'other']));
echo 'Project relocation2 vectors '.$count.' PASS'.PHP_EOL;
