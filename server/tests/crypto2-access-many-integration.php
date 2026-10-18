<?php
/** Synthetic 52-scope actual route. No production limits or runtime flags changed. */
require __DIR__.'/crypto2-access-integration.php';
// Seed an existing policy2 component BEFORE its first crypto head. This isolates
// structural scaling, not P6 conversion or production creation-policy claims.
$organization=['id'=>uid()];$ids=[$organization['id']];$heads=[];$catalogs=[];$start=microtime(true);
q('INSERT INTO familyhub_scopes(id,kind,name,owner_id,sequence,created_at,access_policy_version) VALUES(?,?,?, ?,0,?,2)',[$organization['id'],'organization','Synthetic existing component',$bob['user']['id'],time()]);
q("INSERT INTO familyhub_members(scope_id,user_id,account_id,role,active) VALUES(?,?,?,'owner',1)",[$organization['id'],$bob['user']['id'],$bob['user']['accountId']]);
q("INSERT INTO familyhub_members(scope_id,user_id,account_id,role,active) VALUES(?,?,?,'member',1)",[$organization['id'],$ordinary['user']['id'],$ordinary['user']['accountId']]);
q('INSERT INTO familyhub_organization_leaders VALUES(?,?)',[$organization['id'],$ordinary['user']['accountId']]);
for($i=0;$i<51;$i++){
    $sid=uid();$ids[]=$sid;
    q('INSERT INTO familyhub_scopes(id,kind,name,owner_id,sequence,created_at,organization_id,parent_scope_id,access_policy_version,project_root_id) VALUES(?,?,?, ?,0,?,?,?,2,?)',[$sid,'project','Synthetic existing child',$bob['user']['id'],time(),$organization['id'],$organization['id'],uid()]);
    q("INSERT INTO familyhub_members(scope_id,user_id,account_id,role,active) VALUES(?,?,?,'owner',1)",[$sid,$bob['user']['id'],$bob['user']['accountId']]);
}
foreach($ids as $i=>$sid){
    if($i%5===0){$prefix='access_many_setup_'.bin2hex(random_bytes(8));}
    q('INSERT INTO familyhub_finance_policy(scope_id,enabled,revision,sequence,required_contract_version) VALUES(?,1,1,0,3)',[$sid]);
    q("INSERT INTO familyhub_finance_grants(scope_id,account_id,access_level) VALUES(?,?,'write')",[$sid,$bob['user']['accountId']]);
    $scope=(new \Kanboard\Plugin\FamilyHub\Model\NativeCryptoScopeV2($container))->catalogScope($sid,['user'=>['id'=>$bob['user']['id'],'account_id'=>$bob['user']['accountId']],'device'=>['id'=>$bob['device']['id']]]);
    send2('crypto2.scope.prepare',['scopeId'=>$sid,'expectedAccessRevision'=>$scope['accessRevision']],$bob,$bobKey);
    $body=candidate2($scope,$bobState);$body['accessBasis']=$scope['accessBasis'];$body['members']=accessMembers2($scope['members'],$actors);
    if(!array_filter($body['members'],fn($m)=>$m['financeRole']!=='none')){$body['keyIds']['finance']=null;$body['keyCommitments']['finance']=null;}
    $put=send2('crypto2.scope.headPut',$body,$bob,$bobKey);$head=call('crypto2.scope.headGet',['scopeId'=>$sid,'headHash'=>$put['headHash']],$bob);
    foreach($body['members'] as $member){[$u,$k,$r,$st]=$actors[$member['accountId']];accessGrants2($head,[$head],$u,$k,$r,$st,$bob,$bobKey);}
    $manifest=call('crypto2.grants.manifest',['scopeId'=>$sid,'headHash'=>$head['headHash']],$bob);
    send2('crypto2.scope.activate',['scopeId'=>$sid,'headHash'=>$head['headHash'],'grantManifestHash'=>$manifest['grantManifestHash'],'authorDirectoryHeadHash'=>$bobState['headHash']],$bob,$bobKey);
    $heads[$sid]=$head;$catalogs[$sid]=$scope;
}
$parentCatalog=$catalogs[$organization['id']];
$fixtureMigration=uid();q('INSERT INTO familyhub_crypto_migrations_v2 VALUES(?,?,?,?,?,?,?,?,?)',[$fixtureMigration,uid(),hash('sha256','synthetic many access component'),json_encode($ids),hash('sha256','synthetic participants'),'committed',hash('sha256','synthetic challenge'),time(),time()]);
foreach($ids as $sid){q("UPDATE familyhub_crypto_scopes SET state='active',migration_id=? WHERE scope_id=?",[$fixtureMigration,$sid]);}
$prefix='access_many_prepare_'.bin2hex(random_bytes(8));
$intent=send2('crypto2.access.prepare',['scopeId'=>$organization['id'],'membershipHeadHash'=>$heads[$organization['id']]['headHash'],'expectedAccessRevision'=>$parentCatalog['accessRevision'],'authorDirectoryHeadHash'=>$bobState['headHash'],'action'=>['kind'=>'leader','accountId'=>$ordinary['user']['accountId'],'enabled'=>false]],$bob,$bobKey);
ck($intent['affectedCount']===52,'leader component captures parent plus 51 actual encrypted project heads');
$after=null;$descriptors=[];$pages=0;
do{$page=call('crypto2.access.portions',['intentHash'=>$intent['intentHash'],'limit'=>20]+($after?['afterToken'=>$after]:[]),$bob);$pages++;foreach($page['portions'] as $descriptor){$descriptors[]=$descriptor;}$after=$page['nextAfterToken'];}while($page['hasMore']);
$seen=array_column($descriptors,'scopeToken');$sorted=$seen;sort($sorted,SORT_STRING);
ck($pages===3&&count($descriptors)===52&&count(array_unique($seen))===52&&$seen===$sorted,'affected commitment pages cover every child exactly once in deterministic order');
$hash=hash_init('sha256');hash_update($hash,"JivieAccessComponent/v2\n".\Kanboard\Plugin\FamilyHub\Model\NativeCryptoCodec::canonical((object)['version'=>2,'serverId'=>$bob['serverId'],'intentHash'=>$intent['intentHash']])."\n");
foreach($descriptors as $d){hash_update($hash,\Kanboard\Plugin\FamilyHub\Model\NativeCryptoCodec::canonical((object)array_intersect_key($d,array_flip(['scopeToken','headHash','accessRevision','rawAccessRevision','policyVersion'])))."\n");}
ck(hash_final($hash)===$intent['affectedHash'],'full bounded descriptor stream matches exact final activation root');
$prepared=[];$i=0;
foreach($heads as $sid=>$source){
    if($i++%3===0){$prefix='access_many_approval_'.bin2hex(random_bytes(8));}
    $pending=call('crypto2.access.pending',['scopeId'=>$sid],$bob)['intents'][0];$scope=$catalogs[$sid];
    $body=candidate2($scope,$bobState,$source['payload']['epoch']+1,$source['headHash'],['content'=>hash('sha256',''),'finance'=>$source['payload']['keyIds']['finance']===null?null:hash('sha256','')]);$body['accessBasis']=$pending['accessBasis'];$body['accessRevision']=$pending['future']['accessRevision'];$body['members']=accessMembers2($pending['future']['members'],$actors);
    if($source['payload']['keyIds']['finance']===null){$body['keyIds']['finance']=null;$body['keyCommitments']['finance']=null;}
    $consent=['version'=>2,'operation'=>'crypto2.access.scopeConsent','serverId'=>$bob['serverId'],'scopeId'=>$sid,'intentHash'=>$intent['intentHash'],'affectedCount'=>52,'affectedHash'=>$intent['affectedHash'],'previousHeadHash'=>$source['headHash'],'expectedAccessRevision'=>$pending['expectedAccessRevision'],'accessBasis'=>$pending['accessBasis'],'resultingAccessRevision'=>$body['accessRevision'],'resultingDescriptor'=>$pending['future']['descriptor'],'resultingFinancePolicy'=>$pending['future']['financePolicy'],'membersHash'=>\Kanboard\Plugin\FamilyHub\Model\NativeCryptoV2Codec::hash($body['members']),'accountId'=>$bob['user']['accountId'],'deviceId'=>$bob['device']['id'],'authorDirectoryHeadHash'=>$bobState['headHash']];
    $body['accessIntentProof']=inner2($consent,"JivieE2EE/accessScopeConsent/v2\n",$bobKey);
    $put=send2('crypto2.scope.headPut',$body,$bob,$bobKey);$next=call('crypto2.scope.headGet',['scopeId'=>$sid,'headHash'=>$put['headHash']],$bob);
    foreach(['content','finance'] as $domain){if($source['payload']['keyIds'][$domain]!==null)close2($sid,$next['headHash'],$source,$domain,$bobState,0,$bob,$bobKey);}
    $history=[];$cursor=$source;
    while(true){array_unshift($history,$cursor);if($cursor['payload']['epoch']===1)break;$cursor=call('crypto2.scope.headGet',['scopeId'=>$sid,'headHash'=>$cursor['payload']['previousHeadHash']],$bob);}
    $history[]=$next;
    foreach($body['members'] as $member){[$u,$k,$r,$st]=$actors[$member['accountId']];accessGrants2($next,$history,$u,$k,$r,$st,$bob,$bobKey);}
    $manifest=call('crypto2.grants.manifest',['scopeId'=>$sid,'headHash'=>$next['headHash']],$bob);
    $inner=content2('crypto2.scope.activate',['scopeId'=>$sid,'headHash'=>$next['headHash'],'grantManifestHash'=>$manifest['grantManifestHash'],'authorDirectoryHeadHash'=>$bobState['headHash'],'accessIntentHash'=>$intent['intentHash'],'affectedCount'=>52,'affectedHash'=>$intent['affectedHash']],$bob,$bobKey);
    $prepared[$sid]=[$next,$inner];
    if($i<52)send2('crypto2.access.approve',['intentHash'=>$intent['intentHash'],'scopeId'=>$sid,'activationProof'=>$inner],$bob,$bobKey);
}
$prefix='access_many_final_'.bin2hex(random_bytes(8));
$finalPayload=['intentHash'=>$intent['intentHash'],'affectedCount'=>52,'affectedHash'=>$intent['affectedHash']];
deny(fn()=>send2('crypto2.access.activate',$finalPayload,$bob,$bobKey),'crypto_access_approval_required','missing last page child approval causes zero SQL or head activation');
ck((bool)q('SELECT account_id FROM familyhub_organization_leaders WHERE scope_id=? AND account_id=?',[$organization['id'],$ordinary['user']['accountId']])&&q('SELECT head_hash FROM familyhub_crypto_scope_state WHERE scope_id=?',[$organization['id']])[0]['head_hash']===$heads[$organization['id']]['headHash'],'52-scope failed activation retains old leader and parent head');
$last=array_key_last($prepared);send2('crypto2.access.approve',['intentHash'=>$intent['intentHash'],'scopeId'=>$last,'activationProof'=>$prepared[$last][1]],$bob,$bobKey);
class AccessMeasuredStatement extends PDOStatement {
    protected function __construct(){}
    public function execute(?array $params=null):bool{if(str_starts_with($this->queryString,'SELECT * FROM familyhub_scopes WHERE (id=? OR parent_scope_id=? OR organization_id=?)')){$GLOBALS['accessBasePages']++;}return parent::execute($params);}
}
$pdo->setAttribute(PDO::ATTR_STATEMENT_CLASS,[AccessMeasuredStatement::class,[]]);$accessBasePages=0;$commitStart=microtime(true);
$request=content2('crypto2.access.activate',$finalPayload,$bob,$bobKey);$result=call('crypto2.access.activate',$request,$bob);$commitSeconds=microtime(true)-$commitStart;
ck($result['state']==='applied'&&$accessBasePages===6,'52-scope final activation performs exactly two bounded base CAS scans rather than one per child');
ck(call('crypto2.access.activate',$request,$bob)===$result&&!q('SELECT account_id FROM familyhub_organization_leaders WHERE scope_id=? AND account_id=?',[$organization['id'],$ordinary['user']['accountId']]),'large atomic leader removal has exact immutable lost ACK and applies only once');
foreach($prepared as $sid=>[$next]){ck(q('SELECT head_hash FROM familyhub_crypto_scope_state WHERE scope_id=?',[$sid])[0]['head_hash']===$next['headHash'],'component activates exact approved scope head '.$sid);}
echo 'PERFORMANCE: setup+approval '.round(microtime(true)-$start,3).'s; final commit '.round($commitSeconds,3).'s; full-base pages '.$accessBasePages.PHP_EOL;
echo 'Crypto2 many access integration: '.$checks.' checks PASS'.PHP_EOL;
