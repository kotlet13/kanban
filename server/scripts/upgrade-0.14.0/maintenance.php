<?php
if(PHP_SAPI!=='cli'){http_response_code(404);exit;}
ini_set('display_errors','0');ini_set('log_errors','0');error_reporting(0);umask(0077);
function stop(string $code):never{throw new RuntimeException($code);}
set_error_handler(static function():never{stop('filesystem_warning');});
require __DIR__.'/deployment.php';
function bytes(string $p):string{if(is_link($p)||!is_file($p))stop('file_guard');$b=file_get_contents($p);if(!is_string($b))stop('file_read');return $b;}
function writePrivate(string $p,string $b,int $mode=0600):void{if(file_exists($p)||is_link($p))stop('exclusive_destination');$f=fopen($p,'xb');if(!$f)stop('exclusive_create');try{if(fwrite($f,$b)!==strlen($b)||!fflush($f))stop('write_failed');}finally{fclose($f);}chmod($p,$mode);}
require WORK.'/maintenance-guards.php';require WORK.'/delivery-guards.php';
try{
 if(realpath(SITE)!==SITE||realpath(WORK)!==WORK||(fileperms(WORK)&0077)!==0||hash('sha256',bytes(CONFIG))!==CONFIG_SHA)stop('fixed_site_config_guard');
 require CONFIG;deliveryGuard();$mode=$argv[1]??'';
 if($mode==='--prepare'){
  if(hash('sha256',bytes(WORK.'/crontab.original'))!==CRON_SHA)stop('fresh_captured_cron_changed');if($argc!==2||hash('sha256',bytes(SITE.'/.htaccess'))!==HTACCESS_SHA)stop('original_https_guard');
  $scripts=['reminders.php','delivery.php','account-mail.php','account-deletion-cleanup.php','push.php'];$counts=array_fill_keys($scripts,0);$out='';
  foreach(preg_split('/(?<=\n)/',bytes(WORK.'/crontab.original'),-1,PREG_SPLIT_NO_EMPTY)as$line){$matches=[];if(!str_starts_with(ltrim($line),'#'))foreach($scripts as$script)if(preg_match('~'.preg_quote(SITE.'/plugins/FamilyHub/cli/'.$script,'~').'(?=\s|$)~',$line))$matches[]=$script;if(count($matches)>1)stop('combined_cron_rejected');if($matches){$counts[$matches[0]]++;$out.='# Jivie review upgrade paused: '.$line;}else$out.=$line;}
  foreach($counts as$count)if($count!==1)stop('exact_five_crons_required');
  writePrivate(WORK.'/crontab.paused',$out);writePrivate(WORK.'/htaccess.original',bytes(SITE.'/.htaccess'));
  echo "Exact original cron/HTTPS retained; five-worker pause candidate prepared. Site unchanged.\n";
 }elseif($mode==='--pause'){
  if($argc!==2||hash('sha256',bytes(WORK.'/crontab.current'))!==hash('sha256',bytes(WORK.'/crontab.paused'))||hash('sha256',bytes(SITE.'/.htaccess'))!==HTACCESS_SHA)stop('pause_guard');
  $text="# JIVIE REVIEW UPGRADE MAINTENANCE\nRewriteEngine On\nRewriteRule ^ - [R=503,L]\n".bytes(WORK.'/htaccess.original');
  writePrivate(WORK.'/maintenance.sha256',hash('sha256',$text));writePrivate(WORK.'/maintenance.started',(string)time());$tmp=SITE.'/.htaccess.review-pause';writePrivate($tmp,$text,0644);if(!rename($tmp,SITE.'/.htaccess'))stop('maintenance_activate');
  $h=curl_init(PUBLIC_URL.'/index.php');curl_setopt_array($h,[CURLOPT_RETURNTRANSFER=>true,CURLOPT_FOLLOWLOCATION=>false,CURLOPT_CONNECTTIMEOUT=>10,CURLOPT_TIMEOUT=>20,CURLOPT_SSL_VERIFYPEER=>true,CURLOPT_SSL_VERIFYHOST=>2]);$b=curl_exec($h);$status=curl_getinfo($h,CURLINFO_HTTP_CODE);curl_close($h);if($b===false||$status!==503)stop('https_503_required');
  echo "Five test1 worker crons paused and HTTPS503 verified. Wait 65 actual seconds.\n";
 }else stop('usage_guard');
}catch(Throwable $e){$c=$e instanceof RuntimeException&&preg_match('/^[a-z0-9_]+$/D',$e->getMessage())?$e->getMessage():'private_diagnostic_required';fwrite(STDERR,"Lifecycle18 maintenance stopped: $c. Preserve files; no credentials printed.\n");exit(1);}
