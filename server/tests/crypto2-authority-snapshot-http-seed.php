<?php
/** New disposable loopback fixture only; redirect credentials to a private file. */
ob_start();
require __DIR__.'/crypto-http-seed.php';
$fixture = json_decode(ob_get_clean(), true, 128, JSON_THROW_ON_ERROR);
$url = getenv('JIVIE_AUTHORITY_SNAPSHOT_SERVER_URL');
if (!is_string($url) || !preg_match('~^http://127\.0\.0\.1:[0-9]+$~D', $url)) {
    throw new RuntimeException('Explicit synthetic loopback URL required');
}
$fixture['serverUrl'] = $url;
echo json_encode($fixture, JSON_THROW_ON_ERROR).PHP_EOL;
