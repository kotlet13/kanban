<?php
require '/var/www/app/app/common.php';
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoMigrationReceiptV3 as C;
$f=json_decode(file_get_contents(__DIR__.'/fixtures/e2ee-migration-receipts-v3.json'),true,32,JSON_THROW_ON_ERROR);
$n=0;
$check=static function($v)use(&$n){if(!$v)throw new RuntimeException('receipt vector');$n++;};
$s=C::section($f['common'],$f['content'],$f['finance'],$f['localIntents']);
$check($s===['kind'=>'receipts','count'=>6,'root'=>$f['root']]);
$check(C::artifact($f['localIntents']['artifactId'],str_repeat('2',64),'finance',$f['finance'])===$f['artifact']);
foreach(['captureId','migrationId','serverId','accountId'] as $k){$c=$f['common'];$c[$k]='00000000-0000-4000-8000-000000000099';$check(C::section($c,$f['content'],$f['finance'],$f['localIntents'])['root']!==$f['root']);}
foreach([null,-1,9007199254740991] as $bad){$l=$f['localIntents'];$l['intentCount']=$bad;try{C::section($f['common'],$f['content'],$f['finance'],$l);throw new RuntimeException('accepted count');}catch(\Kanboard\Plugin\FamilyHub\Model\NativeError $e){$n++;}}
echo "$n PASS\n";
