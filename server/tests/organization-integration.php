<?php
// Actual HTTP, fresh synthetic fixtures only; no existing account or volume reset.
require '/var/www/app/app/common.php';
if (!defined('FAMILYHUB_DEVELOPMENT_MODE') || FAMILYHUB_DEVELOPMENT_MODE !== true) { throw new RuntimeException('Development only'); }
$pdo=$container['db']->getConnection(); $checks=0; $prefix='org_'.bin2hex(random_bytes(6)); $password=bin2hex(random_bytes(18));
function uuid(){ $s=bin2hex(random_bytes(16));return substr($s,0,8).'-'.substr($s,8,4).'-4'.substr($s,13,3).'-a'.substr($s,17,3).'-'.substr($s,20); }
function check($condition,$description){global$checks;if(!$condition){throw new RuntimeException('FAIL: '.$description);}$checks++;echo 'PASS: '.$description.PHP_EOL;}
function call($operation,array$params=[],$token=null){$h=curl_init('http://127.0.0.1/index.php?controller=NativeApiController&action=handle&plugin=FamilyHub');$headers=['Content-Type: application/json'];if($token){$headers[]='Authorization: Bearer '.$token;}curl_setopt_array($h,[CURLOPT_POST=>true,CURLOPT_RETURNTRANSFER=>true,CURLOPT_HTTPHEADER=>$headers,CURLOPT_POSTFIELDS=>json_encode(['v'=>1,'op'=>$operation,'params'=>(object)$params])]);$raw=curl_exec($h);$status=curl_getinfo($h,CURLINFO_HTTP_CODE);curl_close($h);return['status'=>$status,'body'=>json_decode($raw,true,64,JSON_THROW_ON_ERROR)];}
function data($reply){if($reply['status']!==200){throw new RuntimeException('HTTP '.$reply['status'].' '.($reply['body']['error']['code']??'unknown'));}return$reply['body']['data'];}
function denied($reply,$code,$description){check(($reply['body']['error']['code']??'')===$code,$description);}
function operation($id,$type,$payload,$revision=0,$opId=null,$deleted=false){return['opId'=>$opId??uuid(),'recordId'=>$id,'type'=>$type,'expectedRevision'=>$revision,'deleted'=>$deleted,'payload'=>$payload];}
function push($scope,$op,$version=3){return['scopeId'=>$scope,'operation'=>$op,'operationContractVersion'=>$version];}
function invite($scope,$recipient,$owner,$recipientToken){$i=data(call('invitations.create',['scopeId'=>$scope,'recipientUsername'=>$recipient,'role'=>'member','requestId'=>uuid()],$owner));data(call('invitations.accept',['token'=>$i['token']],$recipientToken));}
$names=[];$ids=[];$sessions=[];
foreach(['owner','member','external','outsider']as$name){$names[$name]=$prefix.'_'.$name;$ids[$name]=$container['userModel']->create(['username'=>$names[$name],'password'=>$password,'role'=>'app-user']);$sessions[$name]=data(call('auth.login',['username'=>$names[$name],'password'=>$password,'deviceName'=>'Synthetic organization']));}
$o=$sessions['owner']['token'];$m=$sessions['member']['token'];$e=$sessions['external']['token'];$x=$sessions['outsider']['token'];
$caps=data(call('capabilities'));check(in_array(3,$caps['recordContractVersions'],true)&&$caps['features']['organizations']&&$caps['features']['householdPeople'],'rich and organization capabilities');
$org=uuid();$orgRequest=['id'=>$org,'kind'=>'organization','name'=>'Synthetic organization','requestId'=>uuid()];$created=data(call('scopes.create',$orgRequest,$o));check($created['scope']['requiredRecordContractVersion']===3,'organization requires rich client');check(data(call('scopes.create',$orgRequest,$o))['scope']['id']===$org,'organization create replay exact');
check(!in_array($org,array_column(data(call('scopes.list',[],$o))['scopes'],'id'),true),'legacy scope list hides unknown organization kind');
check(in_array($org,array_column(data(call('scopes.list',['includeOrganizations'=>true],$o))['scopes'],'id'),true),'new scope list includes authorized organization');
invite($org,$names['member'],$o,$m);
$child=uuid();$create=['id'=>$child,'kind'=>'project','name'=>'Actual created project','organizationId'=>$org,'requestId'=>uuid()];$project=data(call('scopes.create',$create,$o));check($project['scope']['organizationId']===$org&&$project['scope']['role']==='owner','organization owner explicitly owns created project');
$root=data(call('sync3.pull',['scopeId'=>$child,'cursor'=>0],$o))['records'];check(count($root)===1&&$root[0]['id']===$child&&$root[0]['payload']['title']===$create['name'],'project scope atomically contains real initial project');
denied(call('scopes.create',['id'=>uuid(),'kind'=>'project','name'=>'Forbidden','organizationId'=>$org,'requestId'=>uuid()],$m),'permission_revoked','organization member cannot create owner-only project');
denied(call('sync3.pull',['scopeId'=>$child,'cursor'=>0],$m),'permission_revoked','organization membership grants no child project access');
invite($child,$names['external'],$o,$e);
denied(call('sync3.pull',['scopeId'=>$org,'cursor'=>0],$e),'permission_revoked','external child member cannot read parent');
denied(call('scopes.members',['scopeId'=>$org],$e),'permission_revoked','external child member cannot enumerate parent members');
check(array_column(data(call('scopes.list',['includeOrganizations'=>true],$e))['scopes'],'id')===[$child],'external member sees only explicit child project');
denied(call('sync2.pull',['scopeId'=>$child,'cursor'=>0],$o),'client_upgrade_required','old client cannot truncate organization project metadata');
$sibling=uuid();data(call('scopes.create',['id'=>$sibling,'kind'=>'project','name'=>'Sibling project','organizationId'=>$org,'requestId'=>uuid()],$o));
denied(call('sync3.pull',['scopeId'=>$sibling,'cursor'=>0],$e),'permission_revoked','external project member cannot read sibling organization project');
$initialPayload=$root[0]['payload'];
denied(call('sync3.push',push($child,operation(uuid(),'project',$initialPayload)),$o),'project_scope_single_project','child owner cannot add another project to an organization project scope');
denied(call('sync3.push',push($child,operation(uuid(),'project',$initialPayload)),$e),'project_scope_single_project','external project editor cannot grow access by adding another project');
$initialPayload['title']='Renamed actual project';data(call('sync3.push',push($child,operation($child,'project',$initialPayload,1)),$o));
$scopeView=array_values(array_filter(data(call('scopes.list',['includeOrganizations'=>true],$o))['scopes'],fn($s)=>$s['id']===$child))[0];check($scopeView['name']==='Renamed actual project','project rename updates parent overview and space picker name');
$stamp='2026-10-08T04:00:00.000Z';$person=uuid();$profile=['name'=>'Synthetic person','notes'=>'No account','archived'=>false,'createdAt'=>$stamp,'updatedAt'=>$stamp];
data(call('sync3.push',push($child,operation($person,'householdPerson',$profile)),$o));
$q=$pdo->prepare('SELECT COUNT(*) FROM familyhub_inbox WHERE scope_id=? AND target_type=? AND target_id=?');$q->execute([$child,'householdPerson',$person]);check((int)$q->fetchColumn()===0,'person profile never creates notification recipient or event');$q->closeCursor();
$task=uuid();$payload=['title'=>'Person task','notes'=>'','projectId'=>$child,'dueAt'=>null,'isCompleted'=>false,'startAt'=>null,'endAt'=>null,'assigneeAccountIds'=>[],'phaseId'=>null,'estimateMinutes'=>60,'availabilityMinutes'=>60,'availabilityPeriod'=>'day','timer'=>['elapsedSeconds'=>0,'runningSince'=>null,'runId'=>null],'assigneePersonId'=>$person,'subjectPersonIds'=>[$person],'createdAt'=>$stamp,'updatedAt'=>$stamp];
check(data(call('sync3.push',push($child,operation($task,'task',$payload)),$o))['record']['payload']['assigneePersonId']===$person,'person task reference survives exact rich round trip');
$other=uuid();data(call('scopes.create',['id'=>$other,'kind'=>'household','name'=>'Other','requestId'=>uuid()],$o));
denied(call('sync3.push',push($other,operation(uuid(),'task',array_replace($payload,['projectId'=>null]))),$o),'person_missing','profile from another scope cannot be referenced');
$profile['archived']=true;data(call('sync3.push',push($child,operation($person,'householdPerson',$profile,1)),$o));
$payload['notes']='Retain historical person';check(data(call('sync3.push',push($child,operation($task,'task',$payload,1)),$o))['record']['revision']===2,'archived person remains valid historical task reference');
denied(call('sync3.push',push($child,operation(uuid(),'task',$payload)),$o),'person_archived','new task cannot assign archived profile');
denied(call('sync3.push',push($child,operation($person,'householdPerson',null,2,null,true)),$o),'live_children','deletion cannot silently lose person references');
$oldScope=uuid();data(call('scopes.create',['id'=>$oldScope,'kind'=>'project','name'=>'Legacy pending','requestId'=>uuid()],$o));$legacyId=uuid();$legacyPayload=['title'=>'Old operation','description'=>'','area'=>'home','startAt'=>null,'endAt'=>null,'createdAt'=>$stamp,'updatedAt'=>$stamp];$oldOp=operation($legacyId,'project',$legacyPayload);$oldParams=['scopeId'=>$oldScope,'operation'=>$oldOp];data(call('sync2.push',$oldParams,$o));
check(data(call('sync3.push',push($oldScope,$oldOp,2),$o))['replayed'],'new client replays immutable sync2 op with original hash');
invite($oldScope,$names['member'],$o,$m);
$legacyTask=uuid();$legacyTaskPayload=['title'=>'Legacy notification','notes'=>'','projectId'=>$legacyId,'dueAt'=>null,'isCompleted'=>false,'startAt'=>null,'endAt'=>null,'assigneeAccountIds'=>[],'createdAt'=>$stamp,'updatedAt'=>$stamp];
data(call('sync2.push',['scopeId'=>$oldScope,'operation'=>operation($legacyTask,'task',$legacyTaskPayload)],$o));
$legacyEvents=data(call('inbox.sync',['cursor'=>0,'limit'=>100],$m))['items'];$legacyEvent=array_values(array_filter($legacyEvents,fn($event)=>$event['targetId']===$legacyTask))[0];
$legacyOpen=data(call('inbox.open',['id'=>$legacyEvent['id'],'recordContractVersion'=>2,'financeContractVersion'=>1],$m));check(!array_key_exists('timer',$legacyOpen['record']['payload'])&&!array_key_exists('phaseId',$legacyOpen['record']['payload']),'explicit legacy inbox contract returns no rich defaults');
$modernOpen=data(call('inbox.open',['id'=>$legacyEvent['id'],'recordContractVersion'=>3],$m));check($modernOpen['record']['payload']['timer']['elapsedSeconds']===0,'modern inbox contract adds safe defaults to legacy task');
$modernTaskPayload=array_replace($legacyTaskPayload,['phaseId'=>null,'estimateMinutes'=>20,'availabilityMinutes'=>null,'availabilityPeriod'=>null,'timer'=>['elapsedSeconds'=>0,'runningSince'=>null,'runId'=>null],'assigneePersonId'=>null,'subjectPersonIds'=>[]]);
data(call('sync3.push',push($oldScope,operation($legacyTask,'task',$modernTaskPayload,1)),$o));
denied(call('inbox.open',['id'=>$legacyEvent['id'],'recordContractVersion'=>2],$m),'client_upgrade_required','legacy inbox caller gets clear upgrade for promoted rich task');
check(data(call('inbox.open',['id'=>$legacyEvent['id'],'recordContractVersion'=>3],$m))['record']['payload']['estimateMinutes']===20,'modern inbox opens rich task through historical notification');
$rich=array_replace($legacyPayload,['phases'=>[['id'=>'local-phase','title'=>'Phase','milestone'=>'Goal','startAt'=>null,'endAt'=>null]],'availabilityMinutes'=>120,'availabilityPeriod'=>'week']);data(call('sync3.push',push($oldScope,operation($legacyId,'project',$rich,1)),$o));
denied(call('sync2.push',['scopeId'=>$oldScope,'operation'=>operation($legacyId,'project',$legacyPayload,2)],$o),'client_upgrade_required','old update cannot erase rich phase metadata');
$pulled=data(call('sync3.pull',['scopeId'=>$oldScope,'cursor'=>0],$o));check(array_values(array_filter($pulled['records'],fn($row)=>$row['id']===$legacyId))[0]['payload']['phases'][0]['milestone']==='Goal','rich milestone survives old-client rejection');
$bad=array_replace($payload,['projectId'=>$child,'phaseId'=>'missing','assigneePersonId'=>null,'subjectPersonIds'=>[]]);denied(call('sync3.push',push($child,operation(uuid(),'task',$bad)),$o),'parent_missing','phase must belong to referenced project');
data(call('scopes.removeMember',['scopeId'=>$child,'userId'=>$ids['external'],'requestId'=>uuid()],$o));denied(call('sync3.pull',['scopeId'=>$child,'cursor'=>0],$e),'permission_revoked','revoked child membership immediately stops server access');
denied(call('sync3.pull',['scopeId'=>$other,'cursor'=>0],$x),'permission_revoked','unrelated household remains private');
check(data(call('finance.policy',['scopeId'=>$org],$m))['grant']==='none','organization membership never opens finance rights');
// Compound task + financial cost: both ACLs/CAS and receipts share one commit.
data(call('finance.enable',['scopeId'=>$child,'enabled'=>true,'requestId'=>uuid()],$o));
$account=uuid();$accountPayload=['name'=>'Synthetic ledger','currency'=>'EUR','openingBalanceMinor'=>null,'openingBalanceAt'=>null,'ownerAccountId'=>null,'archived'=>false,'createdAt'=>$stamp,'updatedAt'=>$stamp];
data(call('finance2.push',['scopeId'=>$child,'operation'=>operation($account,'financeAccount',$accountPayload)],$o));
$costTask=uuid();$costId=uuid();$costTaskPayload=array_replace($payload,['title'=>'Compound task','assigneePersonId'=>null,'subjectPersonIds'=>[],'dueAt'=>'2026-11-01T09:00:00.000Z']);
$costPayload=['accountId'=>$account,'kind'=>'expense','status'=>'planned','amountMinor'=>0,'currency'=>'EUR','title'=>'Synthetic task cost','notes'=>'','category'=>'','payerAccountId'=>null,'recipientAccountId'=>null,'occurredAt'=>$stamp,'plannedAt'=>$costTaskPayload['dueAt'],'paidAt'=>null,'taskId'=>$costTask,'ledgerAccountId'=>$account,'payerPersonId'=>null,'recipientPersonId'=>null,'createdByPersonId'=>null,'recurrenceRuleId'=>null,'occurrenceKey'=>null,'createdAt'=>$stamp,'updatedAt'=>$stamp];
$compound=push($child,operation($costTask,'task',$costTaskPayload));$compound['financeOperation']=operation($costId,'financeEntry',$costPayload);$compound['financeOperationContractVersion']=2;
denied(call('sync3.pushTaskWithCost',$compound,$o),'validation_error','invalid cost rolls back whole compound request');
$records=data(call('sync3.pull',['scopeId'=>$child,'cursor'=>0],$o))['records'];check(!in_array($costTask,array_column($records,'id'),true),'financial validation failure leaves no task record');
denied(call('sync3.pushTaskWithCost',$compound,$o),'validation_error','failed compound retry keeps immutable failed outcome');
$altered=$compound;$altered['financeOperation']['payload']['amountMinor']=1200;denied(call('sync3.pushTaskWithCost',$altered,$o),'idempotency_mismatch','failed compound operation ID cannot silently change body');
$compound['operation']['opId']=uuid();$compound['financeOperation']['opId']=uuid();
$costPayload['amountMinor']=1200;$compound['financeOperation']['payload']=$costPayload;
$applied=data(call('sync3.pushTaskWithCost',$compound,$o));check($applied['record']['id']===$costTask&&$applied['finance']['record']['id']===$costId,'compound commits exact task and financial cost once');
check(data(call('sync3.pushTaskWithCost',$compound,$o))['replayed'],'lost compound response retries both original operations safely');
invite($child,$names['member'],$o,$m);
$costTaskPayload['dueAt']='2026-11-03T09:00:00.000Z';
$derived=data(call('sync3.push',push($child,operation($costTask,'task',$costTaskPayload,1)),$m));
check(!isset($derived['finance'])&&!str_contains(json_encode($derived),'amountMinor'),'ordinary task editor without finance grant changes due without financial data response');
$costRecords=data(call('finance2.pull',['scopeId'=>$child,'cursor'=>0],$o))['records'];$costRecord=array_values(array_filter($costRecords,fn($r)=>$r['id']===$costId))[0];
check($costRecord['payload']['plannedAt']===$costTaskPayload['dueAt']&&$costRecord['payload']['amountMinor']===1200,'trusted task derivation moves planned date and preserves amount');
denied(call('finance2.pull',['scopeId'=>$child,'cursor'=>0],$m),'finance_forbidden','task membership still cannot read derived financial cost');
$forbidden=push($child,operation($costTask,'task',array_replace($costTaskPayload,['title'=>'Forbidden cost edit']),2));$forbidden['financeOperation']=operation($costId,'financeEntry',array_replace($costRecord['payload'],['amountMinor'=>999]),$costRecord['revision']);$forbidden['financeOperationContractVersion']=2;
$blocked=call('sync3.pushTaskWithCost',$forbidden,$m);denied($blocked,'finance_forbidden','explicit task cost edit requires separate financial write grant');check($blocked['body']['error']['details']===[],'compound ACL rejection exposes no financial snapshot');
$paidPayload=array_replace($costRecord['payload'],['status'=>'posted','paidAt'=>'2026-10-20T09:00:00.000Z','occurredAt'=>'2026-10-20T09:00:00.000Z']);
data(call('finance2.push',['scopeId'=>$child,'operation'=>operation($costId,'financeEntry',$paidPayload,$costRecord['revision'])],$o));
$costTaskPayload['dueAt']='2026-11-07T09:00:00.000Z';data(call('sync3.push',push($child,operation($costTask,'task',$costTaskPayload,2)),$m));
$costRecords=data(call('finance2.pull',['scopeId'=>$child,'cursor'=>0],$o))['records'];$costRecord=array_values(array_filter($costRecords,fn($r)=>$r['id']===$costId))[0];check($costRecord['payload']['paidAt']===$paidPayload['paidAt']&&$costRecord['payload']['occurredAt']===$paidPayload['occurredAt']&&$costRecord['payload']['status']==='posted','task reschedule never overwrites payment facts');
data(call('sync3.push',push($child,operation($costTask,'task',null,3,null,true)),$m));
$costRecords=data(call('finance2.pull',['scopeId'=>$child,'cursor'=>0],$o))['records'];$costRecord=array_values(array_filter($costRecords,fn($r)=>$r['id']===$costId))[0];check($costRecord['payload']['taskId']===null&&$costRecord['payload']['amountMinor']===1200,'task delete detaches and preserves historical financial entry');
// New financial targets open only after current financial rights are checked.
data(call('finance.grant',['scopeId'=>$child,'accountId'=>$sessions['member']['user']['accountId'],'grant'=>'read','requestId'=>uuid()],$o));
$ruleId=uuid();$rulePayload=['title'=>'Synthetic salary rule','kind'=>'salary','ledgerAccountId'=>$account,'currency'=>'EUR','estimatedAmountMinor'=>10000,'loanPrincipalMinor'=>null,'startYear'=>2026,'startMonth'=>11,'monthDay'=>25,'endYear'=>null,'endMonth'=>null,'active'=>true,'remindersEnabled'=>true,'reminderMinuteOfDay'=>540,'createdAt'=>$stamp,'updatedAt'=>$stamp];
data(call('finance2.push',['scopeId'=>$child,'operation'=>operation($ruleId,'financeRecurrenceRule',$rulePayload)],$o));
$events=data(call('inbox.sync',['cursor'=>0],$m))['items'];$ruleEvent=array_values(array_filter($events,fn($event)=>$event['targetId']===$ruleId))[0];
$open=data(call('inbox.open',['id'=>$ruleEvent['id'],'financeContractVersion'=>2],$m));check($open['record']['type']==='financeRecurrenceRule'&&$open['record']['contractVersion']===2,'new financial rule opens under finance contract with current rights');
denied(call('inbox.open',['id'=>$ruleEvent['id']],$m),'unsupported_version','old financial client cannot misinterpret rich financial rule');
check(data(call('inbox.group',['id'=>$ruleEvent['id']],$m))['items'][0]['targetId']===$ruleId,'new rule group opens under current financial read grant');
data(call('finance.grant',['scopeId'=>$child,'accountId'=>$sessions['member']['user']['accountId'],'grant'=>'none','requestId'=>uuid()],$o));
denied(call('inbox.group',['id'=>$ruleEvent['id']],$m),'finance_forbidden','finance revocation blocks opening a previously downloaded rule group');
$hidden=call('inbox.open',['id'=>$ruleEvent['id'],'financeContractVersion'=>2],$m);denied($hidden,'permission_revoked','finance revocation blocks opening stored financial rule reference');check(!isset($hidden['body']['data'])&&$hidden['body']['error']['details']===[],'denied new financial target reveals no payload');
// Recoverable archive suspends data writes, preserves history and allows ACL management.
$archiveParams=['scopeId'=>$child,'archived'=>true,'requestId'=>uuid()];
$recordsBeforeArchive=data(call('sync3.pull',['scopeId'=>$child,'cursor'=>0],$o))['records'];$moneyBeforeArchive=data(call('finance2.pull',['scopeId'=>$child,'cursor'=>0],$o))['records'];
check(data(call('scopes.archive',$archiveParams,$o))['scope']['archived'],'owner archives an organization project scope');
check(data(call('scopes.archive',$archiveParams,$o))['scope']['archived'],'archive request replay is idempotent');
check(!in_array($child,array_column(data(call('scopes.list',['includeOrganizations'=>true],$o))['scopes'],'id'),true),'archived project excluded from default active scope list');
$archivedScopes=data(call('scopes.list',['includeOrganizations'=>true,'includeArchived'=>true],$o))['scopes'];check(array_values(array_filter($archivedScopes,fn($s)=>$s['id']===$child))[0]['archived'],'archived project remains discoverable explicitly');
$archivedTask=array_replace($payload,['title'=>'Forbidden while archived']);denied(call('sync3.push',push($child,operation($task,'task',$archivedTask,2)),$o),'scope_archived','archived project rejects even owner data writes');
check(data(call('sync3.pull',['scopeId'=>$child,'cursor'=>0],$o))['records']===$recordsBeforeArchive,'archive preserves exact project/task/person records');
check(data(call('finance2.pull',['scopeId'=>$child,'cursor'=>0],$o))['records']===$moneyBeforeArchive,'archive preserves exact financial history');
$archivePolicy=data(call('finance2.policy',['scopeId'=>$child],$o));check($archivePolicy['grant']==='read','archived financial grant remains readable with writing suspended');
denied(call('reminders.put',['id'=>uuid(),'scopeId'=>$child,'targetType'=>'task','targetId'=>$task,'remindAt'=>gmdate('Y-m-d\TH:i:s\Z',time()+3600),'expectedRevision'=>0,'requestId'=>uuid()],$o),'scope_archived','archive prevents new active reminders');
data(call('scopes.removeMember',['scopeId'=>$child,'userId'=>$ids['member'],'requestId'=>uuid()],$o));denied(call('sync3.pull',['scopeId'=>$child,'cursor'=>0],$m),'permission_revoked','owner can still revoke archived project membership');
data(call('finance.grant',['scopeId'=>$child,'accountId'=>$sessions['owner']['user']['accountId'],'grant'=>'write','requestId'=>uuid()],$o));
check(!data(call('scopes.archive',['scopeId'=>$child,'archived'=>false,'requestId'=>uuid()],$o))['scope']['archived'],'owner restores project without deleting data');
check(data(call('finance2.policy',['scopeId'=>$child],$o))['grant']==='write','restore resumes existing financial writing grant');
check(data(call('sync3.pull',['scopeId'=>$child,'cursor'=>0],$o))['records']===$recordsBeforeArchive,'restore preserves canonical record revisions and content');
// Policy-v2 organization detachment keeps a foreign child private and intact.
$deleteName=$prefix.'_detach';$deleteId=$container['userModel']->create(['username'=>$deleteName,'password'=>$password,'role'=>'app-user']);$deleteSession=data(call('auth.login',['username'=>$deleteName,'password'=>$password,'deviceName'=>'Disposable detach'],$x));$d=$deleteSession['token'];
$detachOrg=uuid();data(call('scopes.create',['id'=>$detachOrg,'kind'=>'organization','name'=>'Disposable parent','requestId'=>uuid()],$d));
$foreignChild=uuid();data(call('scopes.create',['id'=>$foreignChild,'kind'=>'project','name'=>'Private external project','requestId'=>uuid()],$x));
// Synthetic transferred-project state: parent association itself grants no membership.
$pdo->prepare('UPDATE familyhub_scopes SET organization_id=?,required_record_contract=3 WHERE id=?')->execute([$detachOrg,$foreignChild]);
$foreignProject=$foreignChild;data(call('sync3.push',push($foreignChild,operation($foreignProject,'project',array_replace($rich,['title'=>'Private child content']))),$x));
data(call('finance.enable',['scopeId'=>$foreignChild,'enabled'=>true,'requestId'=>uuid()],$x));
$secretAccount=uuid();data(call('finance2.push',['scopeId'=>$foreignChild,'operation'=>operation($secretAccount,'financeAccount',array_replace($accountPayload,['name'=>'Private child ledger','openingBalanceMinor'=>777777,'openingBalanceAt'=>$stamp]))],$x));
$beforePolicy=data(call('finance2.policy',['scopeId'=>$foreignChild],$x));
denied(call('account.deletion.preview',[],$d),'client_upgrade_required','legacy deletion policy cannot implicitly detach organization projects');
$preview=data(call('account.deletion.preview',['policyVersion'=>2],$d));
$link=array_values(array_filter($preview['resolutions'],fn($r)=>$r['type']==='organizationProjectLink'))[0];
check($preview['policyVersion']===2&&$link['name']===null&&$link['childScopeId']===null&&$link['recordId']!==$foreignChild,'foreign child preview exposes opaque structural choice without identity or name');
check(!str_contains(json_encode($preview),'Private child')&&!str_contains(json_encode($preview),'777777'),'organization deletion preview excludes foreign financial and project details');
$confirm=['operationId'=>uuid(),'receiptToken'=>bin2hex(random_bytes(32)),'previewHash'=>$preview['previewHash'],'password'=>$password,'confirmation'=>'DELETE','ownedScopeDeletions'=>[$detachOrg],'policyVersion'=>2];
denied(call('account.deletion.confirm',$confirm,$d),'deletion_blocked','organization detach requires explicit structural decision');
$confirm['resolutions']=[['scopeId'=>$link['scopeId'],'recordId'=>$link['recordId'],'action'=>'detachOrganization']];
check(data(call('account.deletion.confirm',$confirm,$d))['deleted'],'explicit synthetic account deletion completes with structural detach');
$afterScope=array_values(array_filter(data(call('scopes.list',['includeOrganizations'=>true],$x))['scopes'],fn($s)=>$s['id']===$foreignChild))[0];
check($afterScope['organizationId']===null&&$afterScope['role']==='owner','retained child becomes standalone and retains explicit membership');
check(data(call('finance2.policy',['scopeId'=>$foreignChild],$x))===$beforePolicy,'organization detach changes no child finance grant or policy');
check(data(call('sync3.pull',['scopeId'=>$foreignChild,'cursor'=>0],$x))['records'][0]['payload']['title']==='Private child content','child project content remains intact');
check(data(call('finance2.pull',['scopeId'=>$foreignChild,'cursor'=>0],$x))['records'][0]['payload']['openingBalanceMinor']===777777,'child financial data remains intact');
// Removing a founder keeps the single root needed by the successor's tasks.
$founderName=$prefix.'_founder';$founderId=$container['userModel']->create(['username'=>$founderName,'password'=>$password,'role'=>'app-user']);$founder=data(call('auth.login',['username'=>$founderName,'password'=>$password,'deviceName'=>'Synthetic founder']));$f=$founder['token'];
$founderOrg=uuid();data(call('scopes.create',['id'=>$founderOrg,'kind'=>'organization','name'=>'Founder org','requestId'=>uuid()],$f));
$keptProject=uuid();data(call('scopes.create',['id'=>$keptProject,'kind'=>'project','name'=>'Founder project','organizationId'=>$founderOrg,'requestId'=>uuid()],$f));
$rootPayload=data(call('sync3.pull',['scopeId'=>$keptProject,'cursor'=>0],$f))['records'][0]['payload'];$rootPayload['description']='Private founder description';$rootPayload['phases']=[['id'=>'kept-phase','title'=>'Private phase title','milestone'=>'Private milestone','startAt'=>null,'endAt'=>null]];
data(call('sync3.push',push($keptProject,operation($keptProject,'project',$rootPayload,1)),$f));
invite($keptProject,$names['outsider'],$f,$x);
$foreignTaskId=uuid();$foreignTaskPayload=array_replace($payload,['title'=>'Successor task','projectId'=>$keptProject,'phaseId'=>'kept-phase','assigneePersonId'=>null,'subjectPersonIds'=>[]]);data(call('sync3.push',push($keptProject,operation($foreignTaskId,'task',$foreignTaskPayload)),$x));
$preview=data(call('account.deletion.preview',['policyVersion'=>2],$f));$resolutions=[];foreach($preview['resolutions']as$r){$resolutions[]=['scopeId'=>$r['scopeId'],'recordId'=>$r['recordId'],'action'=>$r['action']];}
$confirm=['operationId'=>uuid(),'receiptToken'=>bin2hex(random_bytes(32)),'previewHash'=>$preview['previewHash'],'password'=>$password,'confirmation'=>'DELETE','ownedScopeDeletions'=>[$founderOrg],'ownershipTransfers'=>[['scopeId'=>$keptProject,'successorAccountId'=>$sessions['outsider']['user']['accountId']]],'resolutions'=>$resolutions,'policyVersion'=>2];
check(data(call('account.deletion.confirm',$confirm,$f))['deleted'],'synthetic founder deletion resolves project root explicitly');
$kept=data(call('sync3.pull',['scopeId'=>$keptProject,'cursor'=>0],$x))['records'];$rootKept=array_values(array_filter($kept,fn($r)=>$r['id']===$keptProject))[0];$taskKept=array_values(array_filter($kept,fn($r)=>$r['id']===$foreignTaskId))[0];
check(!$rootKept['deleted']&&$rootKept['payload']['title']==='Shared project'&&$rootKept['payload']['description']===''&&$rootKept['payload']['phases'][0]['id']==='kept-phase'&&$rootKept['payload']['phases'][0]['milestone']==='','root remains structural with anonymized founder text and preserved phase IDs');
check($taskKept['payload']['projectId']===$keptProject&&$taskKept['payload']['phaseId']==='kept-phase'&&$taskKept['payload']['title']==='Successor task','successor task retains project and phase references');
$foreignTaskPayload['notes']='Still editable';check(data(call('sync3.push',push($keptProject,operation($foreignTaskId,'task',$foreignTaskPayload,1)),$x))['record']['revision']===2,'successor can edit retained project tasks after founder deletion');
echo 'PASS: '.$checks.' organization/person/rich HTTP checks ('.$pdo->getAttribute(PDO::ATTR_DRIVER_NAME).')'.PHP_EOL;
