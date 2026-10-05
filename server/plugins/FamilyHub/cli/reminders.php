<?php
// Execute from a bounded cPanel cron, not an HTTP endpoint.
if (PHP_SAPI !== 'cli') { http_response_code(404); exit; }
require dirname(__DIR__, 3).'/app/common.php';
$options = getopt('', ['limit::']);
$limit = $options['limit'] ?? '100';
if (!is_string($limit) || !preg_match('/^[0-9]{1,3}$/D', $limit)) { fwrite(STDERR, "Invalid limit\n"); exit(2); }
try {
    $result = (new \Kanboard\Plugin\FamilyHub\Model\NativeReminderService($container))->runDue((int)$limit);
    echo json_encode($result, JSON_THROW_ON_ERROR)."\n";
} catch (\Throwable $error) { fwrite(STDERR, "Reminder run failed; no sensitive details logged\n"); exit(1); }
