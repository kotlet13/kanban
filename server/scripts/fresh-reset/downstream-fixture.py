#!/usr/bin/env python3
"""Distinct downstream synthetic pins; capture fixture remains STOP3 and is never invoked."""
from pathlib import Path
import hashlib,json,os,secrets,shutil,subprocess,time,sys
os.umask(0o077);D=Path(__file__).resolve().parent;R=D.parents[2]
P=Path('/Users/anzenovsak/.local/share/jivie/backups/fresh-reset23-fixtures');P.mkdir(parents=True,exist_ok=True,mode=0o700);P.chmod(0o700)
M=P/('downstream-'+secrets.token_hex(4));M.mkdir(mode=0o700);H=M/'home';S=H/'jivie-test.triparna.si';S.parent.mkdir();B=H/'private/jivie-test';B.mkdir(parents=True,mode=0o700);B.parent.chmod(0o700);DATA=B/'data';DATA.mkdir(mode=0o700)
name='jivie-reset-op-'+secrets.token_hex(4);db=name+'-db';runner=name+'-php';restore=name+'-restore';copy=name+'-copy';owned=[];events=[]
def run(args,data=None):return subprocess.run(args,input=data,text=True,capture_output=True)
def record(stage,p):
 events.append({'stage':stage,'exitCode':p.returncode,'stdout':p.stdout,'stderr':p.stderr})
 if p.returncode:raise RuntimeError(stage)
 return p
def ready(n):
 for _ in range(50):
  if run(['docker','exec',n,'mariadb-admin','--protocol=tcp','-h127.0.0.1','ping','-uroot','--silent']).returncode==0:return
  time.sleep(1)
 raise RuntimeError('fresh_db_startup')
def php(args):return run(['docker','exec',runner,'php']+args)
def fail(stage,p,code):
 events.append({'stage':stage,'exitCode':p.returncode,'guarded':p.returncode==1 and code in p.stderr,'stderr':p.stderr})
 if p.returncode!=1 or code not in p.stderr:raise RuntimeError(stage)
def h(b):return hashlib.sha256(b).hexdigest()
try:
 record('fresh-core-copy-container',run(['docker','create','--name',copy,'--network','none','jivie-crypto23-upgrade-fixture:20261028']));owned.append(copy)
 S.mkdir();record('copy-only-core-fixture',run(['docker','cp',copy+':/var/www/app/.',str(S)]));record('remove-copy-container',run(['docker','rm','-v',copy]));owned.remove(copy)
 if (S/'plugins/FamilyHub').exists():shutil.rmtree(S/'plugins/FamilyHub')
 shutil.copytree(R/'server/plugins/FamilyHub',S/'plugins/FamilyHub');shutil.copy2(R/'tools/plugin_release/PUBLIC_NOTICE.md',S/'plugins/FamilyHub/NOTICE.md');(S/'plugins/FamilyHub/docs').mkdir(exist_ok=True)
 for n in ['account-deletion-contract.md','spaces-api-contract.md','linked-payments-api-contract.md','email-invitation-api-contract.md','space-sharing-api-contract.md','moderation-api-contract.md','ideas-api-contract.md','scope-lifecycle-api-contract.md']:shutil.copy2(R/'docs/server'/n,S/'plugins/FamilyHub/docs'/n)
 for n in ['files','cache','files/empty','familyhub','familyhub/attachments','familyhub/ideas','familyhub/ideas/empty']:(DATA/n).mkdir(mode=0o700)
 for n,b in [('files/core.bin',bytes(range(256))),('familyhub/attachments/probe',b'old attachment\0'),('familyhub/ideas/probe',b'old idea\xff')]: (DATA/n).write_bytes(b);(DATA/n).chmod(0o600)
 (B/'fake-private.key').write_bytes(bytes(range(32)));(B/'fake-private.key').chmod(0o600)
 cfg="<?php\ndefine('DB_DRIVER','mysql');define('DB_HOSTNAME','127.0.0.1');define('DB_NAME','tripar13_jivietest');define('DB_USERNAME','root');define('DB_PASSWORD','');define('DATA_DIR','/home/tripar13/private/jivie-test/data');define('FILES_DIR',DATA_DIR.'/files');define('CACHE_DIR',DATA_DIR.'/cache');define('FAMILYHUB_ENABLE_NATIVE_API',true);define('FAMILYHUB_ENABLE_PROJECT_INVITATIONS',false);define('FAMILYHUB_ACCOUNT_MODE','self_hosted');define('FAMILYHUB_ENABLE_CRYPTO_PREVIEW',true);\n"
 (S/'config.php').write_text(cfg);(S/'config.php').chmod(0o600);(S/'.htaccess').write_bytes(b'# synthetic original HTTPS rules\n');(S/'.htaccess').chmod(0o644);ht=(S/'.htaccess').read_bytes()
 cron=''.join('* * * * * php /home/tripar13/jivie-test.triparna.si/plugins/FamilyHub/cli/'+n+'\n'for n in ['reminders.php','delivery.php','account-mail.php','account-deletion-cleanup.php','push.php','security-mail.php'])+'# unrelated job must remain exact\n'
 (M/'cron').write_text(cron);(M/'cron').chmod(0o600)
 record('fresh-source-db',run(['docker','run','-d','--name',db,'--network','none','-e','MARIADB_ALLOW_EMPTY_ROOT_PASSWORD=yes','-e','MARIADB_DATABASE=tripar13_jivietest','mariadb:10.11.19']));owned.append(db);ready(db)
 record('fresh-php',run(['docker','run','-d','--name',runner,'--network','container:'+db,'-v',str(H)+':/home/tripar13','-v',str(R)+':/source:ro','-v',str(M)+':/fixture-work','--entrypoint','sleep','jivie-crypto23-upgrade-fixture:20261028','3600']));owned.append(runner)
 init="""<?php
 require '/var/www/app/vendor/autoload.php';require '/home/tripar13/jivie-test.triparna.si/config.php';
 spl_autoload_register(function($c){$prefix='Kanboard\\\\Plugin\\\\FamilyHub\\\\';if(str_starts_with($c,$prefix))require '/source/server/plugins/FamilyHub/'.str_replace('\\\\','/',substr($c,strlen($prefix))).'.php';});
 $p=new PDO('mysql:host=127.0.0.1;dbname=tripar13_jivietest;charset=utf8mb4','root','',[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION]);
 require '/var/www/app/app/Schema/Mysql.php';for($v=1;$v<=\\Schema\\VERSION;$v++){$f='Schema\\\\version_'.$v;if(function_exists($f))$f($p);}
 require '/source/server/plugins/FamilyHub/Schema/Mysql.php';for($v=1;$v<=23;$v++)('Kanboard\\\\Plugin\\\\FamilyHub\\\\Schema\\\\version_'.$v)($p);
 $p->exec(\"CREATE TABLE schema_version(version INT DEFAULT '0') ENGINE=InnoDB CHARSET=utf8\");$p->exec('INSERT INTO schema_version VALUES(139)');
 $p->exec(\"INSERT INTO plugin_schema_versions(plugin,version) VALUES('familyhub',23)\");
 $p->exec(\"UPDATE familyhub_instance SET server_id='95c11fe0-916c-48be-a3f6-999732846266'\");
 for($i=2;$i<=4;$i++){$aid=sprintf('%08d-1111-4111-a111-111111111111',$i);$p->prepare(\"INSERT INTO users(id,username,password,role) VALUES(?,?,?,'app-user')\")->execute([$i,'synthetic_'.$i,password_hash('fixture-only',PASSWORD_BCRYPT)]);$p->prepare('INSERT INTO familyhub_accounts VALUES(?,?)')->execute([$i,$aid]);}
 $p->exec(\"INSERT INTO familyhub_scopes(id,kind,name,owner_id,created_at) VALUES('77777777-1111-4111-a111-111111111111','household','fixture',2,1)\");
 $p->exec(\"INSERT INTO familyhub_devices(id,user_id,account_id,name,token_hash,credentials_hash,created_at,expires_at) VALUES('88888888-1111-4111-a111-111111111111',2,'00000002-1111-4111-a111-111111111111','fixture','old_token','old_cred',1,9999999999)\");
 echo 'fresh schema23 synthetic source initialized';
 """
 (M/'init.php').write_text(init);record('initialize-source-complete-distinct-downstream-fixture',php(['/fixture-work/init.php']))
 # Explicit independently known pins. Never invoke the stopped capture.php case.
 pins="""require '/home/tripar13/jivie-test.triparna.si/config.php';require '/source/server/scripts/fresh-reset/ResetDatabase.php';$p=new PDO('mysql:host=127.0.0.1;dbname=tripar13_jivietest;charset=utf8mb4','root','',[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION]);$engine=new FamilyHubFreshReset($p);$source=[];foreach(new RecursiveIteratorIterator(new RecursiveDirectoryIterator('/home/tripar13/jivie-test.triparna.si/plugins/FamilyHub',FilesystemIterator::SKIP_DOTS))as$f)if($f->isFile())$source[substr($f->getPathname(),strlen('/home/tripar13/jivie-test.triparna.si/plugins/FamilyHub/'))]=hash_file('sha256',$f->getPathname());ksort($source);$files=[];foreach(['/home/tripar13/jivie-test.triparna.si/config.php','/home/tripar13/private/jivie-test/fake-private.key']as$file)$files[$file]=['sha256'=>hash_file('sha256',$file),'mode'=>fileperms($file)&0777];ksort($files);$constants=[];foreach(get_defined_constants()as$k=>$v)if(str_starts_with($k,'FAMILYHUB_')&&is_scalar($v))$constants[$k]=$v;unset($constants['FAMILYHUB_ENABLE_CRYPTO_PREVIEW']);ksort($constants);$users=$p->query('SELECT u.id,u.username,u.role FROM users u JOIN familyhub_accounts a ON a.user_id=u.id ORDER BY u.id')->fetchAll(PDO::FETCH_ASSOC);foreach($users as &$u)$u['id']=(int)$u['id'];echo json_encode(['format'=>'fresh-reset23-capture-v1','capturedUtc'=>gmdate('c'),'profile'=>'test1','site'=>'/home/tripar13/jivie-test.triparna.si','base'=>'/home/tripar13/private/jivie-test','config'=>'/home/tripar13/jivie-test.triparna.si/config.php','data'=>DATA_DIR,'database'=>'tripar13_jivietest','serverId'=>'95c11fe0-916c-48be-a3f6-999732846266','schema'=>23,'users'=>$users,'definitions'=>$engine->definitions(),'oldSource'=>$source,'deliveryFiles'=>$files,'deliveryConstantsSha256'=>hash('sha256',serialize($constants)),'configPin'=>$files['/home/tripar13/jivie-test.triparna.si/config.php'],'htaccessPin'=>['sha256'=>hash_file('sha256','/home/tripar13/jivie-test.triparna.si/.htaccess'),'mode'=>0644],'cronSha256'=>hash_file('sha256','/fixture-work/cron'),'fixtureOnlyKnownPinsNotCapturePass'=>true]);"""
 capture=record('known-synthetic-pins-not-capture-test',php(['-r',pins]));(M/'capture.json').write_text(capture.stdout);(M/'capture.json').chmod(0o600)
 sealed=record('seal-current-source-and-schema',run(['python3',str(D/'seal.py'),str(M/'capture.json'),str(M/'sealed')]));meta=json.loads(sealed.stdout);host=meta['hostWork'];W=H/Path(host).relative_to('/home/tripar13');shutil.copytree(M/'sealed',W);W.chmod(0o700);(W/'crontab.original').write_text(cron);(W/'crontab.original').chmod(0o600)
 record('check-full-current-backup',php([host+'/backup.php','--check']));record('prepare-six-worker-pause',php([host+'/maintenance.php','--prepare']));record('inspect-pinned-reset',php([host+'/reset.php','--inspect']))
 (W/'crontab.current').write_bytes((W/'crontab.paused').read_bytes());(W/'workers.drained').write_text(h((W/'crontab.paused').read_bytes()));paused=b'# JIVIE FRESH RESET MAINTENANCE\nRewriteEngine On\nRewriteRule ^ - [R=503,L]\n'+ht;(S/'.htaccess').write_bytes(paused);(W/'maintenance.sha256').write_text(h(paused));(W/'maintenance.started').write_text(str(int(time.time())-66))
 # Explicit synthetic clock and cron evidence only; production uses real65s+HTTP503+ps.
 export=record('complete-frozen-backup',php([host+'/backup.php','--export']));info=json.loads(export.stdout);archive=H/Path(info['archivePath']).relative_to('/home/tripar13');sha=info['archiveSha256']
 record('fresh-isolated-restore-db',run(['docker','run','-d','--name',restore,'--network','none','-e','MARIADB_ALLOW_EMPTY_ROOT_PASSWORD=yes','mariadb:10.11.19']));owned.append(restore);ready(restore)
 record('actual-complete-isolated-restore',run(['python3',str(D/'restore-verify.py'),str(archive),'--sha256',sha,'--container',restore,'--private-root',str(P)]));shutil.copy2(archive.parent/'restore-proof.json',W/'restore-proof.json');(W/'restore-proof.json').chmod(0o600)
 record('stage-exact-reset',php([host+'/reset.php','--stage',info['archivePath'],sha]))
 # Real kernel lease conflict. Helper must refuse before directory moves or DB writes.
 holder=run(['docker','exec','-d',runner,'php','-r',"$f=fopen('/home/tripar13/private/jivie-test/data/familyhub/crypto/migration.lock','c');flock($f,LOCK_EX);file_put_contents('/fixture-work/lease-held',(string)getmypid());sleep(60);"]);record('hold-real-maintenance-lease',holder)
 for _ in range(50):
  if (M/'lease-held').exists():break
  time.sleep(.1)
 fail('competing-lease-rejects-apply',php([host+'/reset.php','--apply',info['archivePath'],sha]),'exclusive_crypto_lease_required')
 holder_pid=(M/'lease-held').read_text();assert holder_pid.isdigit();record('release-only-owned-lease-holder',run(['docker','exec',runner,'kill',holder_pid]))
 record('apply-full-quarantine-and-reset',php([host+'/reset.php','--apply',info['archivePath'],sha]));record('independent-read-verify',php([host+'/reset.php','--verify',info['archivePath'],sha]));
 fail('reject-second-apply',php([host+'/reset.php','--apply',info['archivePath'],sha]),'apply_requires_staged_once')
 record('manual-http-release-state',php([host+'/reset.php','--release-http',info['archivePath'],sha]));record('pre-worker-release-no-business-data',php([host+'/reset.php','--worker-release-check']))
 # Capability is synthetic input here; production public-check performs real TLS HTTP.
 state=json.loads((W/'reset-state.json').read_text());(W/'public-capabilities.json').write_text(json.dumps({'data':{'serverId':state['result']['newServerId']}}));(W/'public-capabilities.json').chmod(0o600);(W/'crontab.current').write_text(cron);record('explicit-original-cron-confirmation',php([host+'/reset.php','--confirm-workers-released']))
 assert (DATA/'files/core.bin').read_bytes()==bytes(range(256));assert (B/'fake-private.key').read_bytes()==bytes(range(32));assert (W/'quarantine-data/familyhub/attachments/probe').read_bytes()==b'old attachment\0';assert (W/'quarantine-data/familyhub/ideas/probe').read_bytes()==b'old idea\xff';assert archive.exists()
 print(json.dumps({'status':'PASS','fixtureRoot':str(M),'stages':len(events),'actualFullIsolatedRestore':True,'actualFilesystemQuarantine':True,'actualKernelLockConflict':True,'realCronHttpNotExercised':True,'syntheticDrainClockAndFinalCapabilitiesOnly':True,'originalCaptureFixture':'STOP3_not_repeated'}))
except Exception as e:
 print(json.dumps({'status':'FAIL','stage':str(e),'fixtureRoot':str(M),'last':events[-1] if events else None}));sys.exit(1)
finally:
 for n in reversed(owned):events.append({'cleanup':n,'exitCode':run(['docker','rm','-f','-v',n]).returncode})
 (M/'results.json').write_text(json.dumps(events,indent=2)+'\n');(M/'results.json').chmod(0o600)
