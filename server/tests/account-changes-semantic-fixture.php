<?php
/** New semantic-hint fixtures only. Disposable SQLite, no service/HTTP/native.
 * Directory events use the real authorize/signature/reduce/append models.
 * They do not run NativeCryptoV2Service::project or its full business guards. */
require __DIR__.'/account-changes-fixture.php';
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoDirectoryV2;
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoCodec;
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoV2Codec;

$directory=new NativeCryptoDirectoryV2(['db'=>$db]);
$server=sql('SELECT server_id FROM familyhub_instance')->fetchColumn();
$semanticKeys=[];$semanticRequest=700;
function semanticDevice($id,$epoch,$generation=1){
    global $semanticKeys;
    $pair=sodium_crypto_sign_seed_keypair(hash('sha256','semantic-device-'.$id,true));
    $semanticKeys[$id]=sodium_crypto_sign_secretkey($pair);
    return ['deviceId'=>$id,'signingKeyBase64'=>base64_encode(sodium_crypto_sign_publickey($pair)),
        'encryptionKeyBase64'=>base64_encode(hash('sha256','semantic-box-'.$id,true)),
        'keyringWrite'=>true,'manageDevices'=>true,'addedGeneration'=>$generation,'revokedGeneration'=>null,'identityEpochId'=>$epoch];
}
function semanticProof($command,$secret,$domain=NativeCryptoV2Codec::DOMAIN){
    $bytes=NativeCryptoCodec::canonical((object)$command);
    return ['commandBase64'=>base64_encode($bytes),'signatureBase64'=>base64_encode(sodium_crypto_sign_detached($domain.$bytes,$secret))];
}
function semanticAppend($account,$operation,$fields,$expected=null,$signer='device',$device=null){
    global $directory,$server,$semanticKeys,$semanticRequest;
    $current=$directory->current($account);$before=json_decode($current['snapshot'],true);
    $device??=id($account===id(1)?101:102);
    $expected??=$before;
    $command=['version'=>2,'operation'=>$operation,'serverId'=>$server,'accountId'=>$account,'deviceId'=>$device,
        'requestId'=>id(++$semanticRequest),'signer'=>$signer,'payload'=>[
            'expectedGeneration'=>(int)$current['generation'],'previousHeadHash'=>$current['head_hash'],
            'identityEpochId'=>$before['identityEpochId'],'resultingSnapshotHash'=>NativeCryptoDirectoryV2::snapshotHash($expected),
        ]+$fields];
    $proof=semanticProof($command,$semanticKeys[$signer==='root'?'root:'.$account:$device]);
    [$decoded,$bytes,$signature]=NativeCryptoCodec::decode($proof);
    NativeCryptoV2Codec::verify($bytes,$signature,$directory->authorize($decoded,$current));
    $snapshot=$directory->reduce($decoded,$current);
    global $pdo;$pdo->beginTransaction();
    try{$directory->append($decoded,$proof,$snapshot);$pdo->commit();}catch(\Throwable $e){$pdo->rollBack();throw $e;}
    return $directory->current($account);
}
foreach([1,2] as $n){
    $account=id($n);$epoch=id(90+$n);$pair=sodium_crypto_sign_seed_keypair(hash('sha256','semantic-root-'.$n,true));
    $semanticKeys['root:'.$account]=sodium_crypto_sign_secretkey($pair);
    $device=semanticDevice(id(100+$n),$epoch);
    $snapshot=['version'=>2,'serverId'=>$server,'accountId'=>$account,
        'rootSigningKeyBase64'=>base64_encode(sodium_crypto_sign_publickey($pair)),
        'rootEncryptionKeyBase64'=>base64_encode(str_repeat(chr(64+$n),32)),
        'recoveryRootCiphertextHash'=>hash('sha256',str_repeat('R',48)),'recoveryRootEpochId'=>$epoch,
        'identityEpochId'=>$epoch,'devices'=>[$device],'keyringEntries'=>[]];
    $command=['version'=>2,'operation'=>'crypto2.account.initialize','serverId'=>$server,'accountId'=>$account,
        'deviceId'=>$device['deviceId'],'requestId'=>id(++$semanticRequest),'signer'=>'root','payload'=>[
            'expectedGeneration'=>0,'previousHeadHash'=>NativeCryptoDirectoryV2::ZERO,'identityEpochId'=>$epoch,
            'resultingSnapshotHash'=>NativeCryptoDirectoryV2::snapshotHash($snapshot),
            'rootSigningKeyBase64'=>$snapshot['rootSigningKeyBase64'],'rootEncryptionKeyBase64'=>$snapshot['rootEncryptionKeyBase64'],
            'deviceSigningKeyBase64'=>$device['signingKeyBase64'],'deviceEncryptionKeyBase64'=>$device['encryptionKeyBase64'],
            'keyringCiphertextBase64'=>base64_encode(str_repeat('R',48))]];
    $proof=semanticProof($command,$semanticKeys['root:'.$account]);
    [$decoded,$bytes,$signature]=NativeCryptoCodec::decode($proof);
    NativeCryptoV2Codec::verify($bytes,$signature,$directory->authorize($decoded,null));
    $directory->append($decoded,$proof,$directory->reduce($decoded,null));
}
// Same-account private scope, shared parent and inherited child are distinct.
sql("UPDATE familyhub_scopes SET kind='household' WHERE id=?",[id(3)]);
sql("INSERT INTO familyhub_members VALUES(?,?,?,'member',1)",[id(3),2,id(2)]);
sql("INSERT INTO familyhub_scopes(id,kind,name,owner_id,sequence,created_at,access_policy_version,parent_scope_id) VALUES(?,'project','CHILD_SENTINEL',1,0,1,3,?)",[id(6),id(3)]);

/** Counter projection seam matching StorageV2:241-259, NOT a storage admission
 * or records.batch test. The transaction includes task/tombstone and cursor. */
function semanticTaskCommit($deleted=false){
    global $pdo;$pdo->beginTransaction();
    $sequence=(int)sql("SELECT sequence FROM familyhub_crypto_domain_cursors WHERE scope_id=? AND domain='content'",[id(3)])->fetchColumn()+1;
    $row=sql('SELECT id FROM familyhub_crypto_records WHERE scope_id=? AND id=?',[id(3),id(300)])->fetchColumn();
    if($row)sql('UPDATE familyhub_crypto_records SET revision=revision+1,deleted=?,sequence=? WHERE scope_id=? AND id=?',[(int)$deleted,$sequence,id(3),id(300)]);
    else sql('INSERT INTO familyhub_crypto_records VALUES(?,?,?,?,?,?,?,?,?,?)',[id(3),id(300),'task',1,(int)$deleted,$sequence,1,'CIPHERTEXT_SENTINEL','{}','PROOF_SENTINEL']);
    sql("UPDATE familyhub_crypto_domain_cursors SET sequence=? WHERE scope_id=? AND domain='content'",[$sequence,id(3)]);
    sql('UPDATE familyhub_crypto_scopes SET sequence=sequence+1 WHERE scope_id=?',[id(3)]);
    $pdo->commit();return $sequence;
}
function semanticResult($name){global $checks;echo json_encode(['test'=>$name,'status'=>'pass','checks'=>$checks,
    'fixture'=>'isolated-memory-sqlite','directoryModelSignatures'=>true,'storageMutation'=>'explicit counter projection seam',
    'fullServiceAdmission'=>false,'http'=>false,'native'=>false]).PHP_EOL;}
