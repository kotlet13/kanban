<?php
/** Public capability advertisement only; explicitly opted-in disposable SQLite. */
umask(0077);
$mode = getenv('JIVIE_INVITATION_CAPABILITIES_MODE');
if (getenv('JIVIE_INVITATION_CAPABILITIES_FIXTURE') !== 'fresh-sqlite'
    || !in_array($mode, ['ready', 'disabled'], true)) {
    throw new RuntimeException('Explicit disposable fixture opt-in required');
}
require '/var/www/app/app/common.php';
if (session_status() === PHP_SESSION_ACTIVE) { session_abort(); }

use Kanboard\Plugin\FamilyHub\Model\NativeCryptoService;
use Kanboard\Plugin\FamilyHub\Model\NativeService;

$pdo = $container['db']->getConnection();
if (!defined('FAMILYHUB_DEVELOPMENT_MODE') || FAMILYHUB_DEVELOPMENT_MODE !== true
    || $pdo->getAttribute(PDO::ATTR_DRIVER_NAME) !== 'sqlite'
    || (int)$pdo->query('SELECT COUNT(*) FROM familyhub_accounts')->fetchColumn() !== 0
    || (int)$pdo->query('SELECT COUNT(*) FROM familyhub_scopes')->fetchColumn() !== 0) {
    throw new RuntimeException('Fresh opted-in synthetic SQLite fixture required');
}
set_error_handler(static function ($severity, $message, $file, $line) {
    throw new ErrorException($message, 0, $severity, $file, $line);
});
$checks = 0;
function checkInvitationCapabilities($value, $label) {
    global $checks;
    if (!$value) { throw new RuntimeException('FAIL: '.$label); }
    $checks++;
    echo 'PASS: '.$label.PHP_EOL;
}
checkInvitationCapabilities(NativeCryptoService::enabled($pdo) === ($mode === 'ready'), 'actual crypto readiness matches fixture mode');
ob_start();
try {
    $caps = (new NativeService($container))->dispatch('capabilities', [], '', 'synthetic-capabilities');
    $clean = ob_get_contents() === '';
} finally { ob_end_clean(); }
$wire = json_decode(json_encode($caps, JSON_THROW_ON_ERROR), true, 32, JSON_THROW_ON_ERROR);
checkInvitationCapabilities($clean && $wire['enabled'] === true && $wire['api'] === 'familyhub_native', 'real anonymous dispatch returns clean public capabilities');
checkInvitationCapabilities($wire['invitationContractVersions'] === ($mode === 'ready' ? [1, 2, 3, 4] : [1, 2, 3]), $mode === 'ready' ? 'ready crypto advertises implemented invitation v4' : 'unavailable crypto preserves legacy invitation contracts');
echo 'Invitation capabilities '.$mode.': '.$checks.' checks PASS'.PHP_EOL;
