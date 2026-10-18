<?php
/** Pure synthetic floor test, deliberately with the runtime preview disabled. */
require '/var/www/app/plugins/FamilyHub/Model/NativeError.php';
require '/var/www/app/plugins/FamilyHub/Model/NativeCryptoV2Boundary.php';
define('FAMILYHUB_ENABLE_CRYPTO_PREVIEW', false);
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoV2Boundary;
use Kanboard\Plugin\FamilyHub\Model\NativeError;
$checks=0;
function checkFloor($value,$label){global $checks;if(!$value){throw new RuntimeException($label);}$checks++;echo 'PASS: '.$label.PHP_EOL;}
function rejectFloor($pdo,$account,$payload,$label){try{NativeCryptoV2Boundary::guardV1($pdo,$account,$payload);$blocked=false;}catch(NativeError $e){$blocked=$e->errorCode==='crypto_upgrade_required';}checkFloor($blocked,$label);}
$p=new PDO('sqlite::memory:');$p->setAttribute(PDO::ATTR_ERRMODE,PDO::ERRMODE_EXCEPTION);
checkFloor(!NativeCryptoV2Boundary::account($p,'a'),'old schema without v2 evidence preserves legacy account');
$p->exec('CREATE TABLE familyhub_crypto_directory(account_id TEXT)');$p->exec("INSERT INTO familyhub_crypto_directory VALUES('a')");
rejectFloor($p,'a',[],'missing derived cache cannot hide immutable directory floor with preview disabled');
$p->exec('CREATE TABLE familyhub_crypto_directory_state(account_id TEXT)');
rejectFloor($p,'a',[],'empty derived cache cannot hide immutable directory floor');
$p->exec('CREATE TABLE familyhub_crypto_scope_heads(scope_id TEXT)');$p->exec("INSERT INTO familyhub_crypto_scope_heads VALUES('scope-2')");
rejectFloor($p,'v1-member',['scopeId'=>'scope-2'],'v1 member cannot inject a staged v2 scope before migration commit');
rejectFloor($p,'v1-member',['records'=>[['scopeId'=>'scope-2']]],'batch scopes enforce durable v2 floor');
checkFloor(!NativeCryptoV2Boundary::scope($p,'old-preview'),'unrelated legacy preview scope retains original protocol');
$p->exec('CREATE TABLE familyhub_crypto_migrations_v2(id TEXT,state TEXT)');$p->exec("INSERT INTO familyhub_crypto_migrations_v2 VALUES('m','fenced')");
$p->exec('CREATE TABLE familyhub_crypto_migration_portions_v2(migration_id TEXT,scope_ids TEXT,state TEXT)');$q=$p->prepare('INSERT INTO familyhub_crypto_migration_portions_v2 VALUES(?,?,?)');$q->execute(['m','["migration-scope"]','fenced']);
rejectFloor($p,'v1-member',['scopeIds'=>['migration-scope']],'migration contribution alone establishes v2 scope floor');
checkFloor(!NativeCryptoV2Boundary::scope($p,'migration'),'migration association never uses a partial scope substring');
echo 'Crypto2 boundary: '.$checks.' checks PASS'.PHP_EOL;
