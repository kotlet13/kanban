<?php
/** Synthetic policy4 transport, real users FK cascade; never run on hosting. */
require __DIR__.'/crypto2-invitation-integration.php';
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoAccountTombstoneV2;
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoAccountDeletionV2;
$ownerAccount=$fresh['user']['accountId'];$ownerUser=$fresh['user']['id'];
$personal=send2('crypto2.scope.ensurePersonal',['id'=>uid()],$fresh,$freshKeys)['scope'];
$personalBody=candidate2($personal,$state);$personalPending=send2('crypto2.scope.headPut',$personalBody,$fresh,$freshKeys);
$personalHead=call('crypto2.scope.headGet',['scopeId'=>$personal['id'],'headHash'=>$personalPending['headHash']],$fresh);
grants2($personalHead,[$personalHead],$fresh,$freshKeys,$root,$epoch);
$personalManifest=call('crypto2.grants.manifest',['scopeId'=>$personal['id'],'headHash'=>$personalPending['headHash']],$fresh);
send2('crypto2.scope.activate',['scopeId'=>$personal['id'],'headHash'=>$personalPending['headHash'],'authorDirectoryHeadHash'=>$state['headHash'],'grantManifestHash'=>$personalManifest['grantManifestHash']],$fresh,$freshKeys);
q('INSERT INTO familyhub_crypto_blob_chunks_v2(scope_id,blob_id,chunk_offset,data) VALUES(?,?,0,?)',[$personal['id'],uid(),base64_encode(random_bytes(64))]);
$foreignChild=uid();q('INSERT INTO familyhub_scopes(id,kind,name,owner_id,sequence,created_at,access_policy_version,parent_scope_id) VALUES(?,?,?,?,0,?,3,?)',[$foreignChild,'project','Synthetic foreign dependency',$recipient['user']['id'],time(),$personal['id']]);
$foreignPreview=call('account.deletion.preview',['policyVersion'=>4],$fresh);
$privateChoices=array_values(array_filter($foreignPreview['cryptoScopes'],fn($s)=>$s['scopeId']===$personal['id']));
ck(count($privateChoices)===1&&$privateChoices[0]['privateOwned']===false&&!in_array('deletePrivate',$privateChoices[0]['allowedActions'],true),'unexpected foreign child prevents private erasure');
q('DELETE FROM familyhub_scopes WHERE id=?',[$foreignChild]);

$before=q('SELECT generation,authorization FROM familyhub_crypto_directory WHERE account_id=? ORDER BY generation',[$ownerAccount]);
$headBefore=q('SELECT * FROM familyhub_crypto_scope_heads WHERE scope_id=? ORDER BY epoch',[$shared['id']]);
$preview=call('account.deletion.preview',['policyVersion'=>4],$fresh);
ck($preview['policyVersion']===4&&$preview['cryptoRetention']['mayRetainEncryptedHistoricalBackups']===true,'no-key policy4 declares exact retained ciphertext/backup exception');
$selection=array_map(fn($s)=>['scopeId'=>$s['scopeId'],'action'=>$s['privateOwned']?'deletePrivate':'preserveReadOnly','headHash'=>$s['headHash'],'accessRevision'=>$s['accessRevision']],$preview['cryptoScopes']);
$delete=['operationId'=>uid(),'receiptToken'=>bin2hex(random_bytes(32)),'previewHash'=>$preview['previewHash'],'password'=>$alice['password'],'confirmation'=>'DELETE','policyVersion'=>4,'cryptoResolutions'=>$selection];
$bad=$delete;$bad['password']='Synthetic-wrong-password';deny(fn()=>call('account.deletion.confirm',$bad,$fresh),'invalid_credentials','wrong password cannot create carrier or delete original user');
ck(!NativeCryptoAccountTombstoneV2::account($pdo,$ownerAccount)&&count(q('SELECT id FROM users WHERE id=?',[$ownerUser]))===1,'step-up failure preserves all live identity');
$stale=$delete;$stale['cryptoResolutions'][0]['headHash']=str_repeat('f',64);deny(fn()=>call('account.deletion.confirm',$stale,$fresh),'deletion_preview_stale','exact per-scope head resolution is mandatory');
// Roll back after a deliberately injected final users-delete failure. No carrier,
// orphaned block or missing keyring can escape the enclosing transaction.
if($pdo->getAttribute(PDO::ATTR_DRIVER_NAME)==='sqlite'){
 q('CREATE TRIGGER deletion_rollback_test BEFORE DELETE ON users WHEN OLD.id='.(int)$ownerUser." BEGIN SELECT RAISE(ABORT,'synthetic'); END");
 try{call('account.deletion.confirm',$delete,$fresh);ck(false,'failure injected');}catch(PDOException $e){ck(true,'SQL deletion failure aborts complete cleanup');}
 q('DROP TRIGGER deletion_rollback_test');
 ck(!NativeCryptoAccountTombstoneV2::account($pdo,$ownerAccount)&&q('SELECT generation,authorization FROM familyhub_crypto_directory WHERE account_id=? ORDER BY generation',[$ownerAccount])===$before,'rollback restores identity and exact signed history');
}else{
 // Only test DDL uses the disposable synthetic database administrator. All
 // business API calls keep the normal application PDO/principal.
 $triggerPdo=$pdo;
 if(getenv('JIVIE_DELETE_TEST_ADMIN_PASSWORD')!==false){
   if(!preg_match('/^jivie_deletion_core_[a-f0-9]+$/D',DB_NAME)||!FAMILYHUB_DEVELOPMENT_MODE){throw new RuntimeException('Isolated synthetic DB required');}
   $triggerPdo=new PDO('mysql:host='.DB_HOSTNAME.';dbname='.DB_NAME,'root',getenv('JIVIE_DELETE_TEST_ADMIN_PASSWORD'),[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION]);
 }
 $triggerPdo->exec("CREATE TRIGGER deletion_rollback_test BEFORE DELETE ON users FOR EACH ROW BEGIN IF OLD.id=".(int)$ownerUser." THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='synthetic'; END IF; END");
 try{call('account.deletion.confirm',$delete,$fresh);ck(false,'failure injected');}catch(PDOException $e){ck(true,'SQL deletion failure aborts complete cleanup');}
 $triggerPdo->exec('DROP TRIGGER deletion_rollback_test');
 ck(!NativeCryptoAccountTombstoneV2::account($pdo,$ownerAccount)&&q('SELECT generation,authorization FROM familyhub_crypto_directory WHERE account_id=? ORDER BY generation',[$ownerAccount])===$before,'rollback restores identity and exact signed history');
}
$result=call('account.deletion.confirm',$delete,$fresh);
ck($result['deleted']===true,'authenticated login/password deletes without E2EE file or device signature');
ck(q('SELECT blob_id FROM familyhub_crypto_blob_chunks_v2 WHERE scope_id=?',[$personal['id']])===[]&&q('SELECT deleted_at FROM familyhub_scopes WHERE id=?',[$personal['id']])[0]['deleted_at']!==null,'reviewed wholly private active ciphertext and chunk closure removed');
ck(q('SELECT id FROM users WHERE id=?',[$ownerUser])===[],'original users row really deleted through FK path');
$t=q('SELECT * FROM familyhub_crypto_account_tombstones_v2 WHERE account_id=?',[$ownerAccount])[0];$carrier=(int)$t['carrier_user_id'];
ck(q('SELECT generation,authorization FROM familyhub_crypto_directory WHERE account_id=? ORDER BY generation',[$ownerAccount])===$before&&q('SELECT * FROM familyhub_crypto_scope_heads WHERE scope_id=? ORDER BY epoch',[$shared['id']])===$headBefore,'retained directory and shared signed scope bytes remain exact');
ck((int)q('SELECT user_id FROM familyhub_accounts WHERE account_id=?',[$ownerAccount])[0]['user_id']===$carrier,'account FK now references pseudonymous carrier, never a new login');
$u=q('SELECT * FROM users WHERE id=?',[$carrier])[0];ck($u['email']===''&&$u['name']==='Deleted account'&&$u['token']===''&&$u['api_access_token']===''&&(int)$u['is_active']===0,'carrier contains no original address/name/session credentials');
deny(fn()=>call('auth.me',[],$fresh),'device_revoked','old account transport denied after deletion');
ck(call('account.deletion.status',['operationId'=>$delete['operationId'],'receiptToken'=>$delete['receiptToken']])['deleted']===true,'lost confirmation ACK resolves without bearer by exact original receipt');
$surviving=call('crypto2.scope.headGet',['scopeId'=>$shared['id']],$recipient);
ck($surviving['headHash']===$head2['headHash'],'remaining member can retrieve unchanged historical shared head');
$dir=call('crypto2.directory.read',['scopeId'=>$shared['id'],'accountId'=>$ownerAccount,'directoryHeadHash'=>$state['headHash'],'afterGeneration'=>0,'limit'=>20],$recipient);
ck($dir['accountId']===$ownerAccount&&count($dir['entries'])>0,'historical UUID prefix remains scoped-readable after login removal');
// A direct DB reactivation must not revive authority; app admin edits are denied
// too. Original address reuse creates an unrelated account UUID.
q("UPDATE users SET is_active=1,disable_login_form=0,password=? WHERE id=?",[password_hash('Synthetic-reactivate-123',PASSWORD_BCRYPT),$carrier]);
deny(fn()=>call('auth.login',['username'=>$u['username'],'password'=>'Synthetic-reactivate-123','deviceName'=>'denied']),'invalid_credentials','permanent tombstone denies reactivated carrier login');
ck($container['userModel']->update(['id'=>$carrier,'is_active'=>1])===false&&$container['userModel']->remove($carrier)===false,'core admin cannot revive or cascade-remove carrier');
$container['userModel']->create(['username'=>$alice['username'],'password'=>$alice['password'],'role'=>'app-user']);$replacement=call('auth.login',['username'=>$alice['username'],'password'=>$alice['password'],'deviceName'=>'new identity']);
ck($replacement['user']['accountId']!==$ownerAccount&&q('SELECT scope_id FROM familyhub_members WHERE account_id=?',[$replacement['user']['accountId']])===[],'reused username has unrelated UUID and zero old grants');
// Sequential second deletion must not overwrite/fail the first scoped block.
$p2=call('account.deletion.preview',['policyVersion'=>4],$recipient);$r2=['operationId'=>uid(),'receiptToken'=>bin2hex(random_bytes(32)),'previewHash'=>$p2['previewHash'],'password'=>$recipient['password'],'confirmation'=>'DELETE','policyVersion'=>4,'cryptoResolutions'=>array_map(fn($s)=>['scopeId'=>$s['scopeId'],'action'=>$s['privateOwned']?'deletePrivate':'preserveReadOnly','headHash'=>$s['headHash'],'accessRevision'=>$s['accessRevision']],$p2['cryptoScopes'])];
if(getenv('JIVIE_DELETE_CORE_SECOND')==='1'){
 $coreDirectory=q('SELECT generation,authorization FROM familyhub_crypto_directory WHERE account_id=? ORDER BY generation',[$recipient['user']['accountId']]);
 ck($container['userModel']->remove($recipient['user']['id'])===true,'actual core userModel removal preserves foreign shared history before FK cascade');
 ck(q('SELECT generation,authorization FROM familyhub_crypto_directory WHERE account_id=? ORDER BY generation',[$recipient['user']['accountId']])===$coreDirectory&&q('SELECT * FROM familyhub_crypto_scope_heads WHERE scope_id=? ORDER BY epoch',[$shared['id']])===$headBefore,'core users FK path retains exact signed prefix and shared head');
}else{ck(call('account.deletion.confirm',$r2,$recipient)['deleted']===true,'second shared member can delete without overwriting first block');}
ck(count(q('SELECT account_id FROM familyhub_crypto_account_tombstones_v2 WHERE account_id IN (?,?)',[$ownerAccount,$recipient['user']['accountId']]))===2,'both permanent tombstones survive same scope');
echo 'Deletion policy4 total '.$checks.PHP_EOL;
