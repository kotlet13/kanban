#!/usr/bin/env python3
"""Synthetic MariaDB18 code-only patch rehearsal; never connects to a hosted server."""
from pathlib import Path
import subprocess,secrets,time,json,shutil,zipfile,os
os.umask(0o077)
D=Path(__file__).resolve().parent;R=D.parents[2]
PRIOR=Path('/Users/anzenovsak/.local/share/jivie/backups/lifecycle18-fixtures/fixture-97ed90a5')
ROOT=Path('/Users/anzenovsak/.local/share/jivie/backups/sound-default-fixtures');ROOT.mkdir(mode=0o700,parents=True,exist_ok=True)
M=ROOT/('fixture-'+secrets.token_hex(4));M.mkdir(mode=0o700);H=M/'home';shutil.copytree(PRIOR/'home',H)
S=H/'jivie-test.triparna.si';B=H/'private/jivie-test';shutil.rmtree(S/'plugins/FamilyHub')
with zipfile.ZipFile(R/'build/release/FamilyHub-0.14.0-upgrade-20261014.zip')as z:
 for e in z.infolist():
  p=S/'plugins'/e.filename;p.parent.mkdir(mode=0o755,parents=True,exist_ok=True);p.write_bytes(z.read(e));p.chmod(0o644)
W=B/('sound-default-0.14.1-'+time.strftime('%Y%m%d-%H%M%S',time.gmtime()));W.mkdir(mode=0o700);host='/home/tripar13/private/jivie-test/'+W.name
for n in ['capture.php','common.php','old-manifest.json']:shutil.copy2(D/n,W/n);(W/n).chmod(0o600)
(W/'cron.capture').write_bytes((B/'cron.capture').read_bytes());(W/'cron.capture').chmod(0o600)
shutil.copy2(PRIOR/'db.env',M/'db.env');db='jivie-sound-fixture-db-'+secrets.token_hex(3);runner='jivie-sound-fixture-php-'+secrets.token_hex(3);reports=[]
def run(args,data=None):return subprocess.run(args,input=data,capture_output=True,text=True)
def php(args):return run(['docker','exec',runner,'php']+args)
def check(stage,r):
 reports.append({'stage':stage,'returnCode':r.returncode,'stdout':r.stdout,'stderr':r.stderr})
 if r.returncode:raise RuntimeError(stage)
def negative(stage,r,guard):
 assert r.returncode==1 and guard in r.stderr,(stage,r.stderr);reports.append({'stage':stage,'guarded':True})
try:
 check('database-start',run(['docker','run','-d','--name',db,'--network','none','--env-file',str(M/'db.env'),'mariadb:10.11.19']))
 for _ in range(45):
  r=run(['docker','exec',db,'sh','-c','mariadb-admin --protocol=tcp -h127.0.0.1 ping -uroot -p"$MARIADB_ROOT_PASSWORD" --silent'])
  if r.returncode==0:break
  time.sleep(1)
 else:raise RuntimeError('database_startup')
 check('synthetic17-import',run(['docker','exec','-i',db,'sh','-c','mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" tripar13_jivietest'],(PRIOR/'verified-restore/database.sql').read_text()))
 check('runner-start',run(['docker','run','-d','--name',runner,'--network','container:'+db,'-v',str(H)+':/home/tripar13','--entrypoint','sleep','kanban-test2-php84-tokenizer:20261011','3600']))
 check('baseline18-initialize',php(['-r',"require '/home/tripar13/jivie-test.triparna.si/app/common.php';$container['pluginLoader']->scan();echo 'synthetic schema18';"]))
 seed="require '/home/tripar13/jivie-test.triparna.si/config.php';$p=new PDO('mysql:host=127.0.0.1;dbname=tripar13_jivietest;charset=utf8mb4',DB_USERNAME,DB_PASSWORD);$q=$p->prepare('INSERT INTO familyhub_inbox_preferences VALUES(?,?,?,?)');foreach(['tasks'=>'{\"sound\":false, \"push\":true, \"inApp\":true, \"email\":false}','events'=>'{\"sound\":true}','reminders'=>'{\"push\":false}']as$c=>$json)$q->execute(['12345678-1234-4234-a234-123456789111','12345678-1234-4234-a234-123456789abc',$c,$json]);echo 'synthetic false/true/partial raw JSON rows seeded';"
 check('seed-raw-legacy-settings',php(['-r',seed]))
 check('capture',php([host+'/capture.php','test1',host+'/cron.capture']));capture=M/'capture.json';capture.write_text(reports[-1]['stdout']);capture.chmod(0o600)
 check('prepare',run(['python3',str(D/'prepare.py'),str(capture),str(M/'sealed'),'--host-work',host]))
 for p in (M/'sealed').rglob('*'):
  dest=W/p.relative_to(M/'sealed')
  if p.is_dir():dest.mkdir(mode=0o700,exist_ok=True)
  else:shutil.copy2(p,dest)
 (W/'crontab.current').write_bytes((W/'cron.capture').read_bytes());(W/'crontab.current').chmod(0o600)
 for n in ['common.php','capture.php','patch.php','deployment.php']:check('lint-'+n,php(['-l',host+'/'+n]))
 check('preflight',php([host+'/patch.php','--check']))
 target=W/'files/Model/NativeNotificationPreferences.php';body=target.read_bytes();target.write_bytes(body+b'\n// synthetic drift\n');negative('staged-hash-mismatch',php([host+'/patch.php','--apply']),'staged_php_hash');target.write_bytes(body)
 target=S/'plugins/FamilyHub/Model/NativeNotificationPreferences.php';body=target.read_bytes();target.write_bytes(body+b'\n// synthetic drift\n');negative('old-source-mismatch',php([host+'/patch.php','--apply']),'exact_old101_source_required');target.write_bytes(body)
 (W/'crontab.current').write_text('# synthetic changed cron\n');negative('cron-mismatch',php([host+'/patch.php','--apply']),'database_data_config_cron_changed_recapture_required');(W/'crontab.current').write_bytes((W/'cron.capture').read_bytes())
 check('apply',php([host+'/patch.php','--apply']));checkpoint=json.loads(reports[-1]['stdout']);assert checkpoint['allPreferenceBytesPreserved']and checkpoint['preferenceRows']==3 and not checkpoint['databaseRowsWritten']and not checkpoint['ddlExecuted']and not checkpoint['cronChanged']
 negative('reapply-refused',php([host+'/patch.php','--apply']),'fresh_destination_required')
 (M/'fixture-evidence.json').write_text(json.dumps({'pass':True,'syntheticOnly':True,'actualMariaDB':'10.11.19','schema':18,'network':'none','checkpoint':checkpoint,'reports':reports},indent=2)+'\n');print('Code-only fixture PASS; private evidence '+str(M/'fixture-evidence.json'))
except Exception as e:
 (M/'fixture-failure.json').write_text(json.dumps({'reports':reports,'failure':str(e)},indent=2)+'\n');print('Code-only fixture stopped: private evidence '+str(M/'fixture-failure.json'));raise
finally:
 for name in [runner,db]:run(['docker','rm','-fv',name])
