<?php
// Isolated loopback development environment; never use this file in production.
define('DB_DRIVER', 'sqlite');
define('LOG_DRIVER', 'system');
define('DEBUG', false);
define('FAMILYHUB_DEVELOPMENT_ENVIRONMENT', true);
define('FAMILYHUB_DEVELOPMENT_MODE', true);
define('PLUGIN_INSTALLER', false);
define('FAMILYHUB_ENABLE_PROJECT_INVITATIONS', true);
define('FAMILYHUB_ENABLE_NATIVE_API', true);
define('FAMILYHUB_CORS_ORIGINS', ['http://127.0.0.1:18770', 'http://127.0.0.1:18771']);
