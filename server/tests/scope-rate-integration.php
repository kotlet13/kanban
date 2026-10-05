<?php
// Real durable budgets, unique synthetic identities/IP keys, no counter resets.
require '/var/www/app/app/common.php';
use Kanboard\Plugin\FamilyHub\Model\NativeAuthService;
use Kanboard\Plugin\FamilyHub\Model\NativeScopeService;
use Kanboard\Plugin\FamilyHub\Model\NativeError;
if (!defined('FAMILYHUB_DEVELOPMENT_MODE') || FAMILYHUB_DEVELOPMENT_MODE !== true) {
    throw new RuntimeException('Isolated synthetic development only');
}
$checks = 0;
function check($condition, $description) {
    global $checks;
    if (!$condition) { throw new RuntimeException('FAIL: '.$description); }
    $checks++; echo 'PASS: '.$description.PHP_EOL;
}
function rejects($service, $operation, $code) {
    try { $service->execute($operation, []); }
    catch (NativeError $error) { return $error->getMessage() === $code; }
    return false;
}
$prefix = 'scope_rate_'.bin2hex(random_bytes(6));
$ip = $prefix.'_nat'; $password = bin2hex(random_bytes(12)); $sessions = [];
for ($i = 0; $i < 2; $i++) {
    $name = $prefix.'_'.$i;
    check($container['userModel']->create(['username'=>$name,'password'=>$password,'role'=>'app-user']) > 0, 'synthetic ordinary account '.$i);
    $sessions[] = (new NativeAuthService($container, '', $ip))->execute('auth.login', ['username'=>$name,'password'=>$password,'deviceName'=>'Rate fixture']);
}
$first = new NativeScopeService($container, 'Bearer '.$sessions[0]['token'], $ip);
$second = new NativeScopeService($container, 'Bearer '.$sessions[1]['token'], $ip);
$pdo = $container['db']->getConnection();
$start = microtime(true);
for ($i = 0; $i < 600; $i++) {
    $result = $first->execute('scopes.list', []);
    if ($result['scopes'] !== []) { throw new RuntimeException('Unexpected synthetic scope data'); }
}
check(microtime(true)-$start < 60, '600 real reads fit one budget window');
check(rejects($first, 'scopes.list', 'rate_limited'), '601st account read denied');
check($second->execute('scopes.list', [])['scopes'] === [], 'other person behind same NAT keeps independent read budget');
$otherIp = new NativeScopeService($container, 'Bearer '.$sessions[0]['token'], $prefix.'_other_ip');
check(rejects($otherIp, 'scopes.list', 'rate_limited'), 'changing IP does not evade account budget');
for ($i = 0; $i < 120; $i++) {
    if (!rejects($second, 'scopes.unsupported', 'unsupported_operation')) { throw new RuntimeException('Unexpected mutation budget response'); }
}
check(rejects($second, 'scopes.unsupported', 'rate_limited'), '121st mutation still denied independently of polling reads');
$unauthenticated = new NativeScopeService($container, '', $prefix.'_untrusted_ip');
$start = microtime(true);
for ($i = 0; $i < 2400; $i++) {
    if (!rejects($unauthenticated, 'scopes.list', 'auth_required')) { throw new RuntimeException('Unexpected IP envelope response'); }
}
check(microtime(true)-$start < 60, '2400 unauthenticated reads fit one budget window');
check(rejects($unauthenticated, 'scopes.list', 'rate_limited'), 'IP abuse envelope applies before authentication');
check($second->execute('scopes.list', [])['scopes'] === [], 'exhausted mutation bucket does not block authorized reads');
echo 'SUCCESS '.$checks.' scope rate checks ('.$pdo->getAttribute(PDO::ATTR_DRIVER_NAME).')'.PHP_EOL;
