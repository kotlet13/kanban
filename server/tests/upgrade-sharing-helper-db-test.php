<?php
// Unique disposable databases in the local synthetic MariaDB fixture only.
$helper=$argv[1]??'/tmp/upgrade-cpanel-jivie-sharing.php';
$source=file_get_contents($helper);
$root=sys_get_temp_dir().'/jivie-sharing-db-test-'.bin2hex(random_bytes(8));mkdir($root,0700);
$source=str_replace(['/home/tripar13/jivie-test.triparna.si','/home/tripar13/private/jivie-test'],[$root.'/site',$root.'/private'],$source);
$boundary=strpos($source,"try{\n    \$mode=");if($boundary===false)throw new RuntimeException('Helper boundary changed');
eval(substr($source,5,$boundary-5));
require '/var/www/app/plugins/FamilyHub/Schema/SharingSchema.php';
$checks=0;
function check($ok,$name){global$checks;if(!$ok)throw new RuntimeException('Failed check: '.$name);$checks++;echo 'PASS: '.$name."\n";}
function reject($fn,$name){try{$fn();}catch(Throwable $e){check(true,$name);return;}throw new RuntimeException('Expected rejection: '.$name);}
$db='jivie_sharing_helper_'.bin2hex(random_bytes(6));$restore=$db.'_restore';
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
 $before=snapshot($pdo);$cols=array_map(fn($table)=>$table['columns'],$before['tables']);
 $dump=$root.'/dump.sql';dumpDatabase($pdo,$dump);
 $restored=new PDO('mysql:host=database;dbname='.$restore.';charset=utf8mb4','root','familyhub-root-development-only',[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION]);
 $restored->exec(bytes($dump));
 check(snapshot($restored)===$before,'schema14 private SQL restores every table/identity/password/token/body/binary/null/large decimal exactly');
 \Kanboard\Plugin\FamilyHub\Schema\SharingSchema::create($pdo,true);
 $pdo->exec("UPDATE plugin_schema_versions SET version=15 WHERE plugin='familyhub' AND version=14");
 check(tableState($pdo,$cols)===$before['tables'],'schema15 preserves all historic table columns and sentinel request/token data');
 $after=snapshot($pdo);
 foreach(['serverId','accountHash','passwordHash','enrollmentHash']as$field)check($after[$field]===$before[$field],'schema15 retains '.$field);
 check($after['schema']===15,'only FamilyHub schema version advances14 to15');
 validateNewSchema($pdo,$before);check(true,'migration creates exactly empty relocation table, copied parent and original invitation defaults');
 check(query($pdo,"SELECT id,organization_access_policy FROM familyhub_scopes ORDER BY id")===query($restored,"SELECT id,organization_access_policy FROM familyhub_scopes ORDER BY id"),'historic policy1 and policy2 never silently advance');
 check(query($pdo,"SELECT id,parent_scope_id FROM familyhub_scopes WHERE organization_id IS NOT NULL ORDER BY id")===[['id'=>'project-one','parent_scope_id'=>'org-one'],['id'=>'project-two','parent_scope_id'=>'org-two']],'only explicit historical organization parents copied');
 $afterFirst=snapshot($pdo);\Kanboard\Plugin\FamilyHub\Schema\SharingSchema::create($pdo,true);check(snapshot($pdo)===$afterFirst,'repeated sharing migration preserves full data and original policies');
 $pdo->exec("UPDATE familyhub_invitations SET invitation_contract=3 WHERE id='old-invite'");reject(fn()=>validateNewSchema($pdo,$before),'historic invitation contract expansion rejected');$pdo->exec("UPDATE familyhub_invitations SET invitation_contract=1 WHERE id='old-invite'");
 $pdo->exec("UPDATE familyhub_invitations SET access_scope='space' WHERE id='old-invite'");reject(fn()=>validateNewSchema($pdo,$before),'historic invitation scope expansion rejected');$pdo->exec('UPDATE familyhub_invitations SET access_scope=NULL');
 $pdo->exec("UPDATE familyhub_scopes SET parent_scope_id='org-one' WHERE id='household'");reject(fn()=>validateNewSchema($pdo,$before),'inferred household parent rejected');$pdo->exec("UPDATE familyhub_scopes SET parent_scope_id=NULL WHERE id='household'");
 $pdo->exec("UPDATE familyhub_scopes SET parent_scope_id=NULL WHERE id='project-two'");reject(fn()=>validateNewSchema($pdo,$before),'lost explicit project parent rejected');$pdo->exec("UPDATE familyhub_scopes SET parent_scope_id='org-two' WHERE id='project-two'");
 $pdo->exec("INSERT INTO familyhub_record_relocations VALUES ('org-one','synthetic-record',0,'project-one')");reject(fn()=>validateNewSchema($pdo,$before),'automatic record relocation during migration rejected');$pdo->exec('DELETE FROM familyhub_record_relocations');
 $pdo->exec('CREATE TABLE unexpected (id INT) ENGINE=InnoDB');reject(fn()=>validateNewSchema($pdo,$before),'unexpected added table rejected');$pdo->exec('DROP TABLE unexpected');
 $pdo->exec('ALTER TABLE synthetic_records ADD COLUMN unwanted INT DEFAULT NULL');reject(fn()=>validateNewSchema($pdo,$before),'unreviewed new column on historic table rejected');$pdo->exec('ALTER TABLE synthetic_records DROP COLUMN unwanted');
 $pdo->exec('DROP INDEX familyhub_scope_parent ON familyhub_scopes');reject(fn()=>validateNewSchema($pdo,$before),'missing parent lookup index rejected');$pdo->exec('CREATE INDEX familyhub_scope_parent ON familyhub_scopes(parent_scope_id)');
 $pdo->exec('ALTER TABLE familyhub_record_relocations DROP PRIMARY KEY');reject(fn()=>validateNewSchema($pdo,$before),'missing relocation primary key rejected');$pdo->exec('ALTER TABLE familyhub_record_relocations ADD PRIMARY KEY(scope_id,record_id,finance)');
 $pdo->exec("UPDATE familyhub_scopes SET organization_access_policy=3 WHERE id='org-two'");check(tableState($pdo,$cols)!==$before['tables'],'silent policy2 expansion detected by full historic hash');$pdo->exec("UPDATE familyhub_scopes SET organization_access_policy=2 WHERE id='org-two'");
 $pdo->exec("UPDATE familyhub_invitations SET token_hash='changed-token' WHERE id='old-invite'");check(tableState($pdo,$cols)!==$before['tables'],'historic pending token mutation detected');$pdo->exec("UPDATE familyhub_invitations SET token_hash='sentinel-token-hash' WHERE id='old-invite'");
 $pdo->exec("UPDATE familyhub_invitations SET request_hash='changed-body' WHERE id='old-invite'");check(tableState($pdo,$cols)!==$before['tables'],'historic pending request-body mutation detected');$pdo->exec("UPDATE familyhub_invitations SET request_hash='sentinel-body-hash' WHERE id='old-invite'");
 directory(SITE);directory(SITE.'/plugins');directory(SITE.'/plugins/FamilyHub');writePrivate(SITE.'/plugins/FamilyHub/Plugin.php','synthetic-prior-code');directory(BASE);directory(WORK);
 writePrivate(ORIGINAL,'original');writePrivate(PAUSED,'paused');writePrivate(CURRENT,'paused');
 $state=['phase'=>'snapshot','configHashes'=>[],'codeHashes'=>inventory(SITE.'/plugins/FamilyHub')];
 reject(fn()=>abortGuard($pdo,$state),'abort after schema15 migration rejected');$pdo->exec("UPDATE plugin_schema_versions SET version=14 WHERE plugin='familyhub'");
 abortGuard($pdo,$state);check(true,'abort accepts original code schema14 and its own paused cron');
 $bad=$state;$bad['phase']='healthy';reject(fn()=>abortGuard($pdo,$bad),'abort healthy deployment rejected');
 replacePrivate(CURRENT,'later-cron-edit');reject(fn()=>abortGuard($pdo,$state),'abort refuses later cron edits');replacePrivate(CURRENT,'original');
 replacePrivate(SITE.'/plugins/FamilyHub/Plugin.php','changed-code');reject(fn()=>abortGuard($pdo,$state),'abort refuses changed prior code');
 echo 'SUCCESS '.$checks." sharing upgrade helper DB checks (local synthetic MariaDB only)\n";
}finally{
 foreach([$db,$restore]as$name)$admin->exec('DROP DATABASE '.identifier($name));
 $remove=function($path)use(&$remove){if(is_link($path)||is_file($path)){unlink($path);return;}foreach(new DirectoryIterator($path)as$f)if(!$f->isDot())$remove($f->getPathname());rmdir($path);};$remove($root);
}
