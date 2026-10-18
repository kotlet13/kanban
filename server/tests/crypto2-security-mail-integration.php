<?php
// No SMTP connection: these constants only enable the supported email-request path.
define('FAMILYHUB_ACCOUNT_MAIL_KEY_BASE64',base64_encode(random_bytes(32)));
define('FAMILYHUB_SMTP_HOST','127.0.0.1');define('FAMILYHUB_SMTP_PORT',39999);
define('FAMILYHUB_SMTP_ENCRYPTION','none');define('FAMILYHUB_SMTP_ALLOW_LOCAL_PLAINTEXT',true);
define('FAMILYHUB_SMTP_FROM','sender@capture.invalid');define('FAMILYHUB_PUBLIC_URL','http://127.0.0.1:18785');
require __DIR__.'/crypto2-integration.php';
use Kanboard\Plugin\FamilyHub\Model\NativeAccountMailTransport;
use Kanboard\Plugin\FamilyHub\Model\NativeSecurityMailQueue;
$before=q('SELECT kind,COUNT(*) AS n FROM familyhub_crypto_security_events WHERE account_id=? GROUP BY kind',[$fresh['user']['accountId']]);
ck(count(array_filter($before,fn($r)=>$r['kind']==='crypto.recoveryStarted'&&(int)$r['n']===1))===1&&count(array_filter($before,fn($r)=>$r['kind']==='crypto.recoveryCompleted'&&(int)$r['n']===1))===1,'v2 recoverEpoch exact replay queues one start and one completion notice');
q('UPDATE users SET language=? WHERE id=?',['en',$fresh['user']['id']]);
$transport=new class {public $messages=[];public function send($email,$purpose,$code,$id,$language,$details){[$title,$body]=NativeAccountMailTransport::securityMessage($details['eventKind'],$language);$this->messages[]=['email'=>$email,'purpose'=>$purpose,'code'=>$code,'language'=>$language,'kind'=>$details['eventKind'],'title'=>$title,'body'=>$body];return ['accepted'=>true];}};
$queue=new NativeSecurityMailQueue($container);$result=['sent'=>0];for($pass=0;$pass<100;$pass++){ $next=$queue->run(50,$transport);$result['sent']+=$next['sent'];if(array_sum($next)<50)break; }$own=array_values(array_filter($transport->messages,fn($m)=>$m['kind']==='crypto.recoveryCompleted'&&$m['language']==='en'));
ck($result['sent']>=1&&count($own)>=1&&str_contains($own[0]['body'],'Account access recovery has completed.'),'v2 recovery notice reaches captured transport in stored account language with translated event type');
ck(array_reduce($transport->messages,fn($ok,$m)=>$ok&&$m['purpose']==='security'&&$m['code']===''&&!str_contains($m['body'],'commandBase64')&&!str_contains($m['body'],'sealedEnvelopeBase64'),true),'captured notices contain fixed generic text and no recovery material');
$again=$queue->run(50,$transport);ck($again['sent']===0,'drained v2 notice queue does not send a second notification');
[$title,$body]=NativeAccountMailTransport::securityMessage('auth.resetRequested','');ck(str_contains($body,'Zahtevana je bila ponastavitev')&&str_contains($body,'A login password reset was requested.'),'missing locale uses explicit bilingual notice with concrete event in both languages');
$identity=q('SELECT * FROM familyhub_email_identities WHERE account_id=?',[$fresh['user']['accountId']])[0];
function securityEvent2($account,$identity,$age=0,$attempts=0){$id=uid();q('INSERT INTO familyhub_crypto_security_events VALUES(?,?,?,?,?,?,?,?,?)',[$id,$account,'crypto.recoveryCompleted',$identity['email'],(int)$identity['revision'],'pending',$attempts,time()-1,time()-$age]);return $id;}
// Retry tests use only an in-memory throwing transport; no SMTP connection.
$retryId=securityEvent2($fresh['user']['accountId'],$identity);
$failure=new class { public $calls=0;public function send(...$args){$this->calls++;throw new RuntimeException('Synthetic unavailable transport');}};
$failed=$queue->run(50,$failure);$retryRow=q('SELECT * FROM familyhub_crypto_security_events WHERE id=?',[$retryId])[0];
ck($failed['retry']===1&&$failure->calls===1&&(int)$retryRow['attempts']===1&&$retryRow['state']==='retry'&&(int)$retryRow['next_attempt']>time(),'transport failure schedules bounded due retry without marking delivered');
ck($queue->run(50,$failure)['retry']===0&&$failure->calls===1,'not-yet-due retry is not sent again');
q('UPDATE familyhub_crypto_security_events SET next_attempt=? WHERE id=?',[time()-1,$retryId]);$sentBefore=count($transport->messages);
ck($queue->run(50,$transport)['sent']===1&&count($transport->messages)===$sentBefore+1,'due retry can succeed with captured transport');
$changed=securityEvent2($fresh['user']['accountId'],$identity);$sentBefore=count($transport->messages);
call('account.email.request',['email'=>$prefix.'_replacement@capture.invalid','language'=>'en','password'=>$alice['password']],$fresh);
$changedIdentity=q('SELECT * FROM familyhub_email_identities WHERE account_id=?',[$fresh['user']['accountId']])[0];
ck((int)$changedIdentity['revision']>(int)$identity['revision']&&$changedIdentity['pending_email']!==null,'supported email-change request advances revision before confirmation');
ck($queue->run(50,$transport)['sent']===1&&count($transport->messages)===$sentBefore+1&&end($transport->messages)['email']===$identity['email']&&end($transport->messages)['code']==='','email-change request cannot suppress generic recovery notice to original verified address');
$unknown=securityEvent2($fresh['user']['accountId'],$identity);q('UPDATE familyhub_crypto_security_events SET kind=? WHERE id=?',['unknown.event',$unknown]);$sentBefore=count($transport->messages);
ck($queue->run(50,$transport)['cancelled']===1&&count($transport->messages)===$sentBefore,'unknown security event kind never reaches transport');
$identity=q('SELECT * FROM familyhub_email_identities WHERE account_id=?',[$fresh['user']['accountId']])[0];
$expired=securityEvent2($fresh['user']['accountId'],$identity,86401);$ceiling=securityEvent2($fresh['user']['accountId'],$identity,0,5);$sentBefore=count($transport->messages);
ck($queue->run(50,$transport)['cancelled']===2&&count($transport->messages)===$sentBefore,'expired and attempt-ceiling events cancel without calling transport');
echo 'Crypto2 security mail integration: '.$checks.' checks PASS'.PHP_EOL;
