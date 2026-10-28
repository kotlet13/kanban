#!/usr/bin/env python3
"""Replay only failing downstream apply on retained exact synthetic backup; no capture/export/restore-test rerun."""
from pathlib import Path
import subprocess,json,secrets,time,shutil,hashlib,sys,os
os.umask(0o077)
D=Path(__file__).resolve().parent;M=Path(sys.argv[1]);H=M/'home';results=json.loads((M/'results.json').read_text());seal=json.loads(next(r['stdout']for r in results if r['stage']=='seal'));host=seal['hostWork']+'/';W=H/Path(seal['hostWork']).relative_to('/home/tripar13');backup=json.loads(next(r['stdout']for r in results if r['stage']=='full-consistent-export'));A=H/Path(backup['archivePath']).relative_to('/home/tripar13');digest=backup['archiveSha256'];db='jivie-crypto23-apply-retry-db-'+secrets.token_hex(3);runner='jivie-crypto23-apply-retry-php-'+secrets.token_hex(3);report=[]
def run(args,data=None):return subprocess.run(args,input=data,capture_output=True,text=True)
def result(stage,r):
 report.append({'stage':stage,'returnCode':r.returncode,'stdout':r.stdout,'stderr':r.stderr})
 if r.returncode:raise RuntimeError(stage)
def php(args):return run(['docker','exec',runner,'php']+args)
def negative(stage,r,code):
 report.append({'stage':stage,'returnCode':r.returncode,'guarded':r.returncode==1 and code in r.stderr})
 if r.returncode!=1 or code not in r.stderr:raise RuntimeError(stage)
prefix="require '/home/tripar13/jivie-test.triparna.si/config.php';$p=new PDO('mysql:host=127.0.0.1;dbname=tripar13_jivietest;charset=utf8mb4',DB_USERNAME,DB_PASSWORD,[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION]);"
try:
 result('fresh-isolated-apply-db',run(['docker','run','-d','--name',db,'--network','none','-e','MARIADB_ALLOW_EMPTY_ROOT_PASSWORD=yes','mariadb:10.11.19']))
 for _ in range(45):
  if run(['docker','exec',db,'mariadb-admin','--protocol=tcp','-h127.0.0.1','ping','-uroot','--silent']).returncode==0:break
  time.sleep(1)
 else:raise RuntimeError('db_startup')
 result('recreate-only-synthetic-baseline-db',run(['docker','exec','-i',db,'mariadb','-uroot'], 'CREATE DATABASE tripar13_jivietest CHARACTER SET utf8mb4;'))
 result('reload-retained-verified-baseline-input',run(['docker','exec','-i',db,'mariadb','-uroot','tripar13_jivietest'],(A.parent/'verified-restore/database.sql').read_text()))
 result('php-start',run(['docker','run','-d','--name',runner,'--network','container:'+db,'-v',str(H)+':/home/tripar13','--entrypoint','sleep','jivie-crypto23-upgrade-fixture:20261028','3600']))
 # Recreate the exact applyinput on this disposablefixtureonly, never productionstate.
 state=json.loads((W/'state.json').read_text());assert state['phase']=='migrating';state['phase']='paused';(W/'state.json').write_text(json.dumps(state,indent=2)+'\n');(W/'state.json').chmod(0o600);shutil.copy2(D/'schema-guards.php',W/'schema-guards.php');(W/'schema-guards.php').chmod(0o600);(W/'workers.drained').write_text(hashlib.sha256((W/'crontab.paused').read_bytes()).hexdigest())
 result('apply-attempt2',php([host+'upgrade.php','--apply',digest]));result('verify-once-after-apply',php([host+'upgrade.php','--verify',digest]))
 result('mutate-old-history-for-rejection',php(['-r',prefix+"$p->exec(\"UPDATE familyhub_inbox_state SET sequence=sequence+1\");"]))
 negative('old-history-change-blocks-release',php([host+'upgrade.php','--release',digest]),'historical_row_values_changed')
 result('repair-synthetic-history',php(['-r',prefix+"$p->exec(\"UPDATE familyhub_inbox_state SET sequence=sequence-1\");"]))
 result('release-http-state',php([host+'upgrade.php','--release',digest]));(W/'crontab.current').write_bytes((W/'crontab.upgraded').read_bytes());(W/'public-capabilities.json').write_text(json.dumps({'data':{'serverId':'95c11fe0-916c-48be-a3f6-999732846266','cryptoTransportVersions':[1,2]}}));(W/'public-capabilities.json').chmod(0o600);result('confirm-cron-state-synthetic-public-proof',php([host+'upgrade.php','--confirm-release',digest]))
 print(json.dumps({'status':'PASS','fixtureRoot':str(M),'report':'apply-retry-results.json','captureCase':'STOP3_not_repeated','backupAndRestoreCases':'priorPASS_not_repeated','realHttpsAndCronNotExercised':True,'syntheticDrainClockOnly':True}))
except Exception as e:
 print(json.dumps({'status':'FAIL','code':str(e),'fixtureRoot':str(M),'last':report[-1]if report else None}));sys.exit(1)
finally:
 (M/'apply-retry-results.json').write_text(json.dumps(report,indent=2)+'\n');(M/'apply-retry-results.json').chmod(0o600)
 for name in [runner,db]:run(['docker','rm','-f','-v',name])
