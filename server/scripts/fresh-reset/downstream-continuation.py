#!/usr/bin/env python3
"""Continue failing reset stage only from already PASS backup+isolated restore."""
from pathlib import Path
import hashlib,json,os,secrets,shutil,subprocess,time,sys
os.umask(0o077);D=Path(__file__).resolve().parent;R=D.parents[2];M=Path(sys.argv[1]);H=M/'home';S=H/'jivie-test.triparna.si';B=H/'private/jivie-test';DATA=B/'data';events=[];owned=[]
previous=json.loads((M/'results.json').read_text());export=json.loads(next(x['stdout']for x in previous if x.get('stage')=='complete-frozen-backup'));archive=H/Path(export['archivePath']).relative_to('/home/tripar13');sha=export['archiveSha256'];newparent=archive.parent.with_name(archive.parent.name.replace('crypto23-preupgrade-','fresh-reset23-before-',1));archive.parent.rename(newparent);archive=newparent/archive.name
assert hashlib.sha256(archive.read_bytes()).hexdigest()==sha
host='/home/tripar13/'+str(next((B).glob('fresh-reset23-*')).relative_to(H));W=H/Path(host).relative_to('/home/tripar13');hostarchive='/home/tripar13/'+str(archive.relative_to(H));name='jivie-reset-cont-'+secrets.token_hex(4);db=name+'-db';runner=name+'-php'
def run(args,data=None):return subprocess.run(args,input=data,text=True,capture_output=True)
def record(stage,p):
 events.append({'stage':stage,'exitCode':p.returncode,'stdout':p.stdout,'stderr':p.stderr})
 if p.returncode:raise RuntimeError(stage)
 return p
def ready(n):
 for _ in range(50):
  if run(['docker','exec',n,'mariadb-admin','--protocol=tcp','-h127.0.0.1','ping','-uroot','--silent']).returncode==0:return
  time.sleep(1)
 raise RuntimeError('new_source_db_startup')
def refresh():
 (W/'crontab.current').write_bytes((W/'crontab.paused').read_bytes());(W/'workers.drained').write_text(hashlib.sha256((W/'crontab.paused').read_bytes()).hexdigest())
def php(args):
 refresh();return run(['docker','exec',runner,'php']+args)
def fail(stage,p,code):
 events.append({'stage':stage,'exitCode':p.returncode,'guarded':p.returncode==1 and code in p.stderr,'stderr':p.stderr})
 if p.returncode!=1 or code not in p.stderr:raise RuntimeError(stage)
try:
 # Known exact synthetic SQL/row/file restore already verified independently once.
 record('fresh-continuation-db',run(['docker','run','-d','--name',db,'--network','none','-e','MARIADB_ALLOW_EMPTY_ROOT_PASSWORD=yes','-e','MARIADB_DATABASE=tripar13_jivietest','mariadb:10.11.19']));owned.append(db);ready(db)
 record('load-already-verified-source-snapshot',run(['docker','exec','-i',db,'mariadb','-uroot','tripar13_jivietest'],(archive.parent/'verified-restore/database.sql').read_text()))
 # Refresh reviewed helper code only; frozen deployment/schema/source pins unchanged.
 for n in ['backup-library.php','backup.php','ResetDatabase.php','InventoryFiles.php','reset.php','maintenance-guards.php','delivery-guards.php']:
  shutil.copy2(D/n,W/n);(W/n).chmod(0o600)
 record('fresh-continuation-php',run(['docker','run','-d','--name',runner,'--network','container:'+db,'-v',str(H)+':/home/tripar13','-v',str(R)+':/source:ro','-v',str(M)+':/fixture-work','--entrypoint','sleep','jivie-crypto23-upgrade-fixture:20261028','3600']));owned.append(runner)
 record('stage-after-path-correction',php([host+'/reset.php','--stage',hostarchive,sha]))
 holder="""$f=fopen('/home/tripar13/private/jivie-test/data/familyhub/crypto/migration.lock','c');flock($f,LOCK_EX);file_put_contents('/fixture-work/continuation-lease-held',(string)getmypid());sleep(60);"""
 record('hold-real-crypto-lock',run(['docker','exec','-d',runner,'php','-r',holder]))
 for _ in range(50):
  if (M/'continuation-lease-held').exists():break
  time.sleep(.1)
 fail('actual-competing-lease-refuses-apply',php([host+'/reset.php','--apply',hostarchive,sha]),'exclusive_crypto_lease_required')
 pid=(M/'continuation-lease-held').read_text();assert pid.isdigit();record('release-only-owned-lock-holder',run(['docker','exec',runner,'kill',pid]))
 record('apply-quarantine-and-db-once',php([host+'/reset.php','--apply',hostarchive,sha]));record('read-verify-after-apply',php([host+'/reset.php','--verify',hostarchive,sha]))
 fail('second-apply-refused',php([host+'/reset.php','--apply',hostarchive,sha]),'apply_requires_staged_once')
 record('explicit-http-release',php([host+'/reset.php','--release-http',hostarchive,sha]));assert (S/'.htaccess').stat().st_mode&0o777==0o644
 record('post-http-empty-queue-and-retention-guard',php([host+'/reset.php','--worker-release-check']))
 state=json.loads((W/'reset-state.json').read_text());(W/'public-capabilities.json').write_text(json.dumps({'data':{'serverId':state['result']['newServerId']}}));(W/'public-capabilities.json').chmod(0o600);(W/'crontab.current').write_bytes((W/'crontab.original').read_bytes())
 # Confirm original cron state without refreshing it back to synthetic paused bytes.
 record('original-cron-release-confirmation',run(['docker','exec',runner,'php',host+'/reset.php','--confirm-workers-released']))
 assert (DATA/'files/core.bin').read_bytes()==bytes(range(256));assert (B/'fake-private.key').read_bytes()==bytes(range(32));assert (W/'quarantine-data/familyhub/attachments/probe').read_bytes()==b'old attachment\0';assert (W/'quarantine-data/familyhub/ideas/probe').read_bytes()==b'old idea\xff';assert archive.exists()
 print(json.dumps({'status':'PASS','fixtureRoot':str(M),'stages':len(events),'actualFullIsolatedRestore':'prior_PASS_not_repeated','actualFilesystemQuarantine':True,'actualKernelLockConflict':True,'releaseHtaccessMode644':True,'syntheticDrainClockAndFinalCapabilityOnly':True,'originalCaptureFixture':'STOP3_not_repeated','backupAndRestoreCases':'prior_PASS_not_repeated'}))
except Exception as e:
 print(json.dumps({'status':'FAIL','stage':str(e),'fixtureRoot':str(M),'last':events[-1] if events else None}));sys.exit(1)
finally:
 for n in reversed(owned):events.append({'cleanup':n,'exitCode':run(['docker','rm','-f','-v',n]).returncode})
 (M/'continuation-results.json').write_text(json.dumps(events,indent=2)+'\n');(M/'continuation-results.json').chmod(0o600)
