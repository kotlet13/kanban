<?php
/** Durable source boundary remains closed after terminal state/cache drift. */
require '/var/www/app/plugins/FamilyHub/Model/NativeError.php';
require '/var/www/app/plugins/FamilyHub/Model/NativeCryptoFence.php';

use Kanboard\Plugin\FamilyHub\Model\NativeCryptoFence;
use Kanboard\Plugin\FamilyHub\Model\NativeError;

$pdo = new PDO('sqlite::memory:');
$pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
$pdo->exec('CREATE TABLE familyhub_crypto_scopes(scope_id TEXT PRIMARY KEY,state TEXT)');
$pdo->exec('CREATE TABLE familyhub_crypto_scope_origins(scope_id TEXT PRIMARY KEY)');
$pdo->exec('CREATE TABLE familyhub_scopes(id TEXT PRIMARY KEY,parent_scope_id TEXT,organization_id TEXT)');
$pdo->exec("INSERT INTO familyhub_scopes VALUES('scope',NULL,NULL)");
$checks = 0;
foreach ([null,'preparing','staged','aborted','fenced','verified','active','committed','retired','unknown-terminal',''] as $state) {
    $pdo->exec('DELETE FROM familyhub_crypto_scopes');
    if ($state !== null) {
        $q = $pdo->prepare('INSERT INTO familyhub_crypto_scopes VALUES(?,?)');
        $q->execute(['scope',$state]);
    }
    $blocked = $state !== null && !in_array($state,['preparing','staged','aborted'],true);
    if (NativeCryptoFence::workerBlocked($pdo,'scope') !== $blocked) {
        throw new RuntimeException('Worker state boundary mismatch');
    }
    $checks++;
    $eligible = $pdo->query('SELECT s.id FROM familyhub_scopes s WHERE '.NativeCryptoFence::workerDiscoverySql($pdo,'s.id'))->fetchColumn() !== false;
    if ($eligible === $blocked) { throw new RuntimeException('Discovery state boundary mismatch'); }
    $checks++;
    try {
        NativeCryptoFence::guard($pdo,'scope');
        $code = null;
    } catch (NativeError $error) {
        $code = $error->errorCode;
    }
    $expected = in_array($state,['fenced','verified'],true) ? 'crypto_migration_in_progress' :
        ($blocked ? 'crypto_upgrade_required' : null);
    if ($code !== $expected) {
        throw new RuntimeException('Writer state boundary mismatch');
    }
    $checks++;
}
$pdo->exec('DELETE FROM familyhub_crypto_scopes');
$pdo->exec("INSERT INTO familyhub_crypto_scope_origins VALUES('scope')");
if (!NativeCryptoFence::workerBlocked($pdo,'scope')) {
    throw new RuntimeException('Exact origin must survive derived cache loss');
}
$checks++;
if ($pdo->query('SELECT s.id FROM familyhub_scopes s WHERE '.NativeCryptoFence::workerDiscoverySql($pdo,'s.id'))->fetchColumn() !== false) {
    throw new RuntimeException('Origin must be excluded before worker LIMIT');
}
$checks++;
try {
    NativeCryptoFence::guard($pdo,'scope');
    throw new RuntimeException('Origin writer was not blocked');
} catch (NativeError $error) {
    if ($error->errorCode !== 'crypto_upgrade_required') {
        throw $error;
    }
}
$checks++;
$pdo->exec('DROP TABLE familyhub_crypto_scope_origins');
$pdo->exec("INSERT INTO familyhub_crypto_scopes VALUES('scope','fenced')");
if ($pdo->query('SELECT s.id FROM familyhub_scopes s WHERE '.NativeCryptoFence::workerDiscoverySql($pdo,'s.id'))->fetchColumn() !== false) {
    throw new RuntimeException('Missing origin table must not hide surviving scope fence');
}
$checks++;
$pdo->exec('DROP TABLE familyhub_crypto_scopes');
if ($pdo->query('SELECT s.id FROM familyhub_scopes s WHERE '.NativeCryptoFence::workerDiscoverySql($pdo,'s.id'))->fetchColumn() !== 'scope') {
    throw new RuntimeException('Schema19 discovery must preserve ordinary worker eligibility');
}
$checks++;
echo 'Crypto fence durable states: '.$checks.' checks PASS'.PHP_EOL;
