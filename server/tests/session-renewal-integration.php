<?php
// Disposable synthetic users only. No pre-existing fixtures or volumes change.
umask(0077);
define('FAMILYHUB_ACCOUNT_MAIL_KEY_BASE64', base64_encode(random_bytes(32)));
define('FAMILYHUB_SMTP_HOST', '127.0.0.1');
define('FAMILYHUB_SMTP_FROM', 'sender@capture.invalid');
require '/var/www/app/app/common.php';
if (session_status() === PHP_SESSION_ACTIVE) { session_abort(); }
if (!defined('FAMILYHUB_DEVELOPMENT_MODE') || FAMILYHUB_DEVELOPMENT_MODE !== true) { throw new RuntimeException('Synthetic development only'); }
use Kanboard\Plugin\FamilyHub\Model\NativeService;
use Kanboard\Plugin\FamilyHub\Model\NativeError;
use Kanboard\Plugin\FamilyHub\Model\NativeAccountMailCrypto;
use Kanboard\Plugin\FamilyHub\Model\NativeAccountTokens;
$pdo = $container['db']->getConnection(); $service = new NativeService($container);
$prefix = 'renewal_'.bin2hex(random_bytes(6)); $password = bin2hex(random_bytes(18));
$ip = 'synthetic-renewal-'.bin2hex(random_bytes(8)); $checks = 0; $ids = [];
function check($value, $description) { global $checks; if (!$value) { throw new RuntimeException('FAIL: '.$description); } $checks++; echo 'PASS: '.$description.PHP_EOL; }
function api($operation, $params=[], $token='') { global $service, $ip; return $service->dispatch($operation, $params, $token ? 'Bearer '.$token : '', $ip); }
function query($sql, $params=[]) { global $pdo; $q=$pdo->prepare($sql); $q->execute($params); $rows=$q->fetchAll(PDO::FETCH_ASSOC); $q->closeCursor(); return $rows; }
function change($sql, $params) { global $pdo; $q=$pdo->prepare($sql); $q->execute($params); $q->closeCursor(); }
function denied($operation, $params, $token, $code, $description) { try { api($operation, $params, $token); $ok=false; } catch (NativeError $error) { $ok=$error->errorCode===$code; } check($ok,$description); }
function session($name) { global $container,$prefix,$password,$ids; $ids[$name]=$container['userModel']->create(['username'=>$prefix.'_'.$name,'password'=>$password,'role'=>'app-user']); return api('auth.login',['username'=>$prefix.'_'.$name,'password'=>$password,'deviceName'=>'Disposable renewal test']); }
function renewRequest($session) { global $ip; return ['operation'=>'auth.renew','params'=>['deviceId'=>$session['device']['id']],'bearer'=>'Bearer '.$session['token'],'ip'=>$ip]; }
function due($session) { change('UPDATE familyhub_devices SET expires_at=? WHERE id=?',[time()+60,$session['device']['id']]); }
function race(array $requests) {
    $children=[]; $paths=[];
    try {
        foreach ($requests as $request) {
            $path='/tmp/familyhub-renewal-race-'.bin2hex(random_bytes(8)).'.json';
            file_put_contents($path,json_encode($request)); chmod($path,0600); $paths[]=$path;
            $process=proc_open([PHP_BINARY,'/familyhub-tests/account-race-child.php',$path],[0=>['pipe','r'],1=>['pipe','w'],2=>['pipe','w']],$pipes);
            stream_set_timeout($pipes[1],20);
            if (trim(fgets($pipes[1]))!=='ready') { throw new RuntimeException('Race worker unavailable'); }
            $children[]=[$process,$pipes];
        }
        foreach ($children as [$process,$pipes]) { fwrite($pipes[0],"go\n"); fflush($pipes[0]); }
        $results=[];
        foreach ($children as [$process,$pipes]) { $results[]=json_decode(fgets($pipes[1]),true,32,JSON_THROW_ON_ERROR); foreach($pipes as $pipe){fclose($pipe);} proc_close($process); }
        return $results;
    } finally { foreach($paths as $path){@unlink($path);} }
}
try {
    check(api('capabilities')['features']['sessionRenewal'] === true, 'capability advertises supported renewal');
    $active=session('active'); $device=$active['device']['id']; $token=$active['token'];
    denied('auth.renew',['deviceId'=>$device],'','auth_required','renewal requires native bearer');
    $foreign=session('foreign');
    denied('auth.renew',['deviceId'=>$foreign['device']['id']],$token,'permission_revoked','bearer cannot renew a different device');
    $unchanged=api('auth.renew',['deviceId'=>$device],$token);
    check($unchanged['device']['expiresAt']===$active['device']['expiresAt'],'early renewal does not indefinitely advance expiry on retries');
    due($active); $renewed=api('auth.renew',['deviceId'=>$device],$token);
    check($renewed['device']['expiresAt']>=time()+2591998 && $renewed['device']['expiresAt']<=time()+2592000,'near expiry extends by thirty days');
    check($renewed['device']['id']===$device && $renewed['user']['accountId']===$active['user']['accountId'] && !isset($renewed['token']),'renewal binds existing account/device and never rotates bearer');
    check(query('SELECT token_hash FROM familyhub_devices WHERE id=?',[$device])[0]['token_hash']===hash('sha256',$token),'stored bearer hash remains unchanged');
    check(api('auth.renew',['deviceId'=>$device],$token)['device']['expiresAt']===$renewed['device']['expiresAt'],'lost reply retry returns same renewed expiry');
    due($active); $out=race([renewRequest($active),renewRequest($active)]);
    check($out[0]['ok'] && $out[1]['ok'],'two simultaneous renewals safely complete');
    check(count(query('SELECT id FROM familyhub_devices WHERE user_id=? AND account_id=?',[$ids['active'],$active['user']['accountId']]))===1,'concurrent renewal never creates another device');
    $expired=session('expired'); change('UPDATE familyhub_devices SET expires_at=? WHERE id=?',[time()-1,$expired['device']['id']]);
    denied('auth.renew',['deviceId'=>$expired['device']['id']],$expired['token'],'device_revoked','expired bearer cannot be revived');
    $revoked=session('revoked'); due($revoked);
    $revoke=renewRequest($revoked); $revoke['operation']='auth.revoke';
    $out=race([renewRequest($revoked),$revoke]);
    check($out[1]['ok'] && ($out[0]['ok'] || $out[0]['error']==='device_revoked'),'concurrent revoke serializes with renewal');
    denied('auth.renew',['deviceId'=>$revoked['device']['id']],$revoked['token'],'device_revoked','revoke wins permanently after concurrent renewal');
    foreach (['password','totp','inactive','deleted','recycled'] as $name) {
        $s=session($name); due($s);
        if ($name==='password') { change('UPDATE users SET password=? WHERE id=?',[password_hash('changed-synthetic-password',PASSWORD_BCRYPT),$ids[$name]]); }
        if ($name==='totp') { change('UPDATE users SET twofactor_activated=1,twofactor_secret=? WHERE id=?',['JBSWY3DPEHPK3PXP',$ids[$name]]); }
        if ($name==='inactive') { change('UPDATE users SET is_active=0 WHERE id=?',[$ids[$name]]); }
        if ($name==='deleted') { $container['userModel']->remove($ids[$name]); }
        if ($name==='recycled') { change('UPDATE familyhub_accounts SET account_id=? WHERE user_id=?',[substr(bin2hex(random_bytes(18)),0,36),$ids[$name]]); }
        denied('auth.renew',['deviceId'=>$s['device']['id']],$s['token'],'device_revoked',$name.' change prevents renewal');
    }
    $reset=session('reset'); $account=$reset['user']['accountId'];
    api('account.email.request',['email'=>$prefix.'@capture.invalid','language'=>'sl','password'=>$password],$reset['token']);
    $row=query("SELECT * FROM familyhub_account_tokens WHERE account_id=? AND purpose='verify' AND revoked_at IS NULL",[$account])[0];
    $cipher=query('SELECT token_cipher FROM familyhub_account_mail WHERE token_id=?',[$row['id']])[0]['token_cipher'];
    $code=NativeAccountMailCrypto::decrypt($cipher,(new NativeAccountTokens($container))->aad($row['id'],$account));
    api('account.email.confirm',['token'=>$code],$reset['token']);
    api('auth.reset.request',['username'=>$prefix.'_reset','language'=>'sl']);
    $row=query("SELECT * FROM familyhub_account_tokens WHERE account_id=? AND purpose='reset' AND revoked_at IS NULL",[$account])[0];
    $cipher=query('SELECT token_cipher FROM familyhub_account_mail WHERE token_id=?',[$row['id']])[0]['token_cipher'];
    $code=NativeAccountMailCrypto::decrypt($cipher,(new NativeAccountTokens($container))->aad($row['id'],$account));
    due($reset);
    $resetRequest=['operation'=>'auth.reset.confirm','params'=>['token'=>$code,'password'=>'new-synthetic-password-123'],'mailKey'=>FAMILYHUB_ACCOUNT_MAIL_KEY_BASE64,'ip'=>$ip];
    $out=race([renewRequest($reset),$resetRequest]);
    check($out[1]['ok'] && ($out[0]['ok'] || $out[0]['error']==='device_revoked'),'password reset and renewal serialize on same user');
    denied('auth.renew',['deviceId'=>$reset['device']['id']],$reset['token'],'device_revoked','reset revokes renewed bearer and retry cannot revive it');
    echo 'PASS: '.$checks.' session renewal checks ('.$pdo->getAttribute(PDO::ATTR_DRIVER_NAME).')'.PHP_EOL;
} finally {
    // Only IDs created by this invocation; no pre-existing QA account is touched.
    foreach($ids as $id) { $container['userModel']->remove($id); }
}
