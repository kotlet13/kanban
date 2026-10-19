<?php
// Isolated source-only fixture: no database, account, network, or host config.
namespace Kanboard\Plugin\FamilyHub\Model { abstract class NativeDatabase {} }
namespace {
require __DIR__.'/../plugins/FamilyHub/Model/NativeService.php';
use Kanboard\Plugin\FamilyHub\Model\NativeService;
function check($ok, $message) {
    if (!$ok) { throw new RuntimeException($message); }
    echo "PASS: $message\n";
}
$mode = $argv[1] ?? 'missing';
define('MAIL_SMTP_PASSWORD', 'private-smtp-sentinel');
define('FAMILYHUB_CRYPTO_PRIVATE_KEY', 'private-key-sentinel');
if ($mode === 'public') {
    define('FAMILYHUB_HOSTING_OPERATOR_NAME', ' Synthetic Hosting ');
    define('FAMILYHUB_HOSTING_OPERATOR_CONTACT', 'host@example.test');
} elseif ($mode === 'invalid') {
    define('FAMILYHUB_HOSTING_OPERATOR_NAME', "spoof\u{202e}host");
    define('FAMILYHUB_HOSTING_OPERATOR_CONTACT', str_repeat('a', 301));
} elseif ($mode === 'wrong-types') {
    define('FAMILYHUB_HOSTING_OPERATOR_NAME', ['secret' => 'not-public']);
    define('FAMILYHUB_HOSTING_OPERATOR_CONTACT', true);
}
$reply = NativeService::hostingInformation();
check(is_object($reply), 'public information is an object even when empty');
if ($mode === 'public') {
    check((array)$reply === ['operatorName'=>'Synthetic Hosting','operatorContact'=>'host@example.test'], 'only explicit public fields are trimmed and returned');
} else {
    check((array)$reply === [], 'missing or malformed operator metadata stays absent');
}
check(strpos(json_encode($reply), 'sentinel') === false, 'unrelated private configuration is never disclosed');
}
