#!/usr/bin/env python3
"""Owned mobile QA 18801 source/schema upgrade; no authenticated or business RPCs."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import shutil
import socket
import sqlite3
import ssl
import subprocess
import urllib.request

REPO = Path(__file__).resolve().parents[2]
LIVE = REPO / 'build/qa/jivie-mobile-two-user-20261018/server'
SOURCE = REPO / 'server/plugins/FamilyHub'
PUBLIC = REPO / 'build/qa/jivie-mobile-update-20261024/server'
PRIVATE_ROOT = Path('/Users/anzenovsak/Library/Application Support/JivieLocalTest/20261018-mobile-two-user')
PRIVATE = PRIVATE_ROOT / 'upgrade149ed06-20261024'
CA = REPO / 'build/qa/jivie-mobile-tls-renewal-20261021/public/qa-ca.pem'
PREFIX = 'jivie-mobile-two-user-20261018'
SERVICES = ['gateway', 'account-mail-worker', 'app', 'mailpit']
NAMES = {key: PREFIX + '-' + key + '-1' for key in SERVICES}
SID = 'a1f38e6b-9092-4d22-a281-76aaa8b31eb9'
URL = 'https://192.168.132.29:18801/'


def save(path, value):
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2) + '\n')
    if str(path).startswith(str(PRIVATE_ROOT)): path.chmod(0o600)


def run(args, input=None, timeout=45):
    result = subprocess.run(args, input=input, capture_output=True, timeout=timeout)
    if result.returncode:
        PRIVATE.mkdir(mode=0o700, parents=True, exist_ok=True)
        save(PRIVATE / 'last-command-error-private.json', {'command': args[:3], 'code': result.returncode,
             'stdout': result.stdout.decode(errors='replace')[:16384], 'stderr': result.stderr.decode(errors='replace')[:16384]})
        raise RuntimeError('Owned QA command failed: ' + ' '.join(args[:3]))
    return result.stdout


def manifest(root):
    return {str(path.relative_to(root)): {'sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'bytes': path.stat().st_size}
            for path in sorted(root.rglob('*')) if path.is_file()}


def inventory():
    rows = [json.loads(line) for line in run(['docker', 'ps', '-a', '--format', '{{json .}}']).splitlines()]
    return {row['Names']: {key: row[key] for key in ['ID', 'State', 'Image']} for row in rows}


def owned():
    result = {}
    for service, name in NAMES.items():
        obj = json.loads(run(['docker', 'inspect', name]))[0]
        labels = obj['Config']['Labels']
        if labels.get('com.docker.compose.project') != PREFIX or labels.get('com.docker.compose.service') != service:
            raise RuntimeError('Wrong mobile QA ownership')
        mounts = {mount['Destination']: mount for mount in obj['Mounts']}
        if service in ['app', 'account-mail-worker']:
            source = mounts['/var/www/app/plugins/FamilyHub']
            if source['RW'] is not False or source['Source'].removeprefix('/host_mnt') != str(LIVE / 'FamilyHub'):
                raise RuntimeError('Wrong mobile source bind')
            if mounts['/var/www/app/data'].get('Name') != PREFIX + '_app-data':
                raise RuntimeError('Wrong retained mobile data volume')
        if service == 'gateway' and obj['State']['Running'] and obj['HostConfig']['PortBindings'].get('8443/tcp') != [{'HostIp': '192.168.132.29', 'HostPort': '18801'}]:
            raise RuntimeError('Wrong mobile TLS binding')
        result[service] = {'id': obj['Id'], 'image': obj['Image'], 'running': obj['State']['Running'],
                           'startedAt': obj['State']['StartedAt'], 'networkNames': sorted(obj['NetworkSettings']['Networks'])}
    return result


def db_report(path):
    connection = sqlite3.connect(path.as_uri() + '?mode=ro&immutable=1', uri=True)
    try:
        tables = {}
        for (name,) in connection.execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"):
            rows = connection.execute('SELECT * FROM "' + name.replace('"', '""') + '"').fetchall()
            tables[name] = {'rows': len(rows), 'sha256': hashlib.sha256(b'\n'.join(sorted(repr(row).encode() for row in rows))).hexdigest()}
        objects = {(kind + ':' + name): hashlib.sha256(repr((table, sql)).encode()).hexdigest()
                   for kind, name, table, sql in connection.execute('SELECT type,name,tbl_name,sql FROM sqlite_master ORDER BY type,name')}
        return {'integrity': connection.execute('PRAGMA integrity_check').fetchone()[0], 'tables': tables,
                'objects': objects, 'schemaVersions': connection.execute('SELECT * FROM plugin_schema_versions').fetchall(),
                'serverId': connection.execute('SELECT server_id FROM familyhub_instance WHERE id=1').fetchone()[0]}
    finally:
        connection.close()


def consistent_database(copied_data, tag):
    # Retained cold/paused copies include WAL/SHM. Never use immutable=1 on
    # those files directly: SQLite backup consolidates their complete view.
    work = PRIVATE / ('sqlite-work-' + tag)
    work.mkdir(mode=0o700)
    for suffix in ['', '-wal', '-shm', '-journal']:
        source = copied_data / ('db.sqlite' + suffix)
        if source.exists(): shutil.copyfile(source, work / source.name)
    # A closed WAL-header database may need SQLite-created sidecars even with
    # no retained WAL. This is a disposable PRIVATE copy, never the cold copy.
    source = sqlite3.connect(work / 'db.sqlite')
    source.execute('PRAGMA query_only=ON')
    destination_path = PRIVATE / ('database-' + tag + '-consistent.sqlite')
    destination = sqlite3.connect(destination_path)
    try:
        source.backup(destination)
        destination.execute('PRAGMA journal_mode=DELETE')
        destination.commit()
    finally:
        source.close()
        destination.close()
    destination_path.chmod(0o600)
    if Path(str(destination_path) + '-wal').exists(): raise RuntimeError('Consolidated snapshot still has WAL')
    return destination_path


def tls():
    if hashlib.sha256(CA.read_bytes()).hexdigest() != 'b9af2a77f19f4b541fd035858d4800408239b8d32d696f6075add608afe540f5':
        raise RuntimeError('Wrong renewed mobile public CA')
    context = ssl.create_default_context(cafile=str(CA))
    with socket.create_connection(('192.168.132.29', 18801), timeout=4) as connection:
        with context.wrap_socket(connection, server_hostname='192.168.132.29') as secure:
            return {'leafSha256': hashlib.sha256(secure.getpeercert(binary_form=True)).hexdigest(),
                    'notAfter': secure.getpeercert()['notAfter'], 'caSha256': hashlib.sha256(CA.read_bytes()).hexdigest()}


def apply(resume_after_stop=False, resume_after_backup=False):
    resuming = resume_after_stop or resume_after_backup
    ledger_path = PUBLIC / 'attempts.json'
    attempts = json.loads(ledger_path.read_text()) if ledger_path.exists() else []
    if not resuming and (attempts or PRIVATE.exists()):
        raise RuntimeError('Preserve an existing upgrade attempt; inspect before any continuation')
    PRIVATE.mkdir(mode=0o700, parents=True, exist_ok=resuming)
    if run(['git', 'rev-parse', '--short=7', 'HEAD']).decode().strip() != '149ed06':
        raise RuntimeError('Exact reviewed HEAD required')
    if run(['ipconfig', 'getifaddr', 'en0']).decode().strip() != '192.168.132.29':
        raise RuntimeError('Historical QA LAN address changed')
    current_owned = owned()
    if resuming:
        if resume_after_stop and (len(attempts) != 1 or attempts[0]['status'] != 'started' or list(PRIVATE.iterdir())):
            raise RuntimeError('Exact one failed pre-backup ownership-check attempt required')
        if resume_after_backup and (len(attempts) != 2 or attempts[0]['status'] != 'fixture-fail' or attempts[1]['status'] != 'started' or not (PRIVATE / 'backup-manifest-private.json').exists()):
            raise RuntimeError('Exact retained cold-copy snapshot failure required')
        preflight = json.loads((PUBLIC / 'preflight.json').read_text())
        before_owned = preflight['beforeOwned']
        if any(current_owned[key]['running'] or current_owned[key]['id'] != value['id'] or current_owned[key]['image'] != value['image'] for key, value in before_owned.items()):
            raise RuntimeError('Stopped owned service identity changed')
        if '192.168.132.29:18801:8443' not in (LIVE / 'compose-tls.yaml').read_text():
            raise RuntimeError('Configured inactive mobile port changed')
        before_inventory = json.loads((PUBLIC / 'initial-docker-inventory.json').read_text())
        tls_before = preflight['tls']
        if resume_after_stop:
            attempts[0].update(status='fixture-fail', reason='Stopped Docker gateway reports inactive placeholder port; source/data untouched')
        else:
            attempts[1].update(status='fixture-fail', reason='Private read-only WAL-header snapshot needs SQLite sidecars; original cold copy intact, source/data untouched')
    else:
        before_owned = current_owned
        if not all(item['running'] for item in before_owned.values()): raise RuntimeError('Initial owned service states changed')
        before_inventory = inventory()
    before_source, target = manifest(LIVE / 'FamilyHub'), manifest(SOURCE)
    changed = [path for path in target if before_source.get(path) != target[path]]
    if len(changed) != 17 or len(before_source) != 182 or len(target) != 186 or set(before_source) - set(target):
        raise RuntimeError('Unexpected reviewed source delta')
    if resuming:
        if changed != preflight['sourceDelta'] or target != json.loads((PUBLIC / 'source-target.json').read_text()):
            raise RuntimeError('Frozen source changed after the stopped preflight')
    else:
        tls_before = tls()
        run(['docker', 'exec', NAMES['app'], 'test', '-f', '/var/www/app/data/.jivie-local-initialized'])
        lint = {}
        for path in changed:
            if path.endswith('.php'):
                lint[path] = run(['docker', 'exec', '-i', NAMES['app'], 'php', '-l'], input=(SOURCE / path).read_bytes()).decode().strip()
        save(PUBLIC / 'preflight.json', {'head': '149ed06', 'beforeOwned': before_owned, 'sourceDelta': changed,
             'sourceFilesBefore': len(before_source), 'sourceFilesAfter': len(target), 'tls': tls_before, 'phpLintCount': len(lint)})
        save(PUBLIC / 'initial-docker-inventory.json', before_inventory)
        save(PUBLIC / 'source-target.json', target)
        save(PUBLIC / 'lint.json', lint)
    number = len(attempts) + 1
    if number > 3: raise RuntimeError('Three preparation attempts exhausted')
    attempts.append({'attempt': number, 'status': 'started', 'atUtc': datetime.datetime.now(datetime.timezone.utc).isoformat()})
    save(ledger_path, attempts)
    if not resuming: run(['docker', 'stop', '--time', '20', *NAMES.values()], timeout=90)
    if any(item['running'] for item in owned().values()): raise RuntimeError('Owned cold-backup stop incomplete')
    if not resume_after_backup:
        shutil.copytree(LIVE, PRIVATE / 'server-before')
        shutil.copytree(PRIVATE_ROOT / 'tls', PRIVATE / 'tls-before')
        shutil.copyfile(PRIVATE_ROOT / 'secrets.php', PRIVATE / 'secrets-before.php')
        run(['docker', 'cp', NAMES['app'] + ':/var/www/app/data', str(PRIVATE / 'app-data-before')])
        run(['docker', 'cp', NAMES['mailpit'] + ':/data', str(PRIVATE / 'mail-data-before')])
        for path in PRIVATE.rglob('*'): path.chmod(0o700 if path.is_dir() else 0o600)
        backup_manifest = manifest(PRIVATE)
        save(PRIVATE / 'backup-manifest-private.json', backup_manifest)
    else:
        backup_manifest = json.loads((PRIVATE / 'backup-manifest-private.json').read_text())
        if not all(hashlib.sha256((PRIVATE / path).read_bytes()).hexdigest() == value['sha256'] for path, value in backup_manifest.items()):
            raise RuntimeError('Original cold backup changed')
    before_snapshot = consistent_database(PRIVATE / 'app-data-before', 'before-' + str(number))
    before_db = db_report(before_snapshot)
    if before_db['integrity'] != 'ok' or before_db['serverId'] != SID or len(before_db['tables']) != 220 or before_db['schemaVersions'] != [('familyhub', 20)]:
        raise RuntimeError('Unexpected retained cold database')
    save(PUBLIC / 'database-before.json', before_db)
    queue_connection = sqlite3.connect(before_snapshot.as_uri() + '?mode=ro&immutable=1', uri=True)
    try:
        pending_queues = {table: queue_connection.execute("SELECT COUNT(*) FROM " + table + " WHERE state NOT IN ('accepted','sent','cancelled','expired')").fetchone()[0]
                          for table in ['familyhub_account_mail', 'familyhub_invitation_mail', 'familyhub_crypto_invitation_mail_v2', 'familyhub_deliveries', 'familyhub_crypto_security_events']}
    finally: queue_connection.close()
    if any(pending_queues.values()): raise RuntimeError('Preserve pending mail jobs; do not resume a delivery worker automatically')
    save(PUBLIC / 'backup-evidence.json', {'path': str(PRIVATE), 'fileCount': len(backup_manifest),
         'manifestSha256': hashlib.sha256((PRIVATE / 'backup-manifest-private.json').read_bytes()).hexdigest(),
         'verifiedColdCopies': all(hashlib.sha256((PRIVATE / p).read_bytes()).hexdigest() == value['sha256'] for p, value in backup_manifest.items()),
         'privateDirectoryMode': oct(PRIVATE.stat().st_mode & 0o777), 'databaseIntegrity': before_db['integrity']})
    for path in changed:
        destination = LIVE / 'FamilyHub' / path
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(SOURCE / path, destination)
    if manifest(LIVE / 'FamilyHub') != target: raise RuntimeError('Deployed source mismatch')
    run(['docker', 'start', NAMES['app']])
    # Existing initialization marker suppresses account/bootstrap mutations.
    # Official app bootstrap performs only reviewed Schema\Sqlite\version_21.
    import time
    deadline = time.monotonic() + 45
    while True:
        probe = subprocess.run(['docker', 'exec', NAMES['app'], 'curl', '-fsS', 'http://127.0.0.1/healthcheck.php'], capture_output=True)
        if probe.returncode == 0: break
        if time.monotonic() >= deadline: raise RuntimeError('Owned app bootstrap readiness deadline')
        time.sleep(0.25)
    run(['docker', 'pause', NAMES['app']])
    try: run(['docker', 'cp', NAMES['app'] + ':/var/www/app/data', str(PRIVATE / 'app-data-after')])
    finally: run(['docker', 'unpause', NAMES['app']])
    for path in (PRIVATE / 'app-data-after').rglob('*'): path.chmod(0o700 if path.is_dir() else 0o600)
    after_db = db_report(consistent_database(PRIVATE / 'app-data-after', 'after-' + str(number)))
    new_tables = sorted(set(after_db['tables']) - set(before_db['tables']))
    expected_new = ['familyhub_crypto_invitation_publications_v5', 'familyhub_crypto_invitation_reservations_v5']
    changed_tables = [name for name in before_db['tables'] if before_db['tables'][name] != after_db['tables'].get(name)]
    if (after_db['integrity'] != 'ok' or after_db['serverId'] != SID or new_tables != expected_new or
            changed_tables != ['plugin_schema_versions'] or any(after_db['tables'][name]['rows'] for name in new_tables) or
            after_db['schemaVersions'] != [('familyhub', 21)] or
            any(after_db['objects'].get(name) != value for name, value in before_db['objects'].items())):
        raise RuntimeError('Unexpected database migration delta; preserve stopped inbound and backup')
    save(PUBLIC / 'database-after.json', after_db)
    save(PUBLIC / 'database-comparison.json', {'existingTableCount': 220, 'unchangedExistingDataTables': 219, 'existingBusinessTablesExact': True,
         'changedExistingTables': changed_tables, 'newEmptyTables': new_tables, 'existingDDLExact': True,
         'schemaVersionBefore': 20, 'schemaVersionAfter': 21, 'serverIdUnchanged': True})
    if manifest(PRIVATE / 'tls-before') != manifest(PRIVATE_ROOT / 'tls') or hashlib.sha256((PRIVATE / 'secrets-before.php').read_bytes()).hexdigest() != hashlib.sha256((PRIVATE_ROOT / 'secrets.php').read_bytes()).hexdigest():
        raise RuntimeError('QA keys or TLS changed')
    for path, value in manifest(PRIVATE / 'server-before').items():
        if not path.startswith('FamilyHub/') and manifest(LIVE).get(path) != value: raise RuntimeError('QA non-plugin configuration changed')
    run(['docker', 'start', NAMES['mailpit'], NAMES['gateway']])
    deadline = time.monotonic() + 10
    while True:
        try:
            after_tls = tls()
            break
        except (ConnectionRefusedError, TimeoutError):
            if time.monotonic() >= deadline: raise
            time.sleep(0.2)
    if after_tls != tls_before: raise RuntimeError('TLS changed during source upgrade')
    request = urllib.request.Request(URL + 'index.php?plugin=FamilyHub&controller=NativeApiController&action=handle',
        data=b'{"v":1,"op":"capabilities","params":{}}', headers={'Content-Type': 'application/json'})
    with urllib.request.urlopen(request, context=ssl.create_default_context(cafile=str(CA)), timeout=15) as response:
        capabilities = json.load(response)['data']; status = response.status
    if status != 200 or capabilities['serverId'] != SID or capabilities['invitationPreauthorizationVersions'] != [1]:
        raise RuntimeError('Upgraded public capabilities mismatch')
    # Resume exactly the already-running local-only worker, with terminal queues.
    run(['docker', 'start', NAMES['account-mail-worker']])
    after_owned = owned()
    if any(after_owned[key]['id'] != value['id'] or after_owned[key]['image'] != value['image'] or not after_owned[key]['running'] for key, value in before_owned.items()):
        raise RuntimeError('Owned service identity or state changed unexpectedly')
    current_inventory = inventory()
    other_changes = [name for name in sorted(set(before_inventory) | set(current_inventory)) if name not in NAMES.values() and before_inventory.get(name) != current_inventory.get(name)]
    if other_changes: raise RuntimeError('Other container state/image changed: inspect metadata')
    attempts[-1].update(status='pass', completedAtUtc=datetime.datetime.now(datetime.timezone.utc).isoformat())
    save(ledger_path, attempts)
    result = {'status': 'PASS', 'head': '149ed06', 'sourceFiles': len(target), 'sourceChangedOrAdded': len(changed),
              'sameServerId': True, 'schema': 21, 'oldBusinessTablesExact': True, 'oldDDLExact': True,
              'newEmptyTables': new_tables, 'configTLSKeysUnchanged': True, 'strictTLSCapabilitiesHttp': status,
              'publicRequests': 1, 'authenticatedBusinessRPCs': 0, 'newMailOrPushSent': False,
              'pendingMailJobsBeforeResume': pending_queues,
              'allOriginalOwnedServicesRestoredRunning': True, 'beforeOwned': before_owned, 'afterOwned': after_owned,
              'otherContainerStateOrImageChanges': other_changes, 'pushConfigured': False, 'pushDeliveryUnverified': True,
              'privateBackupRetained': str(PRIVATE)}
    save(PUBLIC / 'upgrade-result.json', result)
    print(json.dumps({key: value for key, value in result.items() if key not in ['beforeOwned', 'afterOwned']}))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['apply', 'resume-after-cold-stop', 'resume-from-cold-backup'])
    args = parser.parse_args()
    os.umask(0o077)
    apply(resume_after_stop=args.action == 'resume-after-cold-stop', resume_after_backup=args.action == 'resume-from-cold-backup')


if __name__ == '__main__': main()
