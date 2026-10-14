<?php
// New synthetic accounts/scopes only. Exercise real HTTP and stored payloads.
require '/var/www/app/app/common.php';
if (!defined('FAMILYHUB_DEVELOPMENT_MODE') || FAMILYHUB_DEVELOPMENT_MODE !== true) { throw new RuntimeException('Development only'); }
$checks = 0;
function uid() { $h=bin2hex(random_bytes(16)); return substr($h,0,8).'-'.substr($h,8,4).'-4'.substr($h,13,3).'-a'.substr($h,17,3).'-'.substr($h,20); }
function check($condition,$label) { global $checks; if (!$condition) { throw new RuntimeException('FAIL: '.$label); } ++$checks; echo 'PASS: '.$label.PHP_EOL; }
function api($op,array $params=[],$token=null) {
    $h=curl_init('http://127.0.0.1/index.php?controller=NativeApiController&action=handle&plugin=FamilyHub');
    $headers=['Content-Type: application/json']; if ($token) { $headers[]='Authorization: Bearer '.$token; }
    curl_setopt_array($h,[CURLOPT_POST=>true,CURLOPT_RETURNTRANSFER=>true,CURLOPT_HTTPHEADER=>$headers,CURLOPT_POSTFIELDS=>json_encode(['v'=>1,'op'=>$op,'params'=>(object)$params])]);
    $raw=curl_exec($h); $status=curl_getinfo($h,CURLINFO_HTTP_CODE); curl_close($h);
    return ['status'=>$status,'body'=>json_decode($raw,true,64,JSON_THROW_ON_ERROR)];
}
function data($r) { if ($r['status']!==200) { throw new RuntimeException('HTTP '.$r['status'].' '.($r['body']['error']['code']??'unknown')); } return $r['body']['data']; }
function denied($r,$code,$label) { check(($r['body']['error']['code']??'')===$code,$label); }
function operation($id,$payload,$revision=0) { return ['opId'=>uid(),'recordId'=>$id,'type'=>'garden','expectedRevision'=>$revision,'deleted'=>false,'payload'=>$payload]; }
$prefix='garden_scene_'.bin2hex(random_bytes(5)); $password=bin2hex(random_bytes(18)); $sessions=[];
foreach (['owner','member','outsider'] as $who) {
    $container['userModel']->create(['username'=>$prefix.'_'.$who,'password'=>$password,'role'=>'app-user']);
    $sessions[$who]=data(api('auth.login',['username'=>$prefix.'_'.$who,'password'=>$password,'deviceName'=>'Garden scene synthetic test']));
    data(api('moderation.acceptPolicy',['policyVersion'=>1],$sessions[$who]['token']));
}
$o=$sessions['owner']['token']; $m=$sessions['member']['token']; $x=$sessions['outsider']['token'];
$caps=data(api('capabilities')); check(in_array(6,$caps['recordContractVersions'],true),'record6 advertised');
$house=uid(); data(api('scopes.create',['id'=>$house,'kind'=>'household','name'=>'Synthetic scene garden','requestId'=>uid()],$o));
$invite=data(api('invitations.create',['scopeId'=>$house,'recipientUsername'=>$prefix.'_member','role'=>'member','requestId'=>uid()],$o));
data(api('invitations.accept',['token'=>$invite['token']],$m));
$garden=uid(); $area=uid(); $planting=uid(); $stamp='2026-10-14T10:00:00.000Z';
$p=['version'=>3,'id'=>$garden,'name'=>'Measured garden','notes'=>'Synthetic only','widthMeters'=>12,'heightMeters'=>8,'areas'=>[['id'=>$area,'label'=>'Carrots','x'=>0.1,'y'=>0.1,'width'=>0.4,'height'=>0.3,'kind'=>'bed','archived'=>false]],'seasons'=>[['year'=>2026,'notes'=>'Preserved history','plantings'=>[['id'=>$planting,'areaId'=>$area,'crop'=>'Carrot','variety'=>'','family'=>'Apiaceae','status'=>'actual','notes'=>'','sowAt'=>'2026-03-01','plantAt'=>null,'harvestAt'=>null,'harvested'=>false,'spacingCm'=>12.5,'illustration'=>'carrot','visualGrowthDays'=>75]]]],'revision'=>0,'createdAt'=>$stamp,'updatedAt'=>$stamp];
$op=operation($garden,$p); $args=['scopeId'=>$house,'operation'=>$op,'operationContractVersion'=>6];
denied(api('sync5.push',array_replace($args,['operationContractVersion'=>5]),$o),'client_upgrade_required','old wire cannot submit scene garden');
$saved=data(api('sync6.push',$args,$o)); check($saved['record']['payload']===$p,'all physical/illustration/history fields stored exactly');
check(data(api('sync6.push',$args,$o))['replayed'],'same scene operation replays exactly');
$pull=data(api('sync6.pull',['scopeId'=>$house,'cursor'=>0],$m));
check(array_values(array_filter($pull['records'],fn($r)=>$r['id']===$garden))[0]['payload']===$p,'second accepted device receives complete scene');
denied(api('sync5.pull',['scopeId'=>$house,'cursor'=>0],$m),'client_upgrade_required','old client cannot truncate upgraded scope');
denied(api('sync6.pull',['scopeId'=>$house,'cursor'=>0],$x),'permission_revoked','outsider cannot read garden');
$harvest=$p; $harvest['seasons'][0]['plantings'][0]['harvested']=true; $harvest['seasons'][0]['plantings'][0]['harvestAt']='2026-10-14';
$next=data(api('sync6.push',['scopeId'=>$house,'operation'=>operation($garden,$harvest,1),'operationContractVersion'=>6],$m));
check($next['record']['payload']===$harvest,'member harvest preserves planting identity and all history');
denied(api('sync6.push',['scopeId'=>$house,'operation'=>operation($garden,$p,1),'operationContractVersion'=>6],$o),'conflict','stale scene cannot erase harvested state');
foreach (['partial_size','bad_size','missing_field','bad_spacing','bad_growth','bad_illustration','bad_harvest','unknown'] as $case) {
    $bad=$harvest;
    if ($case==='partial_size') { $bad['heightMeters']=null; }
    if ($case==='bad_size') { $bad['widthMeters']=0; }
    if ($case==='missing_field') { unset($bad['seasons'][0]['plantings'][0]['spacingCm']); }
    if ($case==='bad_spacing') { $bad['seasons'][0]['plantings'][0]['spacingCm']=1001; }
    if ($case==='bad_growth') { $bad['seasons'][0]['plantings'][0]['visualGrowthDays']=0; }
    if ($case==='bad_illustration') { $bad['seasons'][0]['plantings'][0]['illustration']='new_unknown'; }
    if ($case==='bad_harvest') { $bad['seasons'][0]['plantings'][0]['status']='planned'; }
    if ($case==='unknown') { $bad['forgottenField']='must not discard'; }
    denied(api('sync6.push',['scopeId'=>$house,'operation'=>operation($garden,$bad,2),'operationContractVersion'=>6],$o),'validation_error','strict scene validation: '.$case);
}
$legacy=$p; $legacy['version']=2; unset($legacy['widthMeters'],$legacy['heightMeters']); foreach (['harvested','spacingCm','illustration','visualGrowthDays'] as $key) { unset($legacy['seasons'][0]['plantings'][0][$key]); }
denied(api('sync6.push',['scopeId'=>$house,'operation'=>operation($garden,$legacy,2),'operationContractVersion'=>6],$o),'client_upgrade_required','format downgrade cannot remove scene fields');
$legacyId=uid(); $legacy['id']=$legacyId; $legacyOp=operation($legacyId,$legacy);
check(data(api('sync6.push',['scopeId'=>$house,'operation'=>$legacyOp,'operationContractVersion'=>4],$o))['record']['payload']===$legacy,'original v2 operation can still cross new bridge unchanged');
$final=data(api('sync6.pull',['scopeId'=>$house,'cursor'=>0],$o));
check(array_values(array_filter($final['records'],fn($r)=>$r['id']===$garden))[0]['payload']===$harvest,'failed edits never mutate stored garden');
echo 'Garden scene checks: '.$checks.PHP_EOL;
