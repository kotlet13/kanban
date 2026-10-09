<?php
// Actual HTTP, fresh synthetic fixtures only; no existing account or volume reset.
require '/var/www/app/app/common.php';
if (!defined('FAMILYHUB_DEVELOPMENT_MODE') || FAMILYHUB_DEVELOPMENT_MODE !== true) { throw new RuntimeException('Development only'); }
$pdo=$container['db']->getConnection();
\Kanboard\Plugin\FamilyHub\Schema\LinkedPaymentsSchema::create($pdo,$pdo->getAttribute(PDO::ATTR_DRIVER_NAME)!=='sqlite');
\Kanboard\Plugin\FamilyHub\Schema\SpacesSchema::create($pdo,$pdo->getAttribute(PDO::ATTR_DRIVER_NAME)!=='sqlite');
\Kanboard\Plugin\FamilyHub\Schema\SpacesSchema::create($pdo,$pdo->getAttribute(PDO::ATTR_DRIVER_NAME)!=='sqlite'); $checks=0; $prefix='spaces_'.bin2hex(random_bytes(6)); $password=bin2hex(random_bytes(18));
function uuid(){ $s=bin2hex(random_bytes(16));return substr($s,0,8).'-'.substr($s,8,4).'-4'.substr($s,13,3).'-a'.substr($s,17,3).'-'.substr($s,20); }
function check($condition,$description){global$checks;if(!$condition){throw new RuntimeException('FAIL: '.$description);}$checks++;echo 'PASS: '.$description.PHP_EOL;}
function call($operation,array$params=[],$token=null){$h=curl_init('http://127.0.0.1/index.php?controller=NativeApiController&action=handle&plugin=FamilyHub');$headers=['Content-Type: application/json'];if($token){$headers[]='Authorization: Bearer '.$token;}curl_setopt_array($h,[CURLOPT_POST=>true,CURLOPT_RETURNTRANSFER=>true,CURLOPT_HTTPHEADER=>$headers,CURLOPT_POSTFIELDS=>json_encode(['v'=>1,'op'=>$operation,'params'=>(object)$params])]);$raw=curl_exec($h);$status=curl_getinfo($h,CURLINFO_HTTP_CODE);curl_close($h);return['status'=>$status,'body'=>json_decode($raw,true,64,JSON_THROW_ON_ERROR)];}
function data($reply){if($reply['status']!==200){throw new RuntimeException('HTTP '.$reply['status'].' '.($reply['body']['error']['code']??'unknown'));}return$reply['body']['data'];}
function denied($reply,$code,$description){check(($reply['body']['error']['code']??'')===$code,$description);}
function operation($id,$type,$payload,$revision=0,$opId=null,$deleted=false){return['opId'=>$opId??uuid(),'recordId'=>$id,'type'=>$type,'expectedRevision'=>$revision,'deleted'=>$deleted,'payload'=>$payload];}
function push($scope,$op,$version=3){return['scopeId'=>$scope,'operation'=>$op,'operationContractVersion'=>$version];}
function invite($scope,$recipient,$owner,$recipientToken){$i=data(call('invitations.create',['scopeId'=>$scope,'recipientUsername'=>$recipient,'role'=>'member','requestId'=>uuid()],$owner));data(call('invitations.accept',['token'=>$i['token']],$recipientToken));}
function parallelCalls($calls) {
    $multi=curl_multi_init();$handles=[];
    foreach($calls as [$operation,$params,$token]) {$h=curl_init('http://127.0.0.1/index.php?controller=NativeApiController&action=handle&plugin=FamilyHub');curl_setopt_array($h,[CURLOPT_POST=>true,CURLOPT_RETURNTRANSFER=>true,CURLOPT_HTTPHEADER=>['Content-Type: application/json','Authorization: Bearer '.$token],CURLOPT_POSTFIELDS=>json_encode(['v'=>1,'op'=>$operation,'params'=>(object)$params])]);$handles[]=$h;curl_multi_add_handle($multi,$h);}
    do {curl_multi_exec($multi,$running);if($running){curl_multi_select($multi,0.1);}}while($running);
    $results=[];foreach($handles as $h){$results[]=['status'=>curl_getinfo($h,CURLINFO_HTTP_CODE),'body'=>json_decode(curl_multi_getcontent($h),true)];curl_multi_remove_handle($multi,$h);curl_close($h);}curl_multi_close($multi);return $results;
}
$names=[];$ids=[];$sessions=[];
foreach(['owner','member','external','outsider']as$name){$names[$name]=$prefix.'_'.$name;$ids[$name]=$container['userModel']->create(['username'=>$names[$name],'password'=>$password,'role'=>'app-user']);$sessions[$name]=data(call('auth.login',['username'=>$names[$name],'password'=>$password,'deviceName'=>'Synthetic organization']));}
$o=$sessions['owner']['token'];$m=$sessions['member']['token'];$e=$sessions['external']['token'];$x=$sessions['outsider']['token'];
$caps=data(call('capabilities'));check($caps['features']['organizationLeadership']&&$caps['features']['scopeAccessChanges']&&$caps['features']['householdGardenSync']&&in_array(4,$caps['recordContractVersions'],true),'spaces/garden versioned capabilities');
$org=uuid();$create=['id'=>$org,'kind'=>'organization','name'=>'Modern synthetic org','accessPolicyVersion'=>2,'requestId'=>uuid()];
foreach(['login-ip:','scopes-ip:','invitation-ip:','finance-ip:','inbox-ip:','sync-ip:'] as $key){$pdo->prepare('DELETE FROM familyhub_rate_limits WHERE id=?')->execute([hash('sha256',$key.'127.0.0.1')]);}
$created=data(call('scopes.create',$create,$o))['scope'];check($created['id']===$org&&$created['accessPolicyVersion']===2&&$created['organizationLeader'],'stable client UUID and owner default leadership');
check(data(call('scopes.create',$create,$o))['scope']===$created,'lost create response preserves exact identity and body');
invite($org,$names['member'],$o,$m);invite($org,$names['outsider'],$o,$x);
$child=uuid();data(call('scopes.create',['id'=>$child,'kind'=>'project','name'=>'Modern project','organizationId'=>$org,'requestId'=>uuid()],$o));
check(data(call('finance.policy',['scopeId'=>$child],$o))['enabled'],'modern organization projects enable finance without separate consent toggle');
denied(call('finance.enable',['scopeId'=>$child,'enabled'=>false,'requestId'=>uuid()],$o),'managed_by_organization_policy','policy2 cannot silently disable agreed project finance');
$invitation=data(call('invitations.create',['scopeId'=>$child,'recipientUsername'=>$names['external'],'role'=>'member','requestId'=>uuid()],$o));
check($invitation['invitation']['projectFinanceIncluded'],'project invitation discloses automatic finance read');
check(data(call('invitations.preview',['token'=>$invitation['token']]))['scope']['projectFinanceIncluded'],'public invitation preview discloses finance read');
denied(call('sync3.pull',['scopeId'=>$child,'cursor'=>0],$e),'permission_revoked','pending invitation grants no project access');
data(call('invitations.accept',['token'=>$invitation['token']],$e));
data(call('finance.enable',['scopeId'=>$child,'enabled'=>true,'requestId'=>uuid()],$o));
$stamp='2026-10-09T08:00:00.000Z';$account=uuid();$accountPayload=['name'=>'Organization ledger','currency'=>'EUR','openingBalanceMinor'=>0,'ownerAccountId'=>null,'createdAt'=>$stamp,'updatedAt'=>$stamp];
data(call('finance.push',['scopeId'=>$child,'operation'=>operation($account,'financeAccount',$accountPayload)],$o));
check(data(call('finance.policy',['scopeId'=>$child],$e))['grant']==='read','accepted member reads project finance without grant');
check(data(call('finance.pull',['scopeId'=>$child,'cursor'=>0],$e))['records'][0]['id']===$account,'automatic read includes complete project finance');
denied(call('finance.push',['scopeId'=>$child,'operation'=>operation(uuid(),'financeAccount',$accountPayload)],$e),'finance_forbidden','automatic project finance read never grants write');
data(call('finance.grant',['scopeId'=>$child,'accountId'=>$sessions['external']['user']['accountId'],'grant'=>'none','requestId'=>uuid()],$o));
check(data(call('finance.policy',['scopeId'=>$child],$e))['grant']==='read','removing explicit financial grant cannot bypass accepted-member read rule');
denied(call('finance.pull',['scopeId'=>$child,'cursor'=>0],$m),'permission_revoked','ordinary organization member has no child financial access');
$leader=['scopeId'=>$org,'accountId'=>$sessions['member']['user']['accountId'],'enabled'=>true,'requestId'=>uuid()];
denied(call('scopes.setLeader',$leader,$m),'permission_revoked','organization member cannot promote self');
$leadership=data(call('scopes.setLeader',$leader,$o));check(array_values(array_filter($leadership['members'],fn($r)=>$r['accountId']===$leader['accountId']))[0]['organizationLeader'],'owner explicitly grants leadership');
check(data(call('scopes.setLeader',$leader,$o))===$leadership,'leadership mutation replay exact');
$listed=data(call('scopes.list',['includeOrganizations'=>true,'includeAccessChanges'=>true],$m));$childView=array_values(array_filter($listed['scopes'],fn($r)=>$r['id']===$child))[0];
check($childView['role']==='viewer'&&$childView['accessSource']==='leadership'&&$childView['accessPolicyVersion']===2,'leader lists effective read-only existing project');
check(data(call('finance.pull',['scopeId'=>$child,'cursor'=>0],$m))['records'][0]['id']===$account,'leader reads all existing project finance');
check(data(call('sync3.pull',['scopeId'=>$child,'cursor'=>0],$m))['records'][0]['id']===$child,'leader reads existing project contents');
$future=uuid();data(call('scopes.create',['id'=>$future,'kind'=>'project','name'=>'Future project','organizationId'=>$org,'requestId'=>uuid()],$o));
check(data(call('sync3.pull',['scopeId'=>$future,'cursor'=>0],$m))['records'][0]['id']===$future,'leader automatically reads future project');
denied(call('sync3.push',push($child,operation(uuid(),'shoppingList',['title'=>'Forbidden','createdAt'=>$stamp,'updatedAt'=>$stamp])),$m),'permission_revoked','leadership is not project edit permission');
data(call('finance.enable',['scopeId'=>$org,'enabled'=>true,'requestId'=>uuid()],$o));
check(data(call('finance.policy',['scopeId'=>$org],$o))['managedByOrganizationPolicy'],'policy exposes managed state to client');
check(data(call('finance.policy',['scopeId'=>$org],$m))['grant']==='read','leader automatically reads general organization finance');
denied(call('finance.pull',['scopeId'=>$org,'cursor'=>0],$x),'finance_forbidden','ordinary org member cannot read general org finance');
$inbox=data(call('inbox.sync',['cursor'=>0],$e))['items'];$financeEvent=array_values(array_filter($inbox,fn($r)=>$r['targetId']===$account))[0];
check(data(call('inbox.open',['id'=>$financeEvent['id']],$e))['record']['id']===$account,'project-member financial inbox opens through central effective ACL');
$leaderInbox=data(call('inbox.sync',['cursor'=>0],$m))['items'];check(!array_filter($leaderInbox,fn($r)=>$r['targetId']===$account),'leadership does not subscribe to all project notifications');
$before=data(call('finance.policy',['scopeId'=>$child],$m));
$removeLeader=['scopeId'=>$org,'accountId'=>$leader['accountId'],'enabled'=>false,'requestId'=>uuid()];data(call('scopes.setLeader',$removeLeader,$o));
denied(call('finance.pull',['scopeId'=>$child,'cursor'=>0],$m),'permission_revoked','revoked leadership immediately blocks project finance');
$revoked=data(call('scopes.list',['includeOrganizations'=>true,'includeAccessChanges'=>true],$m))['revokedScopeIds'];check(in_array($child,$revoked,true)&&in_array($future,$revoked,true),'positive revocation journal identifies lost derived scopes');
data(call('scopes.setLeader',array_replace($leader,['requestId'=>uuid()]),$o));
check(data(call('finance.policy',['scopeId'=>$child],$m))['revision']>$before['revision'],'leadership changes advance financial access revision');
check(!in_array($child,data(call('scopes.list',['includeAccessChanges'=>true],$m))['revokedScopeIds'],true),'restored effective rights clear prior revoke evidence');
invite($child,$names['member'],$o,$m);
data(call('scopes.setLeader',array_replace($removeLeader,['requestId'=>uuid()]),$o));
check(data(call('finance.policy',['scopeId'=>$child],$m))['grant']==='read','direct project membership survives leadership revoke');
check(!in_array($child,data(call('scopes.list',['includeAccessChanges'=>true],$m))['revokedScopeIds'],true),'alternate direct rights prevent false revoke journal entry');
data(call('scopes.removeMember',['scopeId'=>$child,'userId'=>$ids['external'],'requestId'=>uuid()],$o));
denied(call('inbox.open',['id'=>$financeEvent['id']],$e),'permission_revoked','confirmed member revoke blocks previously stored financial reference');
check(in_array($child,data(call('scopes.list',['includeAccessChanges'=>true],$e))['revokedScopeIds'],true),'confirmed direct revoke has positive listing evidence');
denied(call('sync3.pull',['scopeId'=>uuid(),'cursor'=>0],$e),'scope_unavailable','missing scope is reconciliation, not confirmed revoke');
check(!isset(data(call('scopes.list',[],$e))['revokedScopeIds']),'legacy scope list response remains opt-in');
$house=uuid();$housePublication=['id'=>$house,'kind'=>'household','name'=>'Unrelated household','address'=>'Original local address','requestId'=>uuid()];$houseWire=data(call('scopes.create',$housePublication,$o))['scope'];check($houseWire['address']==='Original local address'&&$houseWire['metadataRevision']===0,'initial publication retains local household address');
$metadata=['scopeId'=>$house,'name'=>'Updated home','address'=>'Updated address','expectedRevision'=>0,'requestId'=>uuid()];$updatedHouse=data(call('scopes.updateMetadata',$metadata,$o));check($updatedHouse['scope']['address']==='Updated address'&&$updatedHouse['scope']['metadataRevision']===1,'owner updates scoped metadata with authoritative revision');check(data(call('scopes.updateMetadata',$metadata,$o))===$updatedHouse,'metadata lost-response retry exact');denied(call('scopes.updateMetadata',array_replace($metadata,['requestId'=>uuid()]),$o),'metadata_conflict','stale metadata editor cannot overwrite another update');
denied(call('sync3.pull',['scopeId'=>$house,'cursor'=>0],$m),'permission_revoked','leadership cannot cross into another household');
denied(call('scopes.setLeader',['scopeId'=>$org,'accountId'=>$sessions['external']['user']['accountId'],'enabled'=>true,'requestId'=>uuid()],$o),'assignee_not_member','leader grant requires accepted organization membership');
denied(call('scopes.setLeader',['scopeId'=>$org,'accountId'=>$sessions['owner']['user']['accountId'],'enabled'=>false,'requestId'=>uuid()],$o),'cannot_remove_owner','organization owner default leadership cannot be disabled');
// Legacy organizations change only after an exact, current preview.
$unled=['scopeId'=>$org,'accountId'=>$sessions['outsider']['user']['accountId'],'enabled'=>false,'requestId'=>uuid()];data(call('scopes.setLeader',$unled,$o));
check(!in_array($future,data(call('scopes.list',['includeAccessChanges'=>true],$x))['revokedScopeIds'],true),'nonleader disable never leaks inaccessible project IDs through revocation journal');
$legacy=uuid();data(call('scopes.create',['id'=>$legacy,'kind'=>'organization','name'=>'Legacy org','requestId'=>uuid()],$o));$oldChild=uuid();data(call('scopes.create',['id'=>$oldChild,'kind'=>'project','name'=>'Legacy project','organizationId'=>$legacy,'requestId'=>uuid()],$o));invite($oldChild,$names['external'],$o,$e);
data(call('finance.enable',['scopeId'=>$oldChild,'enabled'=>true,'requestId'=>uuid()],$o));
denied(call('finance.pull',['scopeId'=>$oldChild,'cursor'=>0],$e),'finance_forbidden','omitted access policy preserves historic financial isolation');
$disabledChild=uuid();data(call('scopes.create',['id'=>$disabledChild,'kind'=>'project','name'=>'Disabled legacy project','organizationId'=>$legacy,'requestId'=>uuid()],$o));invite($disabledChild,$names['external'],$o,$e);
$preview=data(call('scopes.accessMigrationPreview',['scopeId'=>$legacy],$o));$disabledPreview=array_values(array_filter($preview['projects'],fn($p)=>$p['scopeId']===$disabledChild))[0];check(!$disabledPreview['financeWasEnabled']&&in_array($sessions['external']['user']['accountId'],array_column($disabledPreview['additionalReaders'],'accountId'),true),'disabled legacy finance reader expansion is explicit in preview');
$enabledPreview=array_values(array_filter($preview['projects'],fn($p)=>$p['scopeId']===$oldChild))[0];check($preview['fromVersion']===1&&$preview['toVersion']===2&&$enabledPreview['additionalReaders'][0]['accountId']===$sessions['external']['user']['accountId'],'migration preview lists users gaining project financial read');
data(call('finance.grant',['scopeId'=>$oldChild,'accountId'=>$sessions['external']['user']['accountId'],'grant'=>'read','requestId'=>uuid()],$o));
denied(call('scopes.accessMigrationApply',['scopeId'=>$legacy,'previewHash'=>$preview['previewHash'],'requestId'=>uuid()],$o),'access_preview_changed','stale finance/member preview cannot widen rights');
$preview=data(call('scopes.accessMigrationPreview',['scopeId'=>$legacy],$o));
invite($oldChild,$names['outsider'],$o,$x);
denied(call('scopes.accessMigrationApply',['scopeId'=>$legacy,'previewHash'=>$preview['previewHash'],'requestId'=>uuid()],$o),'access_preview_changed','accepted child member invalidates migration preview');
$preview=data(call('scopes.accessMigrationPreview',['scopeId'=>$legacy],$o));$apply=['scopeId'=>$legacy,'previewHash'=>$preview['previewHash'],'requestId'=>uuid()];$applied=data(call('scopes.accessMigrationApply',$apply,$o));check($applied['scope']['accessPolicyVersion']===2,'current explicit preview applies policy2');check(data(call('scopes.accessMigrationApply',$apply,$o))===$applied,'migration apply survives lost response exactly');
check(data(call('finance.policy',['scopeId'=>$disabledChild],$e))['enabled']&&data(call('finance.policy',['scopeId'=>$disabledChild],$e))['grant']==='read','explicit migration enables previously disabled project finances');
// Stable local project publication retains its original domain timestamp and phase identity.
$localProject=uuid();$initial=['title'=>'Originally local','description'=>'Local notes','area'=>'home','startAt'=>null,'endAt'=>null,'phases'=>[['id'=>'phase-local','title'=>'Preparation','milestone'=>'Ready','startAt'=>null,'endAt'=>null]],'availabilityMinutes'=>60,'availabilityPeriod'=>'day','createdAt'=>'2025-01-01T08:00:00.000Z','updatedAt'=>$stamp];
$publish=['id'=>$localProject,'kind'=>'project','name'=>$initial['title'],'organizationId'=>$org,'projectPayload'=>$initial,'requestId'=>uuid()];
data(call('scopes.create',$publish,$o));check(data(call('sync3.pull',['scopeId'=>$localProject,'cursor'=>0],$o))['records'][0]['payload']===$initial,'local project publication preserves createdAt/phases and UUID');check(data(call('scopes.create',$publish,$o))['scope']['id']===$localProject,'exact local project publication retry keeps one root');
// Garden sync is complete bounded document CRUD with shared household permissions.
data(call('finance.enable',['scopeId'=>$house,'enabled'=>true,'requestId'=>uuid()],$o));$houseAccount=uuid();data(call('finance.push',['scopeId'=>$house,'operation'=>operation($houseAccount,'financeAccount',$accountPayload)],$o));
$priorTask=uuid();$priorCost=uuid();$taskPayload=['title'=>'Task beside garden','notes'=>'','projectId'=>null,'dueAt'=>null,'isCompleted'=>false,'startAt'=>null,'endAt'=>null,'assigneeAccountIds'=>[],'phaseId'=>null,'estimateMinutes'=>null,'availabilityMinutes'=>null,'availabilityPeriod'=>null,'timer'=>['elapsedSeconds'=>0,'runningSince'=>null,'runId'=>null],'assigneePersonId'=>null,'subjectPersonIds'=>[],'createdAt'=>$stamp,'updatedAt'=>$stamp];
$costPayload=['accountId'=>$houseAccount,'kind'=>'expense','status'=>'planned','amountMinor'=>3000,'currency'=>'EUR','title'=>'Garden cost','notes'=>'','category'=>'','payerAccountId'=>null,'recipientAccountId'=>null,'occurredAt'=>$stamp,'plannedAt'=>null,'paidAt'=>null,'taskId'=>$priorTask,'ledgerAccountId'=>$houseAccount,'payerPersonId'=>null,'recipientPersonId'=>null,'createdByPersonId'=>null,'recurrenceRuleId'=>null,'occurrenceKey'=>null,'createdAt'=>$stamp,'updatedAt'=>$stamp];
$priorPair=['scopeId'=>$house,'operation'=>operation($priorTask,'task',$taskPayload),'operationContractVersion'=>3,'financeOperation'=>operation($priorCost,'financeEntry',$costPayload),'financeOperationContractVersion'=>2];data(call('sync3.pushTaskWithCost',$priorPair,$o));
$garden=uuid();$gardenPayload=['version'=>2,'id'=>$garden,'name'=>'Household garden','notes'=>'Shared notes','areas'=>[['id'=>'bed-stable','label'=>'Bed','x'=>0.1,'y'=>0.1,'width'=>0.5,'height'=>0.5,'kind'=>'bed','archived'=>false]],'seasons'=>[['year'=>2026,'notes'=>'Season','plantings'=>[['id'=>'plant-stable','areaId'=>'bed-stable','crop'=>'Carrot','variety'=>'','family'=>'Apiaceae','status'=>'planned','notes'=>'','sowAt'=>'2026-03-01','plantAt'=>null,'harvestAt'=>'2026-09-01']]]],'revision'=>0,'createdAt'=>$stamp,'updatedAt'=>$stamp];
invite($house,$names['external'],$o,$e);
$gardenOp=['scopeId'=>$house,'operation'=>operation($garden,'garden',$gardenPayload),'operationContractVersion'=>4];
$added=data(call('sync4.push',$gardenOp,$o));check($added['record']['payload']===$gardenPayload,'garden format2 preserves every stable ID/calendar/payload field');check(data(call('sync4.push',$gardenOp,$o))['replayed'],'garden lost-response retry does not duplicate');
check(data(call('sync4.pushTaskWithCost',$priorPair,$o))['replayed'],'contract4 compound bridge replays original contract3 pair/hash after garden');
$plainTask=uuid();check(data(call('sync4.push',['scopeId'=>$house,'operation'=>operation($plainTask,'task',$taskPayload),'operationContractVersion'=>3],$o))['record']['id']===$plainTask,'garden household accepts ordinary task3 over transport4');
$pairedTask=uuid();$pairedCost=uuid();$newPair=['scopeId'=>$house,'operation'=>operation($pairedTask,'task',$taskPayload),'operationContractVersion'=>3,'financeOperation'=>operation($pairedCost,'financeEntry',array_replace($costPayload,['taskId'=>$pairedTask])),'financeOperationContractVersion'=>2];
$paired=data(call('sync4.pushTaskWithCost',$newPair,$o));check($paired['record']['id']===$pairedTask&&$paired['finance']['record']['id']===$pairedCost,'garden household atomically accepts task3/finance2 cost over transport4');check(data(call('sync4.pushTaskWithCost',$newPair,$o))['replayed'],'transport4 compound retry preserves both immutable operation IDs');
check(array_values(array_filter(data(call('sync4.pull',['scopeId'=>$house,'cursor'=>0],$e))['records'],fn($r)=>$r['id']===$garden))[0]['payload']===$gardenPayload,'accepted household member receives garden');
denied(call('sync3.pull',['scopeId'=>$house,'cursor'=>0],$e),'client_upgrade_required','older client cannot truncate a garden household');
denied(call('sync4.pull',['scopeId'=>$house,'cursor'=>0],$m),'permission_revoked','organization leadership never opens household garden');
$changed=array_replace($gardenPayload,['notes'=>'Member update']);$update=['scopeId'=>$house,'operation'=>operation($garden,'garden',$changed,1),'operationContractVersion'=>4];
check(data(call('sync4.push',$update,$e))['record']['revision']===2,'household garden edit honors canonical revision');
denied(call('sync4.push',['scopeId'=>$house,'operation'=>operation($garden,'garden',$gardenPayload,1),'operationContractVersion'=>4],$o),'conflict','concurrent garden edit has visible immutable conflict');
$invalid=$changed;$invalid['seasons'][0]['plantings'][0]['harvestAt']='2026-02-30';denied(call('sync4.push',['scopeId'=>$house,'operation'=>operation($garden,'garden',$invalid,2),'operationContractVersion'=>4],$e),'invalid_date_range','invalid garden calendar day rejected');
denied(call('sync4.push',['scopeId'=>$org,'operation'=>operation($garden,'garden',$gardenPayload),'operationContractVersion'=>4],$o),'validation_error','garden cannot publish to organization');
$wrongId=$changed;$wrongId['id']=uuid();denied(call('sync4.push',['scopeId'=>$house,'operation'=>operation($garden,'garden',$wrongId,2),'operationContractVersion'=>4],$o),'validation_error','garden envelope and payload identity must match');
$delete=['scopeId'=>$house,'operation'=>operation($garden,'garden',null,2,null,true),'operationContractVersion'=>4];check(data(call('sync4.push',$delete,$e))['record']['deleted'],'garden deletion is retained tombstone');check(data(call('sync4.push',$delete,$e))['replayed'],'garden tombstone retry exact');
data(call('scopes.removeMember',['scopeId'=>$house,'userId'=>$ids['external'],'requestId'=>uuid()],$o));denied(call('sync4.push',$delete,$e),'permission_revoked','revoked garden member cannot replay prior success');
// Real HTTP race has a valid serialized outcome and never restores revoked read.
data(call('scopes.setLeader',array_replace($leader,['requestId'=>uuid()]),$o));
$race=parallelCalls([['sync3.pull',['scopeId'=>$future,'cursor'=>0],$m],['scopes.setLeader',array_replace($removeLeader,['requestId'=>uuid()]),$o]]);
check($race[1]['status']===200&&in_array($race[0]['status'],[200,403],true),'concurrent leadership revoke/project read serializes under parent lock');
denied(call('sync3.pull',['scopeId'=>$future,'cursor'=>0],$m),'permission_revoked','post-race project read cannot restore revoked leadership');
data(call('scopes.setLeader',array_replace($leader,['requestId'=>uuid()]),$o));
data(call('scopes.removeMember',['scopeId'=>$org,'userId'=>$ids['member'],'requestId'=>uuid()],$o));
check(data(call('finance.policy',['scopeId'=>$child],$m))['grant']==='read','removing org member clears leadership while retaining independent project membership');
denied(call('sync3.pull',['scopeId'=>$future,'cursor'=>0],$m),'permission_revoked','removed org member has no stale future-project leadership');
$statement=$pdo->prepare('SELECT COUNT(*) FROM familyhub_organization_leaders WHERE scope_id=? AND account_id=?');$statement->execute([$org,$leader['accountId']]);check((int)$statement->fetchColumn()===0,'org member removal purges stored leadership grant');$statement->closeCursor();
$deleteName=$prefix.'_deletable';$deleteId=$container['userModel']->create(['username'=>$deleteName,'password'=>$password,'role'=>'app-user']);$deleteSession=data(call('auth.login',['username'=>$deleteName,'password'=>$password,'deviceName'=>'Disposable leader']));$d=$deleteSession['token'];
invite($org,$deleteName,$o,$d);data(call('scopes.setLeader',['scopeId'=>$org,'accountId'=>$deleteSession['user']['accountId'],'enabled'=>true,'requestId'=>uuid()],$o));
$deletePreview=data(call('account.deletion.preview',['policyVersion'=>2],$d));
check(data(call('account.deletion.confirm',['operationId'=>uuid(),'receiptToken'=>bin2hex(random_bytes(32)),'previewHash'=>$deletePreview['previewHash'],'password'=>$password,'confirmation'=>'DELETE','policyVersion'=>2],$d))['deleted'],'synthetic leader account deletion completes through fresh preview');
$statement=$pdo->prepare('SELECT COUNT(*) FROM familyhub_organization_leaders WHERE account_id=?');$statement->execute([$deleteSession['user']['accountId']]);check((int)$statement->fetchColumn()===0,'account deletion purges leadership grant');$statement->closeCursor();
echo 'PASS: '.$checks.' spaces access/garden HTTP checks ('.$pdo->getAttribute(PDO::ATTR_DRIVER_NAME).')'.PHP_EOL;
