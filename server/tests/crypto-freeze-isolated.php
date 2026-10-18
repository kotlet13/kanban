<?php
/** Fresh disposable SQL per suite. Never invoke against a hosting container. */
if (PHP_SAPI !== 'cli' || getenv('JIVIE_CRYPTO_FREEZE_SYNTHETIC') !== '1') {
    throw new RuntimeException('Explicit synthetic matrix invocation required');
}
$suite = $argv[1] ?? '';
if (!preg_match('/^[a-z0-9-]+\.php$/D', $suite) || str_contains($suite, 'seed') || !is_file('/familyhub-tests/'.$suite)) {
    throw new RuntimeException('Exact existing non-seed suite required');
}
$taskRoot = '/tmp/jivie-crypto-freeze-'.bin2hex(random_bytes(8));
mkdir($taskRoot, 0700);
define('DATA_DIR', $taskRoot);
$mysql = getenv('FAMILYHUB_CRYPTO_TEST_MYSQL') === '1';
$taskDatabase = null;
if ($mysql) {
    // These credentials belong solely to compose.crypto-database-tests.yaml.
    $taskDatabase = 'jivie_deletion_core_'.bin2hex(random_bytes(8));
    $taskAdmin = new PDO('mysql:host=database;charset=utf8mb4', 'root', 'familyhub-root-development-only', [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);
    $taskAdmin->exec('CREATE DATABASE `'.$taskDatabase.'` CHARACTER SET utf8mb4');
    putenv('DATABASE_URL=mysql://root:familyhub-root-development-only@database/'.$taskDatabase);
    putenv('JIVIE_DELETE_TEST_ADMIN_PASSWORD=familyhub-root-development-only');
    // common.php parses the isolated URL before the fixed synthetic config.
    // Ignore only its redundant DB constant declarations, not SQL/test errors.
    set_error_handler(function ($level, $message) {
        return $level === E_WARNING && preg_match('/^Constant DB_(DRIVER|HOSTNAME|NAME|USERNAME|PASSWORD) already defined$/D', $message);
    });
} else {
    define('DB_FILENAME', $taskRoot.'/db.sqlite');
}
register_shutdown_function(function () use ($mysql, $taskDatabase, $taskRoot) {
    if ($mysql && $taskDatabase) {
        $admin = new PDO('mysql:host=database;charset=utf8mb4', 'root', 'familyhub-root-development-only', [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);
        $admin->exec('DROP DATABASE `'.$taskDatabase.'`');
    }
    $remove = function ($path) use (&$remove) {
        if (is_link($path) || is_file($path)) { unlink($path); return; }
        if (!is_dir($path)) return;
        foreach (new DirectoryIterator($path) as $entry) if (!$entry->isDot()) $remove($entry->getPathname());
        rmdir($path);
    };
    $remove($taskRoot);
});
require '/familyhub-tests/'.$suite;
