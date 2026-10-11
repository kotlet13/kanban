<?php
// Independent synthetic race process; no secrets in argv/output.
if (PHP_SAPI !== 'cli') { exit(2); }
$fixture = json_decode(file_get_contents($argv[1]), true, 16, JSON_THROW_ON_ERROR);
require '/var/www/app/app/common.php';
if (!defined('FAMILYHUB_DEVELOPMENT_MODE') || FAMILYHUB_DEVELOPMENT_MODE !== true) { exit(2); }
if (session_status() === PHP_SESSION_ACTIVE) { session_abort(); }
class RetentionChild extends \Kanboard\Plugin\FamilyHub\Model\NativeInboxRetention {
    public function own($now = null) { return $this->transaction(fn () => $this->pruneForUser($this->actor()['user'], 500, $now)); }
}
echo "ready\n"; flush();
if (trim(fgets(STDIN)) !== 'go') { exit(2); }
echo "attempting\n"; flush();
try {
    if ($fixture['action'] === 'prune') {
        $deleted = (new RetentionChild($container, 'Bearer '.$fixture['token']))->own($fixture['now'] ?? null);
        echo 'done:'.$deleted."\n";
    } else {
        (new \Kanboard\Plugin\FamilyHub\Model\NativeInboxService($container, 'Bearer '.$fixture['token'], $fixture['ip']))->execute('inbox.read', $fixture['params']);
        echo "done:read\n";
    }
} catch (\Kanboard\Plugin\FamilyHub\Model\NativeError $error) { echo 'done:error:'.$error->getMessage()."\n"; }
catch (\Throwable $ignored) { fwrite(STDERR, "Retention race failed\n"); exit(1); }
flush();
