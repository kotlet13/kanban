<?php
/** Synthetic SQL/API parity and denied-boundary controls for the new transport.
 * Existing setup supplies real signed account/scope chains; no native QA data. */
require __DIR__.'/crypto2-creation-integration.php';
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoAuthoritySnapshotV2;
use Kanboard\Plugin\FamilyHub\Model\NativeDatabase;
use Kanboard\Plugin\FamilyHub\Model\NativeError;

$before = $checks;
function snapshotEntry($snapshot, $operation, $params) {
    foreach ($snapshot['entries'] as $entry) {
        if ($entry['operation']===$operation && (array)$entry['params']==$params) { return $entry; }
    }
    return null;
}
deny(fn()=>call('crypto2.authority.snapshot'), 'auth_required', 'snapshot requires a valid device bearer');
ck(call('capabilities')['cryptoAuthoritySnapshotVersions']===[1], 'snapshot capability is explicitly negotiated');
$snapshot = call('crypto2.authority.snapshot', ['scopeId'=>$newId,'accountAfterGeneration'=>0], $fresh);
ck($snapshot['version']===1 && $snapshot['serverId']===$fresh['serverId'] && $snapshot['accountId']===$fresh['user']['accountId'] && $snapshot['deviceId']===$fresh['device']['id'], 'snapshot envelope binds full caller identity');
ck(strlen(json_encode($snapshot,JSON_THROW_ON_ERROR))<=1250000 && count($snapshot['entries'])<=512, 'aggregate snapshot bytes and items are bounded');
$heads=[]; $keys=[];
foreach ($snapshot['entries'] as $entry) {
    $operation=$entry['operation']; $params=(array)$entry['params'];
    $key=$operation.'\n'.\Kanboard\Plugin\FamilyHub\Model\NativeCryptoCodec::canonical((object)$params);
    ck(!isset($keys[$key]), 'snapshot route selector is unique'); $keys[$key]=true;
    if ($operation==='crypto2.scope.headGet') { $heads[]=$params['scopeId']; }
    if (isset($entry['error'])) {
        deny(fn()=>call($operation,$params,$fresh), $entry['error']['code'], 'composed '.$operation.' '.$entry['error']['code'].' equals original route');
    } else {
        ck(call($operation,$params,$fresh)===$entry['result'], 'composed signed wire equals original route');
    }
}
ck(in_array($newId,$heads,true) && in_array($child['id'],$heads,true), 'whole-space selection includes its eligible child in one request');
$initial = call('crypto2.authority.snapshot', ['accountAfterGeneration'=>0], $fresh);
ck(snapshotEntry($initial,'crypto2.scopes.catalog',['limit'=>50])!==null, 'account snapshot composes exact existing catalog page');
$own = snapshotEntry($initial,'crypto2.account.directory',['afterGeneration'=>0,'limit'=>50]);
ck($own!==null && $own['result']===call('crypto2.account.directory',['afterGeneration'=>0,'limit'=>50],$fresh), 'account snapshot preserves exact own directory bytes and cursors');
$warm = call('crypto2.authority.snapshot', ['scopeId'=>$newId,'accountAfterGeneration'=>$state['generation']], $fresh);
$warmOwn=snapshotEntry($warm,'crypto2.account.directory',['afterGeneration'=>$state['generation'],'limit'=>50]);
ck($warmOwn!==null && count($warmOwn['result']['entries'])===0, 'warm caller cursor avoids own historical replay');
$small=call('crypto2.authority.snapshot',['scopeId'=>$newId,'scopeLimit'=>1],$fresh);
ck($small['hasMoreScopes'] && $small['nextAfterScopeId']!==null && !$small['complete'], 'scope pagination never reports partial space complete');
$tail=call('crypto2.authority.snapshot',['scopeId'=>$newId,'scopeLimit'=>1,'afterScopeId'=>$small['nextAfterScopeId']],$fresh);
ck(!$tail['hasMoreScopes'], 'scope continuation reaches remaining child without expanding scope');
deny(fn()=>call('crypto2.authority.snapshot',['scopeId'=>$newId,'scopeLimit'=>21],$fresh),'validation_error','scope expansion limit rejects before proof assembly');
deny(fn()=>call('crypto2.authority.snapshot',['reads'=>[['operation'=>'crypto2.account.scopeObservation.put']]],$fresh),'validation_error','snapshot cannot dispatch an observation write or arbitrary nested operation');
deny(fn()=>call('crypto2.authority.snapshot',['scopeId'=>$newId],$outsider),'permission_revoked','outsider cannot retrieve owner or child authority');
deny(fn()=>call('crypto2.authority.snapshot',['scopeId'=>uid()],$fresh),'scope_unavailable','unknown scope exposes only original finite error');
// A direct child ACL fixture deliberately leaves its parent's membership absent.
// Its keys are irrelevant: selected child's original head read fails normally,
// but no parent/sibling metadata or proof is manufactured by composition.
$direct=user('snapshot_direct');
$userId=q('SELECT user_id FROM familyhub_accounts WHERE account_id=?',[$direct['user']['accountId']])[0]['user_id'];
q('INSERT INTO familyhub_members(scope_id,user_id,account_id,role,active) VALUES(?,?,?,?,1)',[$child['id'],$userId,$direct['user']['accountId'],'viewer']);
$directSnapshot=call('crypto2.authority.snapshot',['scopeId'=>$child['id']],$direct);
$directScopes=[];
foreach($directSnapshot['entries'] as $entry){$params=(array)$entry['params'];if(isset($params['scopeId']))$directScopes[$params['scopeId']]=true;}
ck(array_keys($directScopes)===[$child['id']], 'direct-child-only snapshot exposes no parent or sibling selectors');
deny(fn()=>call('crypto2.authority.snapshot',['scopeId'=>$newId],$direct),'permission_revoked','direct child cannot select hidden parent');
q('UPDATE familyhub_members SET active=0 WHERE scope_id=? AND account_id=?',[$child['id'],$direct['user']['accountId']]);
deny(fn()=>call('crypto2.authority.snapshot',['scopeId'=>$child['id']],$direct),'permission_revoked','fresh snapshot denies committed membership revocation');
$pending=call('crypto2.authority.snapshot',['scopeId'=>$newId,'pendingCapability'=>'private-candidate-capability'],$fresh);
ck($pending['entries']===[] && !$pending['complete'], 'pending capability never expands private candidate into whole-space snapshot');
echo 'Crypto2 authority snapshot: '.($checks-$before).' new controls PASS'.PHP_EOL;
