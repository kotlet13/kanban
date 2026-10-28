#!/usr/bin/env python3
"""Synthetic populated19→23, full backup+actual isolatedrestore+strictpreservation. No live host."""
from pathlib import Path
import zipfile,subprocess,time,secrets,hashlib,json,shutil,os,sys
os.umask(0o077)
D=Path(__file__).resolve().parent;R=D.parents[2]
PRIVATE=Path('/Users/anzenovsak/.local/share/jivie/backups/crypto23-fixtures');PRIVATE.mkdir(parents=True,exist_ok=True,mode=0o700);PRIVATE.chmod(0o700)
M=PRIVATE/('fixture-'+secrets.token_hex(4));M.mkdir(mode=0o700);H=M/'home';S=H/'jivie-test.triparna.si';S.parent.mkdir()
shutil.copytree(Path('/Users/anzenovsak/.local/share/jivie/backups/crypto23-schema-oracle-20261028/site'),S)
B=H/'private/jivie-test';B.mkdir(parents=True,mode=0o700);B.parent.chmod(0o700);DATA=B/'data';DATA.mkdir(mode=0o700)
for n in ['files','cache','files/empty']:(DATA/n).mkdir(mode=0o700)
# Old exact107 reviewed release source retained privately; no production SQL/config used.
assert b'const VERSION = 19;'in(S/'plugins/FamilyHub/Schema/Mysql.php').read_bytes()
cfg="<?php\ndefine('DB_DRIVER','mysql');define('DB_HOSTNAME','127.0.0.1');define('DB_NAME','tripar13_jivietest');define('DB_USERNAME','root');define('DB_PASSWORD','');define('DATA_DIR','/home/tripar13/private/jivie-test/data');define('FILES_DIR',DATA_DIR.'/files');define('CACHE_DIR',DATA_DIR.'/cache');define('FAMILYHUB_ENABLE_NATIVE_API',true);define('FAMILYHUB_ENABLE_PROJECT_INVITATIONS',false);define('FAMILYHUB_ACCOUNT_MODE','self_hosted');\n"
(S/'config.php').write_text(cfg);(S/'config.php').chmod(0o600);ht=(S/'.htaccess').read_bytes()
for n in ['capture.php','crypto-runtime.php']:shutil.copy2(D/n,B/n);(B/n).chmod(0o600)
cron=''.join('* * * * * php /home/tripar13/jivie-test.triparna.si/plugins/FamilyHub/cli/'+n+'\n'for n in ['reminders.php','delivery.php','account-mail.php','account-deletion-cleanup.php','push.php'])+'# unrelated cron preserved\n';(B/'cron.capture').write_text(cron);(B/'cron.capture').chmod(0o600)
( DATA/'files/probe.bin').write_bytes(bytes(range(256)));(DATA/'files/probe.bin').chmod(0o600)
db='jivie-crypto23-fixture-db-'+secrets.token_hex(3);runner='jivie-crypto23-fixture-php-'+secrets.token_hex(3);restore='jivie-crypto23-fixture-restore-'+secrets.token_hex(3);reports=[]
def run(args,data=None):return subprocess.run(args,input=data,capture_output=True,text=True)
def php(args):return run(['docker','exec',runner,'php']+args)
def result(stage,r):
 reports.append({'stage':stage,'returnCode':r.returncode,'stdout':r.stdout,'stderr':r.stderr})
 if r.returncode:raise RuntimeError('fixture_stage_'+stage)
def ready(name):
 for _ in range(45):
  if run(['docker','exec',name,'mariadb-admin','--protocol=tcp','-h127.0.0.1','ping','-uroot','--silent']).returncode==0:return
  time.sleep(1)
 raise RuntimeError('fixture_startup')
def negative(stage,r,code):
 reports.append({'stage':stage,'returnCode':r.returncode,'guarded':r.returncode==1 and code in r.stderr})
 if r.returncode!=1 or code not in r.stderr:raise RuntimeError('fixture_negative_'+stage)
prefix="require '/home/tripar13/jivie-test.triparna.si/config.php';$p=new PDO('mysql:host=127.0.0.1;dbname=tripar13_jivietest;charset=utf8mb4',DB_USERNAME,DB_PASSWORD,[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION]);"
try:
 result('db-start',run(['docker','run','-d','--name',db,'--network','none','-e','MARIADB_ALLOW_EMPTY_ROOT_PASSWORD=yes','-e','MARIADB_DATABASE=tripar13_jivietest','mariadb:10.11.19']));ready(db)
 result('php-start',run(['docker','run','-d','--name',runner,'--network','container:'+db,'-v',str(H)+':/home/tripar13','--entrypoint','sleep','jivie-crypto23-upgrade-fixture:20261028','3600']))
 result('baseline19-initialize',php(['-r',"require '/home/tripar13/jivie-test.triparna.si/app/common.php';$container['pluginLoader']->scan();echo 'synthetic19 initialized';"]))
 seed="""$p->exec("UPDATE familyhub_instance SET server_id='95c11fe0-916c-48be-a3f6-999732846266' WHERE id=1");$p->exec("INSERT INTO familyhub_accounts(user_id,account_id) VALUES(1,'12345678-1234-4234-a234-123456789abc')");$p->exec("INSERT INTO familyhub_scopes(id,kind,name,owner_id,created_at) VALUES('12345678-1234-4234-a234-123456789111','household','Synthetic private scope',1,1)");$p->exec("INSERT INTO familyhub_inbox_state(account_id,sequence,visibility_revision) VALUES('12345678-1234-4234-a234-123456789abc',11,7)");$p->exec("INSERT INTO familyhub_devices(id,user_id,account_id,name,token_hash,credentials_hash,created_at,expires_at) VALUES('12345678-1234-4234-a234-123456789222',1,'12345678-1234-4234-a234-123456789abc','Synthetic device',REPEAT('a',64),REPEAT('b',64),1,9999999999)");$p->exec('CREATE TABLE synthetic_backup_probe(id INTEGER PRIMARY KEY,binary_value BLOB,null_value TEXT) ENGINE=InnoDB');$p->exec("INSERT INTO synthetic_backup_probe VALUES(1,X'00FF1027415C0A',NULL)");"""
 result('populated-history-seed',php(['-r',prefix+seed]));result('fresh-read-only-capture',php(['/home/tripar13/private/jivie-test/capture.php','test1','/home/tripar13/private/jivie-test/cron.capture']))
 capture=M/'capture.json';capture.write_text(reports[-1]['stdout']);capture.chmod(0o600)
 result('seal',run(['python3',str(D/'seal.py'),str(capture),str(M/'sealed')]));sealed=json.loads(reports[-1]['stdout']);host=sealed['hostWork']+'/';W=H/Path(sealed['hostWork']).relative_to('/home/tripar13');shutil.copytree(M/'sealed',W);W.chmod(0o700)
 (W/'crontab.original').write_text(cron);(W/'crontab.original').chmod(0o600)
 result('backup-check',php([host+'backup.php','--check']));result('upgrade-check',php([host+'upgrade.php','--check']))
 negative('missing-sodium',php(['-d','disable_functions=sodium_crypto_sign_detached',host+'upgrade.php','--check']),'crypto_runtime_function_missing')
 result('prepare-maintenance',php([host+'maintenance.php','--prepare']))
 (W/'crontab.current').write_bytes((W/'crontab.paused').read_bytes());(W/'workers.drained').write_text(hashlib.sha256((W/'crontab.paused').read_bytes()).hexdigest());paused=b'# JIVIE REVIEW UPGRADE MAINTENANCE\nRewriteEngine On\nRewriteRule ^ - [R=503,L]\n'+ht;(S/'.htaccess').write_bytes(paused);(W/'maintenance.sha256').write_text(hashlib.sha256(paused).hexdigest());(W/'maintenance.started').write_text(str(int(time.time())))
 negative('real-drain-timer-guard',php([host+'backup.php','--export']),'drain_65_seconds_required')
 # Synthetic clock state only: production helper time guard is unchanged and requires real65seconds.
 (W/'maintenance.started').write_text(str(int(time.time())-66))
 result('full-consistent-export',php([host+'backup.php','--export']));backup=json.loads(reports[-1]['stdout']);archive=H/Path(backup['archivePath']).relative_to('/home/tripar13');digest=backup['archiveSha256']
 result('restore-start',run(['docker','run','-d','--name',restore,'--network','none','-e','MARIADB_ALLOW_EMPTY_ROOT_PASSWORD=yes','mariadb:10.11.19']));ready(restore)
 result('actual-isolated-restore',run(['python3',str(D/'restore-verify.py'),str(archive),'--sha256',digest,'--container',restore,'--private-root',str(PRIVATE)]))
 shutil.copy2(archive.parent/'restore-proof.json',W/'restore-proof.json');(W/'restore-proof.json').chmod(0o600)
 result('stage',php([host+'upgrade.php','--stage',backup['archivePath'],digest]));result('apply',php([host+'upgrade.php','--apply',digest]));result('verify',php([host+'upgrade.php','--verify',digest]))
 result('mutate-old-history-for-rejection',php(['-r',prefix+"$p->exec(\"UPDATE familyhub_inbox_state SET sequence=sequence+1\");"]))
 negative('old-history-change-blocks-release',php([host+'upgrade.php','--release',digest]),'historical_row_values_changed')
 result('repair-synthetic-history',php(['-r',prefix+"$p->exec(\"UPDATE familyhub_inbox_state SET sequence=sequence-1\");"]))
 # No second verify rerun: exercise distinct HTTP-release state transition after restoring intentionallymutated fixture.
 result('release-http-state',php([host+'upgrade.php','--release',digest]));(W/'crontab.current').write_bytes((W/'crontab.upgraded').read_bytes());(W/'public-capabilities.json').write_text(json.dumps({'data':{'serverId':'95c11fe0-916c-48be-a3f6-999732846266','cryptoTransportVersions':[1,2]}}));(W/'public-capabilities.json').chmod(0o600);result('confirm-cron-state-synthetic-public-proof',php([host+'upgrade.php','--confirm-release',digest]))
 print(json.dumps({'status':'PASS','fixtureRoot':str(M),'checks':len(reports),'newTables':127,'changedHistoricalDefinitions':3,'realHttpsAndCronNotExercised':True,'syntheticDrainClockOnly':True}))
except Exception as e:
 print(json.dumps({'status':'FAIL','code':str(e),'fixtureRoot':str(M),'last':reports[-1]if reports else None}));sys.exit(1)
finally:
 (M/'results.json').write_text(json.dumps(reports,indent=2)+'\n');(M/'results.json').chmod(0o600)
 for name in [runner,restore,db]:run(['docker','rm','-f','-v',name])
