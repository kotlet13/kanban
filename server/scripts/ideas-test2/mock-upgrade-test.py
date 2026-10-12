#!/usr/bin/env python3
from pathlib import Path
import zipfile,subprocess,time,secrets,hashlib,json,shutil,os
os.umask(0o077)
ROOT=Path(__file__).resolve().parents[3];QA=ROOT/'build/qa/server-loss-test-20261011/package';PRIVATE=Path('/Users/anzenovsak/.local/share/jivie/backups/test2-ideas-preupgrade-20261012');PRIVATE.mkdir(parents=True,exist_ok=True,mode=0o700);PRIVATE.chmod(0o700)
MOCK=PRIVATE/('mock-ideas-'+secrets.token_hex(4));MOCK.mkdir(mode=0o700);HOME=MOCK/'home';SITE=HOME/'jivie-test2.triparna.si';SITE.mkdir(parents=True,mode=0o750);SITE.chmod(0o750);INSTALL=HOME/'private/jivie-test2/install';INSTALL.mkdir(parents=True,mode=0o700)
for p in [HOME/'private',INSTALL.parent,INSTALL]:p.chmod(0o700)
z=zipfile.ZipFile(ROOT/'build/releases/cpanel-fresh/kanboard-v1.2.54-upstream.zip');prefix='kanboard-kanboard-9ce6a5e/'
for info in z.infolist():
 if info.is_dir():continue
 p=SITE/info.filename[len(prefix):];p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(z.read(info))
(SITE/'plugins').mkdir(exist_ok=True);shutil.copy2(ROOT/'build/releases/test2-server-20261011/FamilyHub-0.11.2-source.zip',INSTALL/'FamilyHub-0.11.2-source.zip')
pw=secrets.token_hex(24);cfg=z.read(prefix+'config.default.php').decode().replace("define('DB_DRIVER', 'sqlite');","define('DB_DRIVER', 'mysql');").replace("define('DB_NAME', 'kanboard');","define('DB_NAME', 'tripar13_jivietest2');").replace("define('DB_HOSTNAME', 'localhost');","define('DB_HOSTNAME', '127.0.0.1');").replace("define('DB_PASSWORD', '');","define('DB_PASSWORD', '"+pw+"');")
(SITE/'config.php').write_text(cfg);helper=(QA/'test2-deploy.php').read_text().replace("const CONFIG_SHA='cc1f2c1448eec41b60a0d96cd96d27715c76b60a1a7a77139c53da86c4bc2692';","const CONFIG_SHA='"+hashlib.sha256(cfg.encode()).hexdigest()+"';");(INSTALL/'test2-deploy.php').write_text(helper)
shutil.copy2(ROOT/'build/releases/test2-server-20261011/test2-backup.php',INSTALL/'test2-backup.php')
env=MOCK/'db-env';env.write_text('MARIADB_ROOT_PASSWORD='+pw+'\nMARIADB_DATABASE=tripar13_jivietest2\nMARIADB_ROOT_HOST=%\n');env.chmod(0o600)
export='kanban-ideas-backup-mock-'+secrets.token_hex(3);restore='kanban-ideas-restore-mock-'+secrets.token_hex(3);runner='kanban-ideas-upgrade-runner-'+secrets.token_hex(3);reports=[]
def run(args,input=None):return subprocess.run(args,input=input,capture_output=True,text=True)
def php(args):return run(['docker','exec',runner,'php']+args)
def ready(name,tcp):
 for _ in range(60):
  cmd='mariadb-admin '+('--protocol=tcp -h127.0.0.1 'if tcp else'')+'ping -uroot '+('-p"$MARIADB_ROOT_PASSWORD" 'if name==export else'')+'--silent'
  r=run(['docker','exec',name,'sh','-c',cmd]);
  if r.returncode==0:return
  time.sleep(1)
 raise RuntimeError('mock MariaDB startup failed')
def result(stage,r):
 reports.append({'stage':stage,'returnCode':r.returncode,'stdout':r.stdout.replace(pw,'REDACTED'),'stderr':r.stderr.replace(pw,'REDACTED')});
 if r.returncode:raise RuntimeError('mock stage failed: '+stage)
try:
 r=run(['docker','run','-d','--name',export,'--env-file',str(env),'mariadb:10.11.19']);assert r.returncode==0;ready(export,True)
 r=run(['docker','run','-d','--name',runner,'--network','container:'+export,'-v',str(HOME)+':/home/tripar13','--entrypoint','sleep','kanban-test2-php84-tokenizer:20261011','3600']);assert r.returncode==0
 boot=INSTALL/'mock-bootstrap.php';boot.write_text("<?php require '/home/tripar13/jivie-test2.triparna.si/app/common.php'; $p=$container['db']->getConnection();$p->prepare('UPDATE users SET password=?')->execute([password_hash(bin2hex(random_bytes(24)),PASSWORD_BCRYPT)]);echo 'synthetic core initialized';")
 result('synthetic-core-init',php(['/home/tripar13/private/jivie-test2/install/mock-bootstrap.php']))
 for mode in ['--check','--prepare','--activate','--bootstrap','--enable']:result('deploy'+mode,php(['/home/tripar13/private/jivie-test2/install/test2-deploy.php',mode]))
 seed=INSTALL/'mock-seed.php';seed.write_text("""<?php
require '/home/tripar13/private/jivie-test2/config.php';
$p=new PDO('mysql:host=127.0.0.1;dbname=tripar13_jivietest2;charset=utf8mb4',DB_USERNAME,DB_PASSWORD,[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION]);
$p->exec("UPDATE familyhub_instance SET server_id='f48b41ae-c6bb-4f2d-ae13-0aa7fa255993' WHERE id=1");
$p->exec("INSERT INTO familyhub_accounts(user_id,account_id) VALUES(1,'12345678-1234-4234-a234-123456789abc')");
$p->prepare('INSERT INTO familyhub_devices(id,user_id,account_id,name,token_hash,credentials_hash,created_at,expires_at) VALUES(?,?,?,?,?,?,?,?)')->execute(['12345678-1234-4234-a234-123456789abd',1,'12345678-1234-4234-a234-123456789abc','synthetic-device',str_repeat('a',64),str_repeat('b',64),1,9999999999]);
$p->exec('CREATE TABLE synthetic_backup_probe(id INTEGER PRIMARY KEY,text_value TEXT NULL,value_number DECIMAL(12,2),binary_value LONGBLOB) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4');
$p->prepare('INSERT INTO synthetic_backup_probe VALUES(?,?,?,?)')->execute([1,"Šč ž — quote ' / backslash \\\\ newline\\n",'123.45',hex2bin('0009fffe0d0a')]);
$p->prepare('INSERT INTO synthetic_backup_probe VALUES(?,?,?,?)')->execute([2,null,'-0.10','']);
file_put_contents(DATA_DIR.'/files/synthetic.txt',"š č ž synthetic attachment\\n");chmod(DATA_DIR.'/files/synthetic.txt',0600);
file_put_contents(DATA_DIR.'/files/synthetic-binary.bin',hex2bin('00102030fffe0a'));chmod(DATA_DIR.'/files/synthetic-binary.bin',0600);
echo 'synthetic account/session/table/attachments seeded';
""")
 result('synthetic-seed',php(['/home/tripar13/private/jivie-test2/install/mock-seed.php']))
 # Bring the synthetic legacy deployment to the actual schema16/91-file baseline only.
 oldZip=zipfile.ZipFile(ROOT/'build/releases/FamilyHub-0.12.0-source.zip')
 for ent in oldZip.infolist():
  path=SITE/'plugins'/ent.filename;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(oldZip.read(ent));path.chmod(0o644)
 migrate=INSTALL/'mock-migrate16.php';migrate.write_text("<?php require '/home/tripar13/jivie-test2.triparna.si/app/common.php';if(session_status()===PHP_SESSION_ACTIVE)session_abort();echo 'synthetic schema16 initialized';")
 result('synthetic-schema16-baseline',php(['/home/tripar13/private/jivie-test2/install/mock-migrate16.php']))
 WORK=HOME/'private/jivie-test2/upgrade-0.13.0';WORK.mkdir(mode=0o700)
 shutil.copy2(ROOT/'server/scripts/ideas-test2/source-manifests.json',WORK/'source-manifests.json');(WORK/'source-manifests.json').chmod(0o600)
 fixtureSha=hashlib.sha256((HOME/'private/jivie-test2/config.php').read_bytes()).hexdigest()
 backup=(ROOT/'server/scripts/ideas-test2/backup-test2.php').read_text().replace("const CONFIG_SHA='6886ea49c2735c48150ea466a11309d3e3e832a7110783e28a33b91d02b1416a';","const CONFIG_SHA='"+fixtureSha+"';")
 (INSTALL/'test2-backup.php').write_text(backup);(INSTALL/'test2-backup.php').chmod(0o600)
 result('backup-check',php(['/home/tripar13/private/jivie-test2/install/test2-backup.php','--check']))
 r=php(['-d','disable_functions=imagejpeg','/home/tripar13/private/jivie-test2/install/test2-backup.php','--check']);assert r.returncode==1 and 'gd_png_jpeg_required' in r.stderr;reports.append({'stage':'negative-missing-gd-jpeg','guarded':True})
 result('backup-export',php(['/home/tripar13/private/jivie-test2/install/test2-backup.php','--export']))
 exported=json.loads(reports[-1]['stdout']);archive=MOCK/'Test2-private-backup.zip';source=HOME/Path(exported['archivePath']).relative_to('/home/tripar13');shutil.copy2(source,archive);archive.chmod(0o600)
 r=run(['docker','run','-d','--name',restore,'--network','none','-e','MARIADB_ALLOW_EMPTY_ROOT_PASSWORD=yes','mariadb:10.11.19']);assert r.returncode==0;ready(restore,True)
 # Official MariaDB image declares /var/lib/mysql VOLUME, so its isolated anonymous
 # volume is expected; it is never a host bind or pre-existing named volume.
 result('actual-isolated-restore',run(['python3',str(ROOT/'server/scripts/ideas-test2/restore-verify.py'),str(archive),'--sha256',exported['archiveSha256'],'--container',restore,'--private-root',str(PRIVATE)]))
 proof=json.loads((MOCK/'restore-proof.json').read_text());assert proof['everyRowAndFileHashMatches'] and proof['applicationOrWorkersStarted'] is False
 for f in ['source-manifests.json']:
  shutil.copy2(ROOT/'server/scripts/ideas-test2'/f,WORK/f);(WORK/f).chmod(0o600)
 shutil.copy2(ROOT/'build/releases/FamilyHub-0.13.0-source.zip',WORK/'FamilyHub-0.13.0-source.zip');(WORK/'FamilyHub-0.13.0-source.zip').chmod(0o600)
 shutil.copy2(MOCK/'restore-proof.json',WORK/'restore-proof.json');(WORK/'restore-proof.json').chmod(0o600)
 upgrader=(ROOT/'server/scripts/ideas-test2/upgrade-test2.php').read_text()
 fixtureSha=hashlib.sha256((HOME/'private/jivie-test2/config.php').read_bytes()).hexdigest()
 upgrader=upgrader.replace("const CONFIG_SHA='6886ea49c2735c48150ea466a11309d3e3e832a7110783e28a33b91d02b1416a';","const CONFIG_SHA='"+fixtureSha+"';")
 (WORK/'upgrade-test2.php').write_text(upgrader);(WORK/'upgrade-test2.php').chmod(0o600)
 host='/home/tripar13/private/jivie-test2/upgrade-0.13.0/upgrade-test2.php'
 result('upgrade-check',php([host,'--check']))
 # Independent schema/identity/GD negatives cannot stage or mutate the real upgrade graph.
 dbprefix="require '/home/tripar13/private/jivie-test2/config.php';$p=new PDO('mysql:host=127.0.0.1;dbname=tripar13_jivietest2;charset=utf8mb4',DB_USERNAME,DB_PASSWORD,[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION]);"
 php(['-r',dbprefix+"$p->exec(\"UPDATE plugin_schema_versions SET version=15 WHERE plugin='familyhub'\");"])
 r=php([host,'--check']);assert r.returncode==1 and 'server_identity_or_schema' in r.stderr;reports.append({'stage':'negative-old-schema15','guarded':True});php(['-r',dbprefix+"$p->exec(\"UPDATE plugin_schema_versions SET version=16 WHERE plugin='familyhub'\");"])
 php(['-r',dbprefix+"$p->exec(\"UPDATE familyhub_instance SET server_id='12345678-1234-4234-a234-123456789abc' WHERE id=1\");"])
 r=php([host,'--check']);assert r.returncode==1 and 'server_identity_or_schema' in r.stderr;reports.append({'stage':'negative-other-server-identity','guarded':True});php(['-r',dbprefix+"$p->exec(\"UPDATE familyhub_instance SET server_id='f48b41ae-c6bb-4f2d-ae13-0aa7fa255993' WHERE id=1\");"])
 r=php(['-d','disable_functions=imagejpeg',host,'--check']);assert r.returncode==1 and 'gd_png_jpeg_required' in r.stderr;reports.append({'stage':'negative-upgrade-missing-gd-jpeg','guarded':True})
 proofFile=WORK/'restore-proof.json';proofBytes=proofFile.read_bytes();stale=json.loads(proofBytes);stale['schema']=15;stale['format']='test2-server-loss-restore-proof-v1';proofFile.write_text(json.dumps(stale));proofFile.chmod(0o600)
 r=php([host,'--stage',exported['archivePath'],exported['archiveSha256']]);assert r.returncode==1 and 'actual_restore_proof_guard' in r.stderr;assert not (WORK/'state.json').exists();reports.append({'stage':'negative-old-schema15-restore-proof','guarded':True});proofFile.write_bytes(proofBytes);proofFile.chmod(0o600)
 # Corrupt source package: must refuse before stage, code or API changes.
 real=(WORK/'FamilyHub-0.13.0-source.zip').read_bytes()
 r=php(['-r',"$p='/home/tripar13/private/jivie-test2/upgrade-0.13.0/FamilyHub-0.13.0-source.zip';copy($p,$p.'.good');file_put_contents($p,'corrupt',FILE_APPEND);echo hash_file('sha256',$p);"]);assert r.returncode==0
 reports.append({'stage':'corrupt-bytes-visible-in-fixture','containerPackageSha256':r.stdout,'hostExpectedPackageSha256':hashlib.sha256(real).hexdigest()})
 r=php([host,'--check']);reports.append({'stage':'corrupt-package-result','returnCode':r.returncode,'stdout':r.stdout,'stderr':r.stderr});assert r.returncode==1 and 'archive_hash' in r.stderr
 reports.append({'stage':'negative-corrupt-package','guarded':True});php(['-r',"$p='/home/tripar13/private/jivie-test2/upgrade-0.13.0/FamilyHub-0.13.0-source.zip';copy($p.'.good',$p);"])
 # A proof from any other backup must fail before staging.
 php(['-r',"$p='/home/tripar13/private/jivie-test2/upgrade-0.13.0/restore-proof.json';copy($p,$p.'.good');$j=json_decode(file_get_contents($p),true);$j['archiveSha256']=str_repeat('f',64);file_put_contents($p,json_encode($j));"])
 r=php([host,'--stage',exported['archivePath'],exported['archiveSha256']]);assert r.returncode==1 and 'actual_restore_proof_guard' in r.stderr
 assert not (WORK/'state.json').exists();assert (INSTALL/'deploy-0.11.2/native-api.enabled').exists()
 reports.append({'stage':'negative-wrong-restored-backup','guarded':True});php(['-r',"$p='/home/tripar13/private/jivie-test2/upgrade-0.13.0/restore-proof.json';copy($p.'.good',$p);"])
 result('upgrade-stage',php([host,'--stage',exported['archivePath'],exported['archiveSha256']]))
 php(['-r',dbprefix+"$p->exec(\"UPDATE synthetic_backup_probe SET text_value=CONCAT(text_value,' changed') WHERE id=1\");"])
 r=php([host,'--pause',exported['archiveSha256']]);assert r.returncode==1 and 'old_database_differs_from_verified_backup' in r.stderr;assert (INSTALL/'deploy-0.11.2/native-api.enabled').exists();reports.append({'stage':'negative-live-row-after-verified-backup','guarded':True});php(['-r',dbprefix+"$p->exec(\"UPDATE synthetic_backup_probe SET text_value=REPLACE(text_value,' changed','') WHERE id=1\");"])
 result('upgrade-pause',php([host,'--pause',exported['archiveSha256']]))
 r=php([host,'--apply',exported['archiveSha256']]);assert r.returncode==1 and 'drain_65_seconds_required' in r.stderr
 reports.append({'stage':'negative-premature-apply','guarded':True})
 # Only the fixture clock is advanced. The production drain guard is unchanged.
 r=php([host,'--apply','0'*64]);assert r.returncode==1 and 'paused_phase_or_backup_sha' in r.stderr
 reports.append({'stage':'negative-wrong-apply-backup-sha','guarded':True})
 php(['-r',"$p='/home/tripar13/private/jivie-test2/upgrade-0.13.0/state.json';$j=json_decode(file_get_contents($p),true);$j['pausedAt']-=66;file_put_contents($p,json_encode($j));chmod($p,0600);"])
 result('upgrade-apply',php([host,'--apply',exported['archiveSha256']]))
 result('upgrade-verify-still-paused',php([host,'--verify',exported['archiveSha256']]))
 assert not (INSTALL/'deploy-0.11.2/native-api.enabled').exists() and (WORK/'native-api.paused').exists()
 result('upgrade-release',php([host,'--release',exported['archiveSha256']]))
 assert (INSTALL/'deploy-0.11.2/native-api.enabled').read_bytes()==b'test2-verified-v1\n'
 assert (WORK/'FamilyHub.original').is_dir() and (WORK/'FamilyHub.before').is_dir()
 r=php([host,'--apply',exported['archiveSha256']]);assert r.returncode==1 and 'paused_phase_or_backup_sha' in r.stderr
 reports.append({'stage':'negative-reapply-after-release','guarded':True})
 checkpoint=json.loads((WORK/'release-checkpoint.json').read_text());assert checkpoint['newSchema']==17 and checkpoint['historicRowsDefsPasswordsDevicesAndFilesPreserved']

 (ROOT/'build/qa/jivie-ideas-test2-upgrade/mock-upgrade-evidence.json').write_text(json.dumps({'pass':True,'PHP':'8.4.24','MariaDB':'10.11.19','upgradeHelperConfigShaOnlySubstitution':True,'onlyFixturePausedClockAdvanced':True,'checkpoint':checkpoint,'freshSchema16BackupAndRestoreHelpers':True,'reports':reports,'proof':proof,'archiveKeptOutsideRepo':True,'privateMockRoot':str(MOCK)},indent=2)+'\n');print('Actual nonempty MariaDB16-to17 upgrade, 96 code files, historical preservation, two empty tables, eleven negative guards and explicit release PASS')
except Exception as e:
 (ROOT/'build/qa/jivie-ideas-test2-upgrade/mock-upgrade-failure.json').write_text(json.dumps({'reports':reports,'failure':str(e)},indent=2)+'\n');print('Mock backup/restore failed; see secret-free evidence');raise
finally:
 run(['docker','rm','-fv',runner]);run(['docker','rm','-fv',restore]);run(['docker','rm','-fv',export])
