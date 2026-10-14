<?php
// Production-only CLI auth probe / explicitly addressed one-time test message.
if (PHP_SAPI !== 'cli') { http_response_code(404); exit; }
ini_set('display_errors', '0'); ini_set('log_errors', '0'); error_reporting(0); umask(0077);
const MAIL_BASE = '/home/tripar13/private/jivie-production';
const MAIL_ROOT = '/home/tripar13/jivie.triparna.si';
const MAIL_WORK = MAIL_BASE.'/install/smtp-20261014';
function mailPrivate($p) {
    if (is_link($p) || !is_file($p) || realpath($p) !== $p || (fileperms($p)&0777)!==0600 || fileowner($p)!==fileowner(MAIL_BASE)) { throw new RuntimeException(); }
}
function mailWriteNew($p, $data) {
    $f=fopen($p,'xb'); if (!$f) { throw new RuntimeException(); }
    try { if (fwrite($f,$data)!==strlen($data) || !fflush($f)) { throw new RuntimeException(); } }
    finally { fclose($f); }
    chmod($p,0600);
}
try {
    $mode=$argv[1]??'';
    if (!in_array($mode,['auth','test'],true) || ($mode==='auth' && $argc!==2) || ($mode==='test' && ($argc!==3 || !filter_var($argv[2],FILTER_VALIDATE_EMAIL)))) { throw new RuntimeException(); }
    foreach ([MAIL_BASE,MAIL_BASE.'/install',MAIL_WORK] as $p) { if (is_link($p) || !is_dir($p) || realpath($p)!==$p || (fileperms($p)&0777)!==0700) { throw new RuntimeException(); } }
    foreach ([MAIL_BASE.'/smtp-password.txt', MAIL_BASE.'/smtp-config.php', MAIL_BASE.'/account-mail.key', MAIL_WORK.'/state.json'] as $p) { mailPrivate($p); }
    $stat=stat(MAIL_BASE.'/smtp-password.txt');
    if ($stat['size']<1 || $stat['size']>4096) { throw new RuntimeException(); }
    $state=json_decode(file_get_contents(MAIL_WORK.'/state.json'),true,32,JSON_THROW_ON_ERROR);
    if (!hash_equals($state['smtpSha'],hash_file('sha256',MAIL_BASE.'/smtp-config.php')) || !hash_equals($state['keySha'],hash_file('sha256',MAIL_BASE.'/account-mail.key'))) { throw new RuntimeException(); }
    require MAIL_ROOT.'/vendor/autoload.php';
    require MAIL_ROOT.'/plugins/FamilyHub/Model/NativeVerifiedSmtp.php';
    require MAIL_BASE.'/smtp-config.php';
    if (FAMILYHUB_SMTP_HOST!=='cp-21.controlpanel.si' || FAMILYHUB_SMTP_PORT!==465 || FAMILYHUB_SMTP_ENCRYPTION!=='ssl' || FAMILYHUB_SMTP_FROM!=='admin@jivie.triparna.si' || FAMILYHUB_SMTP_USERNAME!==FAMILYHUB_SMTP_FROM || FAMILYHUB_SMTP_PASSWORD==='' || strlen(base64_decode(FAMILYHUB_ACCOUNT_MAIL_KEY_BASE64,true))!==32) { throw new RuntimeException(); }
    $transport=new \Kanboard\Plugin\FamilyHub\Model\NativeVerifiedSmtp(FAMILYHUB_SMTP_HOST,465,'ssl');
    $transport->setTimeout(10)->setStreamOptions(['ssl'=>['allow_self_signed'=>false,'verify_peer'=>true,'verify_peer_name'=>true,'peer_name'=>FAMILYHUB_SMTP_HOST]]);
    $transport->setUsername(FAMILYHUB_SMTP_USERNAME)->setPassword(FAMILYHUB_SMTP_PASSWORD);
    try {
        $transport->start();
        if ($mode==='auth') {
            // Integer-second stamp avoids PHP losing filesystem nanoseconds.
            $proof=['authenticated'=>true,'verifiedTls'=>true,'smtpSha'=>$state['smtpSha'],'passwordStamp'=>['device'=>$stat['dev'],'inode'=>$stat['ino'],'size'=>$stat['size'],'modified'=>$stat['mtime']]];
            mailWriteNew(MAIL_WORK.'/auth-proof.json',json_encode($proof,JSON_PRETTY_PRINT|JSON_THROW_ON_ERROR)."\n");
            echo "{\"authenticated\":true,\"verifiedTls\":true,\"noMessagesSent\":true}\n";
        } else {
            if ($state['phase']!=='active') { throw new RuntimeException(); }
            // Claim before SMTP: an ambiguous acceptance must never auto-resend.
            mailWriteNew(MAIL_WORK.'/test-message-started.json',json_encode(['started'=>true,'recipient'=>$argv[2]],JSON_THROW_ON_ERROR)."\n");
            $message=new \Swift_Message('Jivie: preizkus pošiljanja e-pošte');
            $message->setId('jivie.smtp.test.20261014@jivie.triparna.si');
            $message->setFrom([FAMILYHUB_SMTP_FROM=>'Jivie'])->setTo([$argv[2]])->setBody("To je dogovorjeni preizkus pošte s produkcijskega strežnika Jivie.\nPošta za povabila in potrditev naslova je nastavljena.\nTo sporočilo ne vsebuje povabila ali prijavnih podatkov.\n",'text/plain','UTF-8');
            if ((new \Swift_Mailer($transport))->send($message)!==1) { throw new RuntimeException(); }
            mailWriteNew(MAIL_WORK.'/test-message-accepted.json',"{\"smtpAccepted\":true}\n");
            echo "{\"smtpAccepted\":true,\"messagesSent\":1}\n";
        }
    } finally { try { $transport->stop(); } catch (Throwable $ignored) {} }
} catch (Throwable $ignored) {
    fwrite(STDERR,"Mail probe failed; secrets and exception details suppressed. No automatic retry.\n"); exit(1);
}
