<?php
// Standalone synthetic filesystem/ZIP/proof checks. Never loads site config/PDO.
$helper=$argv[1]??__DIR__.'/../scripts/upgrade-cpanel-jivie.php';
$source=file_get_contents($helper);if($source===false)throw new RuntimeException('Missing helper');
$root=sys_get_temp_dir().'/jivie-upgrade-test-'.bin2hex(random_bytes(8));mkdir($root,0700);
$source=str_replace(['/home/tripar13/jivie-test.triparna.si','/home/tripar13/private/jivie-test'],[$root.'/site',$root.'/private'],$source);
$boundary=strpos($source,"try{\n    \$mode=");if($boundary===false)throw new RuntimeException('Helper boundary changed');
eval(substr($source,5,$boundary-5));
$checks=0;
function check($value,$description){global$checks;if(!$value)throw new RuntimeException('FAIL: '.$description);$checks++;echo 'PASS: '.$description.PHP_EOL;}
function reject($callback,$description){$rejected=false;try{$callback();}catch(Throwable$e){$rejected=true;}check($rejected,$description);}
try{
 directory(SITE);directory(BASE);directory(WORK);directory(WORK.'/backup');directory(WORK.'/backup/private');
 writePrivate(WORK.'/backup/private/config.php',"<?php // synthetic configuration only\n");
 check((fileperms(WORK.'/backup/private/config.php')&0077)===0,'private files have no group/world access');
 reject(fn()=>writePrivate(WORK.'/backup/private/config.php','overwrite'),'existing private file cannot be overwritten implicitly');
 replacePrivate(WORK.'/backup/private/config.php','synthetic configuration');
 check(bytes(WORK.'/backup/private/config.php')==='synthetic configuration','atomic replace retains exact bytes');
 copyTree(WORK.'/backup/private',WORK.'/copied');check(inventory(WORK.'/copied')===inventory(WORK.'/backup/private'),'private tree copied with exact inventory hashes');
 symlink(WORK.'/backup/private/config.php',WORK.'/copied/link');reject(fn()=>inventory(WORK.'/copied'),'symlink in private tree rejected');unlink(WORK.'/copied/link');
 $crons="MAILTO=synthetic@example.invalid\r\n* * * * * php /another/site/reminders.php\n";
 foreach(['reminders.php','delivery.php','account-mail.php','account-deletion-cleanup.php']as$file)$crons.='* * * * * php '.SITE.'/plugins/FamilyHub/cli/'.$file."\n";
 writePrivate(ORIGINAL,$crons);pauseCandidate();$paused=bytes(PAUSED);
 check(substr_count($paused,'# Jivie upgrade paused: ')===4,'only exact four staging crons paused');
 check(str_replace('# Jivie upgrade paused: ','',$paused)===$crons,'original cron bytes including unrelated job and CRLF retained');
 writePrivate(CURRENT,$paused);writePrivate(WORK.'/crontab.paused-applied','proof');cronProof();check(true,'exact paused cron proof accepted');
 replacePrivate(CURRENT,$paused."# change\n");reject(fn()=>cronProof(),'changed cron proof rejected');
 writePrivate(SITE.'/.htaccess',"# existing rules\nRewriteEngine On\n");$old=bytes(SITE.'/.htaccess');maintenance();
 check(str_ends_with(bytes(SITE.'/.htaccess'),$old),'maintenance preserves original rules byte exactly');
 check(base64_decode(data(WORK.'/htaccess.original')['bytes'],true)===$old,'original maintenance restore bytes captured privately');
 $before=['schema'=>10,'serverId'=>'synthetic-server','accountHash'=>'account','passwordHash'=>'password','enrollmentHash'=>'enrollment','bootstrapClosed'=>true,'tables'=>['users'=>['columns'=>['id','password'],'rows'=>2,'sha256'=>'table-hash']]];
 $state=['sqlSha'=>'sql','privateSha'=>'private','before'=>$before];$files=inventory(WORK.'/backup/private');
 $proof=['verifiedInIsolatedLocalDb'=>true,'sqlSha'=>'sql','privateSha'=>'private','serverId'=>'synthetic-server','restoredSnapshot'=>$before,'restoredPrivateInventory'=>$files];
 validateRestoreProof($proof,$state,$files);check(true,'complete isolated restore proof accepted');
 foreach(['schema','serverId','accountHash','passwordHash','enrollmentHash','bootstrapClosed','tables']as$key){$bad=$proof;$bad['restoredSnapshot'][$key]='changed';reject(fn()=>validateRestoreProof($bad,$state,$files),'changed restored '.$key.' rejected');}
 foreach(['verifiedInIsolatedLocalDb','sqlSha','privateSha','serverId','restoredPrivateInventory']as$key){$bad=$proof;unset($bad[$key]);reject(fn()=>validateRestoreProof($bad,$state,$files),'missing proof '.$key.' rejected');}
 $zip=new ZipArchive();$zip->open(ARCHIVE,ZipArchive::CREATE|ZipArchive::EXCL);$zip->addFromString('FamilyHub/Plugin.php',"<?php echo 'synthetic';\n");$zip->close();manifestLocal(ARCHIVE,MANIFEST);verifyBundle();check(true,'explicit ZIP manifest and PHP syntax accepted');
 $manifest=data(MANIFEST);$bad=$manifest;$bad['files']['FamilyHub/Plugin.php']=str_repeat('0',64);replacePrivate(MANIFEST,json($bad));reject(fn()=>verifyBundle(),'modified staged source hash rejected');replacePrivate(MANIFEST,json($manifest));
 $zip=new ZipArchive();$zip->open(ARCHIVE);$zip->addFromString('FamilyHub/../escape.php','synthetic');$zip->close();unlink(MANIFEST);manifestLocal(ARCHIVE,MANIFEST);reject(fn()=>verifyBundle(),'ZIP traversal path rejected');
 echo 'SUCCESS '.$checks." upgrade helper checks (synthetic, no DB/site connection)\n";
}catch(Throwable$e){echo "FAIL: ".get_class($e)." ".$e->getMessage()."\n";throw $e;}finally{
 $remove=function($path)use(&$remove){if(is_link($path)||is_file($path)){unlink($path);return;}foreach(new DirectoryIterator($path)as$f){if(!$f->isDot())$remove($f->getPathname());}rmdir($path);};$remove($root);
}
