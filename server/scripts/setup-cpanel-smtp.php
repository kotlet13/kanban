<?php
// CLI-only optional SMTP setup for the fresh Jivie test server. No messages sent.
// --check is read-only. --prepare creates private key/config but keeps SMTP off.
// PHP-lint both candidates, then --activate explicitly adds the SMTP require.
if (PHP_SAPI!=='cli') { http_response_code(404);exit; }
ini_set('display_errors','0');ini_set('log_errors','0');error_reporting(0);umask(0077);
final class SmtpSetupGuard extends RuntimeException {}
function stop(string $code): never { throw new SmtpSetupGuard($code); }
set_error_handler(static function(): never { stop('filesystem_or_php_warning'); });
const BASE='/home/tripar13/private/jivie-test';
const WORK=BASE.'/install/smtp-setup';
const PASSWORD=BASE.'/smtp-password.txt';
const KEY=BASE.'/account-mail.key';
const CONFIG=BASE.'/smtp-config.php';
const FEATURES=BASE.'/familyhub-config.php';
const CANDIDATE=WORK.'/familyhub-config.candidate.php';
const STATE=WORK.'/state.json';
const EXPECTED_FEATURE_SHA='8b95f016af472cf681ceba92978ac959df9d945bfb810926567990ee4977f797';
function readPrivate(string $p): string {
    if (is_link($p) || !is_file($p) || (fileperms($p)&0077)!==0) stop('private_file_guard');
    $text=file_get_contents($p);if ($text===false) stop('private_read_failed');return $text;
}
function createPrivate(string $p,string $text): void {
    $f=fopen($p,'xb');if ($f===false) stop('exclusive_create_failed');
    try { if(fwrite($f,$text)!==strlen($text) || !fflush($f)) stop('private_write_failed'); }
    finally { fclose($f); }chmod($p,0600);
}
function directory(string $p): void {
    if (is_link($p) || !is_dir($p) || realpath($p)!==$p || (fileperms($p)&0077)!==0) stop('private_directory_guard');
}
function parse(string $text): void {
    if (!function_exists('token_get_all')) stop('tokenizer_required');
    token_get_all($text,TOKEN_PARSE);
}
function passwordMetadata(): array {
    // Deliberately never read, hash, return or print the mailbox password.
    if (is_link(PASSWORD) || !is_file(PASSWORD) || !is_readable(PASSWORD) || (fileperms(PASSWORD)&0077)!==0 || fileowner(PASSWORD)!==fileowner(BASE)) stop('password_file_permissions_or_owner');
    $size=filesize(PASSWORD);if ($size<1 || $size>4096) stop('password_file_empty_or_too_large');
    return ['inode'=>fileinode(PASSWORD),'size'=>$size,'modified'=>filemtime(PASSWORD)];
}
try {
    if ($argc!==2 || !in_array($argv[1],['--check','--prepare','--activate'],true)) stop('usage_check_prepare_activate');
    directory('/home/tripar13/private');directory(BASE);directory(BASE.'/install');
    if (!extension_loaded('openssl')) stop('openssl_required');
    $passwordStamp=passwordMetadata();
    if (file_exists(STATE)) {
        directory(WORK);$state=json_decode(readPrivate(STATE),true,32,JSON_THROW_ON_ERROR);
        if (!is_array($state) || ($state['version']??null)!==1) stop('state_invalid');
        if (hash('sha256',readPrivate(CONFIG))!==$state['smtpConfigSha256'] || hash('sha256',readPrivate(KEY))!==$state['keySha256']) stop('prepared_private_config_changed');
        if (($state['phase']??'')==='activated') {
            if (hash('sha256',readPrivate(FEATURES))!==$state['candidateSha256']) stop('activated_feature_config_changed');
            echo "Already activated. Password contents unread; no mail sent.\n";exit(0);
        }
        if (($state['phase']??'')!=='prepared' || hash('sha256',readPrivate(FEATURES))!==EXPECTED_FEATURE_SHA || hash('sha256',readPrivate(CANDIDATE))!==$state['candidateSha256'] || $passwordStamp!==$state['passwordMetadata']) stop('prepared_state_or_password_metadata_changed');
        parse(readPrivate(CONFIG));parse(readPrivate(CANDIDATE));
        if ($argv[1]!=='--activate') {echo "Already prepared; SMTP remains off. Lint candidates before activation.\n";exit(0);}
        if (!rename(CANDIDATE,FEATURES)) stop('feature_activation_failed');chmod(FEATURES,0600);
        $state['phase']='activated';createPrivate(STATE.'.activated',json_encode($state,JSON_PRETTY_PRINT|JSON_THROW_ON_ERROR)."\n");
        if (!rename(STATE.'.activated',STATE)) stop('activated_state_write_failed');
        echo "Optional SMTP configuration activated. No account or message created; actual delivery untested.\n";exit(0);
    }
    if ($argv[1]==='--activate') stop('prepare_required');
    $features=readPrivate(FEATURES);parse($features);
    if (hash('sha256',$features)!==EXPECTED_FEATURE_SHA) stop('fresh_feature_config_requires_review');
    foreach([WORK,KEY,CONFIG] as $path) if (file_exists($path) || is_link($path)) stop('unowned_destination_exists');
    if ($argv[1]==='--check') {echo "Checks passed: private password file is non-empty and protected; contents unread. No changes or mail.\n";exit(0);}
    $smtp=<<<'PHP'
<?php
// Private SMTP configuration for jivie-test.triparna.si only.
// A trailing editor newline is removed; never print these loaded values.
define('FAMILYHUB_SMTP_HOST', 'mail.triparna.si');
define('FAMILYHUB_SMTP_PORT', 465);
define('FAMILYHUB_SMTP_ENCRYPTION', 'ssl');
define('FAMILYHUB_SMTP_FROM', 'jivie-test@triparna.si');
define('FAMILYHUB_SMTP_USERNAME', 'jivie-test@triparna.si');
define('FAMILYHUB_SMTP_PASSWORD', rtrim(file_get_contents('/home/tripar13/private/jivie-test/smtp-password.txt'), "\r\n"));
define('FAMILYHUB_ACCOUNT_MAIL_KEY_BASE64', trim(file_get_contents('/home/tripar13/private/jivie-test/account-mail.key')));
PHP;
    $smtp.="\n";$candidate=$features."\nrequire '".CONFIG."';\n";parse($smtp);parse($candidate);
    if (!mkdir(WORK,0700)) stop('mkdir_failed');chmod(WORK,0700);
    createPrivate(WORK.'/familyhub-config.before.php',$features);
    // Generated only when this helper runs on the intended server, after check.
    $key=base64_encode(random_bytes(32))."\n";createPrivate(KEY,$key);
    createPrivate(CONFIG,$smtp);createPrivate(CANDIDATE,$candidate);
    $state=['version'=>1,'phase'=>'prepared','passwordMetadata'=>$passwordStamp,'smtpConfigSha256'=>hash('sha256',$smtp),'candidateSha256'=>hash('sha256',$candidate),'keySha256'=>hash('sha256',$key)];
    createPrivate(STATE,json_encode($state,JSON_PRETTY_PRINT|JSON_THROW_ON_ERROR)."\n");
    echo "Prepared private account-mail key and SMTP candidates; SMTP remains off. Lint before explicit activation. No password read or mail sent.\n";
} catch (SmtpSetupGuard $e) {
    fwrite(STDERR,"SMTP setup stopped: ".$e->getMessage().". No password or key printed.\n");exit(1);
} catch (Throwable $e) {
    fwrite(STDERR,"SMTP setup stopped: parser_or_internal_failure. No exception, password or key printed.\n");exit(1);
}
