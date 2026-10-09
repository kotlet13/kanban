<?php
// Dedicated disposable databases inside the local synthetic MariaDB fixture only.
$source=file_get_contents($argv[1]??'/tmp/upgrade-cpanel-jivie-spaces.php');
$root=sys_get_temp_dir().'/jivie-spaces-db-test-'.bin2hex(random_bytes(8));mkdir($root,0700);
$source=str_replace(['/home/tripar13/jivie-test.triparna.si','/home/tripar13/private/jivie-test'],[$root.'/site',$root.'/private'],$source);
$boundary=strpos($source,"try{\n    \$mode=");eval(substr($source,5,$boundary-5));
require '/var/www/app/plugins/FamilyHub/Schema/SpacesSchema.php';
require '/var/www/app/plugins/FamilyHub/Schema/LinkedPaymentsSchema.php';
$checks=0;
function check($ok,$name){global$checks;if(!$ok)throw new RuntimeException('Failed check');$checks++;echo 'PASS: '.$name."\n";}
function reject($fn,$name){try{$fn();}catch(Throwable $e){check(true,$name);return;}throw new RuntimeException('Expected rejection');}
$db='jivie_spaces_helper_'.bin2hex(random_bytes(6));$restore=$db.'_restore';
$admin=new PDO('mysql:host=database;charset=utf8mb4','root','familyhub-root-development-only',[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION]);
try{
 foreach([$db,$restore]as$name)$admin->exec('CREATE DATABASE '.identifier($name).' CHARACTER SET utf8mb4');
 $pdo=new PDO('mysql:host=database;dbname='.$db.';charset=utf8mb4','root','familyhub-root-development-only',[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION]);
 $pdo->exec("CREATE TABLE plugin_schema_versions (plugin VARCHAR(40) PRIMARY KEY,version INT NOT NULL) ENGINE=InnoDB");
 $pdo->exec("INSERT INTO plugin_schema_versions VALUES ('familyhub',11),('unrelated',2)");
 $pdo->exec("CREATE TABLE familyhub_scopes (id VARCHAR(36) PRIMARY KEY,name VARCHAR(255)) ENGINE=InnoDB");
 $pdo->exec("INSERT INTO familyhub_scopes VALUES ('scope','Sintetični prostor')");
 $pdo->exec("CREATE TABLE synthetic_records (id INT PRIMARY KEY,amount DECIMAL(30,2),payload LONGBLOB,nullable VARCHAR(20)) ENGINE=InnoDB");
 $binary="synthetic\0'\\\xff";$pdo->prepare('INSERT INTO synthetic_records VALUES (1,?,?,NULL)')->execute(['9007199254740993.12',$binary]);
 $before=['tables'=>tableState($pdo)];$cols=array_map(fn($table)=>$table['columns'],$before['tables']);
 $dump=$root.'/dump.sql';dumpDatabase($pdo,$dump);
 $restored=new PDO('mysql:host=database;dbname='.$restore.';charset=utf8mb4','root','familyhub-root-development-only',[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION]);
 $restored->exec(bytes($dump));
 check(tableState($restored)===$before['tables'],'binary/null/large decimal/private SQL dump restored with exact hashes');
 \Kanboard\Plugin\FamilyHub\Schema\SpacesSchema::create($pdo,true);
 \Kanboard\Plugin\FamilyHub\Schema\LinkedPaymentsSchema::create($pdo,true);
 $pdo->exec("UPDATE plugin_schema_versions SET version=13 WHERE plugin='familyhub' AND version=11");
 check(tableState($pdo,$cols)===$before['tables'],'historic columns compared without false failures from five new tables');
 validateNewSchema($pdo,$before);check(true,'schema12/13 migration preserves policy1 and creates exact five empty tables');
 $pdo->exec("UPDATE familyhub_scopes SET access_policy_version=2");reject(fn()=>validateNewSchema($pdo,$before),'historic policy widening rejected');$pdo->exec("UPDATE familyhub_scopes SET access_policy_version=1");
 $pdo->exec("INSERT INTO familyhub_organization_leaders VALUES ('scope','account')");reject(fn()=>validateNewSchema($pdo,$before),'new organization leader rows rejected');$pdo->exec('DELETE FROM familyhub_organization_leaders');
 $pdo->exec('CREATE TABLE unexpected (id INT) ENGINE=InnoDB');reject(fn()=>validateNewSchema($pdo,$before),'unexpected added migration table rejected');$pdo->exec('DROP TABLE unexpected');
 directory(SITE);directory(SITE.'/plugins');directory(SITE.'/plugins/FamilyHub');writePrivate(SITE.'/plugins/FamilyHub/Plugin.php','synthetic');directory(BASE);directory(WORK);
 writePrivate(ORIGINAL,'original');writePrivate(PAUSED,'paused');writePrivate(CURRENT,'paused');
 $state=['phase'=>'snapshot','configHashes'=>[],'codeHashes'=>inventory(SITE.'/plugins/FamilyHub')];
 reject(fn()=>abortGuard($pdo,$state),'abort after migrated schema13 rejected');$pdo->exec("UPDATE plugin_schema_versions SET version=11 WHERE plugin='familyhub'");
 abortGuard($pdo,$state);check(true,'abort before activation accepts only original code schema11 and own paused crons');
 $bad=$state;$bad['phase']='healthy';reject(fn()=>abortGuard($pdo,$bad),'abort healthy deployment rejected');
 replacePrivate(CURRENT,'unrelated edit');reject(fn()=>abortGuard($pdo,$state),'abort refuses to overwrite later cron edits');replacePrivate(CURRENT,'original');
 replacePrivate(SITE.'/plugins/FamilyHub/Plugin.php','changed');reject(fn()=>abortGuard($pdo,$state),'abort refuses changed application code');
 echo 'SUCCESS '.$checks." upgrade helper DB checks (local synthetic MariaDB only)\n";
}finally{
 foreach([$db,$restore]as$name)$admin->exec('DROP DATABASE '.identifier($name));
 $remove=function($path)use(&$remove){if(is_link($path)||is_file($path)){unlink($path);return;}foreach(new DirectoryIterator($path)as$f)if(!$f->isDot())$remove($f->getPathname());rmdir($path);};$remove($root);
}
