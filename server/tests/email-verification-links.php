<?php
/** New standalone verification-link controls: fresh SQLite; no retained server or SMTP. */
define('FAMILYHUB_SMTP_HOST','smtp.synthetic.invalid');
define('FAMILYHUB_SMTP_FROM','sender@synthetic.invalid');
require __DIR__.'/account-changes-fixture.php';
use Kanboard\Plugin\FamilyHub\Model\NativeAccountService;
use Kanboard\Plugin\FamilyHub\Model\NativeAccountTokens;
use Kanboard\Plugin\FamilyHub\Model\NativeAccountMailCrypto;
use Kanboard\Plugin\FamilyHub\Model\NativeAccountMailTransport;
$account=id(1);$server=sql('SELECT server_id FROM familyhub_instance WHERE id=1')->fetchColumn();
sql('INSERT INTO familyhub_email_identities(account_id,pending_email,revision) VALUES(?,?,1)',[$account,'target@synthetic.invalid']);
$tokens=new NativeAccountTokens(['db'=>$db]);
$user=sql('SELECT * FROM users WHERE id=1')->fetch(PDO::FETCH_ASSOC);$user['account_id']=$account;
function issueLink($revision=1){global $tokens,$user,$account,$server;
    $tokens->issue($user,'verify','target@synthetic.invalid',$revision,'sl');
    $row=sql('SELECT * FROM familyhub_account_tokens WHERE account_id=? AND consumed_at IS NULL AND revoked_at IS NULL',[$account])->fetch(PDO::FETCH_ASSOC);
    $cipher=sql('SELECT token_cipher FROM familyhub_account_mail WHERE token_id=?',[$row['id']])->fetchColumn();
    return ['token'=>NativeAccountMailCrypto::decrypt($cipher,$tokens->aad($row['id'],$account)),'accountId'=>$account,'serverId'=>$server,'email'=>$row['email']];
}
$link=issueLink();$service=new NativeAccountService(['db'=>$db],'','synthetic-email-link');
$before=sql('SELECT count(*) FROM familyhub_members')->fetchColumn();
// Actual landing controller runs with a minimal response/config seam; no request
// token reaches PHP because the browser fragment is never part of GET.
eval('namespace Kanboard\\Controller; class BaseController { public $response; public $configModel; public $container; public function __construct($c){$this->container=$c;$this->response=$c["response"];$this->configModel=$c["configModel"];} }');
$response=new class {public $body;public $status=200;public $headers=[];function withHeader($k,$v){$this->headers[$k]=$v;return $this;}function withBody($v){$this->body=$v;return $this;}function withStatusCode($v){$this->status=$v;return $this;}function send(){}function json($v,$s=200){$this->body=$v;$this->status=$s;}};
$config=new class {function get($k){return 'https://synthetic.invalid/jivie';}};
$controller=new \Kanboard\Plugin\FamilyHub\Controller\EmailVerificationController(['db'=>$db,'response'=>$response,'configModel'=>$config]);
$_SERVER=['REQUEST_METHOD'=>'GET','HTTPS'=>'on'];$_GET=[];
$controller->show();
ck($response->status===200 && str_contains($response->body,"onclick=async"),'GET renders an explicit confirmation action');
ck(!str_contains($response->body,$link['token']) && sql('SELECT count(*) FROM familyhub_account_tokens WHERE consumed_at IS NOT NULL')->fetchColumn()===0,'GET and mail preview neither receive nor consume token');
$controller->confirm();ck($response->status===405 && sql('SELECT count(*) FROM familyhub_account_tokens WHERE consumed_at IS NOT NULL')->fetchColumn()===0,'GET on confirm route cannot consume token');

deny(fn()=>$service->confirmLink(array_replace($link,['serverId'=>id(999)])),'account_token_invalid','wrong server binding rejected');
deny(fn()=>$service->confirmLink(array_replace($link,['accountId'=>id(2)])),'account_token_invalid','wrong account binding rejected');
deny(fn()=>$service->confirmLink(array_replace($link,['email'=>'other@synthetic.invalid'])),'account_token_invalid','wrong requested email rejected');
$native=new NativeAccountService(['db'=>$db],bearer(2),'synthetic-email-native');
deny(fn()=>$native->execute('account.email.confirm',$link),'account_token_invalid','signed in foreign account cannot consume link');
$row=sql('SELECT * FROM familyhub_account_tokens WHERE account_id=? AND consumed_at IS NULL AND revoked_at IS NULL',[$account])->fetch(PDO::FETCH_ASSOC);
[$title,$message]=NativeAccountMailTransport::verificationMessage($link['token'],'sl',['serverUrl'=>'https://synthetic.invalid/jivie','serverId'=>$server,'accountId'=>$account,'email'=>$link['email'],'expiresAt'=>$row['expires_at']]);
ck(str_contains($message,'#token=') && str_contains($message,'EmailVerificationController') && str_contains($message,$link['token']),'mail supplies HTTPS fragment link and manual code');
ck(!str_contains(explode('#',$message)[0],$link['token']),'token absent from landing request URL');
ck(sql('SELECT consumed_at FROM familyhub_account_tokens WHERE id=?',[$row['id']])->fetchColumn()===null,'rendering mail does not consume verification');
ck($service->confirmLink($link)===['verified'=>true],'explicit capability confirmation succeeds');
deny(fn()=>$service->confirmLink($link),'account_token_invalid','single use blocks replay');
$status=(new NativeAccountService(['db'=>$db],bearer(1),'synthetic-email-status'))->execute('account.status',[]);
ck($status['emailVerified'] && $status['email']===$link['email'] && $status['pendingEmail']===null,'open mobile bearer sees confirmed status without login');
ck(sql('SELECT count(*) FROM familyhub_members')->fetchColumn()===$before,'verification grants no membership');
$link=issueLink();sql('UPDATE familyhub_email_identities SET pending_email=?,revision=2 WHERE account_id=?',['new@synthetic.invalid',$account]);
deny(fn()=>$service->confirmLink($link),'account_token_invalid','stale identity revision/email rejects old link');
sql('UPDATE familyhub_email_identities SET pending_email=?,revision=1 WHERE account_id=?',['target@synthetic.invalid',$account]);
$link=issueLink();sql('UPDATE familyhub_account_tokens SET expires_at=0 WHERE consumed_at IS NULL AND revoked_at IS NULL');
deny(fn()=>$service->confirmLink($link),'account_token_invalid','expired link rejected');
$link=issueLink();sql('UPDATE users SET password=? WHERE id=1',['synthetic-new-password']);
deny(fn()=>$service->confirmLink($link),'account_token_invalid','credential change rejects mailed link');
echo json_encode(['status'=>'pass','checks'=>$checks,'fixture'=>'fresh SQLite','HTTP'=>false,'SMTP'=>false]).PHP_EOL;
