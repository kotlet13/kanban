<?php
require '/var/www/app/app/common.php';
if (!defined('FAMILYHUB_DEVELOPMENT_MODE') || FAMILYHUB_DEVELOPMENT_MODE !== true) {
    throw new RuntimeException('Synthetic only');
}
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoMigrationProvenanceV2 as Provenance;
use Kanboard\Plugin\FamilyHub\Model\NativeError;

$fixture = json_decode(file_get_contents(__DIR__.'/fixtures/e2ee-migration-provenance-v2.json'), true, 32, JSON_THROW_ON_ERROR);
$checks = 0;
$assert = static function ($condition) use (&$checks) {
    if (!$condition) throw new RuntimeException('Migration provenance golden mismatch');
    $checks++;
};
$reject = static function ($callback) use (&$checks) {
    try {
        $callback();
    } catch (NativeError $error) {
        $checks++;
        return;
    }
    throw new RuntimeException('Invalid provenance accepted');
};
$assert(Provenance::leafHash($fixture['header'], $fixture['leaf']) === $fixture['leafHash']);
$assert(Provenance::root($fixture['header'], [$fixture['leafHash']]) === $fixture['root']);
$assert(Provenance::root($fixture['emptyHeader'], []) === $fixture['emptyRoot']);
$assert(Provenance::portionToken($fixture['header']['serverId'], $fixture['header']['migrationId'], $fixture['leaf']['contributorAccountId']) === $fixture['portionToken']);
$assert(Provenance::inventoryHash($fixture['header']['serverId'], $fixture['header']['migrationId'], $fixture['header']['componentHash'], $fixture['portions']) === $fixture['inventoryHash']);
$swapped = $fixture['portions'];
$swapped[0]['portionToken'] = str_repeat('0', 64);
$assert(Provenance::inventoryHash($fixture['header']['serverId'], $fixture['header']['migrationId'], $fixture['header']['componentHash'], $swapped) !== $fixture['inventoryHash']);
$reject(fn() => Provenance::root($fixture['header'], []));
$two = $fixture['header'];
$two['materializedRecordProofCount'] = 2;
$reject(fn() => Provenance::root($two, [$fixture['leafHash'], $fixture['leafHash']]));
$sorted = [$fixture['leafHash'], str_repeat('f', 64)];
sort($sorted, SORT_STRING);
$reject(fn() => Provenance::root($two, array_reverse($sorted)));
$foreign = $fixture['leaf'];
$foreign['migrationId'] = '88888888-8888-4888-8888-888888888888';
$reject(fn() => Provenance::leafHash($fixture['header'], $foreign));
$foreign = $fixture['header'];
$foreign['domain'] = 'finance';
$reject(fn() => Provenance::root($foreign, [$fixture['leafHash']]));
echo 'Crypto2 migration provenance vectors: '.$checks.' checks PASS'.PHP_EOL;
