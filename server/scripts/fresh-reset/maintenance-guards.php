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
 if(hash('sha256',bytes(WORK.'/crontab.current'))!==hash('sha256',bytes(WORK.'/crontab.paused')))stop('six_worker_crons_not_paused');
 if(trim(bytes(WORK.'/workers.drained'))!==hash('sha256',bytes(WORK.'/crontab.paused'))||time()-filemtime(WORK.'/workers.drained')>120)stop('fresh_worker_drain_proof_required');
}
