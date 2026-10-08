<?php
require '/var/www/app/app/common.php';
if(!defined('FAMILYHUB_DEVELOPMENT_MODE')||FAMILYHUB_DEVELOPMENT_MODE!==true){throw new RuntimeException('Development only');}
use Kanboard\Plugin\FamilyHub\Model\NativeService;
use Kanboard\Plugin\FamilyHub\Model\NativeError;
$service=new NativeService($container);$ip='finance-plan-'.bin2hex(random_bytes(12));$checks=0;$password=bin2hex(random_bytes(20));$prefix='fp_'.bin2hex(random_bytes(8));
function uid(){$h=bin2hex(random_bytes(16));return substr($h,0,8).'-'.substr($h,8,4).'-4'.substr($h,13,3).'-a'.substr($h,17,3).'-'.substr($h,20);}
function api($operation,$params=[],$token=''){global$service,$ip;return $service->dispatch($operation,$params,$token?'Bearer '.$token:'',$ip);}
function check($ok,$description){global$checks;if(!$ok)throw new RuntimeException('FAIL: '.$description);$checks++;echo 'PASS: '.$description.PHP_EOL;}
function denied($operation,$params,$token,$code,$description){try{api($operation,$params,$token);$ok=false;}catch(NativeError$e){$ok=$e->errorCode===$code;}check($ok,$description);}
function operation($scope,$id,$type,$payload,$revision=0,$opId=null){return ['scopeId'=>$scope,'operation'=>['opId'=>$opId??uid(),'recordId'=>$id,'type'=>$type,'expectedRevision'=>$revision,'deleted'=>false,'payload'=>$payload]];}
function user($name){global$container,$prefix,$password;$container['userModel']->create(['username'=>$prefix.$name,'password'=>$password,'role'=>'app-user']);return api('auth.login',['username'=>$prefix.$name,'password'=>$password,'deviceName'=>'Finance planning test']);}
$owner=user('owner');$foreign=user('foreign');$token=$owner['token'];
$scope=api('personal.ensure',[],$token)['scope']['id'];$now=gmdate('Y-m-d\TH:i:s\Z');
$accountId=uid();$account=['name'=>'Personal ledger','currency'=>'EUR','openingBalanceMinor'=>null,'openingBalanceAt'=>null,'archived'=>false,'createdAt'=>$now,'updatedAt'=>$now];
$a=api('finance2.push',operation($scope,$accountId,'personalFinanceAccount',$account),$token);
check($a['record']['contractVersion']===2&&$a['record']['createdByAccountId']===$owner['user']['accountId'],'finance2 author is authenticated actor, independent of participants');
$ruleId=uid();$rule=['title'=>'Expected salary','kind'=>'salary','ledgerAccountId'=>$accountId,'currency'=>'EUR','estimatedAmountMinor'=>123400,'loanPrincipalMinor'=>null,'startYear'=>2026,'startMonth'=>10,'monthDay'=>31,'endYear'=>null,'endMonth'=>null,'active'=>true,'remindersEnabled'=>false,'reminderMinuteOfDay'=>540,'createdAt'=>$now,'updatedAt'=>$now];
api('finance2.push',operation($scope,$ruleId,'financeRecurrenceRule',$rule),$token);
$entryId=uid();$payload=['title'=>'Expected salary','amountMinor'=>123400,'currency'=>'EUR','kind'=>'income','occurredAt'=>$now,'projectId'=>null,'notes'=>'','status'=>'planned','plannedAt'=>$now,'paidAt'=>null,'taskId'=>null,'ledgerAccountId'=>$accountId,'payerPersonId'=>null,'recipientPersonId'=>null,'createdByPersonId'=>null,'recurrenceRuleId'=>$ruleId,'occurrenceKey'=>'2026-10','createdAt'=>$now,'updatedAt'=>$now];
$request=operation($scope,$entryId,'personalFinanceEntry',$payload);$first=api('finance2.push',$request,$token);
check(api('finance2.push',$request,$token)['replayed']===true,'lost ACK replays same monthly occurrence without second audit');
try{api('finance2.push',operation($scope,uid(),'personalFinanceEntry',$payload),$token);$duplicate=null;}catch(NativeError$e){$duplicate=$e;}
check($duplicate&&$duplicate->errorCode==='duplicate_finance_reference'&&$duplicate->details['existingRecord']['id']===$entryId,'second device creation returns existing canonical occurrence');
$actual=array_replace($payload,['amountMinor'=>129900,'status'=>'posted','paidAt'=>$now]);
$posted=api('finance2.push',operation($scope,$entryId,'personalFinanceEntry',$actual,1),$token);
check($posted['record']['id']===$entryId&&$posted['record']['payload']['plannedAt']===$payload['plannedAt']&&$posted['record']['payload']['amountMinor']===129900,'different actual amount posts same occurrence with original expected date');
check(count(api('finance2.audit',['scopeId'=>$scope,'recordId'=>$entryId],$token)['entries'])===2,'confirmation and retry create exactly two audit revisions');
$changed=api('finance2.push',operation($scope,$ruleId,'financeRecurrenceRule',array_replace($rule,['estimatedAmountMinor'=>140000,'monthDay'=>15]),1),$token);
$back=api('finance2.pull',['scopeId'=>$scope,'cursor'=>0],$token);$booked=array_values(array_filter($back['records'],fn($r)=>$r['id']===$entryId))[0];
check($booked['payload']['amountMinor']===129900&&$booked['payload']['paidAt']===$now,'editing monthly estimate does not overwrite confirmed payment');
denied('finance2.push',operation($scope,$ruleId,'financeRecurrenceRule',array_replace($rule,['currency'=>'USD']),2),$token,'rule_currency_immutable','rule currency change cannot orphan historical EUR occurrences');
denied('finance2.push',operation($scope,uid(),'personalFinanceEntry',array_replace($payload,['kind'=>'expense','occurrenceKey'=>'2026-11'])),$token,'validation_error','occurrence kind must match salary rule');
denied('finance2.push',operation($scope,uid(),'personalFinanceEntry',array_replace($payload,['createdByPersonId'=>uid(),'occurrenceKey'=>'2026-11'])),$token,'validation_error','person profile cannot impersonate authenticated financial author');
denied('finance.pull',['scopeId'=>$scope,'cursor'=>0],$token,'unsupported_version','old finance pull cannot display rich planned entries as posted');
denied('finance2.pull',['scopeId'=>$scope,'cursor'=>0],$foreign['token'],'permission_revoked','foreign account cannot read personal planning');
$archived=api('finance2.push',operation($scope,$accountId,'personalFinanceAccount',array_replace($account,['archived'=>true]),1),$token);
denied('finance2.push',operation($scope,uid(),'personalFinanceEntry',array_replace($payload,['occurrenceKey'=>'2026-11'])),$token,'parent_missing','archived account rejects new financial references');
$correction=api('finance2.push',operation($scope,$entryId,'personalFinanceEntry',array_replace($actual,['notes'=>'Historical correction']),2),$token);
check($correction['record']['revision']===3,'existing archived account reference preserves historical correction');
// Bridge original finance1 hash/body across a finance2 scope upgrade.
$shared=uid();api('scopes.create',['id'=>$shared,'kind'=>'household','name'=>'Finance bridge','requestId'=>uid()],$token);api('finance.enable',['scopeId'=>$shared,'enabled'=>true,'requestId'=>uid()],$token);
$oldId=uid();$oldAccount=['name'=>'Legacy ledger','currency'=>'EUR','openingBalanceMinor'=>10000,'ownerAccountId'=>null,'createdAt'=>$now,'updatedAt'=>$now];
$legacy=operation($shared,$oldId,'financeAccount',$oldAccount);api('finance.push',$legacy,$token);
$newId=uid();$richAccount=$account+['ownerAccountId'=>null];api('finance2.push',operation($shared,$newId,'financeAccount',$richAccount),$token);
$bridge=$legacy+['operationContractVersion'=>1];check(api('finance2.push',$bridge,$token)['replayed']===true,'finance2 bridge preserves accepted finance1 lost-ACK request hash');
$pending=operation($shared,$oldId,'financeAccount',array_replace($oldAccount,['name'=>'Pending legacy rename']),1);$pending['operationContractVersion']=1;
check(api('finance2.push',$pending,$token)['record']['revision']===2,'unaccepted legacy pending operation applies without stripping unrelated rich scope records');
$upgrade=array_replace($oldAccount,['openingBalanceAt'=>$now,'archived'=>false]);api('finance2.push',operation($shared,$oldId,'financeAccount',$upgrade,2),$token);
$stale=operation($shared,$oldId,'financeAccount',array_replace($oldAccount,['name'=>'Old overwrite']),3);$stale['operationContractVersion']=1;
denied('finance2.push',$stale,$token,'conflict','old pending body cannot overwrite a newer rich canonical record');
denied('finance.audit',['scopeId'=>$shared,'recordId'=>$newId],$token,'unsupported_version','old audit cannot expose uninterpretable finance2 data');
// Legacy date-null opening must not acquire a made-up cutoff on rename.
$legacyAt='2026-10-04T00:00:00Z';$priorAt='2026-10-01T00:00:00Z';
$legacyLedger=uid();$legacyBody=array_replace($oldAccount,['createdAt'=>$legacyAt,'updatedAt'=>$legacyAt]);
$legacyPush=operation($shared,$legacyLedger,'financeAccount',$legacyBody);$legacyPush['operationContractVersion']=1;
api('finance2.push',$legacyPush,$token);
$oldExpenseId=uid();$oldExpense=['accountId'=>$legacyLedger,'kind'=>'expense','status'=>'posted','amountMinor'=>5000,'currency'=>'EUR','title'=>'Earlier actual expense','notes'=>'','category'=>'','payerAccountId'=>null,'recipientAccountId'=>null,'occurredAt'=>$priorAt,'createdAt'=>$legacyAt,'updatedAt'=>$legacyAt];
$oldExpensePush=operation($shared,$oldExpenseId,'financeEntry',$oldExpense);$oldExpensePush['operationContractVersion']=1;
api('finance2.push',$oldExpensePush,$token);
$renamed=array_replace($legacyBody,['name'=>'Renamed actual ledger','openingBalanceAt'=>null,'archived'=>false]);
$nameAck=api('finance2.push',operation($shared,$legacyLedger,'financeAccount',$renamed,1),$token);
check($nameAck['record']['payload']['openingBalanceAt']===null,'legacy v2 rename keeps date-null opening instead of inventing createdAt cutoff');
$all=api('finance2.pull',['scopeId'=>$shared,'cursor'=>0],$token)['records'];
$oldHistory=array_values(array_filter($all,fn($r)=>$r['id']===$oldExpenseId))[0];
check($oldHistory['payload']['occurredAt']===$priorAt&&$oldHistory['payload']['amountMinor']===5000,'legacy v2 rename preserves prior posted financial history');
$delete=operation($scope,$entryId,'personalFinanceEntry',null,3);$delete['operation']['deleted']=true;
denied('finance2.push',$delete,$token,'recurring_entry_managed_by_rule','direct recurring posted delete cannot silently regenerate expected salary');
echo 'SUCCESS '.$checks.' finance planning checks ('.$container['db']->getConnection()->getAttribute(PDO::ATTR_DRIVER_NAME).')'.PHP_EOL;
