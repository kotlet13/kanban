<?php
// Unique disposable databases in the local synthetic MariaDB fixture only.
$helper=$argv[1]??'/tmp/upgrade-cpanel-jivie-notifications.php';
$source=file_get_contents($helper);
$root=sys_get_temp_dir().'/jivie-notifications-db-test-'.bin2hex(random_bytes(8));mkdir($root,0700);
$source=str_replace(['/home/tripar13/jivie-test.triparna.si','/home/tripar13/private/jivie-test'],[$root.'/site',$root.'/private'],$source);
$boundary=strpos($source,"try{\n    \$mode=");if($boundary===false)throw new RuntimeException('Helper boundary changed');
eval(substr($source,5,$boundary-5));
require '/var/www/app/plugins/FamilyHub/Schema/SharingSchema.php';
$checks=0;
function check($ok,$name){global$checks;if(!$ok)throw new RuntimeException('Failed check: '.$name);$checks++;echo 'PASS: '.$name."\n";}
function reject($fn,$name){try{$fn();}catch(Throwable $e){check(true,$name);return;}throw new RuntimeException('Expected rejection: '.$name);}
$db='jivie_notifications_helper_'.bin2hex(random_bytes(6));$restore=$db.'_restore';
$admin=new PDO('mysql:host=database;charset=utf8mb4','root','familyhub-root-development-only',[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION]);
try{
 foreach([$db,$restore]as$name)$admin->exec('CREATE DATABASE '.identifier($name).' CHARACTER SET utf8mb4');
 $pdo=new PDO('mysql:host=database;dbname='.$db.';charset=utf8mb4','root','familyhub-root-development-only',[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION]);
 $pdo->exec("CREATE TABLE plugin_schema_versions (plugin VARCHAR(40) PRIMARY KEY,version INT NOT NULL) ENGINE=InnoDB");
 $pdo->exec("INSERT INTO plugin_schema_versions VALUES ('familyhub',14),('unrelated',2)");
 $pdo->exec("CREATE TABLE familyhub_instance (id INT PRIMARY KEY,server_id VARCHAR(36) NOT NULL) ENGINE=InnoDB");
 $pdo->exec("INSERT INTO familyhub_instance VALUES (1,'sentinel-server-id')");
 $pdo->exec("CREATE TABLE users (id INT PRIMARY KEY,password VARCHAR(255) NOT NULL) ENGINE=InnoDB");
 $pdo->exec("INSERT INTO users VALUES (7,'sentinel-password-hash'),(9,'other-password-hash')");
 $pdo->exec("CREATE TABLE familyhub_accounts (user_id INT PRIMARY KEY,account_id VARCHAR(36) NOT NULL) ENGINE=InnoDB");
 $pdo->exec("INSERT INTO familyhub_accounts VALUES (7,'sentinel-account-id')");
 $pdo->exec("CREATE TABLE familyhub_enrollment (id INT PRIMARY KEY,token_hash VARCHAR(64),consumed_at BIGINT) ENGINE=InnoDB");
 $pdo->exec("INSERT INTO familyhub_enrollment VALUES (1,'sentinel-enrollment-hash',123456)");
 $pdo->exec("CREATE TABLE familyhub_scopes (id VARCHAR(36) PRIMARY KEY,organization_id VARCHAR(36),organization_access_policy INT NOT NULL DEFAULT 1) ENGINE=InnoDB");
 $pdo->exec("INSERT INTO familyhub_scopes VALUES ('org-one',NULL,1),('org-two',NULL,2),('project-one','org-one',1),('project-two','org-two',2),('household',NULL,1),('personal',NULL,1)");
 $pdo->exec("CREATE TABLE familyhub_invitations (id VARCHAR(36) PRIMARY KEY,recipient_username VARCHAR(100) NOT NULL,token_hash VARCHAR(64) NOT NULL,request_id VARCHAR(36) NOT NULL,request_hash VARCHAR(64) NOT NULL,expires_at BIGINT NOT NULL,recipient_email VARCHAR(254),recipient_account_id VARCHAR(36)) ENGINE=InnoDB CHARSET=utf8mb4");
 $pdo->exec("INSERT INTO familyhub_invitations VALUES ('old-invite','existing.username','sentinel-token-hash','sentinel-request-id','sentinel-body-hash',2000000000,NULL,NULL),('email-invite','','email-token','email-request','email-body',2000000000,'existing@example.invalid','sentinel-account-id')");
 $pdo->exec("CREATE TABLE synthetic_records (id INT PRIMARY KEY,amount DECIMAL(30,2),payload LONGBLOB,nullable VARCHAR(20)) ENGINE=InnoDB");
 $binary="synthetic\0'\\\xff";$pdo->prepare('INSERT INTO synthetic_records VALUES (1,?,?,NULL)')->execute(['9007199254740993.12',$binary]);
 \Kanboard\Plugin\FamilyHub\Schema\SharingSchema::create($pdo,true);
 $pdo->exec("UPDATE plugin_schema_versions SET version=15 WHERE plugin='familyhub'");
 $before=snapshot($pdo);
 $state=['phase'=>'snapshot','before'=>$before,'databaseDefinition'=>databaseDefinition($pdo),'pluginSchemaRows'=>query($pdo,'SELECT * FROM plugin_schema_versions ORDER BY plugin'),'configHashes'=>[]];
 databaseGuard($pdo,$state);check(true,'unchanged schema15 database accepted');
 $dump=$root.'/dump.sql';dumpDatabase($pdo,$dump);
 $restored=new PDO('mysql:host=database;dbname='.$restore.';charset=utf8mb4','root','familyhub-root-development-only',[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION]);
 $restored->exec(bytes($dump));
 check(snapshot($restored)===$before,'schema15 SQL restores every table/identity/password/token/body/binary/null/large decimal exactly');
 databaseGuard($restored,$state);check(true,'restored columns and indexes retain exact definitions');
 foreach(['users'=>"UPDATE users SET password='changed' WHERE id=7",'policy'=>"UPDATE familyhub_scopes SET organization_access_policy=3 WHERE id='org-two'",'preferences'=>"INSERT INTO synthetic_records VALUES (2,1,'new',NULL)",'plugin version'=>"UPDATE plugin_schema_versions SET version=16 WHERE plugin='familyhub'"]as$name=>$sql){
  $pdo->beginTransaction();$pdo->exec($sql);reject(fn()=>databaseGuard($pdo,$state),'changed '.$name.' rejected');$pdo->rollBack();
 }
 $pdo->exec('CREATE TABLE unwanted (id INT) ENGINE=InnoDB');reject(fn()=>databaseGuard($pdo,$state),'added table rejected');$pdo->exec('DROP TABLE unwanted');
 $pdo->exec('ALTER TABLE synthetic_records ADD COLUMN unwanted INT');reject(fn()=>databaseGuard($pdo,$state),'added column rejected');$pdo->exec('ALTER TABLE synthetic_records DROP COLUMN unwanted');
 $pdo->exec('CREATE INDEX unwanted ON synthetic_records(nullable)');reject(fn()=>databaseGuard($pdo,$state),'added index rejected');$pdo->exec('DROP INDEX unwanted ON synthetic_records');
 databaseGuard($pdo,$state);check(true,'all mutation probes restored exactly');
 directory(SITE);directory(SITE.'/plugins');directory(SITE.'/plugins/FamilyHub');writePrivate(SITE.'/plugins/FamilyHub/Plugin.php',"<?php function getPluginVersion() { return '0.11.0'; }");directory(BASE);directory(WORK);
 writePrivate(ORIGINAL,'original');writePrivate(PAUSED,'paused');writePrivate(CURRENT,'paused');writePrivate(WORK.'/crontab.paused-applied','proof');
 $state['codeHashes']=inventory(SITE.'/plugins/FamilyHub');
 abortGuard($pdo,$state);check(true,'abort accepts original schema15 code and paused cron');
 $bad=$state;$bad['phase']='healthy';reject(fn()=>abortGuard($pdo,$bad),'healthy deployment requires explicit code rollback');
 replacePrivate(CURRENT,'later-cron');reject(fn()=>abortGuard($pdo,$state),'abort refuses later cron edit');replacePrivate(CURRENT,'paused');
 directory(WORK.'/backup');directory(WORK.'/backup/private');
 writePrivate(BASE.'/sentinel','private');writePrivate(WORK.'/backup/private/sentinel','private');
 maintenance();
 rename(SITE.'/plugins/FamilyHub',WORK.'/code-original');directory(SITE.'/plugins/FamilyHub');
 copy($argv[2],ARCHIVE);chmod(ARCHIVE,0600);manifestLocal(ARCHIVE,MANIFEST);$bundle=verifyBundle();
 $zip=new ZipArchive();$zip->open(ARCHIVE);foreach($bundle['files']as$name=>$hash){$to=SITE.'/plugins/'.$name;$parent=dirname($to);if(!is_dir($parent))mkdir($parent,0700,true);writePrivate($to,$zip->getFromName($name));}$zip->close();
 $state['phase']='healthy';rollbackGuard($pdo,$state);check(true,'code-only rollback accepts unchanged schema15 database and pinned active tree');
 $bad=$state;$bad['phase']='released';reject(fn()=>rollbackGuard($pdo,$bad),'rollback after maintenance release rejected');
 replacePrivate(CURRENT,'later-cron');reject(fn()=>rollbackGuard($pdo,$state),'rollback refuses later cron edit');replacePrivate(CURRENT,'paused');
 replacePrivate(BASE.'/sentinel','later-data');reject(fn()=>rollbackGuard($pdo,$state),'rollback refuses later private data');replacePrivate(BASE.'/sentinel','private');
 replacePrivate(WORK.'/code-original/Plugin.php','changed');reject(fn()=>rollbackGuard($pdo,$state),'rollback refuses changed original code');replacePrivate(WORK.'/code-original/Plugin.php',"<?php function getPluginVersion() { return '0.11.0'; }");
 replacePrivate(SITE.'/plugins/FamilyHub/Plugin.php','changed');reject(fn()=>rollbackGuard($pdo,$state),'rollback refuses changed active code');replacePrivate(SITE.'/plugins/FamilyHub/Plugin.php',file_get_contents('/var/www/app/plugins/FamilyHub/Plugin.php'));
 $pdo->beginTransaction();$pdo->exec("UPDATE users SET password='later-account-change' WHERE id=7");reject(fn()=>rollbackGuard($pdo,$state),'rollback refuses later account/password change');$pdo->rollBack();
 check(!str_contains($source,'SharingSchema::create')&&!str_contains($source,'UPDATE plugin_schema_versions'),'patch helper contains no migration or schema update');
 echo 'SUCCESS '.$checks." notifications upgrade helper DB checks (local synthetic MariaDB only)\n";
}finally{
 foreach([$db,$restore]as$name)$admin->exec('DROP DATABASE '.identifier($name));
 $remove=function($path)use(&$remove){if(is_link($path)||is_file($path)){unlink($path);return;}foreach(new DirectoryIterator($path)as$f)if(!$f->isDot())$remove($f->getPathname());rmdir($path);};$remove($root);
}
