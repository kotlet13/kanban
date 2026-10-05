<?php
require '/var/www/app/app/common.php';
$uid = $container['userModel']->create(array('username' => 'default_policy_test', 'password' => bin2hex(random_bytes(24)), 'role' => 'app-user'));
$container['userSession']->initialize($container['userModel']->getById($uid));
$service = new Kanboard\Plugin\FamilyHub\Model\InvitationService($container);
$capabilities = $service->capabilities();
if ($capabilities['features']['project_invitations'] !== false || $capabilities['features']['finance_acl'] !== false) {
    throw new RuntimeException('Unsafe default capabilities');
}
try {
    $service->create(1, 'other', 'default_policy_request');
    throw new RuntimeException('Unsafe default invitation access');
} catch (JsonRPC\Exception\AccessDeniedException $expected) {
    echo "PASS: packaged plugin defaults to disabled invitations; finance ACL is not claimed.\n";
}
$native = new Kanboard\Plugin\FamilyHub\Model\NativeService($container);
if (Kanboard\Plugin\FamilyHub\Controller\NativeApiController::secureTransport(['REMOTE_ADDR' => '192.0.2.1', 'HTTP_X_FORWARDED_PROTO' => 'https']) !== false ||
        Kanboard\Plugin\FamilyHub\Controller\NativeApiController::secureTransport(['HTTPS' => 'on']) !== true) {
    throw new RuntimeException('Untrusted proxy can claim HTTPS');
}
echo "PASS: native HTTPS check rejects untrusted forwarded protocol.\n";
if ($native->dispatch('capabilities', [], '', '127.0.0.1')['enabled'] !== false) {
    throw new RuntimeException('Unsafe native default');
}
$defaultCapabilities = $native->dispatch('capabilities', [], '', '127.0.0.1');
foreach (['collaboration', 'inbox', 'scheduledReminders', 'finance', 'smtp', 'externalPush', 'privateSync', 'personalFinanceEntry', 'accountEnrollment', 'emailVerification', 'passwordReset'] as $feature) {
    if ($defaultCapabilities['features'][$feature] !== false) { throw new RuntimeException('Unsafe default module capability'); }
}
echo "PASS: collaboration/finance/inbox/reminders/SMTP/push defaults disabled.\n";
if ($defaultCapabilities['pushProjectId'] !== null || Kanboard\Plugin\FamilyHub\Model\NativeFcmConfig::configured()) { throw new RuntimeException('Unconfigured provider claims push readiness'); }
echo "PASS: unconfigured FCM has no public project and cannot claim readiness.\n";
try {
    $native->dispatch('auth.login', ['username' => 'unused', 'password' => 'unused', 'deviceName' => 'unused'], '', '127.0.0.1');
    throw new RuntimeException('Unsafe native authentication access');
} catch (Kanboard\Plugin\FamilyHub\Model\NativeError $expected) {
    if ($expected->errorCode !== 'feature_disabled') { throw $expected; }
    echo "PASS: packaged plugin native account/sync API defaults to disabled.\n";
}
try {
    $native->dispatch('sync.pull', ['scopeId' => 'irrelevant', 'cursor' => 0], '', '127.0.0.1');
    throw new RuntimeException('Unsafe native sync access');
} catch (Kanboard\Plugin\FamilyHub\Model\NativeError $expected) {
    if ($expected->errorCode !== 'feature_disabled') { throw $expected; }
    echo "PASS: packaged plugin native sync cannot be accessed without explicit enable.\n";
}

try {
    $native->dispatch('finance.pull', ['scopeId' => 'irrelevant', 'cursor' => 0], '', '127.0.0.1');
    throw new RuntimeException('Unsafe default financial access');
} catch (Kanboard\Plugin\FamilyHub\Model\NativeError $expected) {
    if ($expected->errorCode !== 'feature_disabled') { throw $expected; }
    echo "PASS: default plugin financial reads cannot bypass explicit enable.\n";
}
try {
    $native->dispatch('push.register', ['token'=>'unused','platform'=>'ios','language'=>'sl'], '', '127.0.0.1');
    throw new RuntimeException('Unsafe default push registration');
} catch (Kanboard\Plugin\FamilyHub\Model\NativeError $expected) {
    if ($expected->errorCode !== 'feature_disabled') { throw $expected; }
    echo "PASS: push registration cannot implicitly enable native/provider features.\n";
}

foreach (['auth.enroll', 'account.email.request', 'personal.ensure'] as $op) {
    try { $native->dispatch($op, [], '', '127.0.0.1'); throw new RuntimeException('Unsafe default account/private operation'); }
    catch (Kanboard\Plugin\FamilyHub\Model\NativeError $expected) {
        if ($expected->errorCode !== 'feature_disabled') { throw $expected; }
        echo "PASS: packaged plugin blocks ".$op." without explicit native enable.\n";
    }
}
