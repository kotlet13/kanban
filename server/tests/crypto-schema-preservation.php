<?php
/** Empty/partial schema refusal, without changing the integration database. */
require '/var/www/app/app/common.php';if(session_status()===PHP_SESSION_ACTIVE){session_abort();}
if(!defined('FAMILYHUB_DEVELOPMENT_MODE')||FAMILYHUB_DEVELOPMENT_MODE!==true){throw new RuntimeException('Synthetic only');}
use Kanboard\Plugin\FamilyHub\Schema\CryptoSchema;
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoService;
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoFence;
function requireCheck($v,$m){if(!$v){throw new RuntimeException($m);}echo 'PASS: '.$m.PHP_EOL;}
$memory=new PDO('sqlite::memory:');$memory->setAttribute(PDO::ATTR_ERRMODE,PDO::ERRMODE_EXCEPTION);
$memory->exec('CREATE TABLE familyhub_accounts(account_id VARCHAR(36) PRIMARY KEY)');$memory->exec("INSERT INTO familyhub_accounts VALUES('old-account-sentinel')");
requireCheck(!CryptoSchema::ready($memory)&&!NativeCryptoService::enabled($memory),'schema19 has no crypto capability');CryptoSchema::create($memory,false);requireCheck(CryptoSchema::ready($memory),'all additive schema20 columns recognized');
$before=$memory->query('SELECT * FROM familyhub_accounts')->fetchAll(PDO::FETCH_ASSOC);CryptoSchema::create($memory,false);requireCheck($before===$memory->query('SELECT * FROM familyhub_accounts')->fetchAll(PDO::FETCH_ASSOC),'idempotent additive schema preserves existing rows');
$memory->exec('DROP TABLE familyhub_crypto_receipts');$memory->exec('CREATE TABLE familyhub_crypto_receipts(account_id TEXT)');requireCheck(!CryptoSchema::ready($memory)&&!NativeCryptoService::enabled($memory),'partial DDL fails closed even with accounts/scopes present');
$memory->exec("INSERT INTO familyhub_crypto_scopes(scope_id,epoch,sequence,access_revision,state) VALUES('scope',1,0,1,'fenced')");requireCheck(NativeCryptoFence::workerBlocked($memory,'scope')&&NativeCryptoFence::cleanupPaused($memory),'durable fence survives unrelated partial crypto schema');CryptoSchema::create($memory,false);requireCheck(!CryptoSchema::ready($memory),'create never resets or overwrites an incompatible existing table');
echo 'Crypto schema: 6 checks PASS'.PHP_EOL;
