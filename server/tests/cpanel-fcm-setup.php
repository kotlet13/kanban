<?php
// Offline synthetic filesystem tests. No Kanboard bootstrap, DB or real keys.
if (PHP_SAPI !== 'cli') exit(1);
umask(0077);
$helper = $argv[1] ?? dirname(__DIR__).'/scripts/setup-cpanel-fcm.php';
$root = sys_get_temp_dir().'/familyhub-fcm-setup-test-'.bin2hex(random_bytes(8));
mkdir($root, 0700);
$assertions = 0;
function check(bool $condition, string $message): void {
    global $assertions;
    $assertions++;
    if (!$condition) throw new RuntimeException($message);
}
function removeTree(string $path): void {
    if (is_link($path) || !is_dir($path)) { unlink($path); return; }
    foreach (scandir($path) as $entry) if ($entry !== '.' && $entry !== '..') removeTree($path.'/'.$entry);
    rmdir($path);
}
function writePrivate(string $path, string $contents): void { file_put_contents($path, $contents); chmod($path, 0600); }
function fixture(string $name, ?string $features = null): array {
    global $root;
    $home = $root.'/'.$name; $base = $home.'/private/jivie-test';
    foreach ([$home, $home.'/private', $base, $base.'/install', $home.'/public_html', $home.'/test.example.invalid', $home.'/other.example.invalid'] as $directory) mkdir($directory, 0700);
    $features ??= "<?php\n// define('FAMILYHUB_ENABLE_FCM', true); ignored comment\ndefine('FAMILYHUB_ENABLE_NATIVE_API', true);\ndefine('FAMILYHUB_ENABLE_FCM', false);\nrequire __DIR__.'/smtp-config.php';\n";
    writePrivate($base.'/familyhub-config.php', $features);
    writePrivate($base.'/smtp-config.php', "<?php\ndefine('SYNTHETIC_SMTP_UNCHANGED', true);\n");
    $key = openssl_pkey_new(['private_key_type' => OPENSSL_KEYTYPE_RSA, 'private_key_bits' => 2048]);
    openssl_pkey_export($key, $pem);
    $credential = ['type' => 'service_account', 'project_id' => 'synthetic-fcm', 'client_email' => 'offline-test@synthetic-fcm.iam.gserviceaccount.com',
        'token_uri' => 'https://oauth2.googleapis.com/token', 'private_key' => $pem];
    writePrivate($base.'/service-account.json', json_encode($credential, JSON_THROW_ON_ERROR));
    $inventory = ['version' => 1, 'reviewedAllDocumentRoots' => true, 'roots' => [$home.'/public_html', $home.'/test.example.invalid', $home.'/other.example.invalid']];
    writePrivate($base.'/public-roots.json', json_encode($inventory, JSON_THROW_ON_ERROR));
    return ['base' => $base, 'home' => $home, 'web' => $home.'/test.example.invalid', 'features' => $features,
        'featureSha' => hash('sha256', $features), 'rootsSha' => hash_file('sha256', $base.'/public-roots.json'), 'credential' => $credential];
}
function invoke(array $fixture, string $mode, array $overrides = []): array {
    global $helper;
    $options = array_replace(['base' => $fixture['base'], 'web-root' => $fixture['web'], 'project' => 'synthetic-fcm',
        'credential' => $fixture['base'].'/service-account.json', 'public-roots-file' => $fixture['base'].'/public-roots.json',
        'public-roots-sha' => $fixture['rootsSha'], 'expected-feature-sha' => $fixture['featureSha']], $overrides);
    $command = [PHP_BINARY, $helper, $mode];
    foreach ($options as $name => $value) if ($value !== null) $command[] = '--'.$name.'='.$value;
    $process = proc_open($command, [0 => ['pipe', 'r'], 1 => ['pipe', 'w'], 2 => ['pipe', 'w']], $pipes);
    fclose($pipes[0]);
    $output = stream_get_contents($pipes[1]).stream_get_contents($pipes[2]); fclose($pipes[1]); fclose($pipes[2]);
    $status = proc_close($process);
    check(!str_contains($output, 'BEGIN PRIVATE KEY') && !str_contains($output, 'offline-test@'), 'Secret or service identity leaked');
    if (is_file($fixture['base'].'/familyhub-push.key')) {
        check(!str_contains($output, trim(file_get_contents($fixture['base'].'/familyhub-push.key'))), 'Push encryption key leaked');
    }
    return [$status, $output];
}
function succeeds(array $fixture, string $mode, array $overrides = []): string {
    [$status, $output] = invoke($fixture, $mode, $overrides); check($status === 0, 'Expected success: '.$mode.' '.$output); return $output;
}
function fails(array $fixture, string $mode, string $reason, array $overrides = []): void {
    [$status, $output] = invoke($fixture, $mode, $overrides);
    check($status !== 0 && str_contains($output, $reason), 'Expected rejection '.$reason.', got '.$output);
}
function snapshot(string $path): array {
    $result = [];
    $iterator = new RecursiveIteratorIterator(new RecursiveDirectoryIterator($path, FilesystemIterator::SKIP_DOTS), RecursiveIteratorIterator::SELF_FIRST);
    foreach ($iterator as $entry) {
        $file = $entry->getPathname();
        $result[substr($file, strlen($path))] = [$entry->isDir() ? 'dir' : hash_file('sha256', $file), $entry->getPerms() & 0777, $entry->getMTime()];
    }
    ksort($result); return $result;
}

try {
    $valid = fixture('valid'); $base = $valid['base'];
    $before = snapshot($base); succeeds($valid, '--check'); check(snapshot($base) === $before, 'Initial check wrote files');
    fails($valid, '--activate', 'prepare_required'); fails($valid, '--rollback', 'prepare_required');
    fails($valid, '--prepare', 'required_argument_missing', ['expected-feature-sha' => null]);
    fails($valid, '--prepare', 'original_feature_sha_mismatch', ['expected-feature-sha' => str_repeat('a', 64)]);
    check(!is_dir($base.'/install/fcm-setup'), 'Rejected setup created work');
    $smtpBefore = hash_file('sha256', $base.'/smtp-config.php');
    succeeds($valid, '--prepare');
    check(file_get_contents($base.'/familyhub-config.php') === $valid['features'], 'Preparation activated FCM');
    $keyBefore = file_get_contents($base.'/familyhub-push.key');
    check(strlen(base64_decode(trim($keyBefore), true)) === 32, 'Push key size invalid');
    $before = snapshot($base); succeeds($valid, '--check'); check(snapshot($base) === $before, 'Prepared check wrote files');
    succeeds($valid, '--prepare'); check(file_get_contents($base.'/familyhub-push.key') === $keyBefore, 'Repeated prepare changed key');
    foreach ([$base.'/fcm-config.php', $base.'/familyhub-push.key', $base.'/install/fcm-setup/plan.json', $base.'/install/fcm-setup/seal.json',
        $base.'/install/fcm-setup/familyhub-config.before.php', $base.'/install/fcm-setup/familyhub-config.candidate.php', $base.'/install/fcm-setup/lock'] as $file) {
        check((fileperms($file) & 0777) === 0600, 'Artifact permissions are not 0600');
    }
    check((fileperms($base.'/install/fcm-setup') & 0777) === 0700, 'Work directory not 0700');
    succeeds($valid, '--activate'); $active = file_get_contents($base.'/familyhub-config.php');
    check(substr_count($active, 'require '.var_export($base.'/fcm-config.php', true)) === 1, 'Activation include missing or duplicated');
    check(str_replace("define('FAMILYHUB_ENABLE_FCM', false);", 'require '.var_export($base.'/fcm-config.php', true).';', $valid['features']) === $active, 'Activation changed unrelated feature bytes');
    succeeds($valid, '--activate'); succeeds($valid, '--prepare');
    $before = snapshot($base); succeeds($valid, '--check'); check(snapshot($base) === $before, 'Active check wrote files');
    // Include in a separate local PHP process and confirm constants coexist.
    $probe = $base.'/probe.php';
    writePrivate($probe, '<?php require '.var_export($base.'/familyhub-config.php', true).'; exit(FAMILYHUB_ENABLE_FCM === true && FAMILYHUB_ENABLE_NATIVE_API === true && SYNTHETIC_SMTP_UNCHANGED === true && FAMILYHUB_FCM_PROJECT_ID === "synthetic-fcm" && strlen(base64_decode(FAMILYHUB_PUSH_KEY_BASE64, true)) === 32 ? 0 : 1);');
    $process = proc_open([PHP_BINARY, $probe], [1 => ['pipe', 'w'], 2 => ['pipe', 'w']], $pipes);
    $probeOutput = stream_get_contents($pipes[1]).stream_get_contents($pipes[2]); fclose($pipes[1]); fclose($pipes[2]);
    check(proc_close($process) === 0 && $probeOutput === '', 'Activated config does not evaluate cleanly'); unlink($probe);
    succeeds($valid, '--rollback'); succeeds($valid, '--rollback');
    check(file_get_contents($base.'/familyhub-config.php') === $valid['features'], 'Rollback did not restore exact original');
    check(file_get_contents($base.'/familyhub-push.key') === $keyBefore && hash_file('sha256', $base.'/smtp-config.php') === $smtpBefore, 'Rollback changed key or SMTP');
    succeeds($valid, '--activate'); check(file_get_contents($base.'/familyhub-push.key') === $keyBefore, 'Reactivation rotated key');

    $changed = fixture('changed'); succeeds($changed, '--prepare');
    writePrivate($changed['base'].'/familyhub-config.php', $changed['features']."// unrelated later edit\n");
    fails($changed, '--activate', 'feature_config_changed'); fails($changed, '--rollback', 'feature_config_changed');
    check(str_contains(file_get_contents($changed['base'].'/familyhub-config.php'), 'unrelated later edit'), 'Rejected CAS overwrote edit');
    $tampered = fixture('tampered'); succeeds($tampered, '--prepare');
    writePrivate($tampered['base'].'/familyhub-push.key', base64_encode(str_repeat('x', 32))."\n");
    fails($tampered, '--activate', 'prepared_seal_changed');
    $candidateChanged = fixture('candidate-changed'); succeeds($candidateChanged, '--prepare');
    writePrivate($candidateChanged['base'].'/install/fcm-setup/familyhub-config.candidate.php', "<?php // tampered\n");
    fails($candidateChanged, '--activate', 'prepared_artifact_changed');
    $credentialChanged = fixture('credential-changed'); succeeds($credentialChanged, '--prepare');
    writePrivate($credentialChanged['base'].'/service-account.json', json_encode($credentialChanged['credential'])."\n");
    fails($credentialChanged, '--activate', 'prepared_inputs_changed');
    $brokenActive = fixture('broken-active'); succeeds($brokenActive, '--prepare'); succeeds($brokenActive, '--activate');
    unlink($brokenActive['base'].'/service-account.json'); unlink($brokenActive['base'].'/familyhub-push.key');
    fails($brokenActive, '--check', 'private_file_guard'); succeeds($brokenActive, '--rollback');
    check(file_get_contents($brokenActive['base'].'/familyhub-config.php') === $brokenActive['features'], 'Rollback needs the removed credential or key');

    $recovery = fixture('recovery'); succeeds($recovery, '--prepare');
    unlink($recovery['base'].'/install/fcm-setup/seal.json'); unlink($recovery['base'].'/fcm-config.php');
    $recoveryKey = file_get_contents($recovery['base'].'/familyhub-push.key');
    fails($recovery, '--activate', 'private_file_guard'); succeeds($recovery, '--prepare');
    check(file_get_contents($recovery['base'].'/familyhub-push.key') === $recoveryKey, 'Recovery changed key'); succeeds($recovery, '--activate');
    // No state rewrite follows rename: after a lost activation response the
    // durable feature bytes are authoritative, so repeating is safe.
    succeeds($recovery, '--activate'); succeeds($recovery, '--rollback');

    foreach (['empty' => '', 'malformed' => '{', 'wrong-project' => json_encode(array_replace($valid['credential'], ['project_id' => 'wrong-project'])),
        'wrong-endpoint' => json_encode(array_replace($valid['credential'], ['token_uri' => 'http://example.invalid/token'])),
        'wrong-key' => json_encode(array_replace($valid['credential'], ['private_key' => 'invalid-sensitive-placeholder']))] as $name => $value) {
        $bad = fixture($name); writePrivate($bad['base'].'/service-account.json', $value);
        fails($bad, '--prepare', match ($name) { 'empty' => 'private_file_guard', 'malformed' => 'parser_or_internal_failure', 'wrong-key' => 'credential_rsa_invalid', default => 'credential_format_or_project_invalid' });
        check(!is_dir($bad['base'].'/install/fcm-setup'), 'Bad credential generated private artifacts');
    }
    $ec = fixture('ec'); $ecKey = openssl_pkey_new(['private_key_type' => OPENSSL_KEYTYPE_EC, 'curve_name' => 'prime256v1']); openssl_pkey_export($ecKey, $ecPem);
    writePrivate($ec['base'].'/service-account.json', json_encode(array_replace($ec['credential'], ['private_key' => $ecPem])));
    fails($ec, '--prepare', 'credential_rsa_invalid');
    $exposed = fixture('permissions'); chmod($exposed['base'].'/service-account.json', 0644); fails($exposed, '--prepare', 'private_file_guard');
    chmod($exposed['base'].'/service-account.json', 0600); chmod($exposed['base'], 0755); fails($exposed, '--prepare', 'private_directory_guard');
    $linked = fixture('symlink'); rename($linked['base'].'/service-account.json', $linked['base'].'/original.json');
    symlink($linked['base'].'/original.json', $linked['base'].'/service-account.json'); fails($linked, '--prepare', 'private_file_guard');
    $hardlinked = fixture('hardlink'); link($hardlinked['base'].'/service-account.json', $hardlinked['base'].'/copy.json'); fails($hardlinked, '--prepare', 'private_file_guard');
    $occupied = fixture('occupied'); writePrivate($occupied['base'].'/familyhub-push.key', base64_encode(str_repeat('z', 32))); fails($occupied, '--prepare', 'unowned_destination_exists');

    foreach (['missing-roots', 'unreviewed', 'public-private', 'private-public-child', 'changed-roots', 'symlink-root'] as $name) {
        $bad = fixture($name); $inventory = json_decode(file_get_contents($bad['base'].'/public-roots.json'), true);
        if ($name === 'missing-roots') array_shift($inventory['roots']);
        if ($name === 'unreviewed') $inventory['reviewedAllDocumentRoots'] = false;
        if ($name === 'public-private') $inventory['roots'][] = $bad['home'].'/private';
        if ($name === 'private-public-child') { mkdir($bad['base'].'/public-child', 0700); $inventory['roots'][] = $bad['base'].'/public-child'; }
        if ($name === 'symlink-root') { symlink($bad['home'].'/other.example.invalid', $bad['home'].'/alias'); $inventory['roots'][] = $bad['home'].'/alias'; }
        writePrivate($bad['base'].'/public-roots.json', json_encode($inventory)."\n");
        if ($name !== 'changed-roots') $bad['rootsSha'] = hash_file('sha256', $bad['base'].'/public-roots.json');
        fails($bad, '--prepare', match ($name) { 'missing-roots' => 'mandatory_public_roots_missing', 'unreviewed' => 'reviewed_public_roots_required',
            'public-private', 'private-public-child' => 'private_base_overlaps_public_root', 'changed-roots' => 'public_roots_inventory_changed', default => 'directory_path_guard' });
        check(!is_dir($bad['base'].'/install/fcm-setup'), 'Invalid public inventory created artifacts');
    }
    foreach (['duplicate' => "<?php\ndefine('FAMILYHUB_ENABLE_FCM', false);\ndefine('FAMILYHUB_ENABLE_FCM', false);\n",
        'already-true' => "<?php\ndefine('FAMILYHUB_ENABLE_FCM', true);\n", 'conditional' => "<?php\nif (true) define('FAMILYHUB_ENABLE_FCM', false);\n",
        'nested' => "<?php\nfunction ignored() { echo ''; define('FAMILYHUB_ENABLE_FCM', false); }\n",
        'other-constant' => "<?php\ndefine('FAMILYHUB_ENABLE_FCM', false);\ndefine('FAMILYHUB_FCM_PROJECT_ID', 'old');\n",
        'syntax' => "<?php\ndefine('FAMILYHUB_ENABLE_FCM', false) broken\n"] as $name => $features) {
        $bad = fixture($name, $features);
        fails($bad, '--prepare', match ($name) { 'duplicate' => 'single_disabled_fcm_definition_required', 'syntax' => 'parser_or_internal_failure', default => 'feature_fcm_definition_requires_review' });
        check(!is_dir($bad['base'].'/install/fcm-setup'), 'Invalid feature config created artifacts');
    }
    $atEnd = fixture('end-of-file', "<?php\ndefine('FAMILYHUB_ENABLE_FCM', false);"); succeeds($atEnd, '--prepare'); succeeds($atEnd, '--activate');
    echo "PASS: $assertions offline synthetic FCM setup assertions. No network or real credentials.\n";
} finally { removeTree($root); }
