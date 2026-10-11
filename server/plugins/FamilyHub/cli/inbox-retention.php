<?php
// Optional dedicated cleanup; the existing reminders cron also runs retention.
if (PHP_SAPI !== 'cli') { http_response_code(404); exit; }
require dirname(__DIR__, 3).'/app/common.php';
if (session_status() === PHP_SESSION_ACTIVE) { session_abort(); }
$options = getopt('', ['limit::']); $limit = $options['limit'] ?? '100';
if (!is_string($limit) || !preg_match('/^[0-9]{1,3}$/D', $limit)) { fwrite(STDERR, "Invalid limit\n"); exit(2); }
try { echo json_encode((new \Kanboard\Plugin\FamilyHub\Model\NativeInboxRetention($container))->run((int)$limit), JSON_THROW_ON_ERROR)."\n"; }
catch (\Throwable $error) { fwrite(STDERR, "Inbox cleanup failed; no sensitive details logged\n"); exit(1); }
