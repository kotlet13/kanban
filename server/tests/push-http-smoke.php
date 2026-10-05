<?php
// Dedicated network-none container, synthetic config, NO push sender execution.
require '/var/www/app/app/common.php';
if (!defined('FAMILYHUB_DEVELOPMENT_MODE') || FAMILYHUB_DEVELOPMENT_MODE !== true || !\Kanboard\Plugin\FamilyHub\Model\NativeFcmConfig::configured()) { throw new RuntimeException('Synthetic configured HTTP fixture required'); }
if (session_status() === PHP_SESSION_ACTIVE) { session_abort(); }
$checks=0;
function check($ok,$name) { global $checks;if(!$ok){throw new RuntimeException('FAIL: '.$name);}$checks++;echo 'PASS: '.$name.PHP_EOL; }
function call($op,$params=[],$token=null) {
    $headers=['Content-Type: application/json'];if($token){$headers[]='Authorization: Bearer '.$token;}
    $ch=curl_init('http://127.0.0.1/index.php?controller=NativeApiController&action=handle&plugin=FamilyHub');
    curl_setopt_array($ch,[CURLOPT_POST=>true,CURLOPT_POSTFIELDS=>json_encode(['v'=>1,'op'=>$op,'params'=>(object)$params]),CURLOPT_HTTPHEADER=>$headers,CURLOPT_RETURNTRANSFER=>true,CURLOPT_TIMEOUT=>5]);
    $body=curl_exec($ch);$status=curl_getinfo($ch,CURLINFO_HTTP_CODE);curl_close($ch);$json=json_decode($body,true);
    if(!is_array($json)){throw new RuntimeException('Invalid HTTP JSON');}return ['status'=>$status,'body'=>$json];
}
$caps=call('capabilities');check($caps['status']===200 && $caps['body']['data']['features']['externalPush'] && $caps['body']['data']['pushProjectId']==='synthetic-fcm','HTTP capability reflects configured local fixture');
$uid=$container['userModel']->create(['username'=>'push_http_'.bin2hex(random_bytes(4)),'password'=>bin2hex(random_bytes(16)),'role'=>'app-user']);
$session=(new \Kanboard\Plugin\FamilyHub\Model\NativeAuthService($container))->issue($container['userModel']->getById($uid),'Synthetic HTTP');$bearer=$session['token'];
check(call('push.state')['status']===401,'HTTP push state rejects missing bearer');
check(call('push.register',['token'=>'synthetic','platform'=>'android','language'=>'sl'])['status']===401,'HTTP registration rejects missing bearer');
$registration=call('push.register',['token'=>'synthetic-http-token','platform'=>'android','language'=>'sl','expectedRevision'=>0,'projectId'=>'synthetic-fcm'],$bearer);check($registration['status']===200 && $registration['body']['data']['registration']['registered'],'HTTP configured registration accepts current bearer device');
check(strpos(json_encode($registration['body']),'synthetic-http-token')===false,'HTTP response never echoes token');
check(call('push.register',['token'=>'synthetic-http-token','platform'=>'android','language'=>'sl','expectedRevision'=>0],$bearer)['status']===200,'HTTP identical lost-response replay succeeds');
check(call('push.register',['token'=>'new-synthetic-http-token','platform'=>'ios','language'=>'en','expectedRevision'=>0],$bearer)['status']===409,'HTTP stale CAS rotation conflicts');
check(call('push.register',['token'=>'new-synthetic-http-token','platform'=>'ios','language'=>'en','expectedRevision'=>1,'projectId'=>'wrong-project'],$bearer)['body']['error']['code']==='push_project_mismatch','HTTP wrong Firebase project denied');
check(call('push.unregister',['expectedRevision'=>0],$bearer)['status']===409,'HTTP stale unregister conflicts');
check(call('push.unregister',['expectedRevision'=>1],$bearer)['status']===200,'HTTP unregister releases current registration');
check(call('push.unregister',['expectedRevision'=>1],$bearer)['status']===200,'HTTP lost unregister ACK remains idempotent');
check(call('push.state',[],$bearer)['body']['data']['registration']['registered']===false,'HTTP state reflects durable unregister');
echo 'SUCCESS '.$checks.' configured HTTP push checks (no provider network)'.PHP_EOL;
