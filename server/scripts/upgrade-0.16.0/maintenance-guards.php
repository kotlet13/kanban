<?php
// Included only by guarded CLI helpers. Never bootstrap the application or workers.
if(PHP_SAPI!=='cli'){http_response_code(404);exit;}
function maintenanceGuard():void{
 deliveryGuard();
 if((hash('sha256',bytes(CONFIG))!==CONFIG_SHA&&hash('sha256',bytes(CONFIG))!==CONFIG_ENABLED_SHA)||hash('sha256',bytes(WORK.'/htaccess.original'))!==HTACCESS_SHA||hash('sha256',bytes(SITE.'/.htaccess'))!==trim(bytes(WORK.'/maintenance.sha256')))stop('maintenance_config_or_https_changed');
 if(time()-(int)trim(bytes(WORK.'/maintenance.started'))<65)stop('drain_65_seconds_required');
}
function originalCronGuard():void{
 if(hash('sha256',bytes(WORK.'/crontab.original'))!==CRON_SHA)stop('captured_original_cron_changed');
 if(hash('sha256',bytes(WORK.'/crontab.current'))!==hash('sha256',bytes(WORK.'/crontab.original')))stop('original_cron_not_restored');
}
function pausedGuard():void{
 maintenanceGuard();
 if(hash('sha256',bytes(WORK.'/crontab.original'))!==CRON_SHA)stop('captured_original_cron_changed');
 if(hash('sha256',bytes(WORK.'/crontab.current'))!==hash('sha256',bytes(WORK.'/crontab.paused')))stop('five_worker_crons_not_paused');
 if(trim(bytes(WORK.'/workers.drained'))!==hash('sha256',bytes(WORK.'/crontab.paused'))||time()-filemtime(WORK.'/workers.drained')>120)stop('fresh_worker_drain_proof_required');
}

function upgradedCron(string $original):string{
 if(str_contains($original,SITE.'/plugins/FamilyHub/cli/security-mail.php'))stop('security_cron_already_present');
 return $original.(str_ends_with($original,"\n")?'':"\n")."* * * * * /usr/bin/timeout 50s /opt/alt/php84/usr/bin/php ".SITE."/plugins/FamilyHub/cli/security-mail.php 1 >/dev/null 2>&1\n";
}
function releaseCronGuard():void{
 if(hash('sha256',bytes(WORK.'/crontab.original'))!==CRON_SHA)stop('captured_original_cron_changed');
 $candidate=bytes(WORK.'/crontab.upgraded');if($candidate!==upgradedCron(bytes(WORK.'/crontab.original'))||bytes(WORK.'/crontab.current')!==$candidate)stop('release_cron_candidate_guard');
}
