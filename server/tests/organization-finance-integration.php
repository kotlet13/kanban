<?php
/** Synthetic finance4 ACL, canonical parent-account references and compatibility. */
umask(0077);
require '/var/www/app/app/common.php';if(session_status()===PHP_SESSION_ACTIVE){session_abort();}
if(!defined('FAMILYHUB_DEVELOPMENT_MODE')||FAMILYHUB_DEVELOPMENT_MODE!==true){throw new RuntimeException('Synthetic only');}
use Kanboard\Plugin\FamilyHub\Model\NativeService;
use Kanboard\Plugin\FamilyHub\Model\NativeError;
$pdo=$container['db']->getConnection();$service=new NativeService($container);$checks=0;$prefix='orgfin_'.bin2hex(random_bytes(5));$ip=$prefix;$password=bin2hex(random_bytes(16));$stamp='2026-10-17T10:00:00.000Z';
function check($v,$m){global$checks;if(!$v){throw new RuntimeException('FAIL: '.$m);}$checks++;echo 'PASS: '.$m.PHP_EOL;}
function q($s,$p=[]){global$pdo;$q=$pdo->prepare($s);$q->execute($p);$r=$q->fetchAll(PDO::FETCH_ASSOC);$q->closeCursor();return$r;}
function api($op,$p=[],$token=''){global$service,$ip;return$service->dispatch($op,$p,$token?'Bearer '.$token:'',$ip);}
function deny($op,$p,$token,$code){try{api($op,$p,$token);$ok=false;}catch(NativeError$e){$ok=$e->errorCode===$code;if(!$ok){throw new RuntimeException($op.' expected '.$code.' got '.$e->errorCode);}}check($ok,$op.' denies '.$code);}
function uuid(){$h=bin2hex(random_bytes(16));return substr($h,0,8).'-'.substr($h,8,4).'-4'.substr($h,13,3).'-a'.substr($h,17,3).'-'.substr($h,20);}
function user($suffix,$accept=true){global$container,$prefix,$password;$container['userModel']->create(['username'=>$prefix.'_'.$suffix,'password'=>$password,'role'=>'app-user']);$u=api('auth.login',['username'=>$prefix.'_'.$suffix,'password'=>$password,'deviceName'=>'Finance4 test']);if($accept){api('moderation.acceptPolicy',['policyVersion'=>1],$u['token']);}return$u;}
function scope($kind,$u,$parent=null){return api('scopes.create',['id'=>uuid(),'kind'=>$kind,'name'=>'Synthetic '.$kind,'accessPolicyVersion'=>3,'requestId'=>uuid()]+($parent?['parentScopeId'=>$parent]:[]),$u['token'])['scope'];}
function invite($s,$recipient,$owner,$role='member'){$i=api('invitations3.create',['scopeId'=>$s['id'],'recipient'=>$recipient['user']['username'],'role'=>$role,'requestId'=>uuid(),'language'=>'sl','accessScope'=>$s['kind']==='project'?'project':'space'],$owner['token']);api('invitations3.accept',['invitationId'=>$i['invitation']['id']],$recipient['token']);}
function op($scope,$id,$type,$payload,$revision=0){return['scopeId'=>$scope,'operation'=>['opId'=>uuid(),'recordId'=>$id,'type'=>$type,'expectedRevision'=>$revision,'deleted'=>$payload===null,'payload'=>$payload]];}
function account($name='Parent account'){global$stamp;return['name'=>$name,'currency'=>'EUR','openingBalanceMinor'=>123456,'ownerAccountId'=>null,'openingBalanceAt'=>null,'archived'=>false,'createdAt'=>$stamp,'updatedAt'=>$stamp];}
function entry($aid,$parent=null){global$stamp;return['accountId'=>$aid,'accountScopeId'=>$parent,'projectId'=>null,'kind'=>'expense','status'=>'posted','amountMinor'=>30000,'currency'=>'EUR','title'=>'Project expense','notes'=>'','category'=>'','payerAccountId'=>null,'recipientAccountId'=>null,'occurredAt'=>$stamp,'plannedAt'=>null,'paidAt'=>$stamp,'taskId'=>null,'ledgerAccountId'=>$aid,'payerPersonId'=>null,'recipientPersonId'=>null,'createdByPersonId'=>null,'recurrenceRuleId'=>null,'occurrenceKey'=>null,'createdAt'=>$stamp,'updatedAt'=>$stamp];}
$owner=user('owner');$member=user('narrow');$viewer=user('viewer');$foreign=user('foreign');$unaccepted=user('unaccepted',false);
$c=api('capabilities');check($c['features']['organizationFinance']&&$c['financeContractVersions']===[1,2,3]&&$c['organizationFinanceContractVersions']===[1],'explicit finance4 capability and record3 version');
foreach(['organization','household'] as $kind){
 $parent=scope($kind,$owner);$child=scope('project',$owner,$parent['id']);$sibling=scope('project',$owner,$parent['id']);$other=scope('organization',$owner);
 invite($child,$member,$owner);invite($child,$viewer,$owner,'viewer');
 $aid=uuid();$otherAid=uuid();$legacyAid=uuid();$eid=uuid();$body=account();
 $legacy=op($child['id'],$legacyAid,'financeAccount',account('Legacy project account'));api('finance2.push',$legacy,$owner['token']);
 $parentRequest=op($parent['id'],$aid,'financeAccount',$body);api('finance2.push',$parentRequest,$owner['token']);api('finance2.push',op($other['id'],$otherAid,'financeAccount',$body),$owner['token']);
 deny('finance4.push',op($child['id'],uuid(),'financeAccount',account()),$member['token'],'finance_account_parent_required');
 check(api('finance4.push',op($child['id'],$legacyAid,'financeAccount',account('Legacy renamed'),1),$member['token'])['record']['revision']===2,'existing project account stays editable without merging');
 $choices=api('finance4.accountChoices',['scopeId'=>$child['id']],$member['token']);
 check($choices['accountScopeId']===$parent['id']&&$choices['accessRevision']===api('finance4.policy',['scopeId'=>$child['id']],$member['token'])['revision'],'account choices are fenced by exact child finance policy revision');
 check(count($choices['accounts'])===1&&array_keys($choices['accounts'][0])===['scopeId','id','name','currency','archived']&&!str_contains(json_encode($choices),'123456'),'project-only choices contain names/currencies without opening balance or owner');
 check(api('finance4.accountChoices',['scopeId'=>$child['id']],$viewer['token'])['accounts']===$choices['accounts'],'project viewer can read same sanitized choices');
 deny('finance4.pull',['scopeId'=>$parent['id'],'cursor'=>0],$member['token'],'permission_revoked');deny('finance4.accountChoices',['scopeId'=>$child['id']],$foreign['token'],'permission_revoked');
 check(count(api('scopes.list',['includeOrganizations'=>true],$member['token'])['scopes'])===1,'account choices do not confer parent or sibling membership');
 $payload=entry($aid,$parent['id']);$request=op($child['id'],$eid,'financeEntry',$payload);$ack=api('finance4.push',$request,$member['token']);
 check($ack['record']['contractVersion']===3&&$ack['record']['payload']['accountScopeId']===$parent['id'],'canonical entry contract3 links immediate parent account');
 check(api('finance4.push',$request,$member['token'])['replayed']===true&&count(q('SELECT id FROM familyhub_finance_records WHERE id=?',[$eid]))===1,'lost ACK creates one canonical fact only');
 check(q('SELECT scope_id FROM familyhub_finance_records WHERE id=?',[$eid])[0]['scope_id']===$child['id'],'canonical project scope and its ACL remain unchanged');
 // Equal account UUID in another scope is a distinct, unreferenced legacy account.
 q("INSERT INTO familyhub_finance_records(scope_id,id,type,revision,deleted,payload,sequence,updated_at,created_by,updated_by,contract_version) VALUES(?,?,'financeAccount',1,0,?,0,?,?,?,2)",[$child['id'],$aid,json_encode(account('Equal UUID legacy account')),$stamp,$owner['user']['accountId'],$owner['user']['accountId']]);
 check(api('finance4.push',op($child['id'],$aid,'financeAccount',null,1),$member['token'])['record']['deleted'],'parent UUID equality does not lock distinct unused legacy project account');
 check(api('finance4.policy',['scopeId'=>$parent['id']],$owner['token'])['requiredContractVersion']===3,'parent minimum contract fences incomplete old-client balance');
 $visibility=api('finance4.policy',['scopeId'=>$parent['id']],$owner['token']);check($visibility['organizationFinanceComplete']&&$visibility['organizationFinanceScopeIds']===[$child['id']],'parent policy lists every readable canonical contributor');
 $sequences=(array)$visibility['organizationFinanceSequences'];check($sequences[$child['id']]===(int)q('SELECT sequence FROM familyhub_finance_policy WHERE scope_id=?',[$child['id']])[0]['sequence'],'parent policy fences exact required child finance cursor');
 q('INSERT INTO familyhub_moderation_blocks VALUES(?,?,?)',[$child['id'],$owner['user']['accountId'],time()]);
 $hidden=api('finance4.policy',['scopeId'=>$parent['id']],$owner['token']);check(!$hidden['organizationFinanceComplete']&&$hidden['organizationFinanceScopeIds']===[]&&(array)$hidden['organizationFinanceSequences']===[]&&!str_contains(json_encode($hidden),$child['id']),'hidden moderation contributor makes total incomplete without identity leakage');
 $hiddenPull=api('finance4.pull',['scopeId'=>$parent['id'],'cursor'=>0],$owner['token']);check(!$hiddenPull['organizationFinanceComplete']&&$hiddenPull['organizationFinanceScopeIds']===[]&&(array)$hiddenPull['organizationFinanceSequences']===[],'parent pull carries same completeness fence');
 q('DELETE FROM familyhub_moderation_blocks WHERE scope_id=? AND account_id=?',[$child['id'],$owner['user']['accountId']]);
 check(api('finance4.policy',['scopeId'=>$child['id']],$member['token'])['requiredContractVersion']===3,'project minimum contract3 preserved');
 foreach([$parent['id'],$child['id']] as $sid){deny('finance2.pull',['scopeId'=>$sid,'cursor'=>0],$owner['token'],'unsupported_version');deny('finance2.audit',['scopeId'=>$sid,'recordId'=>$aid],$owner['token'],'unsupported_version');}
 $bridge=$parentRequest+['operationContractVersion'=>2];check(api('finance4.push',$bridge,$owner['token'])['replayed']===true,'old accepted finance2 body replay preserved after upgrade');
 deny('finance2.push',op($parent['id'],uuid(),'financeAccount',account()),$owner['token'],'unsupported_version');
 deny('finance4.push',op($child['id'],uuid(),'financeEntry',$payload),$viewer['token'],'finance_forbidden');
 deny('finance4.push',op($child['id'],uuid(),'financeEntry',array_replace($payload,['accountScopeId'=>$other['id'],'accountId'=>$otherAid,'ledgerAccountId'=>$otherAid])),$member['token'],'parent_missing');
 deny('finance4.push',op($child['id'],uuid(),'financeEntry',array_replace($payload,['currency'=>'USD'])),$member['token'],'currency_mismatch');
 deny('finance4.push',op($child['id'],uuid(),'financeEntry',array_replace($payload,['accountId'=>uuid(),'ledgerAccountId'=>null])),$member['token'],'parent_missing');
 deny('finance4.push',op($child['id'],uuid(),'financeEntry',array_replace($payload,['projectId'=>$child['id']])),$member['token'],'parent_missing');
 deny('finance4.push',op($parent['id'],$aid,'financeAccount',null,1),$owner['token'],'live_children');
 $deletion=api('scopes.deletionPreview',['scopeId'=>$child['id']],$owner['token']);check(!$deletion['canDelete']&&in_array('cross_scope_finance_dependency',array_column($deletion['blockers'],'code'),true),'native child deletion cannot erase parent account history');
 $archive=array_replace($body,['archived'=>true]);api('finance4.push',op($parent['id'],$aid,'financeAccount',$archive,1),$owner['token']);
 deny('finance4.push',op($child['id'],uuid(),'financeEntry',$payload),$member['token'],'parent_missing');
 check(api('finance4.push',op($child['id'],$eid,'financeEntry',array_replace($payload,['notes'=>'Historical correction']),1),$member['token'])['record']['revision']===2,'unchanged archived account reference retains historical correction');
 check(api('finance4.accountChoices',['scopeId'=>$child['id']],$member['token'])['accounts'][0]['archived'],'choice marks archived account without leaking balance');
 deny('finance3.paymentCommit',['scopeId'=>$child['id'],'entryId'=>$eid,'expectedEntryRevision'=>2,'eventId'=>uuid(),'paidAt'=>$stamp,'expectReimbursement'=>true,'requestId'=>uuid()],$member['token'],$kind==='organization'?'linked_payment_source_locked':'organization_project_required');
 api('scopes.archive',['scopeId'=>$parent['id'],'archived'=>true,'requestId'=>uuid()],$owner['token']);
 check(api('finance4.accountChoices',['scopeId'=>$child['id']],$member['token'])['accounts']===[],'archived parent offers no writable account choices');
 deny('finance4.push',op($child['id'],uuid(),'financeEntry',$payload),$member['token'],'scope_archived');
 api('scopes.archive',['scopeId'=>$parent['id'],'archived'=>false,'requestId'=>uuid()],$owner['token']);
 api('scopes.removeMember',['scopeId'=>$child['id'],'userId'=>$member['user']['id'],'requestId'=>uuid()],$owner['token']);
 deny('finance4.accountChoices',['scopeId'=>$child['id']],$member['token'],'permission_revoked');deny('finance4.push',$request,$member['token'],'permission_revoked');
 check(count(api('finance4.pull',['scopeId'=>$parent['id'],'cursor'=>0],$owner['token'])['records'])===1,'parent pull stores only account; child entry is never duplicated');
 $beforeDelete=api('finance4.policy',['scopeId'=>$parent['id']],$owner['token']);api('finance4.push',op($child['id'],$eid,'financeEntry',null,2),$owner['token']);$afterDelete=api('finance4.policy',['scopeId'=>$parent['id']],$owner['token']);
 check($afterDelete['revision']>$beforeDelete['revision']&&$afterDelete['organizationFinanceComplete']&&$afterDelete['organizationFinanceScopeIds']===[]&&(array)$afterDelete['organizationFinanceSequences']===[],'last deleted contribution signals parent and removes source from current inventory');
}
// Inline tags validate exact same-scope project and archive/lifecycle boundaries.
$parent=scope('household',$owner);$aid=uuid();api('finance4.push',op($parent['id'],$aid,'financeAccount',account()),$owner['token']);$pid=uuid();
$project=['title'=>'Inline project','description'=>'','area'=>'home','startAt'=>null,'endAt'=>null,'phases'=>[],'availabilityMinutes'=>null,'availabilityPeriod'=>null,'archived'=>false,'createdAt'=>$stamp,'updatedAt'=>$stamp];
api('sync6.push',op($parent['id'],$pid,'project',$project),$owner['token']);$e=uuid();$tagged=array_replace(entry($aid),['projectId'=>$pid]);api('finance4.push',op($parent['id'],$e,'financeEntry',$tagged),$owner['token']);
check(api('finance4.pull',['scopeId'=>$parent['id'],'cursor'=>0],$owner['token'])['records'][1]['payload']['projectId']===$pid,'inline entry tags existing current-scope project');
deny('finance4.push',op($parent['id'],uuid(),'financeEntry',array_replace($tagged,['projectId'=>uuid()])),$owner['token'],'parent_missing');
$preview=api('scopes.projectSharingPreview',['scopeId'=>$parent['id'],'projectId'=>$pid],$owner['token']);check(!$preview['canApply']&&in_array('project_finance_scope_reference',array_column($preview['blockers'],'code'),true),'legacy extraction blocks unsupported tagged financial relocation');
api('sync6.push',op($parent['id'],$pid,'project',array_replace($project,['archived'=>true]),1),$owner['token']);
deny('finance4.push',op($parent['id'],$e,'financeEntry',$tagged,1),$owner['token'],'project_archived');
api('sync6.push',op($parent['id'],$pid,'project',$project,2),$owner['token']);
$preview=api('scopes.deletionPreview',['scopeId'=>$parent['id'],'projectId'=>$pid],$owner['token']);check($preview['counts']['finance']===1,'inline delete preview includes tagged canonical finance entry');
api('scopes.delete',['scopeId'=>$parent['id'],'projectId'=>$pid,'previewHash'=>$preview['previewHash'],'requestId'=>uuid()],$owner['token']);
check((int)q('SELECT deleted FROM familyhub_finance_records WHERE scope_id=? AND id=?',[$parent['id'],$e])[0]['deleted']===1,'inline deletion keeps its canonical finance tombstone');
// JSON null must remain same-scope on SQLite and both MySQL dialects.
$standalone=scope('project',$owner);$ownAccount=uuid();api('finance4.push',op($standalone['id'],$ownAccount,'financeAccount',account()),$owner['token']);api('finance4.push',op($standalone['id'],uuid(),'financeEntry',entry($ownAccount)),$owner['token']);
check(api('scopes.deletionPreview',['scopeId'=>$standalone['id']],$owner['token'])['canDelete'],'explicit null account scope does not create false cross-scope deletion blocker');
deny('finance4.push',op($standalone['id'],$ownAccount,'financeAccount',null,1),$owner['token'],'live_children');
// Compound task costs retain v3, reconcile dates atomically and roll back failures.
$root=scope('organization',$owner);$child=scope('project',$owner,$root['id']);$aid=uuid();api('finance4.push',op($root['id'],$aid,'financeAccount',account()),$owner['token']);$tid=uuid();$costId=uuid();
$task=['title'=>'Task with parent cost','notes'=>'','projectId'=>$child['id'],'dueAt'=>null,'isCompleted'=>false,'startAt'=>null,'endAt'=>null,'assigneeAccountIds'=>[],'phaseId'=>null,'estimateMinutes'=>null,'availabilityMinutes'=>null,'availabilityPeriod'=>null,'timer'=>['elapsedSeconds'=>0,'runningSince'=>null,'runId'=>null],'assigneePersonId'=>null,'subjectPersonIds'=>[],'createdAt'=>$stamp,'updatedAt'=>$stamp];
$cost=array_replace(entry($aid,$root['id']),['taskId'=>$tid,'status'=>'planned','paidAt'=>null]);
$compound=op($child['id'],$tid,'task',$task);$compound['financeOperation']=op($child['id'],$costId,'financeEntry',$cost)['operation'];$compound['financeOperationContractVersion']=3;$compound['operationContractVersion']=3;
$first=api('sync3.pushTaskWithCost',$compound,$owner['token']);check($first['finance']['record']['contractVersion']===3,'compound task cost persists finance3 contract atomically');
check(api('sync3.pushTaskWithCost',$compound,$owner['token'])['replayed'],'compound v3 lost ACK preserves canonical replay');
$policyBefore=api('finance4.policy',['scopeId'=>$root['id']],$owner['token']);
api('sync3.push',op($child['id'],$tid,'task',array_replace($task,['dueAt'=>'2026-10-20T10:00:00.000Z']),1),$owner['token']);
$costRow=q('SELECT * FROM familyhub_finance_records WHERE scope_id=? AND id=?',[$child['id'],$costId])[0];$costPayload=json_decode($costRow['payload'],true);
check((int)$costRow['contract_version']===3&&$costPayload['accountScopeId']===$root['id']&&$costPayload['plannedAt']==='2026-10-20T10:00:00.000Z','task reconciliation retains contract3 and parent reference');
check(api('finance4.policy',['scopeId'=>$root['id']],$owner['token'])['revision']>$policyBefore['revision'],'task reconciliation signals parent account view');
 $freshPolicy=api('finance4.policy',['scopeId'=>$root['id']],$owner['token']);$required=(array)$freshPolicy['organizationFinanceSequences'];$prior=(array)$policyBefore['organizationFinanceSequences'];check($required[$child['id']]>$prior[$child['id']],'unchanged contributor ID still demands newer child cursor after edit');
$bad=op($child['id'],uuid(),'task',$task);$bad['financeOperation']=op($child['id'],uuid(),'financeEntry',array_replace($cost,['taskId'=>$bad['operation']['recordId'],'accountId'=>uuid(),'ledgerAccountId'=>null]))['operation'];$bad['financeOperationContractVersion']=3;$bad['operationContractVersion']=3;
deny('sync3.pushTaskWithCost',$bad,$owner['token'],'parent_missing');check(q('SELECT id FROM familyhub_records WHERE scope_id=? AND id=?',[$child['id'],$bad['operation']['recordId']])===[],'failed parent-account validation rolls back task and cost together');
// Account deletion retains external ledger structure and refuses parent detach.
$deletion=api('account.deletion.preview',['policyVersion'=>3],$owner['token']);
$owned=array_values(array_filter($deletion['ownedScopes'],fn($s)=>$s['id']===$root['id']))[0];check(!$owned['canDeleteScope'],'account deletion cannot detach child from referenced parent ledger');
$author=user('author');invite($child,$author,$owner);$authorEntry=uuid();api('finance4.push',op($child['id'],$authorEntry,'financeEntry',entry($aid,$root['id'])),$author['token']);
$notification=q("SELECT id FROM familyhub_inbox WHERE scope_id=? AND target_id=? AND recipient_account_id=? ORDER BY id DESC",[$child['id'],$authorEntry,$owner['user']['accountId']]);
check((bool)$notification,'parent member receives canonical financial notification');
if($notification){$nid=(int)$notification[0]['id'];deny('inbox.open',['id'=>$nid,'financeContractVersion'=>2],$owner['token'],'unsupported_version');check(api('inbox.open',['id'=>$nid,'financeContractVersion'=>3],$owner['token'])['record']['payload']['accountScopeId']===$root['id'],'v3 notification opens exact canonical parent-account reference');}
$plan=api('account.deletion.preview',['policyVersion'=>3],$author['token']);$resolutions=array_map(fn($r)=>['scopeId'=>$r['scopeId'],'recordId'=>$r['recordId'],'action'=>$r['action']],$plan['resolutions']);
api('account.deletion.confirm',['operationId'=>uuid(),'receiptToken'=>bin2hex(random_bytes(32)),'previewHash'=>$plan['previewHash'],'password'=>$password,'confirmation'=>'DELETE','policyVersion'=>3,'resolutions'=>$resolutions],$author['token']);
$retained=q('SELECT * FROM familyhub_finance_records WHERE scope_id=? AND id=?',[$child['id'],$authorEntry])[0];check(!(int)$retained['deleted']&&json_decode($retained['payload'],true)['amountMinor']===30000&&json_decode($retained['payload'],true)['accountScopeId']===$root['id'],'author account deletion preserves parent-linked canonical financial history');
// Native policy acceptance also covers the new transport.
q("INSERT INTO familyhub_members(scope_id,user_id,account_id,role,active) VALUES(?,?,?,'member',1)",[$parent['id'],$unaccepted['user']['id'],$unaccepted['user']['accountId']]);
deny('finance4.push',op($parent['id'],uuid(),'financeAccount',account()),$unaccepted['token'],'policy_acceptance_required');
echo 'PASS: '.$checks.' organization finance checks ('.$pdo->getAttribute(PDO::ATTR_DRIVER_NAME).')'.PHP_EOL;
