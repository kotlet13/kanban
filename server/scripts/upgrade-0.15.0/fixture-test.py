#!/usr/bin/env python3
"""Populated synthetic schema18 backup, real MariaDB10.11.19 restore and guarded19 upgrade."""
from pathlib import Path
import zipfile,subprocess,time,secrets,hashlib,json,shutil,os,sys
os.umask(0o077)
if sys.argv[1:] not in [[],['--abort-only']]:raise SystemExit('Usage: fixture-test.py [--abort-only]')
ABORT_ONLY=bool(sys.argv[1:])
D=Path(__file__).resolve().parent;R=D.parents[2]
PRIVATE=Path('/Users/anzenovsak/.local/share/jivie/backups/documents19-fixtures');PRIVATE.mkdir(parents=True,exist_ok=True,mode=0o700);PRIVATE.chmod(0o700)
M=PRIVATE/('fixture-'+secrets.token_hex(4));M.mkdir(mode=0o700);H=M/'home';S=H/'jivie-test.triparna.si';S.mkdir(parents=True)
B=H/'private/jivie-test';B.mkdir(parents=True,mode=0o700);B.parent.chmod(0o700);DATA=B/'data';DATA.mkdir(mode=0o700)
for n in ['files','cache','files/empty']:(DATA/n).mkdir(mode=0o700)
for archive,prefix,dest in [(R/'build/releases/cpanel-fresh/kanboard-v1.2.54-upstream.zip','kanboard-kanboard-9ce6a5e/',S),(R/'build/release/FamilyHub-0.14.0-upgrade-20261014.zip','FamilyHub/',S/'plugins/FamilyHub')]:
 with zipfile.ZipFile(archive)as z:
  for e in z.infolist():
   if e.is_dir():continue
   p=dest/e.filename[len(prefix):];p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(z.read(e))
# Hosted0.14.1 consists of the immutable101-file0.14.0 package plus three code-only changes.
for name in ['Model/NativeNotificationPreferences.php','Model/NativePushWorker.php','Plugin.php']:
 p=S/'plugins/FamilyHub'/name;body=p.read_bytes()
 body=body.replace(b"'sound' => false",b"'sound' => true")if name.endswith('NativeNotificationPreferences.php')else(body.replace(b"($settings['sound'] ?? false)",b"($settings['sound'] ?? true)")if name.endswith('NativePushWorker.php')else body.replace(b"return '0.14.0'",b"return '0.14.1'"));p.write_bytes(body)
pw=secrets.token_hex(24);(B/'smtp-password.txt').write_text(secrets.token_hex(32));(B/'smtp-password.txt').chmod(0o600)
cfg="<?php\ndefine('DB_DRIVER','mysql');define('DB_HOSTNAME','127.0.0.1');define('DB_NAME','tripar13_jivietest');define('DB_USERNAME','root');define('DB_PASSWORD','"+pw+"');define('DATA_DIR','/home/tripar13/private/jivie-test/data');define('FILES_DIR',DATA_DIR.'/files');define('CACHE_DIR',DATA_DIR.'/cache');define('FAMILYHUB_ENABLE_NATIVE_API',true);define('FAMILYHUB_ENABLE_FCM',true);define('FAMILYHUB_ENABLE_PROJECT_INVITATIONS',false);define('FAMILYHUB_ACCOUNT_MODE','self_hosted');define('FAMILYHUB_SMTP_PASSWORD',trim(file_get_contents('/home/tripar13/private/jivie-test/smtp-password.txt')));\n"
(S/'config.php').write_text(cfg);(S/'config.php').chmod(0o600);ht=(S/'.htaccess').read_bytes()
shutil.copy2(D/'capture.php',B/'capture.php');(B/'capture.php').chmod(0o600)
scripts=['reminders.php','delivery.php','account-mail.php','account-deletion-cleanup.php','push.php'];cron=''.join('* * * * * php /home/tripar13/jivie-test.triparna.si/plugins/FamilyHub/cli/'+n+'\n'for n in scripts)+'# unrelated cron preserved\n';(B/'cron.capture').write_text(cron);(B/'cron.capture').chmod(0o600)
# Exercise the exact final release artifact, not a reconstructed equivalent.
package=M/'FamilyHub-0.15.0-source.zip';shutil.copy2(R/'build/releases/FamilyHub-0.15.0.zip',package);package.chmod(0o600)
assert hashlib.sha256(package.read_bytes()).hexdigest()=='5c14ca9a79d92cf1c5f71b681d8417f44f4bfb9b474443cdad4dbb3f589f51e7'
with zipfile.ZipFile(package)as z:assert len(z.infolist())==107 and z.testzip()is None
env=M/'db.env';env.write_text('MARIADB_ROOT_PASSWORD='+pw+'\nMARIADB_DATABASE=tripar13_jivietest\nMARIADB_ROOT_HOST=%\n');env.chmod(0o600)
db='jivie-documents19-fixture-db-'+secrets.token_hex(3);runner='jivie-documents19-fixture-php-'+secrets.token_hex(3);restore='jivie-documents19-fixture-restore-'+secrets.token_hex(3);reports=[]
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
 result('baseline18-initialize',php(['-r',"require '/home/tripar13/jivie-test.triparna.si/app/common.php';$container['pluginLoader']->scan();echo 'synthetic18 initialized';"]))
 seed="""$p->exec("UPDATE familyhub_instance SET server_id='95c11fe0-916c-48be-a3f6-999732846266' WHERE id=1");$p->exec("INSERT INTO familyhub_accounts(user_id,account_id) VALUES(1,'12345678-1234-4234-a234-123456789abc')");$p->prepare('UPDATE users SET password=?')->execute([password_hash(bin2hex(random_bytes(24)),PASSWORD_BCRYPT)]);
$p->exec("INSERT INTO familyhub_scopes(id,kind,name,owner_id,created_at) VALUES('12345678-1234-4234-a234-123456789111','household','Synthetic private scope',1,1)");
$p->exec("INSERT INTO familyhub_devices(id,user_id,account_id,name,token_hash,credentials_hash,created_at,expires_at) VALUES('12345678-1234-4234-a234-123456789222',1,'12345678-1234-4234-a234-123456789abc','Synthetic device',REPEAT('a',64),REPEAT('b',64),1,9999999999)");
$p->exec("INSERT INTO familyhub_push_registrations(device_id,account_id,project_id,revision,active,updated_at) VALUES('12345678-1234-4234-a234-123456789222','12345678-1234-4234-a234-123456789abc','synthetic-project',3,1,1)");
$p->exec("INSERT INTO familyhub_reminders(id,scope_id,account_id,target_type,target_id,target_fingerprint,remind_at,remind_epoch,revision,state) VALUES('12345678-1234-4234-a234-123456789333','12345678-1234-4234-a234-123456789111','12345678-1234-4234-a234-123456789abc','task','12345678-1234-4234-a234-123456789444',REPEAT('c',64),'2030-01-01T00:00:00Z',1893456000,4,'pending')");
$p->exec('CREATE TABLE synthetic_backup_probe(id INTEGER PRIMARY KEY,text_value TEXT NULL,value_number DECIMAL(12,2),binary_value LONGBLOB) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4');$p->prepare('INSERT INTO synthetic_backup_probe VALUES(?,?,?,?)')->execute([1,"Šč ž quote ' ",'123.45',hex2bin('0009fffe0a')]);echo 'populated synthetic18 seeded';"""
 result('seed-scopes-reminders-registered-device-binary',php(['-r',prefix+seed]));(DATA/'files/synthetic.bin').write_bytes(bytes.fromhex('0010fffe0a'));(DATA/'files/synthetic.bin').chmod(0o600)
 result('fresh-read-only-capture',php(['/home/tripar13/private/jivie-test/capture.php','test1','/home/tripar13/private/jivie-test/cron.capture']));capture=M/'capture.json';capture.write_text(reports[-1]['stdout']);capture.chmod(0o600)
 result('seal',run(['python3',str(D/'seal.py'),str(capture),str(package),str(M/'sealed')]));seal=json.loads(reports[-1]['stdout']);host=seal['hostWork']+'/';W=H/Path(seal['hostWork']).relative_to('/home/tripar13');shutil.copytree(M/'sealed',W);W.chmod(0o700)
 for n in ['backup.php','upgrade.php','maintenance.php','maintenance-guards.php','delivery-guards.php','deployment.php','abort.php','document-tables.php']:result('lint-'+n,php(['-l',host+n]))
 (W/'crontab.original').write_text(cron);(W/'crontab.original').chmod(0o600)
 result('backup-check',php([host+'backup.php','--check']));result('upgrade-check',php([host+'upgrade.php','--check']))
 negative('missing-ZipArchive',php(['-d','disable_classes=ZipArchive',host+'backup.php','--check']),'php_or_filesystem_warning')
 (DATA/'files/synthetic.bin').chmod(0o644);negative('public-DATA-file',php([host+'backup.php','--check']),'private_data_modes_guard');(DATA/'files/synthetic.bin').chmod(0o600)
 negative('missing-GD',php(['-d','disable_functions=imagejpeg',host+'backup.php','--check']),'gd_png_jpeg_required')
 key=(B/'smtp-password.txt').read_bytes();(B/'smtp-password.txt').write_bytes(b'changed');negative('changed-SMTP-secret',php([host+'backup.php','--check']),'delivery_config_key_or_mode_changed');(B/'smtp-password.txt').write_bytes(key)
 result('prepare-pause-candidate',php([host+'maintenance.php','--prepare']))
 # Fixture only supplies maintenance state; hosted pause requires real HTTPS503 and actual65seconds.
 (W/'crontab.current').write_bytes((W/'crontab.paused').read_bytes());(W/'workers.drained').write_text(hashlib.sha256((W/'crontab.paused').read_bytes()).hexdigest())
 paused=b'# JIVIE REVIEW UPGRADE MAINTENANCE\nRewriteEngine On\nRewriteRule ^ - [R=503,L]\n'+ht;(S/'.htaccess').write_bytes(paused);(W/'maintenance.sha256').write_text(hashlib.sha256(paused).hexdigest());(W/'maintenance.started').write_text(str(int(time.time())))
 negative('premature-export',php([host+'backup.php','--export']),'drain_65_seconds_required');(W/'maintenance.started').write_text(str(int(time.time())-66))
 result('backup-export',php([host+'backup.php','--export']));exported=json.loads(reports[-1]['stdout']);a=M/'Documents19-private-backup.zip';shutil.copy2(H/Path(exported['archivePath']).relative_to('/home/tripar13'),a);a.chmod(0o600)
 if ABORT_ONLY:
  # Only this synthetic process replaces cURL. The hosted helpers retain real
  # strict TLS probes and never load this file or disable cURL functions.
  fake=W/'fixture-curl.php';fake.write_text("""<?php
function curl_init($url){return $url;}
function curl_setopt_array($h,$options){return true;}
function curl_exec($h){return json_encode(['v'=>1,'data'=>['api'=>'familyhub_native','version'=>1,'enabled'=>true,'serverId'=>file_exists(WORK.'/fixture-http-wrong')?'00000000-0000-4000-8000-000000000000':SERVER_ID]]);}
function curl_getinfo($h,$option){return hash_file('sha256',SITE.'/.htaccess')===HTACCESS_SHA?200:503;}
function curl_close($h){}
""");fake.chmod(0o600)
  def abort(mode):return php(['-d','disable_functions=curl_init,curl_setopt_array,curl_exec,curl_getinfo,curl_close','-d','auto_prepend_file='+host+'fixture-curl.php',host+'abort.php',mode])
  result('partial19-fixture-table',php(['-r',prefix+"$p->exec('CREATE TABLE familyhub_document_cleanup(id INTEGER) ENGINE=InnoDB');"]))
  negative('abort-refuses-partial19-table',abort('--check'),'schema19_table_detected')
  result('remove-fixture-partial-table',php(['-r',prefix+"$p->exec('DROP TABLE familyhub_document_cleanup');"]))
  (W/'stage').mkdir(mode=0o700);negative('abort-refuses-stage',abort('--check'),'stage_migration_or_release_detected');(W/'stage').rmdir()
  result('abort-check',abort('--check'))
  (W/'fixture-http-wrong').write_text('synthetic');negative('abort-refuses-wrong-native-identity',abort('--restore-http'),'native_capabilities_identity_guard');(W/'fixture-http-wrong').unlink()
  result('abort-resume-verify-http-after-original-http-restored',abort('--verify-http'))
  negative('abort-refuses-cron-confirm-before-restoration',abort('--confirm-cron'),'original_cron_not_restored')
  (W/'crontab.current').write_text(cron);result('abort-confirm-original-cron',abort('--confirm-cron'))
  assert (S/'.htaccess').read_bytes()==ht and (W/'crontab.current').read_text()==cron
  check=json.loads((W/'abort-checkpoint.json').read_text());assert check['schema']==18 and check['sourceFiles']==101 and check['noSqlRowsWritten'] and check['workerCronRestored']
  negative('abort-refuses-second-completed-abort',abort('--check'),'abort_already_completed')
  negative('upgrade-refuses-completed-abort-work',php([host+'upgrade.php','--stage',exported['archivePath'],exported['archiveSha256']]),'aborted_work_must_not_migrate')
  (M/'fixture-abort-evidence.json').write_text(json.dumps({'pass':True,'syntheticOnly':True,'fixtureOnlyHttpStub':True,'checkpoint':check,'reports':reports},indent=2)+'\n')
  print('PASS: pre-DDL abort preserves schema18/old101/config/keys/HTTPS/cron +6negative guards; private evidence '+str(M/'fixture-abort-evidence.json'));sys.exit(0)
 result('isolated-restore-start',run(['docker','run','-d','--name',restore,'--network','none','-e','MARIADB_ALLOW_EMPTY_ROOT_PASSWORD=yes','mariadb:10.11.19']));ready(restore)
 result('actual-isolated-restore',run(['python3',str(D/'restore-verify.py'),str(a),'--sha256',exported['archiveSha256'],'--container',restore,'--private-root',str(PRIVATE)]));shutil.copy2(M/'restore-proof.json',W/'restore-proof.json');(W/'restore-proof.json').chmod(0o600)
 proof=(W/'restore-proof.json').read_bytes();j=json.loads(proof);j['archiveSha256']='f'*64;(W/'restore-proof.json').write_text(json.dumps(j));negative('wrong-proof',php([host+'upgrade.php','--stage',exported['archivePath'],exported['archiveSha256']]),'actual_restore_proof_guard');(W/'restore-proof.json').write_bytes(proof)
 result('stage',php([host+'upgrade.php','--stage',exported['archivePath'],exported['archiveSha256']]))
 result('mutate-row',php(['-r',prefix+"$p->exec(\"UPDATE synthetic_backup_probe SET text_value='changed' WHERE id=1\");"]));negative('changed-row',php([host+'upgrade.php','--apply',exported['archiveSha256']]),'old_database_differs_from_verified_backup');result('restore-row',php(['-r',prefix+"$p->prepare('UPDATE synthetic_backup_probe SET text_value=? WHERE id=1')->execute([\"Šč ž quote ' \"]); "]))
 result('apply-schema18-to19',php([host+'upgrade.php','--apply',exported['archiveSha256']]))
 result('insert-synthetic-new-document-row',php(['-r',prefix+"$p->exec(\"INSERT INTO familyhub_document_cleanup(storage_key,created_at) VALUES(REPEAT('a',64),1)\");"]))
 negative('nonempty-new-document-table',php([host+'upgrade.php','--verify',exported['archiveSha256']]),'new_empty_document_table_definition_guard')
 result('remove-synthetic-new-document-row',php(['-r',prefix+"$p->exec('DELETE FROM familyhub_document_cleanup');"]))
 result('alter-synthetic-new-document-table',php(['-r',prefix+"$p->exec('ALTER TABLE familyhub_document_cleanup ADD COLUMN unreviewed INTEGER NULL');"]))
 negative('altered-new-document-table',php([host+'upgrade.php','--verify',exported['archiveSha256']]),'new_empty_document_table_definition_guard')
 result('restore-synthetic-new-document-table',php(['-r',prefix+"$p->exec('ALTER TABLE familyhub_document_cleanup DROP COLUMN unreviewed');"]))
 result('verify-paused',php([host+'upgrade.php','--verify',exported['archiveSha256']]))
 result('release-HTTP-while-worker-cron-paused',php([host+'upgrade.php','--release',exported['archiveSha256']]))
 negative('confirm-before-original-cron',php([host+'upgrade.php','--confirm-release',exported['archiveSha256']]),'original_cron_not_restored')
 (W/'crontab.current').write_text(cron);result('confirm-exact-original-cron-restored',php([host+'upgrade.php','--confirm-release',exported['archiveSha256']]))
 assert(S/'.htaccess').read_bytes()==ht and(W/'crontab.current').read_text()==cron
 negative('reapply-after-release',php([host+'upgrade.php','--apply',exported['archiveSha256']]),'paused_phase_or_backup_sha')
 checkpoint=json.loads((W/'release-checkpoint.json').read_text());assert len(checkpoint['newEmptyTables'])==5 and checkpoint['historicRowsDefsPasswordsDevicesAndFilesPreserved']
 evidence={'pass':True,'syntheticOnly':True,'fixtureMaintenanceClockOnlyAdvanced':True,'actualIsolatedRestore':True,'checkpoint':checkpoint,'reports':reports};(M/'fixture-evidence.json').write_text(json.dumps(evidence,indent=2)+'\n');print('PASS: populated schema18→19/export/real isolatedrestore/release +11negative guards; private evidence '+str(M/'fixture-evidence.json'))
except Exception as e:
 (M/'fixture-failure.json').write_text(json.dumps({'reports':reports,'failure':type(e).__name__+':'+str(e)},indent=2)+'\n');print('Fixture stopped; private secret-free evidence '+str(M/'fixture-failure.json'));sys.exit(1)
finally:
 for n in [runner,restore,db]:run(['docker','rm','-fv',n])
