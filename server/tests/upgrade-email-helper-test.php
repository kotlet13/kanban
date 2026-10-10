<?php
// Standalone synthetic filesystem/ZIP/proof checks. Never loads site config/PDO.
$helper=$argv[1]??__DIR__.'/../scripts/upgrade-cpanel-jivie-email.php';
$source=file_get_contents($helper);if($source===false)throw new RuntimeException('Missing helper');
$root=sys_get_temp_dir().'/jivie-email-upgrade-test-'.bin2hex(random_bytes(8));mkdir($root,0700);
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
 foreach(['reminders.php','delivery.php','account-mail.php','account-deletion-cleanup.php','push.php']as$file)$crons.='* * * * * php '.SITE.'/plugins/FamilyHub/cli/'.$file."\n";
 writePrivate(ORIGINAL,$crons);pauseCandidate();$paused=bytes(PAUSED);
 check(substr_count($paused,'# Jivie upgrade paused: ')===5,'only exact five staging crons paused');
 check(str_replace('# Jivie upgrade paused: ','',$paused)===$crons,'original cron bytes including unrelated job and CRLF retained');
 writePrivate(CURRENT,$paused);writePrivate(WORK.'/crontab.paused-applied','proof');cronProof();check(true,'exact paused cron proof accepted');
 replacePrivate(CURRENT,$paused."# change\n");reject(fn()=>cronProof(),'changed cron proof rejected');
 writePrivate(SITE.'/.htaccess',"# existing rules\nRewriteEngine On\n");$old=bytes(SITE.'/.htaccess');maintenance();
 check(str_ends_with(bytes(SITE.'/.htaccess'),$old),'maintenance preserves original rules byte exactly');
 check(base64_decode(data(WORK.'/htaccess.original')['bytes'],true)===$old,'original maintenance restore bytes captured privately');
 $before=['schema'=>13,'serverId'=>'synthetic-server','accountHash'=>'account','passwordHash'=>'password','enrollmentHash'=>'enrollment','bootstrapClosed'=>true,'tables'=>['users'=>['columns'=>['id','password'],'rows'=>2,'sha256'=>'table-hash']]];
 $state=['sqlSha'=>'sql','privateSha'=>'private','before'=>$before];$files=inventory(WORK.'/backup/private');
 $proof=['verifiedInIsolatedLocalDb'=>true,'sqlSha'=>'sql','privateSha'=>'private','serverId'=>'synthetic-server','restoredSnapshot'=>$before,'restoredPrivateInventory'=>$files];
 validateRestoreProof($proof,$state,$files);check(true,'complete isolated restore proof accepted');
 foreach(['schema','serverId','accountHash','passwordHash','enrollmentHash','bootstrapClosed','tables']as$key){$bad=$proof;$bad['restoredSnapshot'][$key]='changed';reject(fn()=>validateRestoreProof($bad,$state,$files),'changed restored '.$key.' rejected');}
 foreach(['verifiedInIsolatedLocalDb','sqlSha','privateSha','serverId','restoredPrivateInventory']as$key){$bad=$proof;unset($bad[$key]);reject(fn()=>validateRestoreProof($bad,$state,$files),'missing proof '.$key.' rejected');}
 copy($argv[2]??'/tmp/FamilyHub-0.10.0-email-source-final.zip',ARCHIVE);chmod(ARCHIVE,0600);
 manifestLocal(ARCHIVE,MANIFEST);$manifest=verifyBundle();check(isset($manifest['files']['FamilyHub/Schema/EmailInvitationSchema.php'])&&count($manifest['files'])>70,'pinned reviewed ZIP and PHP syntax accepted');
 $bad=$manifest;$bad['files']['FamilyHub/Plugin.php']=str_repeat('0',64);replacePrivate(MANIFEST,json($bad));reject(fn()=>verifyBundle(),'modified staged source hash rejected');replacePrivate(MANIFEST,json($manifest));
 $bad=$manifest;$bad['schemaVersion']=13;replacePrivate(MANIFEST,json($bad));reject(fn()=>verifyBundle(),'old target schema manifest rejected');replacePrivate(MANIFEST,json($manifest));
 $bad=$manifest;$bad['pluginVersion']='0.9.0';replacePrivate(MANIFEST,json($bad));reject(fn()=>verifyBundle(),'old target version manifest rejected');replacePrivate(MANIFEST,json($manifest));
 $zip=new ZipArchive();$zip->open(ARCHIVE);$zip->addFromString('FamilyHub/../escape.php','synthetic');$zip->close();unlink(MANIFEST);manifestLocal(ARCHIVE,MANIFEST);reject(fn()=>verifyBundle(),'modified archive rejected despite regenerated manifest');
 restoreMaintenance();check(bytes(SITE.'/.htaccess')===$old,'maintenance restores original htaccess bytes exactly');
 unlink(PAUSED);replacePrivate(ORIGINAL,$crons.'* * * * * php '.SITE.'/plugins/FamilyHub/cli/push.php'."\n");reject(fn()=>pauseCandidate(),'six staging workers cannot be silently paused');
 replacePrivate(ORIGINAL,str_replace('cli/push.php','cli/reminders.php',$crons));reject(fn()=>pauseCandidate(),'duplicate reminder with missing push rejected despite total five lines');
 echo 'SUCCESS '.$checks." upgrade helper checks (synthetic, no DB/site connection)\n";
}catch(Throwable$e){echo "FAIL: ".get_class($e)." ".$e->getMessage()."\n";throw $e;}finally{
 $remove=function($path)use(&$remove){if(is_link($path)||is_file($path)){unlink($path);return;}foreach(new DirectoryIterator($path)as$f){if(!$f->isDot())$remove($f->getPathname());}rmdir($path);};$remove($root);
}
