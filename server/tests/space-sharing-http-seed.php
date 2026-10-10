<?php
// Run only in a fresh, isolated compose.account-tests fixture. No credentials on stdout.
umask(0077);
require '/var/www/app/app/common.php';
if (session_status() === PHP_SESSION_ACTIVE) { session_abort(); }
if (!defined('FAMILYHUB_DEVELOPMENT_MODE') || FAMILYHUB_DEVELOPMENT_MODE !== true) {
    throw new RuntimeException('Synthetic development fixture required');
}
$port = (int)($argv[1] ?? 18384);
if (!in_array($port, [18383, 18384], true)) { throw new RuntimeException('Dedicated loopback port required'); }
$url = 'http://127.0.0.1:'.$port;
$container['configModel']->save(['application_url'=>$url]);
$service = new \Kanboard\Plugin\FamilyHub\Model\NativeService($container);
$pdo = $container['db']->getConnection();
$fixture = ['synthetic'=>true, 'server'=>$url];
$prefix = 'sharing_http_'.bin2hex(random_bytes(5));
foreach (['owner', 'member', 'projectMember'] as $kind) {
    $name = $prefix.'_'.$kind;
    $password = bin2hex(random_bytes(20));
    $email = strtolower($name).'@capture.invalid';
    $container['userModel']->create(['username'=>$name, 'password'=>$password, 'email'=>$email, 'role'=>'app-user']);
    $session = $service->dispatch('auth.login', ['username'=>$name, 'password'=>$password, 'deviceName'=>'Synthetic HTTP fixture'], '', 'sharing-seed-'.bin2hex(random_bytes(8)));
    $query = $pdo->prepare('INSERT INTO familyhub_email_identities(account_id,email,verified_at,revision) VALUES(?,?,?,1)');
    $query->execute([$session['user']['accountId'], $email, time()]);
    $fixture[$kind] = ['username'=>$name, 'password'=>$password, 'email'=>$email];
}
$path = '/tmp/space-sharing-http-fixture.json';
file_put_contents($path, json_encode($fixture, JSON_THROW_ON_ERROR));
chmod($path, 0600);
echo "Three synthetic verified accounts prepared; private JSON written inside fixture.\n";
