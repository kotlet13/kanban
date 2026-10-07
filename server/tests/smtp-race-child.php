<?php
// Isolated synthetic mutation; fixture secrets never appear in argv or output.
if (PHP_SAPI !== 'cli') { exit(2); }
$fixture = json_decode(file_get_contents($argv[1]), true, 16, JSON_THROW_ON_ERROR);
if ($fixture['action'] === 'deliveryCrash') {
    define('FAMILYHUB_SMTP_HOST', '127.0.0.1'); define('FAMILYHUB_SMTP_PORT', $fixture['port']);
    define('FAMILYHUB_SMTP_ENCRYPTION', 'none'); define('FAMILYHUB_SMTP_ALLOW_LOCAL_PLAINTEXT', true);
    define('FAMILYHUB_SMTP_FROM', 'sender@capture.invalid');
}
require '/var/www/app/app/common.php';
if (!defined('FAMILYHUB_DEVELOPMENT_MODE') || FAMILYHUB_DEVELOPMENT_MODE !== true) { exit(2); }
if (session_status() === PHP_SESSION_ACTIVE) { session_abort(); }
echo "ready\n"; flush();
if (trim(fgets(STDIN)) !== 'go') { exit(2); }
echo "attempting\n"; flush();
try {
    $owner = 'Bearer '.$fixture['ownerToken'];
    $recipient = 'Bearer '.$fixture['recipientToken'];
    $scope = $fixture['scope'];
    switch ($fixture['action']) {
        case 'deliveryCrash':
            $transport = new class extends \Kanboard\Plugin\FamilyHub\Model\NativeSmtpTransport {
                public function send($recipient, $inboxId, $accountId) {
                    parent::send($recipient, $inboxId, $accountId);
                    exit(73); // Actual process death after provider ACK, before DB ACK.
                }
            };
            (new \Kanboard\Plugin\FamilyHub\Model\NativeDeliveryService($container))->run(1, $transport);
            throw new RuntimeException();
        case 'email':
            // Core SQL does not acquire the Native global/scope mutex.
            if (!$container['userModel']->update(['id' => $fixture['userId'], 'email' => 'new@capture.invalid'])) { throw new RuntimeException(); }
            break;
        case 'deactivate':
            if (!$container['userModel']->update(['id' => $fixture['userId'], 'is_active' => 0])) { throw new RuntimeException(); }
            break;
        case 'membership':
            (new \Kanboard\Plugin\FamilyHub\Model\NativeScopeService($container, $owner, $fixture['ip']))->execute('scopes.removeMember', ['scopeId' => $scope, 'userId' => $fixture['userId'], 'requestId' => $fixture['requestId']]);
            break;
        case 'finance':
            (new \Kanboard\Plugin\FamilyHub\Model\NativeFinanceService($container, $owner, $fixture['ip']))->execute('finance.grant', ['scopeId' => $scope, 'accountId' => $fixture['accountId'], 'grant' => 'none', 'requestId' => $fixture['requestId']]);
            break;
        case 'preference':
            (new \Kanboard\Plugin\FamilyHub\Model\NativeInboxService($container, $recipient, $fixture['ip']))->execute('inbox.preferences.set', ['scopeId' => $scope, 'category' => 'tasks', 'settings' => ['inApp' => true, 'sound' => false, 'push' => false, 'email' => false], 'requestId' => $fixture['requestId']]);
            break;
        case 'deletion':
            $service = new \Kanboard\Plugin\FamilyHub\Model\NativeAccountDeletionService($container, $recipient, $fixture['ip']);
            $preview = $service->execute('account.deletion.preview', []);
            $result = $service->execute('account.deletion.confirm', ['operationId' => $fixture['requestId'], 'receiptToken' => bin2hex(random_bytes(32)), 'previewHash' => $preview['previewHash'], 'password' => $fixture['password'], 'confirmation' => 'DELETE']);
            if (!$result['deleted']) { throw new RuntimeException(); }
            break;
        default: throw new RuntimeException();
    }
    echo "done\n"; flush();
} catch (\Throwable $ignored) { fwrite(STDERR, "Synthetic SMTP mutation failed\n"); exit(1); }
