<?php
/** Fresh synthetic schema only; no network, hosted config or production rows. */
require getenv('KANBOARD_TEST_AUTOLOAD') ?: '/fixture/vendor/autoload.php';
spl_autoload_register(function ($class) {
    $prefix = 'Kanboard\\Plugin\\FamilyHub\\';
    if (str_starts_with($class, $prefix)) require __DIR__.'/../plugins/FamilyHub/'.str_replace('\\', '/', substr($class, strlen($prefix))).'.php';
});
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoMigrationV2;
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoCaptureInboxStateV3;
use Kanboard\Plugin\FamilyHub\Model\NativeError;

$mysql = getenv('MIGRATION_SCHEMA_MYSQL') === '1';
$p = new PDO($mysql ? 'mysql:host=127.0.0.1;dbname=migration_schema_test;charset=utf8mb4' : 'sqlite::memory:', $mysql ? 'root' : null, null, [PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION]);
$p->exec('CREATE TABLE users(id INTEGER PRIMARY KEY,is_active INTEGER NOT NULL DEFAULT 1); CREATE TABLE projects(id INTEGER PRIMARY KEY)');
require __DIR__.'/../plugins/FamilyHub/Schema/'.($mysql ? 'Mysql' : 'Sqlite').'.php';
for ($v=1; $v<=23; $v++) ('Kanboard\\Plugin\\FamilyHub\\Schema\\version_'.$v)($p);
$c = new Pimple\Container();
$c['db'] = new class($p) { public function __construct(private PDO $pdo) {} public function getConnection() { return $this->pdo; } };
$m = new NativeCryptoMigrationV2($c);
$r = new ReflectionClass($m);
function callPrivate($name, ...$args) { global $r,$m; return $r->getMethod($name)->invoke($m, ...$args); }
function check($value, $label) { if (!$value) throw new RuntimeException('FAIL: '.$label); echo 'PASS: '.$label."\n"; }
function denied($callback, $code, $label) { try { $callback(); } catch (NativeError $e) { check($e->errorCode===$code, $label); return; } throw new RuntimeException('FAIL: '.$label); }
function rows($table, $where='1=1', $params=[]) { global $r; return iterator_to_array(callPrivate('rawRows', ['table'=>$table,'columns'=>explode(',', $r->getConstant('COLUMNS')[$table]),'where'=>$where,'params'=>$params])); }
$account='11111111-1111-4111-8111-111111111111';
$scope='22222222-2222-4222-8222-222222222222';
$p->exec("INSERT INTO users(id) VALUES(1); INSERT INTO familyhub_accounts VALUES(1,'$account')");
$p->exec("INSERT INTO familyhub_scopes(id,kind,name,owner_id,created_at,documents_sequence) VALUES('$scope','household','Synthetic Dom',1,1,17)");
$p->exec("INSERT INTO familyhub_members(scope_id,user_id,account_id,role) VALUES('$scope',1,'$account','owner')");
$p->exec("INSERT INTO familyhub_inbox_state(account_id,sequence,visibility_revision,configuration_revision) VALUES('$account',7,8,19)");
$before=$p->query("SELECT * FROM familyhub_scopes")->fetchAll(PDO::FETCH_ASSOC);
$beforeInbox=$p->query("SELECT * FROM familyhub_inbox_state")->fetchAll(PDO::FETCH_ASSOC);
if (getenv('SKIP_SCHEMA_ACCEPTED') !== '1') check(count(callPrivate('schema'))>40, 'current real schema 23 accepted');
$actor=['user'=>['id'=>1,'account_id'=>$account]];
$found=$m->read('crypto2.migration.capture.discover',['scopeId'=>$scope],$actor);
check($found['captureVersion']===3 && $found['ownedScopeIds']===[$scope] && $found['migrationId']===null, 'actual capture discovery reaches owned legacy household');
check($p->query('SELECT COUNT(*) FROM familyhub_crypto_migrations_v2')->fetchColumn()===0, 'discovery creates no migration');
$raw=rows('familyhub_scopes')[0];
check(base64_decode($raw->documents_sequence['valueBase64'])==='17', 'document counter retained in exact typed source');
$inbox=rows('familyhub_inbox_state')[0];
check(base64_decode($inbox->configuration_revision['valueBase64'])==='19', 'configuration counter retained in exact typed source');
$observed=NativeCryptoCaptureInboxStateV3::observe($account,$inbox);
check(NativeCryptoCaptureInboxStateV3::prepared($account,json_decode(json_encode($observed),true))==$inbox, 'four-column observation roundtrips unchanged');
$old=clone $inbox; unset($old->configuration_revision);
check(NativeCryptoCaptureInboxStateV3::snapshot($account,$inbox,$old)===$old, 'previous signed three-column baseline stays byte-shape compatible');
$p->exec("UPDATE familyhub_inbox_state SET configuration_revision=20");
$new=rows('familyhub_inbox_state')[0];
check(NativeCryptoCaptureInboxStateV3::snapshot($account,$new,$inbox)===$inbox, 'new counter advance retains captured baseline');
denied(fn()=>NativeCryptoCaptureInboxStateV3::snapshot($account,$inbox,$new),'crypto_capture_inbox_state_conflict','new counter rollback rejected');
denied(fn()=>NativeCryptoCaptureInboxStateV3::snapshot($account,$old,$inbox),'crypto_capture_inbox_state_conflict','new captured counter cannot disappear');
$extra=clone $inbox; $extra->unexpected=$inbox->sequence;
denied(fn()=>NativeCryptoCaptureInboxStateV3::observe($account,$extra),'crypto_capture_inbox_state_snapshot','unknown inbox field still rejected');
$p->exec("UPDATE familyhub_inbox_state SET configuration_revision=19");
check($before===$p->query('SELECT * FROM familyhub_scopes')->fetchAll(PDO::FETCH_ASSOC) && $beforeInbox===$p->query('SELECT * FROM familyhub_inbox_state')->fetchAll(PDO::FETCH_ASSOC),'discovery and capture reads preserve synthetic source values');
$p->exec('CREATE TABLE familyhub_crypto_unclassified_v99(id INTEGER)');
denied(fn()=>callPrivate('schema'),'crypto_migration_schema_unsupported','unknown crypto table still rejected');
$p->exec('DROP TABLE familyhub_crypto_unclassified_v99');
$p->exec('ALTER TABLE familyhub_scopes ADD COLUMN unclassified TEXT');
denied(fn()=>callPrivate('schema'),'crypto_migration_schema_unsupported','unknown legacy column still rejected');
