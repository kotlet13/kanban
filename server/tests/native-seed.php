<?php
// Local-only synthetic browser QA. Redirect stdout to a PRIVATE mode-0600 file.
require '/var/www/app/app/common.php';
if (!defined('FAMILYHUB_DEVELOPMENT_MODE') || FAMILYHUB_DEVELOPMENT_MODE !== true ||
        !defined('FAMILYHUB_ENABLE_NATIVE_API') || FAMILYHUB_ENABLE_NATIVE_API !== true) {
    throw new RuntimeException('Synthetic fixture requires explicit isolated development mode');
}
$options = getopt('', ['server:']);
$server = $options['server'] ?? 'http://127.0.0.1:18380';
if (!preg_match('~^http://127\.0\.0\.1:(18380|18381|18382)$~D', $server)) {
    throw new RuntimeException('Synthetic fixture server must be an explicit local QA endpoint');
}
$prefix = 'qa_'.bin2hex(random_bytes(4));
$password = bin2hex(random_bytes(12));
$owner = $prefix.'_owner'; $recipient = $prefix.'_recipient'; $totp = $prefix.'_totp';
$secret = \Otp\GoogleAuthenticator::generateRandom();
foreach ([$owner, $totp] as $username) {
    $id = $container['userModel']->create(['username' => $username, 'password' => $password, 'name' => 'Synthetic QA', 'role' => 'app-user']);
    if (!$id) { throw new RuntimeException('Synthetic fixture creation failed'); }
    if ($username === $totp) {
        $container['db']->table('users')->eq('id', $id)->update(['twofactor_activated' => 1, 'twofactor_secret' => $secret]);
    }
}
echo json_encode(['synthetic' => true, 'server' => $server, 'owner' => ['username' => $owner, 'password' => $password],
                 'recipient' => ['username' => $recipient, 'password' => $password], 'totp' => ['username' => $totp, 'password' => $password, 'secret' => $secret]], JSON_PRETTY_PRINT | JSON_THROW_ON_ERROR).PHP_EOL;
