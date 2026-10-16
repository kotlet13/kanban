<?php
/** End-to-end regression: householdPerson.archived belongs to record3, project.archived to record6. */
umask(0077);
require '/var/www/app/app/common.php';if(session_status()===PHP_SESSION_ACTIVE){session_abort();}
if(!defined('FAMILYHUB_DEVELOPMENT_MODE')||FAMILYHUB_DEVELOPMENT_MODE!==true){throw new RuntimeException('Synthetic only');}
use Kanboard\Plugin\FamilyHub\Model\NativeService;
use Kanboard\Plugin\FamilyHub\Model\NativeError;
$pdo=$container['db']->getConnection();$service=new NativeService($container);$checks=0;$prefix='archive_'.bin2hex(random_bytes(5));$ip='archive-test-'.bin2hex(random_bytes(8));$password=bin2hex(random_bytes(16));$stamp='2026-10-16T12:00:00.000Z';
function check($v,$m){global$checks;if(!$v){throw new RuntimeException('FAIL: '.$m);}$checks++;echo 'PASS: '.$m.PHP_EOL;}
function q($s,$p=[]){global$pdo;$q=$pdo->prepare($s);$q->execute($p);$r=$q->fetchAll(PDO::FETCH_ASSOC);$q->closeCursor();return$r;}
function api($op,$p=[]){global$service,$ip,$owner;return$service->dispatch($op,$p,isset($owner)?'Bearer '.$owner['token']:'',$ip);}
function uuid(){$h=bin2hex(random_bytes(16));return substr($h,0,8).'-'.substr($h,8,4).'-4'.substr($h,13,3).'-a'.substr($h,17,3).'-'.substr($h,20);}
function request($sid,$id,$type,$payload,$revision=0){return ['scopeId'=>$sid,'operation'=>['opId'=>uuid(),'recordId'=>$id,'type'=>$type,'expectedRevision'=>$revision,'deleted'=>false,'payload'=>$payload]];}
function deny($op,$p,$code){try{api($op,$p);$ok=false;}catch(NativeError$e){$ok=$e->errorCode===$code;}check($ok,$op.' denies '.$code);}
$container['userModel']->create(['username'=>$prefix,'password'=>$password,'role'=>'app-user']);$owner=api('auth.login',['username'=>$prefix,'password'=>$password,'deviceName'=>'Archive validation']);api('moderation.acceptPolicy',['policyVersion'=>1]);
$scope=api('scopes.create',['id'=>uuid(),'kind'=>'household','name'=>'Archive validation','accessPolicyVersion'=>3,'requestId'=>uuid()])['scope'];$sid=$scope['id'];$person=uuid();
$payload=['name'=>'Household person','notes'=>'Preserved person notes','archived'=>false,'createdAt'=>$stamp,'updatedAt'=>$stamp];$first=request($sid,$person,'householdPerson',$payload);$created=api('sync3.push',$first);
check($created['record']['payload']['archived']===false&&$created['record']['revision']===1,'record3 creates unarchived household person');check(api('sync3.push',$first)['replayed']===true,'person creation replays original operation');
$archived=array_replace($payload,['archived'=>true]);$updated=api('sync3.push',request($sid,$person,'householdPerson',$archived,1));check($updated['record']['payload']['archived']===true&&$updated['record']['revision']===2,'record3 archives existing household person');
$restored=api('sync3.push',request($sid,$person,'householdPerson',$payload,2));check($restored['record']['payload']['archived']===false&&$restored['record']['revision']===3,'record3 restores household person without changing identity');
foreach([null,0,1,'false',[],new stdClass()]as$bad){deny('sync3.push',request($sid,uuid(),'householdPerson',array_replace($payload,['archived'=>$bad])),'validation_error');}
$missing=$payload;unset($missing['archived']);deny('sync3.push',request($sid,uuid(),'householdPerson',$missing),'validation_error');
check((int)q("SELECT COUNT(*) AS n FROM familyhub_records WHERE scope_id=? AND type='householdPerson'",[$sid])[0]['n']===1,'invalid person archive values do not write records');
$project=['title'=>'Inline project','description'=>'','area'=>'home','startAt'=>null,'endAt'=>null,'phases'=>[],'availabilityMinutes'=>null,'availabilityPeriod'=>null,'createdAt'=>$stamp,'updatedAt'=>$stamp];
deny('sync3.push',request($sid,uuid(),'project',$project+['archived'=>false]),'validation_error');
$projectId=uuid();$current=api('sync6.push',request($sid,$projectId,'project',$project+['archived'=>false]));check($current['record']['payload']['archived']===false,'record6 retains project archive support');
deny('sync6.push',request($sid,uuid(),'project',$project+['archived'=>1]),'validation_error');
api('sync6.push',request($sid,$projectId,'project',$project+['archived'=>true],1));check(json_decode(q('SELECT payload FROM familyhub_records WHERE scope_id=? AND id=?',[$sid,$projectId])[0]['payload'],true)['archived']===true,'project boolean archive persists');
deny('sync6.push',request($sid,uuid(),'shoppingList',['title'=>'Shopping','archived'=>false,'createdAt'=>$stamp,'updatedAt'=>$stamp]),'validation_error');
$read=api('sync6.pull',['scopeId'=>$sid,'cursor'=>0])['records'];$people=array_values(array_filter($read,fn($r)=>$r['id']===$person));check(count($people)===1&&$people[0]['payload']['archived']===false&&$people[0]['payload']['notes']===$payload['notes'],'modern pull preserves person archive state and notes');
echo 'SUCCESS '.$checks.' archive validation checks ('.$pdo->getAttribute(PDO::ATTR_DRIVER_NAME).')'.PHP_EOL;
