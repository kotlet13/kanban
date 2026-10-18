<?php
require __DIR__.'/crypto2-access-integration.php';
require __DIR__.'/crypto2-record-helpers.php';
$parentNow=call('crypto2.scope.headGet',['scopeId'=>$organization['id']],$bob);
$childNow=call('crypto2.scope.headGet',['scopeId'=>$project['id']],$bob);
$parentCatalog=array_values(array_filter(call('crypto2.scopes.catalog',[],$bob)['scopes'],fn($s)=>$s['id']===$organization['id']))[0];
$removal=send2('crypto2.access.prepare',['scopeId'=>$organization['id'],'membershipHeadHash'=>$parentNow['headHash'],'expectedAccessRevision'=>$parentCatalog['accessRevision'],'authorDirectoryHeadHash'=>$bobState['headHash'],'action'=>['kind'=>'leader','accountId'=>$ordinary['user']['accountId'],'enabled'=>false]],$bob,$bobKey);
$pending=call('crypto2.access.pending',['scopeId'=>$project['id']],$bob)['intents'][0];
$childCatalog=array_values(array_filter(call('crypto2.scopes.catalog',[],$bob)['scopes'],fn($s)=>$s['id']===$project['id']))[0];
$body=candidate2($childCatalog,$bobState,3,$childNow['headHash'],['content'=>hash('sha256',''),'finance'=>hash('sha256','')]);$body['accessBasis']=$pending['accessBasis'];$body['accessRevision']=$pending['future']['accessRevision'];$body['members']=accessMembers2($pending['future']['members'],$actors);
$consent=['version'=>2,'operation'=>'crypto2.access.scopeConsent','serverId'=>$bob['serverId'],'scopeId'=>$project['id'],'intentHash'=>$removal['intentHash'],'affectedCount'=>2,'affectedHash'=>$removal['affectedHash'],'previousHeadHash'=>$childNow['headHash'],'expectedAccessRevision'=>$pending['expectedAccessRevision'],'accessBasis'=>$pending['accessBasis'],'resultingAccessRevision'=>$body['accessRevision'],'resultingDescriptor'=>$pending['future']['descriptor'],'resultingFinancePolicy'=>$pending['future']['financePolicy'],'membersHash'=>\Kanboard\Plugin\FamilyHub\Model\NativeCryptoV2Codec::hash($body['members']),'accountId'=>$bob['user']['accountId'],'deviceId'=>$bob['device']['id'],'authorDirectoryHeadHash'=>$bobState['headHash']];
$body['accessIntentProof']=inner2($consent,"JivieE2EE/accessScopeConsent/v2\n",$bobKey);
$put=send2('crypto2.scope.headPut',$body,$bob,$bobKey);$candidate=call('crypto2.scope.headGet',['scopeId'=>$project['id'],'headHash'=>$put['headHash']],$bob);
foreach(['content','finance'] as $domain){close2($project['id'],$candidate['headHash'],$childNow,$domain,$bobState,0,$bob,$bobKey);}
foreach($body['members'] as $member){[$u,$k,$r,$st]=$actors[$member['accountId']];accessGrants2($candidate,[$childHead,$childNow,$candidate],$u,$k,$r,$st,$bob,$bobKey);}
$manifest=call('crypto2.grants.manifest',['scopeId'=>$project['id'],'headHash'=>$candidate['headHash']],$bob);
$inner=content2('crypto2.scope.activate',['scopeId'=>$project['id'],'headHash'=>$candidate['headHash'],'grantManifestHash'=>$manifest['grantManifestHash'],'authorDirectoryHeadHash'=>$bobState['headHash'],'accessIntentHash'=>$removal['intentHash'],'affectedCount'=>2,'affectedHash'=>$removal['affectedHash']],$bob,$bobKey);
send2('crypto2.access.approve',['intentHash'=>$removal['intentHash'],'scopeId'=>$project['id'],'activationProof'=>$inner],$bob,$bobKey);
$before=q('SELECT * FROM familyhub_members WHERE scope_id IN (?,?) ORDER BY scope_id,account_id',[$organization['id'],$project['id']]);
$cancelRequest=content2('crypto2.access.cancel',['intentHash'=>$removal['intentHash'],'affectedCount'=>2,'affectedHash'=>$removal['affectedHash']],$bob,$bobKey);$cancel=call('crypto2.access.cancel',$cancelRequest,$bob);
ck($cancel['cleanupRequired']&&$cancel['cleanupCount']===1,'component cancel after child closure explicitly requires one authorized cleanup');
ck(call('crypto2.access.cancel',$cancelRequest,$bob)===$cancel&&q('SELECT * FROM familyhub_members WHERE scope_id IN (?,?) ORDER BY scope_id,account_id',[$organization['id'],$project['id']])===$before,'cancel exact ACK preserves old SQL memberships and leader authority');
$status=call('crypto2.access.pending',['scopeId'=>$project['id']],$bob);ck($status['cleanupRequired']&&$status['closedDomains']===['content','finance'],'child manager sees resumable closed-domain cleanup after canceled intent');
$opaque=call('crypto2.access.portions',['intentHash'=>$removal['intentHash']],$bob);ck(count(array_filter($opaque['portions'],fn($p)=>$p['cleanupRequired']))===1&&!str_contains(json_encode($opaque),$project['id']),'parent sees cleanup commitments without child roster or IDs');
$blocked=row2($project['id'],$childNow,$bob,$bobKey);
deny(fn()=>call('crypto2.records.batch',batch2([$blocked],$bob,$bobKey),$bob),'crypto_domain_closed','cancel cannot reopen old-epoch business writes after immutable closure');
// Independent child manager performs an ordinary, unchanged-roster successor.
$cleanupBody=candidate2($childCatalog,$bobState,3,$childNow['headHash'],['content'=>hash('sha256',''),'finance'=>hash('sha256','')]);$cleanupBody['accessBasis']=$childCatalog['accessBasis'];$cleanupBody['members']=$childNow['payload']['members'];
$cleanupPut=send2('crypto2.scope.headPut',$cleanupBody,$bob,$bobKey);$cleanup=call('crypto2.scope.headGet',['scopeId'=>$project['id'],'headHash'=>$cleanupPut['headHash']],$bob);
foreach(['content','finance'] as $domain){close2($project['id'],$cleanup['headHash'],$childNow,$domain,$bobState,0,$bob,$bobKey);}
foreach($cleanupBody['members'] as $member){[$u,$k,$r,$st]=$actors[$member['accountId']];accessGrants2($cleanup,[$childHead,$childNow,$cleanup],$u,$k,$r,$st,$bob,$bobKey);}
$cleanupManifest=call('crypto2.grants.manifest',['scopeId'=>$project['id'],'headHash'=>$cleanup['headHash']],$bob);
send2('crypto2.scope.activate',['scopeId'=>$project['id'],'headHash'=>$cleanup['headHash'],'grantManifestHash'=>$cleanupManifest['grantManifestHash'],'authorDirectoryHeadHash'=>$bobState['headHash']],$bob,$bobKey);
$business=row2($project['id'],$cleanup,$bob,$bobKey);ck(call('crypto2.records.batch',batch2([$business],$bob,$bobKey),$bob)['status']==='applied','fresh child successor restores actual writes without changing canceled membership policy');
ck(q('SELECT * FROM familyhub_members WHERE scope_id IN (?,?) ORDER BY scope_id,account_id',[$organization['id'],$project['id']])===$before&&(bool)q('SELECT account_id FROM familyhub_organization_leaders WHERE scope_id=? AND account_id=?',[$organization['id'],$ordinary['user']['accountId']]),'cleanup retains original roster and does not apply canceled leader removal');
echo 'Crypto2 access cancel integration: '.$checks.' checks PASS'.PHP_EOL;
