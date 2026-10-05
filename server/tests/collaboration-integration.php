<?php
// Synthetic HTTP fixtures only. No user data reset, no secrets printed.
require '/var/www/app/app/common.php';
if (!defined('FAMILYHUB_DEVELOPMENT_MODE') || FAMILYHUB_DEVELOPMENT_MODE !== true) { throw new RuntimeException('Development only'); }
$checks=0; $prefix='collab_'.bin2hex(random_bytes(4)); $password=bin2hex(random_bytes(14));
$pdo=$container['db']->getConnection();
foreach(['login-ip:','scopes-ip:','invitation-ip:','sync-ip:','inbox-ip:','reminders-ip:','finance-ip:'] as $key) { $pdo->prepare('DELETE FROM familyhub_rate_limits WHERE id=?')->execute([hash('sha256',$key.'127.0.0.1')]); }
function uuid(){ $h=bin2hex(random_bytes(16));return substr($h,0,8).'-'.substr($h,8,4).'-4'.substr($h,13,3).'-a'.substr($h,17,3).'-'.substr($h,20); }
function check($ok,$message){global $checks;if(!$ok){throw new RuntimeException('FAIL: '.$message);} $checks++;echo 'PASS: '.$message.PHP_EOL;}
function call($op,$params=[],$token=null){$ch=curl_init('http://127.0.0.1/index.php?controller=NativeApiController&action=handle&plugin=FamilyHub');$headers=['Content-Type: application/json'];if($token){$headers[]='Authorization: Bearer '.$token;}curl_setopt_array($ch,[CURLOPT_POST=>true,CURLOPT_RETURNTRANSFER=>true,CURLOPT_HTTPHEADER=>$headers,CURLOPT_POSTFIELDS=>json_encode(['v'=>1,'op'=>$op,'params'=>(object)$params])]);$raw=curl_exec($ch);$status=curl_getinfo($ch,CURLINFO_HTTP_CODE);curl_close($ch);return ['status'=>$status,'body'=>json_decode($raw,true)];}
function data($r){if($r['status']!==200){throw new RuntimeException('Unexpected HTTP '.$r['status'].' '.($r['body']['error']['code']??'invalid'));}return $r['body']['data'];}
function err($r,$code,$status){return $r['status']===$status && ($r['body']['error']['code']??null)===$code;}
function push($scope,$id,$type,$payload,$revision=0,$op=null,$deleted=false){return ['scopeId'=>$scope,'operation'=>['opId'=>$op??uuid(),'recordId'=>$id,'type'=>$type,'expectedRevision'=>$revision,'deleted'=>$deleted,'payload'=>$payload]];}
function inbox($token,$scope){return array_values(array_filter(data(call('inbox.sync',['cursor'=>0,'limit'=>100],$token))['items'],fn($x)=>$x['scopeId']===$scope));}
$sessions=[];$users=[];
foreach(['owner','assigned','observer','foreign'] as $role){$users[$role]=$container['userModel']->create(['username'=>$prefix.'_'.$role,'password'=>$password,'role'=>'app-user']);$sessions[$role]=data(call('auth.login',['username'=>$prefix.'_'.$role,'password'=>$password,'deviceName'=>'Synthetic upgrade']));}
$owner=$sessions['owner']['token'];$assigned=$sessions['assigned']['token'];$observer=$sessions['observer']['token'];$foreign=$sessions['foreign']['token'];
$scope=uuid();data(call('scopes.create',['id'=>$scope,'kind'=>'household','name'=>'Synthetic upgrade','requestId'=>uuid()],$owner));
foreach(['assigned','observer'] as $role){$i=data(call('invitations.create',['scopeId'=>$scope,'recipientUsername'=>$prefix.'_'.$role,'role'=>'member','requestId'=>uuid()],$owner));data(call('invitations.accept',['token'=>$i['token']],$sessions[$role]['token']));}
$now=gmdate('Y-m-d\TH:i:s\Z');$task=uuid();$payload=['title'=>'Task','notes'=>'','projectId'=>null,'dueAt'=>null,'isCompleted'=>false,'createdAt'=>$now,'updatedAt'=>$now];
$legacy=push($scope,$task,'task',$payload);$ack=data(call('sync.push',$legacy,$owner));
check($ack['record']['revision']===1,'v1 pending operation remains valid before upgrade');
$payload+=['startAt'=>$now,'endAt'=>null,'assigneeAccountIds'=>[$sessions['assigned']['user']['accountId']]];
$op=push($scope,$task,'task',$payload,1);$ack=data(call('sync2.push',$op,$owner));
check($ack['record']['createdByAccountId']===$sessions['owner']['user']['accountId'] && $ack['record']['updatedByAccountId']===$sessions['owner']['user']['accountId'],'canonical creator/updater provenance');
check(data(call('sync.push',$legacy,$owner))['replayed'],'v1 original ACK replay survives scope upgrade');
check(err(call('sync.pull',['scopeId'=>$scope,'cursor'=>0],$owner),'client_upgrade_required',409),'v1 pull cannot silently strip extended records');
check(err(call('sync.push',push($scope,uuid(),'task',array_diff_key($payload,array_flip(['startAt','endAt','assigneeAccountIds']))),$owner),'client_upgrade_required',409),'new v1 write rejected after upgrade');
$personal=array_values(array_filter(inbox($assigned,$scope),fn($x)=>$x['targetId']===$task && $x['targetRevision']===2));$awareness=array_values(array_filter(inbox($observer,$scope),fn($x)=>$x['targetId']===$task && $x['targetRevision']===2));
check(count($personal)===1 && $personal[0]['audience']==='personal' && $personal[0]['kind']==='task.assigned','create/update assign produces one personal variant');
check(count($awareness)===1 && $awareness[0]['audience']==='scope','non-designated member receives shared awareness');
check(count(inbox($owner,$scope))===0,'own actions do not self-alert');
$count=count(inbox($assigned,$scope));data(call('sync2.push',$op,$owner));check(count(inbox($assigned,$scope))===$count,'idempotent sync replay creates no inbox duplicate');
$oldSync=data(call('inbox.sync',['cursor'=>0],$assigned));$item=$personal[0];$read=['id'=>$item['id'],'read'=>true,'expectedRevision'=>$item['revision'],'requestId'=>uuid()];$readAck=data(call('inbox.read',$read,$assigned));
check($readAck['item']['readAt']!==null && $readAck['item']['revision']===2,'read state has own monotonic revision');
$delta=data(call('inbox.sync',['cursor'=>$oldSync['cursor'],'visibilityRevision'=>$oldSync['visibilityRevision']],$assigned));check(count($delta['items'])===1 && $delta['items'][0]['readAt']!==null,'old notification read propagates across devices via change cursor');
check(data(call('inbox.read',$read,$assigned))['item']===$readAck['item'],'read ACK replay idempotent');
check(err(call('inbox.read',array_replace($read,['read'=>false,'requestId'=>uuid()]),$assigned),'inbox_conflict',409),'stale read-state toggle cannot overwrite newer state');
check(err(call('inbox.open',['id'=>$item['id']],$foreign),'permission_revoked',403),'inbox open checks recipient identity');
check(data(call('inbox.open',['id'=>$item['id']],$assigned))['record']['id']===$task,'open retrieves currently authorized target');
$list=uuid();data(call('sync2.push',push($scope,$list,'shoppingList',['title'=>'List','createdAt'=>$now,'updatedAt'=>$now]),$owner));$items=[];
foreach(['One','Two'] as $title){$id=uuid();$items[]=$id;data(call('sync2.push',push($scope,$id,'shoppingItem',['listId'=>$list,'title'=>$title,'quantity'=>'','isChecked'=>false,'createdAt'=>$now,'updatedAt'=>$now]),$owner));}
$shopping=array_values(array_filter(inbox($assigned,$scope),fn($x)=>in_array($x['targetId'],$items,true)));
check(count($shopping)===2 && $shopping[0]['groupKey']===$shopping[1]['groupKey'] && $shopping[0]['targetId']!==$shopping[1]['targetId'],'five-minute grouping retains concrete distinct targets');
$first=$shopping[0];data(call('inbox.read',['id'=>$first['id'],'read'=>true,'expectedRevision'=>1,'requestId'=>uuid()],$assigned));
$next=uuid();data(call('sync2.push',push($scope,$next,'shoppingItem',['listId'=>$list,'title'=>'Later','quantity'=>'','isChecked'=>false,'createdAt'=>$now,'updatedAt'=>$now]),$owner));
$nextRows=array_values(array_filter(inbox($assigned,$scope),fn($x)=>$x['targetId']===$next));check($nextRows[0]['readAt']===null,'read captured group IDs never consumes newly added event');
$assignedTasks=[];
foreach(['Assigned one','Assigned two','Assigned three'] as $title){$id=uuid();$assignedTasks[]=$id;data(call('sync2.push',push($scope,$id,'task',array_replace($payload,['title'=>$title])),$owner));}
$batch=array_values(array_filter(inbox($assigned,$scope),fn($x)=>in_array($x['targetId'],$assignedTasks,true)));
check(count($batch)===3 && count(array_unique(array_column($batch,'groupKey')))===1 && count(array_unique(array_column($batch,'targetId')))===3,'fresh create-and-assign tasks batch by scope with exact distinct targets');
check(count(array_filter($batch,fn($x)=>$x['kind']==='task.assigned' && $x['audience']==='personal'))===3,'fresh create plus assign gives exactly one personal event per task');
$rid=uuid();$reminder=['id'=>$rid,'scopeId'=>$scope,'targetType'=>'task','targetId'=>$task,'remindAt'=>$now,'expectedRevision'=>0,'requestId'=>uuid()];
check(data(call('reminders.put',$reminder,$assigned))['reminder']['state']==='pending','schedule own UTC reminder');
$cron=new \Kanboard\Plugin\FamilyHub\Model\NativeReminderService($container);$cron->runDue(100);$due=array_values(array_filter(inbox($assigned,$scope),fn($x)=>$x['kind']==='reminder.due' && $x['targetId']===$task));check(count($due)===1,'first cron actually creates one due reminder event');$state=array_values(array_filter(data(call('reminders.list',['scopeId'=>$scope],$assigned))['reminders'],fn($x)=>$x['id']===$rid));check($state[0]['state']==='delivered','first cron transitions reminder to delivered');$before=count(inbox($assigned,$scope));$cron->runDue(100);check(count(inbox($assigned,$scope))===$before,'cron retries do not duplicate delivered reminder');
$payload['isCompleted']=true;data(call('sync2.push',push($scope,$task,'task',$payload,2),$owner));
check(err(call('reminders.put',array_replace($reminder,['id'=>uuid(),'requestId'=>uuid()]),$assigned),'reminder_target_unavailable',422),'completed task cannot schedule stale reminder');
$project=uuid();$projectPayload=['title'=>'Timeline project','description'=>'','area'=>'home','startAt'=>$now,'endAt'=>'2030-01-03T12:00:00Z','createdAt'=>$now,'updatedAt'=>$now];data(call('sync2.push',push($scope,$project,'project',$projectPayload),$owner));
$event=uuid();$eventPayload=['title'=>'Shared event','notes'=>'','projectId'=>$project,'startAt'=>'2030-01-01T12:00:00Z','endAt'=>'2030-01-01T13:00:00Z','assigneeAccountIds'=>[$sessions['assigned']['user']['accountId']],'createdAt'=>$now,'updatedAt'=>$now];$eventAck=data(call('sync2.push',push($scope,$event,'event',$eventPayload),$owner));check($eventAck['record']['type']==='event' && $eventAck['record']['createdByAccountId']===$sessions['owner']['user']['accountId'],'shared event persists date range and creator for project timeline');
check(err(call('sync2.push',push($scope,$project,'project',null,1,null,true),$owner),'live_children',422),'event reference prevents parent project deletion');
check(err(call('sync2.push',push($scope,uuid(),'event',array_replace($eventPayload,['endAt'=>'2029-01-01T12:00:00Z'])),$owner),'invalid_date_range',422),'event end before start rejected');
$invalid=call('sync2.push',push($scope,uuid(),'task',array_replace($payload,['assigneeAccountIds'=>[$sessions['foreign']['user']['accountId']]])),$owner);check(err($invalid,'assignee_not_member',422) && array_key_exists('serverRecord',$invalid['body']['error']['details']),'foreign assignee rejection preserves an actionable own-record conflict');
$events=array_values(array_filter(inbox($assigned,$scope),fn($x)=>$x['targetId']===$event));check(count($events)===1 && $events[0]['kind']==='event.assigned' && $events[0]['audience']==='personal','shared event targets designated recipient once');
$futureTask=$assignedTasks[0];$futurePayload=array_replace($payload,['title'=>'Assigned one','isCompleted'=>false,'dueAt'=>'2030-01-01T12:00:00Z']);data(call('sync2.push',push($scope,$futureTask,'task',$futurePayload,1),$owner));
$futureReminder=['id'=>uuid(),'scopeId'=>$scope,'targetType'=>'task','targetId'=>$futureTask,'remindAt'=>'2030-01-01T11:00:00Z','expectedRevision'=>0,'requestId'=>uuid()];data(call('reminders.put',$futureReminder,$assigned));
$semantic=array_replace($futurePayload,['title'=>'Title edit only','createdAt'=>substr($now,0,-1).'.000Z','startAt'=>substr($now,0,-1).'.000Z','dueAt'=>'2030-01-01T12:00:00.000Z']);data(call('sync2.push',push($scope,$futureTask,'task',$semantic,2),$owner));
$state=array_values(array_filter(data(call('reminders.list',['scopeId'=>$scope],$assigned))['reminders'],fn($x)=>$x['id']===$futureReminder['id']));check($state[0]['state']==='pending' && $state[0]['revision']===1,'equivalent UTC serialization and title edit preserve planned reminder');
$futurePayload=$semantic;
$futurePayload['dueAt']='2030-01-02T12:00:00Z';data(call('sync2.push',push($scope,$futureTask,'task',$futurePayload,3),$owner));
$state=array_values(array_filter(data(call('reminders.list',['scopeId'=>$scope],$assigned))['reminders'],fn($x)=>$x['id']===$futureReminder['id']));check($state[0]['state']==='cancelled' && $state[0]['revision']===2,'changing due date cancels previously scheduled reminder');
data(call('reminders.put',array_replace($futureReminder,['expectedRevision'=>2,'requestId'=>uuid()]),$assigned));$futurePayload['isCompleted']=true;data(call('sync2.push',push($scope,$futureTask,'task',$futurePayload,4),$owner));
$state=array_values(array_filter(data(call('reminders.list',['scopeId'=>$scope],$assigned))['reminders'],fn($x)=>$x['id']===$futureReminder['id']));check($state[0]['state']==='cancelled' && $state[0]['revision']===4,'completion cancels rescheduled future reminder');
// More than one page, using accepted HTTP writes rather than in-memory imitation.
for($i=0;$i<110;$i++){data(call('sync2.push',push($scope,uuid(),'shoppingItem',['listId'=>$list,'title'=>'Pagination '.$i,'quantity'=>'','isChecked'=>false,'createdAt'=>$now,'updatedAt'=>$now]),$owner));}
$cursor=0;$visibility=null;$all=[];$pages=0;do{$args=['cursor'=>$cursor,'limit'=>17];if($visibility!==null){$args['visibilityRevision']=$visibility;}$page=data(call('inbox.sync',$args,$assigned));$cursor=$page['cursor'];$visibility=$page['visibilityRevision'];$all=array_merge($all,$page['items']);$pages++;}while($page['hasMore']);
check($pages>6 && count(array_filter($all,fn($x)=>$x['kind']==='shoppingItem.created'))===113,'bounded inbox backfill preserves more than one hundred concrete events');
$historic=$all[0];$beforeCursor=$cursor;data(call('inbox.read',['id'=>$historic['id'],'read'=>true,'expectedRevision'=>$historic['revision'],'requestId'=>uuid()],$assigned));$changed=data(call('inbox.sync',['cursor'=>$beforeCursor,'visibilityRevision'=>$visibility],$assigned));check(count($changed['items'])===1 && $changed['items'][0]['id']===$historic['id'],'historic read beyond top100 propagates through change cursor');
$beforeRev=data(call('inbox.sync',['cursor'=>0],$observer));data(call('scopes.removeMember',['scopeId'=>$scope,'userId'=>$users['observer'],'requestId'=>uuid()],$owner));
check(err(call('inbox.sync',['cursor'=>$beforeRev['cursor'],'visibilityRevision'=>$beforeRev['visibilityRevision']],$observer),'visibility_changed',409),'membership removal invalidates historic inbox cursor immediately');
check(count(inbox($observer,$scope))===0,'revoked member sees no historic private inbox references');
check(err(call('inbox.open',['id'=>$awareness[0]['id']],$observer),'permission_revoked',403),'historic open denied after membership removal');
echo 'SUCCESS '.$checks.' collaboration checks ('.$pdo->getAttribute(PDO::ATTR_DRIVER_NAME).')'.PHP_EOL;
