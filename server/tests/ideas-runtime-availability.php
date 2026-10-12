<?php
// Run with `php -d disable_functions=imagejpeg` on a synthetic development fixture.
require '/var/www/app/app/common.php';if(session_status()===PHP_SESSION_ACTIVE)session_abort();
if(!defined('FAMILYHUB_DEVELOPMENT_MODE')||!FAMILYHUB_DEVELOPMENT_MODE){throw new RuntimeException('Synthetic only');}
use Kanboard\Plugin\FamilyHub\Model\NativeService;
use Kanboard\Plugin\FamilyHub\Model\NativeIdeaAssetService;
use Kanboard\Plugin\FamilyHub\Model\NativeError;
if(NativeIdeaAssetService::available()){throw new RuntimeException('Disable imagejpeg for this negative test');}
$s=new NativeService($container);$ip='ideas-runtime-'.bin2hex(random_bytes(8));$call=fn($op,$p=[],$token='')=>$s->dispatch($op,$p,$token?'Bearer '.$token:'',$ip);$cap=$call('capabilities');
if($cap['features']['ideas']||$cap['features']['ideaAssets']||!$cap['features']['recordSync']){throw new RuntimeException('Runtime capability gate');}
function uid(){ $h=bin2hex(random_bytes(16));return substr($h,0,8).'-'.substr($h,8,4).'-4'.substr($h,13,3).'-a'.substr($h,17,3).'-'.substr($h,20); }
$password=bin2hex(random_bytes(16));$username='ideas_runtime_'.bin2hex(random_bytes(6));$container['userModel']->create(['username'=>$username,'password'=>$password,'role'=>'app-user']);$user=$call('auth.login',['username'=>$username,'password'=>$password,'deviceName'=>'Runtime availability']);$token=$user['token'];$scope=$call('personal.ensure',[],$token)['scope']['id'];$stamp=gmdate('Y-m-d\TH:i:s\Z');$id=uid();$base=['scopeId'=>$scope,'operation'=>['opId'=>uid(),'recordId'=>$id,'type'=>'task','expectedRevision'=>0,'deleted'=>false,'payload'=>['title'=>'Old contracts work','notes'=>'','projectId'=>null,'dueAt'=>null,'isCompleted'=>false,'createdAt'=>$stamp,'updatedAt'=>$stamp]]];$call('sync.push',$base,$token);
$base['operation']['recordId']=uid();$base['operation']['opId']=uid();$base['operation']['type']='idea';$base['operation']['payload']=[];try{$call('sync5.push',$base,$token);throw new RuntimeException('Idea write was allowed');}catch(NativeError $e){if($e->errorCode!=='ideas_unavailable'||$e->status!==503)throw $e;}
try{$call('ideas.asset.begin',['scopeId'=>$scope,'boardId'=>uid(),'sha256'=>str_repeat('f',64),'mime'=>'image/png','size'=>50,'width'=>1,'height'=>1],$token);throw new RuntimeException('Asset write was allowed');}catch(NativeError $e){if($e->errorCode!=='ideas_unavailable'||$e->status!==503)throw $e;}
if(count($call('sync.pull',['scopeId'=>$scope,'cursor'=>0],$token)['records'])!==1){throw new RuntimeException('Old record contract regressed');}
echo "PASS: missing GD JPEG runtime hides both idea capabilities, blocks board/asset writes, preserves original record synchronization\n";
