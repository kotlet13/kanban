<?php
/** Actual directory routing/SQL with real signed prefixes. Context rows are
 * installed test fixtures; this does not claim Capture3/source parity. */
require __DIR__.'/crypto2-creation-integration.php';
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoMigrationStructureContextV3;

$issuer=user('scoped_issuer');$issuerRoot=keys();$issuerKey=keys();$issuerEpoch=uid();
$cipher=base64_encode(random_bytes(96));
$snapshot=['version'=>2,'serverId'=>$issuer['serverId'],'accountId'=>$issuer['user']['accountId'],
    'rootSigningKeyBase64'=>$issuerRoot['signPublic'],'rootEncryptionKeyBase64'=>$issuerRoot['boxPublic'],
    'recoveryRootCiphertextHash'=>hash('sha256',base64_decode($cipher)),'recoveryRootEpochId'=>$issuerEpoch,
    'identityEpochId'=>$issuerEpoch,'devices'=>[dev2($issuer,$issuerKey,$issuerEpoch)],'keyringEntries'=>[]];
call('crypto2.account.initialize',request2('crypto2.account.initialize',[
    'rootSigningKeyBase64'=>$issuerRoot['signPublic'],'rootEncryptionKeyBase64'=>$issuerRoot['boxPublic'],
    'deviceSigningKeyBase64'=>$issuerKey['signPublic'],'deviceEncryptionKeyBase64'=>$issuerKey['boxPublic'],
    'keyringCiphertextBase64'=>$cipher],$issuer,$issuerRoot,$snapshot,null,'root'),$issuer);
$initial=call('crypto2.account.status',[],$issuer);
$migration=uid();$capture=uid();$sourceScope=uid();$certificateHash=hash('sha256',random_bytes(32));
$sourceToken=hash('sha256',random_bytes(32));
$eventProof=request2('crypto2.account.migrationAttest',['migrationId'=>$migration,'scopeToken'=>$sourceToken,
    'domain'=>'content','attestationHash'=>$certificateHash],$issuer,$issuerKey,$snapshot,$initial);
call('crypto2.account.migrationAttest',$eventProof,$issuer);$anchor=call('crypto2.account.status',[],$issuer);
$certificate=inner2(['accountId'=>$issuer['user']['accountId'],'authorDirectoryHeadHash'=>$initial['headHash']],
    NativeCryptoMigrationStructureContextV3::CERTIFICATE_DOMAIN,$issuerKey);
$card=inner2(['accountId'=>$issuer['user']['accountId'],'targetMembershipHeadHash'=>$head['headHash'],
    'authorDirectoryHeadHash'=>$anchor['headHash']],NativeCryptoMigrationStructureContextV3::CONTEXT_DOMAIN,$issuerKey);
$contextHash=hash('sha256',random_bytes(32));
q('INSERT INTO familyhub_crypto_structure_sources_v3(migration_id,account_id,scope_id,certificate_hash,statement_authorization,certificate_authorization,event_authorization) VALUES(?,?,?,?,NULL,?,?)',[
    $migration,$issuer['user']['accountId'],$sourceScope,$certificateHash,json_encode($certificate),json_encode($eventProof)]);
q('INSERT INTO familyhub_crypto_structure_contexts_v3(migration_id,scope_id,purpose,context_hash,certificate_hash,authorization) VALUES(?,?,?,?,?,?)',[
    $migration,$newId,'parentAccess',$contextHash,$certificateHash,json_encode($card)]);
$query=['scopeId'=>$newId,'headHash'=>$head['headHash'],'accountId'=>$issuer['user']['accountId']];
// A preexisting legitimate scoped reference must not hide newer independent
// context author/certificate/anchor references for the same issuer.
$delegation=inner2(['payload'=>['parentDirectoryHeadHash'=>$initial['headHash']]],
    'JivieE2EE/lifecycleDelegation/v2\n',$freshKeys);
q('INSERT INTO familyhub_crypto_lifecycle_delegations_v2(scope_id,id,head_hash,parent_scope_id,parent_account_id,proof_hash,authorization) VALUES(?,?,?,?,?,?,?)',[
    $newId,uid(),$head['headHash'],$sourceScope,$issuer['user']['accountId'],hash('sha256',random_bytes(32)),json_encode($delegation)]);
ck(call('crypto2.directory.status',$query,$fresh)['headHash']===$anchor['headHash'],
    'scoped nonmember selector defaults to newest explicitly referenced source/card/anchor prefix');
$exact=$query+['directoryHeadHash'=>$initial['headHash'],'limit'=>1];
ck(call('crypto2.directory.read',$exact,$fresh)['headHash']===$initial['headHash'],
    'exact parentAccess source certificate author prefix remains readable');
ck(call('crypto2.directory.read',$query+['directoryHeadHash'=>$anchor['headHash'],'limit'=>1],$fresh)['hasMore'],
    'exact parentAccess own-log anchor is bounded and readable');
$laterProof=request2('crypto2.account.migrationAttest',['migrationId'=>$migration,'scopeToken'=>hash('sha256','unrelated-token'),
    'domain'=>'content','attestationHash'=>hash('sha256','unrelated-certificate')],$issuer,$issuerKey,$snapshot,$anchor);
call('crypto2.account.migrationAttest',$laterProof,$issuer);$later=call('crypto2.account.status',[],$issuer);
deny(fn()=>call('crypto2.directory.status',$query+['directoryHeadHash'=>$later['headHash']],$fresh),
    'permission_revoked','scoped issuer cannot expose an arbitrary later unrelated directory prefix');
ck(call('crypto2.directory.status',$query,$fresh)['headHash']===$anchor['headHash'],
    'unrelated issuer activity does not silently extend no-selector scoped access');
$wrong=$query;$wrong['accountId']=$outsider['user']['accountId'];
deny(fn()=>call('crypto2.directory.status',$wrong,$fresh),'permission_revoked',
    'context evidence is not an arbitrary account directory oracle');
$consent=inner2(['membershipHeadHash'=>$head['headHash'],'sourceAuthority'=>[
    'accountId'=>$issuer['user']['accountId'],'directoryHeadHash'=>$later['headHash']]],
    NativeCryptoMigrationStructureContextV3::CONSENT_DOMAIN,$freshKeys);
q('INSERT INTO familyhub_crypto_structure_consents_v3(context_hash,account_id,capture_id,source_inventory_root,authorization) VALUES(?,?,?,?,?)',[
    $contextHash,$fresh['user']['accountId'],$capture,hash('sha256','frozen-root'),json_encode($consent)]);
ck(call('crypto2.directory.status',$query+['directoryHeadHash'=>$later['headHash']],$fresh)['headHash']===$later['headHash'],
    'exact explicitly retained contributor consent prefix is readable');
$sourceOnly=$query;$sourceOnly['scopeId']=$space['id'];unset($sourceOnly['headHash']);
deny(fn()=>call('crypto2.directory.status',$sourceOnly+['directoryHeadHash'=>$later['headHash']],$fresh),
    'permission_revoked','same issuer prefix is unavailable through an unrelated visible scope');
echo 'Crypto2 scoped directory prefix routing: '.$checks.' cumulative checks PASS'.PHP_EOL;
