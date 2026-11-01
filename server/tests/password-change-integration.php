<?php
/** Fresh in-memory SQLite, real dispatcher/auth/TOTP/schema. No HTTP or retained data.
 * --case=NAME supports rerunning only a failed group (never successful groups).
 */
define('FAMILYHUB_SMTP_HOST', 'smtp.synthetic.invalid');
define('FAMILYHUB_SMTP_FROM', 'sender@synthetic.invalid');
define('BRUTEFORCE_LOCKDOWN', 3);
define('BRUTEFORCE_LOCKDOWN_DURATION', 15);
require __DIR__.'/account-changes-fixture.php';
require '/var/www/app/vendor/autoload.php';
use Kanboard\Plugin\FamilyHub\Model\NativeService;
use Kanboard\Plugin\FamilyHub\Model\NativePasswordChangeService;
use Kanboard\Plugin\FamilyHub\Model\NativeAccountTokens;
use Kanboard\Plugin\FamilyHub\Model\NativeAccountMailCrypto;
use Kanboard\Plugin\FamilyHub\Model\NativeAccountMailTransport;
use Kanboard\Plugin\FamilyHub\Model\NativeSecurityMailQueue;

sql('ALTER TABLE users ADD COLUMN nb_failed_login INTEGER NOT NULL DEFAULT 0');
sql('ALTER TABLE users ADD COLUMN lock_expiration_date INTEGER NOT NULL DEFAULT 0');
$old = 'old synthetic password'; $new = ' new synthetic password ';
$hash = password_hash($old, PASSWORD_BCRYPT);
sql('UPDATE users SET password=?', [$hash]);
$fingerprint = hash('sha256', json_encode([$hash, 0, null], JSON_THROW_ON_ERROR));
sql('UPDATE familyhub_devices SET credentials_hash=?', [$fingerprint]);
sql('INSERT INTO familyhub_email_identities(account_id,email,verified_at,pending_email,revision) VALUES(?,?,?,?,1)', [id(1), 'owner@synthetic.invalid', time(), 'pending@synthetic.invalid']);
foreach ([101,111] as $d) {
    sql('INSERT INTO familyhub_push_registrations(device_id,account_id,token_hash,token_cipher,project_id,platform,language,revision,active,updated_at) VALUES(?,?,?,?,?,?,?,?,?,?)', [id($d),id(1),hash('sha256',(string)$d),'opaque-push-'.$d,'synthetic','android','sl',1,1,time()]);
    sql('INSERT INTO familyhub_push_jobs(inbox_id,device_id,registration_revision,token_hash,state,attempts,next_attempt,expires_at) VALUES(?,?,?,?,?,?,?,?)', [$d,id($d),1,hash('sha256',(string)$d),'pending',0,time(),time()+3600]);
}
$key = random_bytes(32); $nonce = random_bytes(24); $plain = 'retained encrypted account data';
$cipher = base64_encode($nonce.sodium_crypto_aead_xchacha20poly1305_ietf_encrypt($plain,'synthetic-aad',$nonce,$key));
$sign = sodium_crypto_sign_keypair(); $box = sodium_crypto_box_keypair();
sql('INSERT INTO familyhub_crypto_accounts VALUES(?,?,?,?,?,?,?,?,?,?)', [id(1),base64_encode(sodium_crypto_sign_publickey($sign)),base64_encode(sodium_crypto_box_publickey($box)),$cipher,'genesis','keyring-proof','generation-proof',7,1,2]);
foreach ([101,111] as $d) { sql('INSERT INTO familyhub_crypto_devices(account_id,device_id,signing_key,encryption_key,certificate,keyring_write,manage_devices) VALUES(?,?,?,?,?,1,1)', [id(1),id($d),base64_encode(sodium_crypto_sign_publickey($sign)),base64_encode(sodium_crypto_box_publickey($box)),'signed-device']); }
sql('INSERT INTO familyhub_crypto_records VALUES(?,?,?,?,?,?,?,?,?,?)',[id(3),id(50),'task',9,0,4,1,$cipher,'metadata','signed-record']);
$tables = sql("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name")->fetchAll(PDO::FETCH_COLUMN);
$baseline = [];
foreach ($tables as $table) { $baseline[$table] = sql('SELECT * FROM '.$table)->fetchAll(PDO::FETCH_ASSOC); }
function resetFixture() { global $tables,$baseline,$service,$db; foreach ($tables as $t) { sql('DELETE FROM '.$t); } foreach ($baseline as $t=>$rows) { foreach ($rows as $r) { sql('INSERT INTO '.$t.'('.implode(',',array_keys($r)).') VALUES('.implode(',',array_fill(0,count($r),'?')).')',array_values($r)); } } $service=new NativeService(['db'=>$db]); }
function api($op,$p=[],$who=1) { global $service; return $service->dispatch($op,$p,$who===null?'':bearer($who),'synthetic-password-change'); }
function params() { global $old,$new; return ['currentPassword'=>$old,'newPassword'=>$new]; }
function snapshotCrypto() { global $tables; $out=[]; foreach ($tables as $t) { if (str_starts_with($t,'familyhub_crypto_') && $t!=='familyhub_crypto_security_events' || in_array($t,['familyhub_scopes','familyhub_members','familyhub_records','familyhub_accounts'],true)) { $out[$t]=sql('SELECT * FROM '.$t.' ORDER BY rowid')->fetchAll(PDO::FETCH_ASSOC); } } return $out; }
function issueReset($who=1) { global $db; $u=sql('SELECT * FROM users WHERE id=?',[$who])->fetch(PDO::FETCH_ASSOC);$u['account_id']=id($who);$tokens=new NativeAccountTokens(['db'=>$db]);$tokens->issue($u,'reset','owner@synthetic.invalid',1,'sl');$r=sql("SELECT t.*,m.token_cipher FROM familyhub_account_tokens t JOIN familyhub_account_mail m ON m.token_id=t.id WHERE t.account_id=? AND t.purpose='reset' AND t.revoked_at IS NULL",[id($who)])->fetch(PDO::FETCH_ASSOC);return NativeAccountMailCrypto::decrypt($r['token_cipher'],$tokens->aad($r['id'],id($who))); }
function totp($step=null) { return (new \Otp\Otp())->totp(\Base32\Base32::decode('JBSWY3DPEHPK3PXP'),$step??intdiv(time(),30)); }
function activateTotp() { sql('UPDATE users SET twofactor_activated=1,twofactor_secret=? WHERE id=1',['JBSWY3DPEHPK3PXP']);$u=sql('SELECT * FROM users WHERE id=1')->fetch(PDO::FETCH_ASSOC);sql('UPDATE familyhub_devices SET credentials_hash=? WHERE user_id=1',[hash('sha256',json_encode([$u['password'],1,$u['twofactor_secret']],JSON_THROW_ON_ERROR))]); }
class InterleavedPasswordChange extends NativePasswordChangeService {
    public $afterAccountRate; private $rates=0;
    public function rate(array $buckets) { parent::rate($buckets); if (++$this->rates===2) { ($this->afterAccountRate)(); } }
}
$cases = [];
$cases['success'] = function () use ($new,$old,$key,$plain,$cipher) {
    ck(api('capabilities')['features']['passwordChange']===true,'capability advertises authenticated password change');
    $before=snapshotCrypto();$own=sql('SELECT * FROM familyhub_devices WHERE id=?',[id(101)])->fetch(PDO::FETCH_ASSOC);$foreign=sql('SELECT * FROM familyhub_devices WHERE user_id=2')->fetchAll(PDO::FETCH_ASSOC);
    $reset=issueReset();$u=sql('SELECT * FROM users WHERE id=1')->fetch(PDO::FETCH_ASSOC);$u['account_id']=id(1);global $db;(new NativeAccountTokens(['db'=>$db]))->issue($u,'verify','pending@synthetic.invalid',1,'sl');
    ck(api('account.password.change',params())===['changed'=>true,'sessionPreserved'=>true,'accountId'=>id(1),'deviceId'=>id(101)],'response binds preserved account and device');
    $after=sql('SELECT * FROM familyhub_devices WHERE id=?',[id(101)])->fetch(PDO::FETCH_ASSOC);$own['credentials_hash']=$after['credentials_hash'];
    ck($own===$after && api('auth.me')['device']['id']===id(101),'exact initiating token identity and expiry remain authenticated');
    ck(api('auth.renew',['deviceId'=>id(101)])['device']['id']===id(101),'same initiating bearer can renew after change');
    deny(fn()=>api('auth.me',[],11),'device_revoked','other native session is revoked');
    ck($foreign===sql('SELECT * FROM familyhub_devices WHERE user_id=2')->fetchAll(PDO::FETCH_ASSOC),'foreign account sessions remain exact');
    ck(sql('SELECT active FROM familyhub_push_registrations WHERE device_id=?',[id(101)])->fetchColumn()===1 && sql('SELECT active FROM familyhub_push_registrations WHERE device_id=?',[id(111)])->fetchColumn()===0 && sql('SELECT state FROM familyhub_push_jobs WHERE device_id=?',[id(111)])->fetchColumn()==='cancelled','own push survives and other native push is cancelled');
    ck(sql('SELECT count(*) FROM familyhub_account_tokens WHERE revoked_at IS NULL AND consumed_at IS NULL')->fetchColumn()===0 && sql('SELECT count(*) FROM familyhub_account_mail WHERE token_cipher IS NOT NULL')->fetchColumn()===0 && sql('SELECT pending_email FROM familyhub_email_identities WHERE account_id=?',[id(1)])->fetchColumn()===null,'reset and verification capabilities/mail are invalidated atomically');
    ck(snapshotCrypto()===$before,'all E2EE roots device certificates ciphertext receipts and shared data are byte exact');
    $bytes=base64_decode(sql('SELECT keyring FROM familyhub_crypto_accounts WHERE account_id=?',[id(1)])->fetchColumn());
    ck(sodium_crypto_aead_xchacha20poly1305_ietf_decrypt(substr($bytes,24),'synthetic-aad',substr($bytes,0,24),$key)===$plain,'retained real AEAD account payload still decrypts');
    $stored=sql('SELECT password FROM users WHERE id=1')->fetchColumn();ck(password_verify($new,$stored) && !password_verify(trim($new),$stored),'password bytes including surrounding whitespace are preserved');
    deny(fn()=>api('auth.login',['username'=>'synthetic1','password'=>$old,'deviceName'=>'Synthetic']),'invalid_credentials','old password no longer logs in');
    ck(isset(api('auth.login',['username'=>'synthetic1','password'=>$new,'deviceName'=>'Synthetic'])['token']),'new exact password logs in');
    deny(fn()=>api('auth.reset.confirm',['token'=>$reset,'password'=>'reset synthetic password'],null),'account_token_invalid','old reset cannot revoke preserved session');
    $events=sql('SELECT kind FROM familyhub_crypto_security_events')->fetchAll(PDO::FETCH_COLUMN);ck($events===['auth.passwordChanged'] && !str_contains(json_encode($events),$new),'safe security event contains no password');
    ck(str_contains(NativeAccountMailTransport::securityMessage('auth.passwordChanged','en')[1],'password was changed'),'new audit event has supported security mail copy');
    $transport=new class { public $calls=[];function send(...$args){$this->calls[]=$args;} };
    $delivery=(new NativeSecurityMailQueue(['db'=>$db]))->run(1,$transport);
    ck($delivery===['sent'=>1,'retry'=>0,'cancelled'=>0] && count($transport->calls)===1 && $transport->calls[0][2]==='' && $transport->calls[0][5]===['eventKind'=>'auth.passwordChanged'],'real queue permits fixed password change notice without secrets');
};
$cases['credentials'] = function () {
    $before=snapshotCrypto();$hash=sql('SELECT password FROM users WHERE id=1')->fetchColumn();
    deny(fn()=>api('account.password.change',array_replace(params(),['currentPassword'=>'wrong synthetic password'])),'invalid_credentials','wrong current password rejected');
    ck(sql('SELECT nb_failed_login FROM users WHERE id=1')->fetchColumn()===1 && sql('SELECT password FROM users WHERE id=1')->fetchColumn()===$hash && api('auth.me')['device']['id']===id(101),'wrong password counter commits while current auth and password survive');
    sql('UPDATE users SET lock_expiration_date=? WHERE id=1',[time()+900]);
    deny(fn()=>api('account.password.change',params()),'invalid_credentials','locked account cannot change password');
    ck(snapshotCrypto()===$before,'failed and locked step-up do not mutate E2EE');
};
$cases['validation'] = function () {
    foreach (['short',' '.str_repeat('a',72),"valid-password\0bad",str_repeat(' ',12),"invalid-utf8-\xff"] as $bad) { deny(fn()=>api('account.password.change',array_replace(params(),['newPassword'=>$bad])),$bad==='short'?'password_too_short':'validation_error','reject invalid new password '.strlen($bad).' bytes'); }
    deny(fn()=>api('account.password.change',array_replace(params(),['deviceId'=>id(102)])),'validation_error','caller cannot select a surviving device');
    deny(fn()=>api('account.password.change',params(),null),'auth_required','password change requires native bearer');
};
$cases['totp'] = function () {
    activateTotp();$p=params();
    deny(fn()=>api('account.password.change',$p),'two_factor_required','enabled TOTP cannot be omitted');
    $invalid=totp();$invalid=$invalid==='000000'?'111111':'000000';
    deny(fn()=>api('account.password.change',$p+['otp'=>$invalid]),'invalid_credentials','invalid TOTP rejected');
    ck(sql('SELECT nb_failed_login FROM users WHERE id=1')->fetchColumn()===1,'invalid TOTP counter commits');
    $acceptedCode=totp();
    ck(api('account.password.change',$p+['otp'=>$acceptedCode])['changed']===true,'valid real TOTP changes password');
    global $new;$p=['currentPassword'=>$new,'newPassword'=>'another synthetic password','otp'=>$acceptedCode];
    deny(fn()=>api('account.password.change',$p),'invalid_credentials','accepted TOTP step cannot replay');
};
$cases['actor'] = function () {
    foreach (['expired','revoked','inactive','ldap','disabled','recycled','staleCredentials'] as $change) {
        resetFixture();
        if ($change==='expired') { sql('UPDATE familyhub_devices SET expires_at=0 WHERE id=?',[id(101)]); }
        if ($change==='revoked') { sql('UPDATE familyhub_devices SET revoked_at=1 WHERE id=?',[id(101)]); }
        if ($change==='inactive') { sql('UPDATE users SET is_active=0 WHERE id=1'); }
        if ($change==='ldap') { sql('UPDATE users SET is_ldap_user=1 WHERE id=1'); }
        if ($change==='disabled') { sql('UPDATE users SET disable_login_form=1 WHERE id=1'); }
        if ($change==='recycled') { sql('UPDATE familyhub_accounts SET account_id=? WHERE user_id=1',[id(999)]); }
        if ($change==='staleCredentials') { sql('UPDATE users SET password=? WHERE id=1',['different-hash']); }
        $before=snapshotCrypto();deny(fn()=>api('account.password.change',params()),'device_revoked',$change.' actor cannot change password');ck(snapshotCrypto()===$before,$change.' actor leaves E2EE exact');
    }
};
$cases['rate'] = function () {
    foreach (['password-change-account:'.id(1)=>10,'password-change-ip:synthetic-password-change'=>20] as $bucket=>$limit) {
        resetFixture();sql('INSERT INTO familyhub_rate_limits VALUES(?,?,?)',[hash('sha256',$bucket),time(),$limit]);
        $before=sql('SELECT password FROM users WHERE id=1')->fetchColumn();deny(fn()=>api('account.password.change',params()),'rate_limited','preexisting '.explode(':',$bucket)[0].' limit enforced');ck(sql('SELECT password FROM users WHERE id=1')->fetchColumn()===$before && sql('SELECT attempts FROM familyhub_rate_limits WHERE id=?',[hash('sha256',$bucket)])->fetchColumn()===$limit+1,'rate denial preserves password and commits rate counter');
    }
};
$cases['rollback'] = function () {
    issueReset();$before=[];$names=['users','familyhub_devices','familyhub_push_registrations','familyhub_push_jobs','familyhub_account_tokens','familyhub_account_mail','familyhub_email_identities'];foreach($names as $t){$before[$t]=sql('SELECT * FROM '.$t.' ORDER BY rowid')->fetchAll(PDO::FETCH_ASSOC);}
    $crypto=snapshotCrypto();sql("CREATE TEMP TRIGGER synthetic_audit_failure BEFORE INSERT ON familyhub_crypto_security_events BEGIN SELECT RAISE(ABORT,'synthetic audit storage failure'); END");
    try { api('account.password.change',params());$rejected=false; } catch (PDOException $e) { $rejected=str_contains($e->getMessage(),'synthetic audit storage failure'); } finally { sql('DROP TRIGGER synthetic_audit_failure'); }
    ck($rejected,'audit storage failure rejects password change');$after=[];foreach($names as $t){$after[$t]=sql('SELECT * FROM '.$t.' ORDER BY rowid')->fetchAll(PDO::FETCH_ASSOC);}
    ck($after===$before && snapshotCrypto()===$crypto && api('auth.me')['device']['id']===id(101),'transaction rolls back password survivor binding other revocations tokens mail push and identity together');
};
$cases['interleaving'] = function () use ($db) {
    foreach (['revoke','reset','competingChange'] as $action) {
        resetFixture();$reset=$action==='reset'?issueReset():null;$race=new InterleavedPasswordChange(['db'=>$db],bearer(1),'synthetic-password-change-race');
        $race->afterAccountRate=function () use ($action,$reset) { if ($action==='revoke') { api('auth.revoke',['deviceId'=>id(101)],11); } elseif ($action==='reset') { api('auth.reset.confirm',['token'=>$reset,'password'=>'reset synthetic password'],null); } else { api('account.password.change',params(),11); } };
        $before=snapshotCrypto();deny(fn()=>$race->execute('account.password.change',params()),'device_revoked',$action.' committed after preflight wins before locked actor');ck(snapshotCrypto()===$before,$action.' interleaving preserves E2EE byte exact');
    }
};
$cases['resetBinding'] = function () {
    $token=issueReset();$server=sql('SELECT server_id FROM familyhub_instance WHERE id=1')->fetchColumn();$p=['token'=>$token,'password'=>'reset synthetic password'];
    foreach ([['expectedAccountId'=>id(2),'expectedServerId'=>$server],['expectedAccountId'=>id(1),'expectedServerId'=>id(999)]] as $binding) { deny(fn()=>api('auth.reset.confirm',$p+$binding,null),'password_reset_identity_mismatch','bound reset rejects foreign account/server'); }
    deny(fn()=>api('auth.reset.confirm',$p+['expectedAccountId'=>id(1)],null),'validation_error','bound reset requires complete binding pair');
    ck(api('auth.me')['device']['id']===id(101),'mismatched reset leaves current bearer authenticated');
    $before=snapshotCrypto();ck(api('auth.reset.confirm',$p+['expectedAccountId'=>id(1),'expectedServerId'=>$server],null)===['reset'=>true],'matching bound email reset retains established reset operation');
    deny(fn()=>api('auth.me'),'device_revoked','email reset still revokes initiating native session');ck(snapshotCrypto()===$before,'email password reset never changes E2EE roots ciphertext or devices');
};
$selected=null;foreach(array_slice($argv,1) as $arg) { if(str_starts_with($arg,'--case=')) {$selected=substr($arg,7);}else{throw new RuntimeException('Unknown argument');} }
if ($selected!==null && !isset($cases[$selected])) { throw new RuntimeException('Unknown test case'); }
foreach ($cases as $name=>$run) { if($selected!==null && $selected!==$name){continue;}resetFixture();echo 'CASE: '.$name.PHP_EOL;$run();echo 'CASE PASS: '.$name.PHP_EOL; }
echo json_encode(['status'=>'pass','checks'=>$checks,'case'=>$selected??'all','fixture'=>'fresh in-memory SQLite','dispatcher'=>true,'realTOTP'=>true,'realAEAD'=>true,'interleaving'=>'deterministic pretransaction hook','HTTP'=>false,'phones'=>false]).PHP_EOL;
