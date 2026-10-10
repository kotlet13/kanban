<?php
// Fixture contains synthetic secrets. Only a private path is passed in argv.
$fixture = json_decode(file_get_contents($argv[1]), true, 32, JSON_THROW_ON_ERROR);
if (isset($fixture['mailKey'])) {
    define('FAMILYHUB_ACCOUNT_MAIL_KEY_BASE64', $fixture['mailKey']);
    define('FAMILYHUB_SMTP_HOST', '127.0.0.1'); define('FAMILYHUB_SMTP_FROM', 'sender@capture.invalid');
}
require '/var/www/app/app/common.php';
if (session_status() === PHP_SESSION_ACTIVE) { session_abort(); }
if (!defined('FAMILYHUB_DEVELOPMENT_MODE') || FAMILYHUB_DEVELOPMENT_MODE !== true) { exit(2); }
echo "ready\n"; flush();
if (trim(fgets(STDIN)) !== 'go') { exit(2); }
try {
    if ($fixture['operation']==='test.invitationMail') {
        $transport=new class { public function send($a,$b,$c,$d,$e,$f=[]) { usleep(200000); return ['accepted'=>true]; } };
        $result=(new \Kanboard\Plugin\FamilyHub\Model\NativeInvitationMailQueue($container))->run(1,$transport);
    } else {
    $result = (new \Kanboard\Plugin\FamilyHub\Model\NativeService($container))->dispatch($fixture['operation'], $fixture['params'], $fixture['bearer'] ?? '', $fixture['ip']);
    }
    echo json_encode(['mailCounts'=>$fixture['operation']==='test.invitationMail'?$result:null, 'ok' => true, 'scopeId' => $result['scope']['id'] ?? null, 'accountId' => $result['user']['accountId'] ?? null], JSON_THROW_ON_ERROR).PHP_EOL;
} catch (\Kanboard\Plugin\FamilyHub\Model\NativeError $error) { echo json_encode(['ok' => false, 'error' => $error->errorCode], JSON_THROW_ON_ERROR).PHP_EOL; }

catch (\Throwable $error) { echo json_encode(['ok'=>false,'errorClass'=>get_class($error),'errorCode'=>(string)$error->getCode()],JSON_THROW_ON_ERROR).PHP_EOL; }
