<?php
/** Actual catalog descriptors and protection hash against isolated SQLite.
 * No signed protection-ready mutation, HTTP or native-client result is claimed. */
require __DIR__.'/account-changes-fixture.php';
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoScopeV2;
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoCodec;
$actor=['user'=>['id'=>1,'account_id'=>id(1)],'device'=>['id'=>id(101)]];
$catalog=new NativeCryptoScopeV2(['db'=>$db],bearer(1),'synthetic-catalog-compat');
$keys=['cryptoOrigin','migrationId','migrationState','expectedAccessRevision','accessBasis','cryptoState','headHash','epoch','id','kind','parentScopeId','role','accessRevision','members'];sort($keys);
$before=$catalog->catalog([],$actor);
foreach($before['scopes'] as $scope){$actual=array_keys($scope);sort($actual);ck($actual===$keys,'actual descriptor retains exactly the original14 fields for '.$scope['id']);}
$manifestBefore=$catalog->protectionCatalog($actor);
$h=hash_init('sha256');hash_update($h,"JivieProtectionCatalog/v2\n");
foreach($before['scopes'] as $scope)hash_update($h,NativeCryptoCodec::canonical((object)$scope)."\n");
hash_update($h,NativeCryptoCodec::canonical((object)['count'=>count($before['scopes'])]));
ck($manifestBefore['scopeManifestHash']===hash_final($h),'protection manifest hashes only the original descriptor stream and count');
sql('INSERT INTO familyhub_crypto_record_policy_state_v1 VALUES(?,?,1)',[id(3),id(90)]);
$after=$catalog->catalog([],$actor);
ck($after['scopes']===$before['scopes'],'policy activation leaves every original descriptor byte and value unchanged');
ck($catalog->protectionCatalog($actor)===$manifestBefore,'policy hint activation leaves original protection catalog hash unchanged');
$versions=(array)$after['recordPolicyVersions'];
ck($versions===[id(3)=>1,id(4)=>0]&&!isset($versions[id(5)]),'outer hints contain exact0/1 for returned scopes only and omit inaccessible scope');
$page=$catalog->catalog(['limit'=>1],$actor);
ck($page['hasMore']&&(array)$page['recordPolicyVersions']===[id(3)=>1]&&$page['nextAfterId']===id(3),'policy hints follow the same catalog page boundaries');
$empty=$catalog->catalog(['afterId'=>id(99)],$actor);
ck(is_object($empty['recordPolicyVersions'])&&json_encode($empty['recordPolicyVersions'])==='{}'&&$empty['scopes']===[],'empty page encodes an empty policy map object for strict clients');
ck(!isset($after['scopes'][0]['recordPolicyVersion'],$after['scopes'][0]['requiredCryptoContentContractVersion'],$after['scopes'][0]['requiredCryptoFinanceContractVersion']),'no policy negotiation fields enter the signed protection descriptor');
echo json_encode(['test'=>'crypto-record-policy-catalog-compat','status'=>'pass','checks'=>$checks,'fixture'=>'isolated-memory-sqlite','actualCatalog'=>true,'http'=>false,'protectionReadyMutation'=>false]).PHP_EOL;
