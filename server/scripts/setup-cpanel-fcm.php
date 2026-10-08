<?php
// CLI only; no bootstrap, database, network, provider authentication or delivery.
if (PHP_SAPI !== 'cli') { http_response_code(404); exit; }
ini_set('display_errors', '0');
ini_set('log_errors', '0');
error_reporting(0);
umask(0077);

final class FcmSetupGuard extends RuntimeException {}
function fcmStop(string $code): never { throw new FcmSetupGuard($code); }
set_error_handler(static function(): never { fcmStop('filesystem_or_php_warning'); });

function fcmInside(string $path, string $root): bool
{
    return $path === $root || str_starts_with($path, $root.'/');
}

function fcmDirectory(string $path, bool $private = true): void
{
    clearstatcache(true, $path);
    if (is_link($path) || !is_dir($path) || realpath($path) !== $path) fcmStop('directory_path_guard');
    if ($private && ((fileperms($path) & 0077) !== 0 || fileowner($path) !== $GLOBALS['fcmOwner'])) fcmStop('private_directory_guard');
}

function fcmRead(string $path, int $limit = 1048576): string
{
    clearstatcache(true, $path);
    if (is_link($path) || !is_file($path) || realpath($path) !== $path || !is_readable($path)
        || (fileperms($path) & 0077) !== 0 || fileowner($path) !== $GLOBALS['fcmOwner']
        || filesize($path) < 1 || filesize($path) > $limit || fileinode($path) === false
        || (stat($path)['nlink'] ?? 0) !== 1) fcmStop('private_file_guard');
    $value = file_get_contents($path);
    if ($value === false) fcmStop('private_read_failed');
    return $value;
}

function fcmCreate(string $path, string $value): void
{
    if (is_link($path)) fcmStop('destination_symlink');
    if (file_exists($path)) {
        if (!hash_equals(hash('sha256', $value), hash('sha256', fcmRead($path)))) fcmStop('existing_artifact_changed');
        return;
    }
    $file = fopen($path, 'xb');
    try {
        if (fwrite($file, $value) !== strlen($value) || !fflush($file) || !fsync($file)) fcmStop('private_write_failed');
    } finally { fclose($file); }
    if (!chmod($path, 0600)) fcmStop('private_permissions_failed');
}

function fcmParse(string $value): void { token_get_all($value, TOKEN_PARSE); }

function fcmCandidate(string $original, string $config): string
{
    // Inspect tokens rather than regex comments. Accept only one literal global
    // define('FAMILYHUB_ENABLE_FCM', false); and no other FCM configuration.
    $tokens = token_get_all($original, TOKEN_PARSE);
    $significant = []; $offset = 0; $braceDepth = 0;
    foreach ($tokens as $token) {
        $text = is_array($token) ? $token[1] : $token;
        if (is_array($token) && $token[0] === T_NAMESPACE) fcmStop('feature_namespace_requires_review');
        if (!is_array($token) || !in_array($token[0], [T_WHITESPACE, T_COMMENT, T_DOC_COMMENT], true)) {
            $significant[] = ['text' => $text, 'id' => is_array($token) ? $token[0] : null, 'offset' => $offset, 'depth' => $braceDepth];
        }
        if ($token === '{') $braceDepth++;
        if ($token === '}') $braceDepth--;
        if (is_array($token) && in_array($token[0], [T_CLOSE_TAG, T_INLINE_HTML], true)) fcmStop('feature_php_only_required');
        $offset += strlen($text);
    }
    $matches = [];
    foreach ($significant as $index => $token) {
        if (!str_contains($token['text'], 'FAMILYHUB_ENABLE_FCM')
            && !preg_match('/FAMILYHUB_(?:PUBLIC_ROOT|FCM_[A-Z_]+|PUSH_KEY_BASE64)/', $token['text'])) continue;
        $part = array_slice($significant, $index - 2, 7);
        if ($index < 2 || count($part) !== 7 || $token['depth'] !== 0
            || $part[0]['id'] !== T_STRING || strtolower($part[0]['text']) !== 'define'
            || $part[1]['text'] !== '(' || !in_array($part[2]['text'], ["'FAMILYHUB_ENABLE_FCM'", '"FAMILYHUB_ENABLE_FCM"'], true)
            || $part[3]['text'] !== ',' || $part[4]['id'] !== T_STRING || strtolower($part[4]['text']) !== 'false'
            || $part[5]['text'] !== ')' || $part[6]['text'] !== ';'
            || ($index > 2 && $significant[$index - 3]['text'] !== ';' && $significant[$index - 3]['id'] !== T_OPEN_TAG)) fcmStop('feature_fcm_definition_requires_review');
        $matches[] = [$part[0]['offset'], $part[6]['offset'] + 1];
    }
    if (count($matches) !== 1) fcmStop('single_disabled_fcm_definition_required');
    [$start, $end] = $matches[0];
    $result = substr($original, 0, $start).'require '.var_export($config, true).';'.substr($original, $end);
    fcmParse($result);
    return $result;
}

function fcmCredential(string $path, string $project): string
{
    $raw = fcmRead($path, 65536);
    $value = json_decode($raw, true, 16, JSON_THROW_ON_ERROR);
    if (!is_array($value) || ($value['type'] ?? null) !== 'service_account'
        || ($value['project_id'] ?? null) !== $project
        || !is_string($value['client_email'] ?? null)
        || !preg_match('/^[a-zA-Z0-9._-]+@'.preg_quote($project, '/').'\.iam\.gserviceaccount\.com$/D', $value['client_email'])
        || ($value['token_uri'] ?? null) !== 'https://oauth2.googleapis.com/token'
        || !is_string($value['private_key'] ?? null)) fcmStop('credential_format_or_project_invalid');
    $key = @openssl_pkey_get_private($value['private_key']);
    $details = $key ? openssl_pkey_get_details($key) : false;
    if (!$details || $details['type'] !== OPENSSL_KEYTYPE_RSA || $details['bits'] < 2048) fcmStop('credential_rsa_invalid');
    return hash('sha256', $raw);
}

function fcmReplace(string $features, string $expected, string $value, string $work): void
{
    // Serialize this helper. Other editors must cooperate with flock, too.
    $file = fopen($features, 'rb');
    try {
        if (!flock($file, LOCK_EX) || hash('sha256', fcmRead($features)) !== $expected) fcmStop('feature_compare_and_swap_failed');
        $temporary = $work.'/replacement.'.bin2hex(random_bytes(8)).'.php';
        fcmCreate($temporary, $value);
        if (hash('sha256', fcmRead($features)) !== $expected || !rename($temporary, $features)) fcmStop('feature_compare_and_swap_failed');
    } finally { fclose($file); }
}

try {
    $options = []; $mode = $argv[1] ?? '';
    if (!in_array($mode, ['--check', '--prepare', '--activate', '--rollback'], true)) fcmStop('usage_check_prepare_activate_rollback');
    foreach (array_slice($argv, 2) as $argument) {
        if (!preg_match('/^--([a-z-]+)=(.+)$/D', $argument, $match) || isset($options[$match[1]])) fcmStop('argument_invalid');
        $options[$match[1]] = $match[2];
    }
    foreach (array_keys($options) as $name) {
        if (!in_array($name, ['base', 'web-root', 'project', 'credential', 'public-roots-file', 'public-roots-sha', 'expected-feature-sha'], true)) fcmStop('argument_unknown');
    }
    $base = $options['base'] ?? '/home/tripar13/private/jivie-test';
    $webRoot = $options['web-root'] ?? '/home/tripar13/jivie-test.triparna.si';
    $project = $options['project'] ?? 'jivie-e928a';
    foreach (['credential', 'public-roots-file', 'public-roots-sha', 'expected-feature-sha'] as $required) if (!isset($options[$required])) fcmStop('required_argument_missing');
    foreach (['public-roots-sha', 'expected-feature-sha'] as $name) if (!preg_match('/^[a-f0-9]{64}$/D', $options[$name])) fcmStop('expected_sha_invalid');
    if (!preg_match('/^[a-z][a-z0-9-]{4,28}[a-z0-9]$/D', $project)) fcmStop('project_invalid');
    if (!str_starts_with($base, '/') || !str_starts_with($webRoot, '/')) fcmStop('absolute_paths_required');
    if (!extension_loaded('openssl') || !extension_loaded('curl') || !function_exists('fsync') || !function_exists('token_get_all')) fcmStop('php_extensions_required');
    $GLOBALS['fcmOwner'] = fileowner($base);
    if (function_exists('posix_geteuid') && posix_geteuid() !== $GLOBALS['fcmOwner']) fcmStop('cli_owner_mismatch');
    fcmDirectory(dirname($base)); fcmDirectory($base); fcmDirectory($base.'/install');
    $rootsFile = $options['public-roots-file']; $credential = $options['credential'];
    foreach ([$rootsFile, $credential] as $path) {
        if (!fcmInside($path, $base)) fcmStop('inputs_must_be_in_private_base');
        for ($directory = dirname($path); $directory !== $base; $directory = dirname($directory)) fcmDirectory($directory);
    }
    $rootsText = fcmRead($rootsFile, 65536);
    if (!hash_equals($options['public-roots-sha'], hash('sha256', $rootsText))) fcmStop('public_roots_inventory_changed');
    $inventory = json_decode($rootsText, true, 16, JSON_THROW_ON_ERROR);
    if (!is_array($inventory) || ($inventory['version'] ?? null) !== 1 || ($inventory['reviewedAllDocumentRoots'] ?? null) !== true
        || !is_array($inventory['roots'] ?? null) || !$inventory['roots']) fcmStop('reviewed_public_roots_required');
    $roots = $inventory['roots'];
    foreach ($roots as $root) {
        if (!is_string($root) || !str_starts_with($root, '/')) fcmStop('public_root_invalid');
        fcmDirectory($root, false);
        if (fcmInside($base, $root) || fcmInside($root, $base)) fcmStop('private_base_overlaps_public_root');
    }
    if (!in_array($webRoot, $roots, true) || !in_array(dirname(dirname($base)).'/public_html', $roots, true)) fcmStop('mandatory_public_roots_missing');
    $features = $base.'/familyhub-config.php'; $work = $base.'/install/fcm-setup';
    $config = $base.'/fcm-config.php'; $pushKey = $base.'/familyhub-push.key';
    $credentialSha = null;
    if ($mode === '--rollback') {
        // Disable even if a credential was removed or became invalid. Only the
        // sealed original/candidate feature bytes are needed for restoration.
        if (!is_dir($work)) fcmStop('prepare_required');
        fcmDirectory($work);
        $savedPlan = json_decode(fcmRead($work.'/plan.json'), true, 16, JSON_THROW_ON_ERROR);
        $credentialSha = $savedPlan['credentialSha256'] ?? null;
        if (!is_string($credentialSha) || !preg_match('/^[a-f0-9]{64}$/D', $credentialSha)) fcmStop('prepared_plan_invalid');
    } else { $credentialSha = fcmCredential($credential, $project); }
    $plan = ['version' => 1, 'base' => $base, 'webRoot' => $webRoot, 'project' => $project, 'credential' => $credential,
        'credentialSha256' => $credentialSha, 'rootsSha256' => $options['public-roots-sha'], 'featureSha256' => $options['expected-feature-sha']];
    $planText = json_encode($plan, JSON_PRETTY_PRINT | JSON_THROW_ON_ERROR)."\n";
    $current = fcmRead($features); fcmParse($current);
    $existing = file_exists($work) || is_link($work);
    if ($existing) {
        fcmDirectory($work);
        if (fcmRead($work.'/plan.json') !== $planText) fcmStop('prepared_inputs_changed');
        if (!file_exists($work.'/familyhub-config.before.php') && $mode === '--prepare'
            && hash('sha256', $current) === $options['expected-feature-sha']) {
            fcmCreate($work.'/familyhub-config.before.php', $current);
        }
        $original = fcmRead($work.'/familyhub-config.before.php');
    } else {
        $original = $current;
        foreach ([$config, $pushKey] as $path) if (file_exists($path) || is_link($path)) fcmStop('unowned_destination_exists');
    }
    if (hash('sha256', $original) !== $options['expected-feature-sha']) fcmStop('original_feature_sha_mismatch');
    $candidate = fcmCandidate($original, $config);
    $activeSha = hash('sha256', $candidate);
    $currentSha = hash('sha256', $current);
    if (!in_array($currentSha, [$options['expected-feature-sha'], $activeSha], true)) fcmStop('feature_config_changed');
    if ($mode === '--rollback') {
        fcmRead($work.'/lock');
        $lock = fopen($work.'/lock', 'rb');
        if (!flock($lock, LOCK_EX)) fcmStop('setup_lock_failed');
        $currentSha = hash('sha256', fcmRead($features));
        if ($currentSha === $activeSha) fcmReplace($features, $activeSha, $original, $work);
        elseif ($currentSha !== $options['expected-feature-sha']) fcmStop('feature_config_changed');
        fclose($lock);
        echo "Original feature configuration restored (or already present). Private FCM files retained.\n";
        exit(0);
    }
    $configuration = "<?php\n// Private FCM settings; never print loaded values.\n"
        ."define('FAMILYHUB_ENABLE_FCM', true);\n"
        ."define('FAMILYHUB_PUBLIC_ROOT', ".var_export($webRoot, true).");\n"
        ."define('FAMILYHUB_FCM_PROJECT_ID', ".var_export($project, true).");\n"
        ."define('FAMILYHUB_FCM_SERVICE_ACCOUNT_FILE', ".var_export($credential, true).");\n"
        ."define('FAMILYHUB_PUSH_KEY_BASE64', trim(file_get_contents(".var_export($pushKey, true).")));\n";
    fcmParse($configuration);
    if ($mode === '--check' && !$existing) { echo "Check passed; FCM remains disabled. No files changed; no network or delivery.\n"; exit(0); }
    if (!$existing && $mode !== '--prepare') fcmStop('prepare_required');
    if (!$existing) {
        if (!mkdir($work, 0700)) fcmStop('work_create_failed');
        fcmCreate($work.'/plan.json', $planText);
        fcmCreate($work.'/familyhub-config.before.php', $original);
    }
    // --check does not create a lock or any missing artifact.
    $lock = null;
    if ($mode !== '--check') {
        $lockPath = $work.'/lock';
        if (!file_exists($lockPath)) fcmCreate($lockPath, "FCM helper lock\n");
        fcmRead($lockPath);
        $lock = fopen($lockPath, 'rb');
        if (!flock($lock, LOCK_EX)) fcmStop('setup_lock_failed');
    }
    $sealPath = $work.'/seal.json';
    if (!file_exists($sealPath) && $mode === '--prepare') {
        if (!file_exists($pushKey) && !is_link($pushKey)) fcmCreate($pushKey, base64_encode(random_bytes(32))."\n");
        fcmCreate($config, $configuration);
        fcmCreate($work.'/familyhub-config.candidate.php', $candidate);
    }
    $keyText = fcmRead($pushKey, 128);
    $decoded = base64_decode(trim($keyText), true);
    if ($decoded === false || strlen($decoded) !== 32) fcmStop('push_key_invalid');
    if (fcmRead($config) !== $configuration || fcmRead($work.'/familyhub-config.candidate.php') !== $candidate) fcmStop('prepared_artifact_changed');
    $seal = ['version' => 1, 'planSha256' => hash('sha256', $planText), 'keySha256' => hash('sha256', $keyText),
        'configSha256' => hash('sha256', $configuration), 'candidateSha256' => $activeSha];
    $sealText = json_encode($seal, JSON_PRETTY_PRINT | JSON_THROW_ON_ERROR)."\n";
    if (!file_exists($sealPath) && $mode === '--prepare') fcmCreate($sealPath, $sealText);
    if (fcmRead($sealPath) !== $sealText) fcmStop('prepared_seal_changed');
    // Re-read after acquiring the lock; no stale snapshot may activate/rollback.
    $currentSha = hash('sha256', fcmRead($features));
    if (!in_array($currentSha, [$options['expected-feature-sha'], $activeSha], true)) fcmStop('feature_config_changed');
    if ($mode === '--activate' && $currentSha !== $activeSha) fcmReplace($features, $options['expected-feature-sha'], $candidate, $work);
    if ($lock !== null) fclose($lock);
    if ($mode === '--activate') echo "FCM configuration activated (or already active). No network or delivery; provider unverified.\n";
    else echo "Private FCM artifacts verified; feature configuration ".($currentSha === $activeSha ? 'active' : 'disabled').". No network or delivery.\n";
} catch (FcmSetupGuard $error) {
    fwrite(STDERR, 'FCM setup stopped: '.$error->getMessage().". No secrets printed.\n"); exit(1);
} catch (Throwable $error) {
    fwrite(STDERR, "FCM setup stopped: parser_or_internal_failure. No exception or secrets printed.\n"); exit(1);
}
