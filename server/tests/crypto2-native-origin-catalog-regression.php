<?php
/** Focused persisted-model fixtures in a fresh disposable SQLite database only. */
umask(0077);
require '/var/www/app/app/common.php';
if (session_status() === PHP_SESSION_ACTIVE) { session_abort(); }

use Kanboard\Plugin\FamilyHub\Model\NativeAuthService;
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoCodec;
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoScopeV2;
use Kanboard\Plugin\FamilyHub\Model\NativeError;

$pdo = $container['db']->getConnection();
if (getenv('JIVIE_CATALOG_STATE_FIXTURE') !== 'fresh-sqlite'
    || !defined('FAMILYHUB_DEVELOPMENT_MODE') || FAMILYHUB_DEVELOPMENT_MODE !== true
    || $pdo->getAttribute(PDO::ATTR_DRIVER_NAME) !== 'sqlite'
    || (int)$pdo->query('SELECT COUNT(*) FROM familyhub_accounts')->fetchColumn() !== 0
    || (int)$pdo->query('SELECT COUNT(*) FROM familyhub_scopes')->fetchColumn() !== 0) {
    throw new RuntimeException('A fresh, explicitly opted-in disposable SQLite fixture is required');
}
$checks = 0;
function checkCatalog($ok, $label) {
    global $checks;
    if (!$ok) { throw new RuntimeException('FAIL: '.$label); }
    $checks++;
    echo 'PASS: '.$label.PHP_EOL;
}
function catalogSql($sql, array $params = []) {
    global $pdo;
    $query = $pdo->prepare($sql);
    $query->execute($params);
    return $query;
}
function catalogId() {
    $hex = bin2hex(random_bytes(16));
    return substr($hex, 0, 8).'-'.substr($hex, 8, 4).'-4'.substr($hex, 13, 3).'-a'.substr($hex, 17, 3).'-'.substr($hex, 20);
}

$userId = $container['userModel']->create([
    'username' => 'catalog_'.bin2hex(random_bytes(6)),
    'password' => bin2hex(random_bytes(24)),
    'role' => 'app-user',
]);
$session = (new NativeAuthService($container))->issue($container['userModel']->getById($userId), 'Synthetic catalog fixture');
$actor = ['user' => ['id' => $userId, 'account_id' => $session['user']['accountId']], 'device' => $session['device']];
$signing = sodium_crypto_sign_keypair();
$service = new NativeCryptoScopeV2($container);

function catalogProof(array $command, $domain = "JivieE2EE/v2\n") {
    global $signing;
    $bytes = NativeCryptoCodec::canonical((object)$command);
    return ['commandBase64' => base64_encode($bytes), 'signatureBase64' => base64_encode(sodium_crypto_sign_detached($domain.$bytes, sodium_crypto_sign_secretkey($signing)))];
}

// Seed the persisted read contract directly: no legacy suite, HTTP login, or
// claims about the independent write-path signature verifier are involved.
// catalogScope() and current() below are the actual unmodified service methods.
function catalogFixture($origin = true, $state = 'staged', $headState = null, $migrationId = null) {
    global $actor, $session;
    $id = catalogId();
    catalogSql('INSERT INTO familyhub_scopes(id,kind,name,owner_id,sequence,created_at,access_policy_version,access_revision) VALUES(?,?,?,?,0,?,3,0)', [$id, 'organization', 'Synthetic catalog fixture', $actor['user']['id'], time()]);
    catalogSql("INSERT INTO familyhub_members(scope_id,user_id,account_id,role,active) VALUES(?,?,?,'owner',1)", [$id, $actor['user']['id'], $actor['user']['account_id']]);
    catalogSql('INSERT INTO familyhub_finance_policy(scope_id,enabled,revision,sequence) VALUES(?,0,0,0)', [$id]);
    catalogSql('INSERT INTO familyhub_crypto_scopes(scope_id,epoch,sequence,access_revision,state,migration_id) VALUES(?,1,0,0,?,?)', [$id, $state, $migrationId]);
    $command = ['version' => 2, 'operation' => $origin ? 'crypto2.scope.origin' : 'crypto2.scope.prepare', 'serverId' => $session['serverId'], 'scopeId' => $id, 'accountId' => $actor['user']['account_id'], 'deviceId' => $session['device']['id'], 'requestId' => catalogId()];
    $proof = catalogProof($command, $origin ? "JivieE2EE/scopeOrigin/v2\n" : "JivieE2EE/v2\n");
    if ($origin) {
        catalogSql('INSERT INTO familyhub_crypto_scope_origins VALUES(?,?,?,?)', [$id, $actor['user']['account_id'], json_encode($proof), time()]);
    }
    $baseline = ['version' => 2, 'scopeId' => $id, 'originKind' => $origin ? 'new' : 'legacy', 'originProofHash' => hash('sha256', NativeCryptoCodec::canonical((object)$proof)), 'ownArchived' => false, 'inheritedArchived' => false];
    $initialHash = hash('sha256', "JivieLifecycleBaseline/v2\n".NativeCryptoCodec::canonical((object)$baseline));
    catalogSql('INSERT INTO familyhub_crypto_lifecycle_baselines_v2 VALUES(?,?,?,?,?)', [$id, $initialHash, NativeCryptoCodec::canonical((object)$baseline), json_encode($proof), str_repeat('0', 64)]);
    if ($headState !== null) {
        $body = ['scopeId' => $id, 'epoch' => 1, 'accessRevision' => 0, 'initialLifecycleHash' => $initialHash];
        $headHash = hash('sha256', "JivieScopeHead/v2\n".NativeCryptoCodec::canonical((object)$body));
        $proposal = catalogProof($command + ['payload' => $body]);
        $activation = $headState === 'active' ? json_encode(catalogProof($command + ['payload' => ['scopeId' => $id, 'headHash' => $headHash]])) : null;
        catalogSql('INSERT INTO familyhub_crypto_scope_heads(scope_id,head_hash,epoch,previous_head_hash,access_revision,payload,authorization,activation_authorization,state) VALUES(?,?,1,?,0,?,?,?,?)', [$id, $headHash, str_repeat('0', 64), NativeCryptoCodec::canonical((object)$body), json_encode($proposal), $activation, $headState]);
        if ($headState === 'active') {
            catalogSql('INSERT INTO familyhub_crypto_scope_state VALUES(?,?,1,0,0,0)', [$id, $headHash]);
            foreach (['content', 'finance'] as $domain) { catalogSql('INSERT INTO familyhub_crypto_domain_cursors VALUES(?,?,0)', [$id, $domain]); }
        }
    }
    return $id;
}
function catalogState($id) {
    global $service, $actor;
    return $service->catalogScope($id, $actor);
}
function rejectCatalog($id, $code, $label) {
    try { catalogState($id); $caught = false; }
    catch (NativeError $error) { $caught = $error->errorCode === $code; }
    checkCatalog($caught, $label);
}

checkCatalog(catalogState(catalogFixture())['cryptoState'] === 'staged', 'native origin without a published head remains staged');
checkCatalog(catalogState(catalogFixture(true, 'staged', 'pending'))['cryptoState'] === 'staged', 'native origin with only a pending head remains staged');
$active = catalogFixture(true, 'staged', 'active');
$published = catalogState($active);
checkCatalog($published['cryptoState'] === 'active', 'activated native origin is published by the catalog');
checkCatalog($published['cryptoOrigin'] === true && $published['migrationId'] === null && $published['id'] === $active && $published['epoch'] === 1 && $published['accessRevision'] === 0, 'normalization preserves native origin identity and access metadata');
checkCatalog(catalogSql('SELECT state FROM familyhub_crypto_scopes WHERE scope_id=?', [$active])->fetchColumn() === 'staged', 'catalog normalization never updates persisted scope state');
checkCatalog(catalogState(catalogFixture(false, 'staged', 'active'))['cryptoState'] === 'staged', 'activated legacy staging is not a migration commit');
$migration = catalogId();
catalogSql("INSERT INTO familyhub_crypto_migrations_v2 VALUES(?,?,?,?,?,'preparing',?,?,?)", [$migration, catalogId(), str_repeat('0', 64), '[]', str_repeat('0', 64), str_repeat('0', 64), time(), time()]);
checkCatalog(catalogState(catalogFixture(true, 'staged', 'active', $migration))['cryptoState'] === 'staged', 'unfinished migration staging remains staged even with an origin row');
foreach (['fenced', 'verified', 'committed', 'retired', 'active'] as $state) {
    checkCatalog(catalogState(catalogFixture(true, $state, 'active'))['cryptoState'] === $state, 'catalog preserves raw '.$state.' state');
}
$badHash = catalogFixture(true, 'staged', 'active');
catalogSql('UPDATE familyhub_crypto_scope_heads SET payload=? WHERE scope_id=?', ['{}', $badHash]);
rejectCatalog($badHash, 'crypto_scope_head_unavailable', 'invalid current head body hash still fails closed');
$missingHead = catalogFixture(true, 'staged', 'active');
catalogSql('DELETE FROM familyhub_crypto_scope_heads WHERE scope_id=?', [$missingHead]);
rejectCatalog($missingHead, 'crypto_scope_head_unavailable', 'missing current head still fails closed');
$missingActivation = catalogFixture(true, 'staged', 'active');
catalogSql('UPDATE familyhub_crypto_scope_heads SET activation_authorization=NULL WHERE scope_id=?', [$missingActivation]);
rejectCatalog($missingActivation, 'crypto_scope_head_unavailable', 'missing activation authorization still fails closed');
echo 'Native-origin catalog regression: '.$checks.' checks PASS'.PHP_EOL;
