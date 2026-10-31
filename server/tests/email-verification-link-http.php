<?php
/** New physical loopback HTTP controller seam; isolated fresh SQLite, no TLS/SMTP claim. */
define('FAMILYHUB_SMTP_HOST','smtp.synthetic.invalid');define('FAMILYHUB_SMTP_FROM','sender@synthetic.invalid');
require __DIR__.'/account-changes-fixture.php';
use Kanboard\Plugin\FamilyHub\Model\NativeAccountTokens;
use Kanboard\Plugin\FamilyHub\Model\NativeAccountMailCrypto;
$account=id(1);$server=sql('SELECT server_id FROM familyhub_instance WHERE id=1')->fetchColumn();
sql('INSERT INTO familyhub_email_identities(account_id,pending_email,revision) VALUES(?,?,1)',[$account,'http@synthetic.invalid']);
$user=sql('SELECT * FROM users WHERE id=1')->fetch(PDO::FETCH_ASSOC);$user['account_id']=$account;$tokens=new NativeAccountTokens(['db'=>$db]);$tokens->issue($user,'verify','http@synthetic.invalid',1,'sl');
$row=sql('SELECT * FROM familyhub_account_tokens WHERE account_id=?',[$account])->fetch(PDO::FETCH_ASSOC);$cipher=sql('SELECT token_cipher FROM familyhub_account_mail WHERE token_id=?',[$row['id']])->fetchColumn();
$data=['token'=>NativeAccountMailCrypto::decrypt($cipher,$tokens->aad($row['id'],$account)),'accountId'=>$account,'serverId'=>$server,'email'=>'http@synthetic.invalid'];
$pdo->exec("VACUUM INTO '/tmp/email-links-http.sqlite'");
$port=random_int(30000,40000);$url='http://127.0.0.1:'.$port.'/index.php?controller=EmailVerificationController&action=confirm&plugin=FamilyHub';
$process=proc_open([PHP_BINARY,'-S','127.0.0.1:'.$port,__DIR__.'/email-verification-link-http-router.php'],[0=>['pipe','r'],1=>['file','/tmp/email-links-server.log','a'],2=>['file','/tmp/email-links-server.log','a']],$pipes);
function request($method='POST',$origin='https://synthetic.invalid',$content='application/json',$body=null){global $url,$data;$h=curl_init($url);$headers=['Content-Type: '.$content];if($origin!==null)$headers[]='Origin: '.$origin;curl_setopt_array($h,[CURLOPT_CUSTOMREQUEST=>$method,CURLOPT_HTTPHEADER=>$headers,CURLOPT_POSTFIELDS=>$body??json_encode($data),CURLOPT_RETURNTRANSFER=>true,CURLOPT_TIMEOUT=>3]);$raw=curl_exec($h);$code=curl_getinfo($h,CURLINFO_HTTP_CODE);curl_close($h);return [$code,json_decode($raw,true)];}
try {
    $ready=false;for($i=0;$i<50;$i++){if($s=@fsockopen('127.0.0.1',$port,$e,$m,.1)){fclose($s);$ready=true;break;}usleep(20000);}if(!$ready)throw new RuntimeException('loopback server unavailable');
    ck(request('POST','https://foreign.invalid')[0]===403,'physical HTTP rejects foreign Origin');
    ck(request('POST',null)[0]===403,'physical HTTP rejects absent Origin');
    ck(request('POST','https://synthetic.invalid','text/plain')[0]===415,'physical HTTP rejects non-JSON POST');
    ck(request('POST','https://synthetic.invalid','application/json',str_repeat('x',2050))[0]===413,'physical HTTP bounds confirmation body');
    [$code,$result]=request();ck($code===200 && $result===['verified'=>true],'physical same-origin explicit JSON POST confirms');
    $confirmed=new PDO('sqlite:/tmp/email-links-http.sqlite');
    ck((int)$confirmed->query('SELECT count(*) FROM familyhub_email_identities WHERE verified_at IS NOT NULL')->fetchColumn()===1,'HTTP confirmation commits exact email identity');
    echo json_encode(['status'=>'pass','checks'=>$checks,'transport'=>'isolated loopback HTTP controller seam','TLS'=>false,'SMTP'=>false]).PHP_EOL;
} finally {proc_terminate($process);foreach($pipes as $p)if(is_resource($p))fclose($p);proc_close($process);}
