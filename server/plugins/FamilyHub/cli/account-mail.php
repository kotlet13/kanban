<?php
if (PHP_SAPI !== 'cli') { http_response_code(404); exit; }
require dirname(__DIR__, 3).'/app/common.php';
if (session_status() === PHP_SESSION_ACTIVE) { session_abort(); }
try {
    $options = getopt('', ['limit:']); $value = $options['limit'] ?? '20';
    if (!is_string($value) || !ctype_digit($value)) { throw new \RuntimeException(); }
    $limit = (int)$value;
    echo json_encode((new \Kanboard\Plugin\FamilyHub\Model\NativeAccountMailQueue($container))->run($limit), JSON_THROW_ON_ERROR).PHP_EOL;
} catch (\Throwable $ignored) { fwrite(STDERR, "Account mail unavailable\n"); exit(1); }
