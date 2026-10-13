#!/usr/bin/env python3
"""Exercise only a fresh synthetic export/isolated restore/schema15-to17 fixture."""
from pathlib import Path
import zipfile,subprocess,time,secrets,hashlib,json,shutil,os
os.umask(0o077)
R=Path(__file__).resolve().parents[3];D=Path(__file__).parent
QA=R/'build/qa/reviewer-server-20261013';QA.mkdir(parents=True,exist_ok=True)
PRIVATE=Path('/Users/anzenovsak/.local/share/jivie/backups/reviewer-upgrade-20261013');PRIVATE.mkdir(parents=True,exist_ok=True,mode=0o700);PRIVATE.chmod(0o700)
M=PRIVATE/('fixture-'+secrets.token_hex(4));M.mkdir(mode=0o700)
H=M/'home';S=H/'jivie-test.triparna.si';S.mkdir(parents=True,mode=0o750)
B=H/'private/jivie-test';B.mkdir(parents=True,mode=0o700);B.parent.chmod(0o700)
W=B/'review-upgrade-0.13.0-20261013';W.mkdir(mode=0o700)
DATA=B/'data';DATA.mkdir(mode=0o700)
for name in ['files','cache']:(DATA/name).mkdir(mode=0o700)
with zipfile.ZipFile(R/'build/releases/cpanel-fresh/kanboard-v1.2.54-upstream.zip')as z:
 for ent in z.infolist():
  if ent.is_dir():continue
  p=S/ent.filename[len('kanboard-kanboard-9ce6a5e/'):];p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(z.read(ent))
with zipfile.ZipFile(R/'build/release/FamilyHub-0.11.2-retention-source.zip')as z:
 for n in z.namelist():
  p=S/'plugins'/n;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(z.read(n))
pw=secrets.token_hex(24)
cfg="<?php\ndefine('DB_DRIVER','mysql');define('DB_HOSTNAME','127.0.0.1');define('DB_NAME','tripar13_jivietest');define('DB_USERNAME','root');define('DB_PASSWORD','"+pw+"');define('DATA_DIR','/home/tripar13/private/jivie-test/data');define('FILES_DIR',DATA_DIR.'/files');define('CACHE_DIR',DATA_DIR.'/cache');define('FAMILYHUB_ENABLE_NATIVE_API',true);define('FAMILYHUB_ENABLE_FCM',true);define('FAMILYHUB_ENABLE_PROJECT_INVITATIONS',false);define('FAMILYHUB_ACCOUNT_MODE','self_hosted');\n"
(S/'config.php').write_text(cfg);(S/'config.php').chmod(0o600)
ht=(S/'.htaccess').read_bytes();cs=hashlib.sha256(cfg.encode()).hexdigest();hs=hashlib.sha256(ht).hexdigest()
for name in ['backup.php','upgrade.php','maintenance.php','maintenance-guards.php','source-manifests.json']:
 p=W/name
 if name.endswith('.php'):
  text=(D/name).read_text().replace('1ac606ebd043f741b61b697e02a70bf5afd177d6126c2772689cf9585d6c3b59',cs).replace('950b50a0e6df95a446b1a3023e49fe1d75ff0614a731db848503705c53a98a12',hs);p.write_text(text)
 else:shutil.copy2(D/name,p)
 p.chmod(0o600)
shutil.copy2(R/'build/releases/FamilyHub-0.13.0-source.zip',W/'FamilyHub-0.13.0-source.zip')
env=M/'db.env';env.write_text('MARIADB_ROOT_PASSWORD='+pw+'\nMARIADB_DATABASE=tripar13_jivietest\nMARIADB_ROOT_HOST=%\n');env.chmod(0o600)
db='jivie-review-fixture-db-'+secrets.token_hex(3);runner='jivie-review-fixture-php-'+secrets.token_hex(3);restore='jivie-review-fixture-restore-'+secrets.token_hex(3);reports=[]
def run(args,data=None):return subprocess.run(args,input=data,capture_output=True,text=True)
def php(args):return run(['docker','exec',runner,'php']+args)
def result(stage,r):
 reports.append({'stage':stage,'returnCode':r.returncode,'stdout':r.stdout.replace(pw,'REDACTED'),'stderr':r.stderr.replace(pw,'REDACTED')})
 if r.returncode:raise RuntimeError('fixture stage failed: '+stage)
def ready(name,auth=False):
 for _ in range(45):
  r=run(['docker','exec',name,'sh','-c','mariadb-admin --protocol=tcp -h127.0.0.1 ping -uroot '+('-p"$MARIADB_ROOT_PASSWORD" 'if auth else'')+'--silent'])
  if r.returncode==0:return
  time.sleep(1)
 raise RuntimeError('fixture db startup failed')
host='/home/tripar13/private/jivie-test/review-upgrade-0.13.0-20261013/'
prefix="require '/home/tripar13/jivie-test.triparna.si/config.php';$p=new PDO('mysql:host=127.0.0.1;dbname=tripar13_jivietest;charset=utf8mb4',DB_USERNAME,DB_PASSWORD,[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION]);"
try:
 result('db-start',run(['docker','run','-d','--name',db,'--env-file',str(env),'mariadb:10.11.19']));ready(db,True)
 result('php-start',run(['docker','run','-d','--name',runner,'--network','container:'+db,'-v',str(H)+':/home/tripar13','--entrypoint','sleep','kanban-test2-php84-tokenizer:20261011','3600']))
 for n in ['backup.php','upgrade.php','maintenance.php','maintenance-guards.php']:result('lint-'+n,php(['-l',host+n]))
 result('core-plugin-init',php(['-r',"require '/home/tripar13/jivie-test.triparna.si/app/common.php';$container['pluginLoader']->scan();echo 'synthetic core initialized';"]))
 result('seed',php(['-r',prefix+"$p->exec(\"UPDATE familyhub_instance SET server_id='95c11fe0-916c-48be-a3f6-999732846266' WHERE id=1\");$p->exec(\"INSERT INTO familyhub_accounts(user_id,account_id) VALUES(1,'12345678-1234-4234-a234-123456789abc')\");$p->prepare('UPDATE users SET password=?')->execute([password_hash(bin2hex(random_bytes(24)),PASSWORD_BCRYPT)]);$p->exec('CREATE TABLE synthetic_backup_probe(id INTEGER PRIMARY KEY,text_value TEXT NULL,value_number DECIMAL(12,2),binary_value LONGBLOB) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4');$p->prepare('INSERT INTO synthetic_backup_probe VALUES(?,?,?,?)')->execute([1,\"Šč ž quote ' \", '123.45',hex2bin('0009fffe0a')]);echo 'synthetic data seeded';"]))
 (DATA/'files/synthetic.bin').write_bytes(bytes.fromhex('0010fffe0a'));(DATA/'files/synthetic.bin').chmod(0o600)
 scripts=['reminders.php','delivery.php','account-mail.php','account-deletion-cleanup.php','push.php']
 cron=''.join('* * * * * php /home/tripar13/jivie-test.triparna.si/plugins/FamilyHub/cli/'+n+'\n'for n in scripts)+'# unrelated cron preserved\n'
 (W/'crontab.original').write_text(cron);(W/'crontab.original').chmod(0o600)
 result('backup-check',php([host+'backup.php','--check']))
 result('upgrade-check',php([host+'upgrade.php','--check']))
 r=php(['-d','disable_functions=imagejpeg',host+'backup.php','--check']);assert r.returncode==1 and 'gd_png_jpeg_required' in r.stderr;reports.append({'stage':'missing-GD','guarded':True})
 result('prepare-pause-candidate',php([host+'maintenance.php','--prepare']))
 # Only this fixture supplies a synthetic cron/maintenance state and advances its clock.
 (W/'crontab.current').write_bytes((W/'crontab.paused').read_bytes());(W/'workers.drained').write_text(hashlib.sha256((W/'crontab.paused').read_bytes()).hexdigest())
 paused=b'# JIVIE REVIEW UPGRADE MAINTENANCE\nRewriteEngine On\nRewriteRule ^ - [R=503,L]\n'+ht
 (S/'.htaccess').write_bytes(paused);(W/'maintenance.sha256').write_text(hashlib.sha256(paused).hexdigest());(W/'maintenance.started').write_text(str(int(time.time())))
 r=php([host+'backup.php','--export']);assert r.returncode==1 and 'drain_65_seconds_required' in r.stderr;reports.append({'stage':'premature-export','guarded':True})
 (W/'maintenance.started').write_text(str(int(time.time())-66))
 result('backup-export',php([host+'backup.php','--export']));exported=json.loads(reports[-1]['stdout'])
 a=M/'ReviewTest1-private-backup.zip';shutil.copy2(H/Path(exported['archivePath']).relative_to('/home/tripar13'),a);a.chmod(0o600)
 result('isolated-restore-start',run(['docker','run','-d','--name',restore,'--network','none','-e','MARIADB_ALLOW_EMPTY_ROOT_PASSWORD=yes','mariadb:10.11.19']));ready(restore)
 result('actual-isolated-restore',run(['python3',str(D/'restore-verify.py'),str(a),'--sha256',exported['archiveSha256'],'--container',restore,'--private-root',str(PRIVATE)]))
 shutil.copy2(M/'restore-proof.json',W/'restore-proof.json');(W/'restore-proof.json').chmod(0o600)
 proof=(W/'restore-proof.json').read_bytes();j=json.loads(proof);j['archiveSha256']='f'*64;(W/'restore-proof.json').write_text(json.dumps(j))
 r=php([host+'upgrade.php','--stage',exported['archivePath'],exported['archiveSha256']]);assert r.returncode==1 and 'actual_restore_proof_guard' in r.stderr;reports.append({'stage':'wrong-proof','guarded':True});(W/'restore-proof.json').write_bytes(proof)
 result('stage',php([host+'upgrade.php','--stage',exported['archivePath'],exported['archiveSha256']]))
 result('mutate-fixture-row',php(['-r',prefix+"$p->exec(\"UPDATE synthetic_backup_probe SET text_value='changed' WHERE id=1\");"]))
 r=php([host+'upgrade.php','--apply',exported['archiveSha256']]);assert r.returncode==1 and 'old_database_differs_from_verified_backup' in r.stderr;reports.append({'stage':'changed-row','guarded':True})
 result('restore-fixture-row',php(['-r',prefix+"$p->prepare('UPDATE synthetic_backup_probe SET text_value=? WHERE id=1')->execute([\"Šč ž quote ' \"]); "]))
 result('apply-schema15-to17',php([host+'upgrade.php','--apply',exported['archiveSha256']]))
 result('verify-paused',php([host+'upgrade.php','--verify',exported['archiveSha256']]))
 (W/'crontab.current').write_text(cron)
 result('release',php([host+'upgrade.php','--release',exported['archiveSha256']]))
 assert (S/'.htaccess').read_bytes()==ht and (W/'crontab.current').read_text()==cron
 r=php([host+'upgrade.php','--apply',exported['archiveSha256']]);assert r.returncode==1 and 'paused_phase_or_backup_sha' in r.stderr;reports.append({'stage':'reapply-after-release','guarded':True})
 checkpoint=json.loads((W/'release-checkpoint.json').read_text());assert len(checkpoint['newEmptyTables'])==6 and checkpoint['historicRowsDefsPasswordsDevicesAndFilesPreserved']
 (QA/'fixture-evidence.json').write_text(json.dumps({'pass':True,'fixtureConfigPinsOnlySubstituted':True,'onlyFixtureClockAdvanced':True,'checkpoint':checkpoint,'reports':reports},indent=2)+'\n')
 print('Synthetic export/isolated restore/schema15-to17 + six empty tables/preservation/release and negative guards PASS')
except Exception as e:
 (QA/'fixture-failure.json').write_text(json.dumps({'reports':reports,'failure':str(e)},indent=2)+'\n');print('Fixture stopped; secret-free evidence saved');raise
finally:
 for n in [runner,restore,db]:run(['docker','rm','-fv',n])
