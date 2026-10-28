#!/usr/bin/env python3
"""Create only fresh network-none synthetic MariaDB; never use an existing DB."""
from pathlib import Path
import json, secrets, subprocess, time
ROOT=Path(__file__).resolve().parents[3]
OUT=ROOT/'build/qa/fresh-reset-20261028';OUT.mkdir(parents=True,exist_ok=True)
name='jivie-fresh-reset-'+secrets.token_hex(5);created=False;events=[]
def run(argv):
    p=subprocess.run(argv,text=True,capture_output=True)
    events.append({'command':argv,'exitCode':p.returncode,'stdout':p.stdout,'stderr':p.stderr})
    if p.returncode:raise RuntimeError(p.stderr)
    return p
try:
    run(['docker','run','-d','--network','none','--name',name,'-e','MARIADB_ALLOW_EMPTY_ROOT_PASSWORD=yes','mariadb:10.11.19']);created=True
    for _ in range(50):
        p=subprocess.run(['docker','exec',name,'mariadb-admin','--protocol=tcp','-h127.0.0.1','ping','-uroot','--silent'],capture_output=True)
        if p.returncode==0:break
        time.sleep(1)
    else:raise RuntimeError('synthetic_db_startup')
    run(['docker','exec',name,'mariadb','-uroot','-e','CREATE DATABASE fresh_reset_synthetic CHARACTER SET utf8mb4'])
    p=run(['docker','run','--rm','--network','container:'+name,'--read-only','--tmpfs','/tmp:rw,size=64m','-e','FRESH_RESET_MYSQL=1','-v',str(ROOT)+':/source:ro','--entrypoint','php','jivie-crypto23-upgrade-fixture:20261028','/source/server/scripts/fresh-reset/fixture.php'])
    print(p.stdout)
finally:
    if created:
        p=subprocess.run(['docker','rm','-f','-v',name],text=True,capture_output=True)
        events.append({'cleanupExitCode':p.returncode,'stdout':p.stdout,'stderr':p.stderr})
    path=OUT/('mariadb-'+name+'.json');path.write_text(json.dumps(events,indent=2)+'\n');print(path)
