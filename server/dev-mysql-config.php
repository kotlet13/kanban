<?php
// Disposable local database matrix; never use this configuration in production.
define('DB_DRIVER', 'mysql');
define('DB_HOSTNAME', 'database');
define('DB_NAME', 'kanboard');
define('DB_USERNAME', 'familyhub_dev');
define('DB_PASSWORD', 'familyhub-development-only');
define('LOG_DRIVER', 'system');
define('DEBUG', false);
define('FAMILYHUB_DEVELOPMENT_ENVIRONMENT', true);
define('FAMILYHUB_DEVELOPMENT_MODE', true);
define('PLUGIN_INSTALLER', false);
define('FAMILYHUB_ENABLE_PROJECT_INVITATIONS', true);
define('FAMILYHUB_ENABLE_NATIVE_API', true);
define('FAMILYHUB_CORS_ORIGINS', ['http://127.0.0.1:18770', 'http://127.0.0.1:18771']);
