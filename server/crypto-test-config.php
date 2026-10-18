<?php
// Synthetic local fixture only. No SMTP, FCM or production connection is configured.
require getenv('FAMILYHUB_CRYPTO_TEST_MYSQL')==='1'?'/familyhub-mysql-config.php':'/familyhub-dev-config.php';
define('FAMILYHUB_ENABLE_CRYPTO_PREVIEW',true);
