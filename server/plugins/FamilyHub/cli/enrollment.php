<?php
if (PHP_SAPI !== 'cli') { http_response_code(404); exit; }
// Fallback: redirect stdout into a private file, never into public cron logs/email.
require dirname(__DIR__, 3).'/app/common.php';
if (session_status() === PHP_SESSION_ACTIVE) { session_abort(); }
try {
    $options = getopt('', ['admin-user-id:']);
    if (!isset($options['admin-user-id']) || !ctype_digit($options['admin-user-id']) || (int)$options['admin-user-id'] < 1) { throw new \RuntimeException(); }
    echo json_encode((new \Kanboard\Plugin\FamilyHub\Model\NativeEnrollmentService($container))->issue((int)$options['admin-user-id']), JSON_THROW_ON_ERROR).PHP_EOL;
} catch (\Throwable $ignored) { fwrite(STDERR, "Enrollment unavailable\n"); exit(1); }
