#!/usr/bin/env python3
"""Populated synthetic schema17 backup, real MariaDB10.11.19 restore and guarded18 upgrade."""
from pathlib import Path
import zipfile,subprocess,time,secrets,hashlib,json,shutil,os,sys
os.umask(0o077)
D=Path(__file__).resolve().parent;R=D.parents[2]
PRIVATE=Path('/Users/anzenovsak/.local/share/jivie/backups/lifecycle18-fixtures');PRIVATE.mkdir(parents=True,exist_ok=True,mode=0o700);PRIVATE.chmod(0o700)
M=PRIVATE/('fixture-'+secrets.token_hex(4));M.mkdir(mode=0o700);H=M/'home';S=H/'jivie-test.triparna.si';S.mkdir(parents=True)
B=H/'private/jivie-test';B.mkdir(parents=True,mode=0o700);B.parent.chmod(0o700);DATA=B/'data';DATA.mkdir(mode=0o700)
for n in ['files','cache','files/empty']:(DATA/n).mkdir(mode=0o700)
for archive,prefix,dest in [(R/'build/releases/cpanel-fresh/kanboard-v1.2.54-upstream.zip','kanboard-kanboard-9ce6a5e/',S),(R/'build/releases/FamilyHub-0.13.0-source.zip','FamilyHub/',S/'plugins/FamilyHub')]:
 with zipfile.ZipFile(archive)as z:
  for e in z.infolist():
   if e.is_dir():continue
   p=dest/e.filename[len(prefix):];p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(z.read(e))
pw=secrets.token_hex(24);(B/'smtp-password.txt').write_text(secrets.token_hex(32));(B/'smtp-password.txt').chmod(0o600)
cfg="<?php\ndefine('DB_DRIVER','mysql');define('DB_HOSTNAME','127.0.0.1');define('DB_NAME','tripar13_jivietest');define('DB_USERNAME','root');define('DB_PASSWORD','"+pw+"');define('DATA_DIR','/home/tripar13/private/jivie-test/data');define('FILES_DIR',DATA_DIR.'/files');define('CACHE_DIR',DATA_DIR.'/cache');define('FAMILYHUB_ENABLE_NATIVE_API',true);define('FAMILYHUB_ENABLE_FCM',true);define('FAMILYHUB_ENABLE_PROJECT_INVITATIONS',false);define('FAMILYHUB_ACCOUNT_MODE','self_hosted');define('FAMILYHUB_SMTP_PASSWORD',trim(file_get_contents('/home/tripar13/private/jivie-test/smtp-password.txt')));\n"
(S/'config.php').write_text(cfg);(S/'config.php').chmod(0o600);ht=(S/'.htaccess').read_bytes()
shutil.copy2(D/'capture.php',B/'capture.php');(B/'capture.php').chmod(0o600)
scripts=['reminders.php','delivery.php','account-mail.php','account-deletion-cleanup.php','push.php'];cron=''.join('* * * * * php /home/tripar13/jivie-test.triparna.si/plugins/FamilyHub/cli/'+n+'\n'for n in scripts)+'# unrelated cron preserved\n';(B/'cron.capture').write_text(cron);(B/'cron.capture').chmod(0o600)
# Build a private fixture-only0.14 package. Actual releases require their separate reviewed artifact.
package=M/'FamilyHub-0.14.0-source.zip';old=json.loads((R/'server/scripts/reviewer-test1/source-manifests.json').read_text())['new'];names=set(json.loads((R/'tools/plugin_release/source_manifest.json').read_text()))|{n for n in old if not(n.endswith('.php')or n=='LICENSE')}|{'docs/scope-lifecycle-api-contract.md'}
with zipfile.ZipFile(package,'w',zipfile.ZIP_DEFLATED)as z:
 for n in sorted(names):
  p=(R/'tools/plugin_release/PUBLIC_README.md') if n=='README.md' else ((R/'docs/server'/n[5:]) if n.startswith('docs/') else R/'server/plugins/FamilyHub'/n)
  body=p.read_bytes()
  e=zipfile.ZipInfo('FamilyHub/'+n);e.external_attr=0o100644<<16;e.compress_type=zipfile.ZIP_DEFLATED;z.writestr(e,body)
env=M/'db.env';env.write_text('MARIADB_ROOT_PASSWORD='+pw+'\nMARIADB_DATABASE=tripar13_jivietest\nMARIADB_ROOT_HOST=%\n');env.chmod(0o600)
db='jivie-lifecycle18-fixture-db-'+secrets.token_hex(3);runner='jivie-lifecycle18-fixture-php-'+secrets.token_hex(3);restore='jivie-lifecycle18-fixture-restore-'+secrets.token_hex(3);reports=[]
def run(args,data=None):return subprocess.run(args,input=data,capture_output=True,text=True)
def php(args):return run(['docker','exec',runner,'php']+args)
def result(stage,r):
 reports.append({'stage':stage,'returnCode':r.returncode,'stdout':r.stdout.replace(pw,'REDACTED'),'stderr':r.stderr.replace(pw,'REDACTED')})
 if r.returncode:raise RuntimeError('fixture_stage_'+stage)
def ready(name,auth=False):
 for _ in range(45):
  r=run(['docker','exec',name,'sh','-c','mariadb-admin --protocol=tcp -h127.0.0.1 ping -uroot '+('-p"$MARIADB_ROOT_PASSWORD" 'if auth else'')+'--silent'])
  if r.returncode==0:return
  time.sleep(1)
 raise RuntimeError('fixture_startup')
def negative(stage,r,code):
 assert r.returncode==1 and code in r.stderr,(stage,r.stdout,r.stderr);reports.append({'stage':stage,'guarded':True})
prefix="require '/home/tripar13/jivie-test.triparna.si/config.php';$p=new PDO('mysql:host=127.0.0.1;dbname=tripar13_jivietest;charset=utf8mb4',DB_USERNAME,DB_PASSWORD,[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION]);"
try:
 result('db-start',run(['docker','run','-d','--name',db,'--env-file',str(env),'mariadb:10.11.19']));ready(db,True)
 result('php-start',run(['docker','run','-d','--name',runner,'--network','container:'+db,'-v',str(H)+':/home/tripar13','--entrypoint','sleep','kanban-test2-php84-tokenizer:20261011','3600']))
 result('baseline17-initialize',php(['-r',"require '/home/tripar13/jivie-test.triparna.si/app/common.php';$container['pluginLoader']->scan();echo 'synthetic17 initialized';"]))
 seed="""$p->exec("UPDATE familyhub_instance SET server_id='95c11fe0-916c-48be-a3f6-999732846266' WHERE id=1");$p->exec("INSERT INTO familyhub_accounts(user_id,account_id) VALUES(1,'12345678-1234-4234-a234-123456789abc')");$p->prepare('UPDATE users SET password=?')->execute([password_hash(bin2hex(random_bytes(24)),PASSWORD_BCRYPT)]);
$p->exec("INSERT INTO familyhub_scopes(id,kind,name,owner_id,created_at) VALUES('12345678-1234-4234-a234-123456789111','household','Synthetic private scope',1,1)");
$p->exec("INSERT INTO familyhub_devices(id,user_id,account_id,name,token_hash,credentials_hash,created_at,expires_at) VALUES('12345678-1234-4234-a234-123456789222',1,'12345678-1234-4234-a234-123456789abc','Synthetic device',REPEAT('a',64),REPEAT('b',64),1,9999999999)");
$p->exec("INSERT INTO familyhub_push_registrations(device_id,account_id,project_id,revision,active,updated_at) VALUES('12345678-1234-4234-a234-123456789222','12345678-1234-4234-a234-123456789abc','synthetic-project',3,1,1)");
$p->exec("INSERT INTO familyhub_reminders(id,scope_id,account_id,target_type,target_id,target_fingerprint,remind_at,remind_epoch,revision,state) VALUES('12345678-1234-4234-a234-123456789333','12345678-1234-4234-a234-123456789111','12345678-1234-4234-a234-123456789abc','task','12345678-1234-4234-a234-123456789444',REPEAT('c',64),'2030-01-01T00:00:00Z',1893456000,4,'pending')");
$p->exec('CREATE TABLE synthetic_backup_probe(id INTEGER PRIMARY KEY,text_value TEXT NULL,value_number DECIMAL(12,2),binary_value LONGBLOB) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4');$p->prepare('INSERT INTO synthetic_backup_probe VALUES(?,?,?,?)')->execute([1,"Šč ž quote ' ",'123.45',hex2bin('0009fffe0a')]);echo 'populated synthetic17 seeded';"""
 result('seed-scopes-reminders-registered-device-binary',php(['-r',prefix+seed]));(DATA/'files/synthetic.bin').write_bytes(bytes.fromhex('0010fffe0a'));(DATA/'files/synthetic.bin').chmod(0o600)
 result('fresh-read-only-capture',php(['/home/tripar13/private/jivie-test/capture.php','test1','/home/tripar13/private/jivie-test/cron.capture']));capture=M/'capture.json';capture.write_text(reports[-1]['stdout']);capture.chmod(0o600)
 result('seal',run(['python3',str(D/'seal.py'),str(capture),str(package),str(M/'sealed')]));seal=json.loads(reports[-1]['stdout']);host=seal['hostWork']+'/';W=H/Path(seal['hostWork']).relative_to('/home/tripar13');shutil.copytree(M/'sealed',W);W.chmod(0o700)
 for n in ['backup.php','upgrade.php','maintenance.php','maintenance-guards.php','delivery-guards.php','deployment.php']:result('lint-'+n,php(['-l',host+n]))
 (W/'crontab.original').write_text(cron);(W/'crontab.original').chmod(0o600)
 result('backup-check',php([host+'backup.php','--check']));result('upgrade-check',php([host+'upgrade.php','--check']))
 negative('missing-GD',php(['-d','disable_functions=imagejpeg',host+'backup.php','--check']),'gd_png_jpeg_required')
 key=(B/'smtp-password.txt').read_bytes();(B/'smtp-password.txt').write_bytes(b'changed');negative('changed-SMTP-secret',php([host+'backup.php','--check']),'delivery_config_key_or_mode_changed');(B/'smtp-password.txt').write_bytes(key)
 result('prepare-pause-candidate',php([host+'maintenance.php','--prepare']))
 # Fixture only supplies maintenance state; hosted pause requires real HTTPS503 and actual65seconds.
 (W/'crontab.current').write_bytes((W/'crontab.paused').read_bytes());(W/'workers.drained').write_text(hashlib.sha256((W/'crontab.paused').read_bytes()).hexdigest())
 paused=b'# JIVIE REVIEW UPGRADE MAINTENANCE\nRewriteEngine On\nRewriteRule ^ - [R=503,L]\n'+ht;(S/'.htaccess').write_bytes(paused);(W/'maintenance.sha256').write_text(hashlib.sha256(paused).hexdigest());(W/'maintenance.started').write_text(str(int(time.time())))
 negative('premature-export',php([host+'backup.php','--export']),'drain_65_seconds_required');(W/'maintenance.started').write_text(str(int(time.time())-66))
 result('backup-export',php([host+'backup.php','--export']));exported=json.loads(reports[-1]['stdout']);a=M/'Lifecycle18-private-backup.zip';shutil.copy2(H/Path(exported['archivePath']).relative_to('/home/tripar13'),a);a.chmod(0o600)
 result('isolated-restore-start',run(['docker','run','-d','--name',restore,'--network','none','-e','MARIADB_ALLOW_EMPTY_ROOT_PASSWORD=yes','mariadb:10.11.19']));ready(restore)
 result('actual-isolated-restore',run(['python3',str(D/'restore-verify.py'),str(a),'--sha256',exported['archiveSha256'],'--container',restore,'--private-root',str(PRIVATE)]));shutil.copy2(M/'restore-proof.json',W/'restore-proof.json');(W/'restore-proof.json').chmod(0o600)
 proof=(W/'restore-proof.json').read_bytes();j=json.loads(proof);j['archiveSha256']='f'*64;(W/'restore-proof.json').write_text(json.dumps(j));negative('wrong-proof',php([host+'upgrade.php','--stage',exported['archivePath'],exported['archiveSha256']]),'actual_restore_proof_guard');(W/'restore-proof.json').write_bytes(proof)
 result('stage',php([host+'upgrade.php','--stage',exported['archivePath'],exported['archiveSha256']]))
 result('mutate-row',php(['-r',prefix+"$p->exec(\"UPDATE synthetic_backup_probe SET text_value='changed' WHERE id=1\");"]));negative('changed-row',php([host+'upgrade.php','--apply',exported['archiveSha256']]),'old_database_differs_from_verified_backup');result('restore-row',php(['-r',prefix+"$p->prepare('UPDATE synthetic_backup_probe SET text_value=? WHERE id=1')->execute([\"Šč ž quote ' \"]); "]))
 result('apply-schema17-to18',php([host+'upgrade.php','--apply',exported['archiveSha256']]))
 result('verify-paused',php([host+'upgrade.php','--verify',exported['archiveSha256']]))
 result('release-HTTP-while-worker-cron-paused',php([host+'upgrade.php','--release',exported['archiveSha256']]))
 negative('confirm-before-original-cron',php([host+'upgrade.php','--confirm-release',exported['archiveSha256']]),'original_cron_not_restored')
 (W/'crontab.current').write_text(cron);result('confirm-exact-original-cron-restored',php([host+'upgrade.php','--confirm-release',exported['archiveSha256']]))
 assert(S/'.htaccess').read_bytes()==ht and(W/'crontab.current').read_text()==cron
 negative('reapply-after-release',php([host+'upgrade.php','--apply',exported['archiveSha256']]),'paused_phase_or_backup_sha')
 checkpoint=json.loads((W/'release-checkpoint.json').read_text());assert len(checkpoint['newEmptyTables'])==1 and checkpoint['historicRowsDefsPasswordsDevicesAndFilesPreserved']
 evidence={'pass':True,'syntheticOnly':True,'fixtureMaintenanceClockOnlyAdvanced':True,'actualIsolatedRestore':True,'checkpoint':checkpoint,'reports':reports};(M/'fixture-evidence.json').write_text(json.dumps(evidence,indent=2)+'\n');print('PASS: populated schema17→18/export/real isolatedrestore/release +7negative guards; private evidence '+str(M/'fixture-evidence.json'))
except Exception as e:
 (M/'fixture-failure.json').write_text(json.dumps({'reports':reports,'failure':type(e).__name__+':'+str(e)},indent=2)+'\n');print('Fixture stopped; private secret-free evidence '+str(M/'fixture-failure.json'));sys.exit(1)
finally:
 for n in [runner,restore,db]:run(['docker','rm','-fv',n])
