#!/usr/bin/env python3
"""Owned disposable loopback server for the full-sync recovery lab.

Never attaches or copies an existing QA data volume. Secrets stay in a 0700
private root. This script prepares infrastructure, not business-test results.
"""
import argparse
import json
import os
from pathlib import Path
import secrets
import socket
import subprocess
import time
import urllib.request

REPO = Path(__file__).resolve().parents[2]
ROOT = Path('/tmp/jivie-fullsync-lab-20261021')
EVIDENCE = REPO / 'build/qa/local-diagnostics/full-sync-lab-20261021/environment'
NAME = 'jivie-fullsync-lab-20261021'
LABEL = 'si.triparna.jivie.fullsync-lab=20261021'
PORT = 59777
IMAGE = 'familyhub-crypto-tests:local'
VOLUMES = {suffix: f'{NAME}-{suffix}' for suffix in ('data', 'plugins', 'tls')}


def save(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + '.tmp')
    tmp.write_text(json.dumps(value, indent=2) + '\n')
    tmp.chmod(0o600)
    tmp.replace(path)


def run(args, *, input=None, timeout=45):
    result = subprocess.run(args, input=input, capture_output=True, text=True,
                            timeout=timeout, check=False)
    if result.returncode:
        # Errors may contain synthetic credentials. Keep diagnostic output private.
        save(ROOT / 'last-command-error-private.json', {
            'command': args[:3], 'returncode': result.returncode,
            'stdout': result.stdout[:16384], 'stderr': result.stderr[:16384]})
        raise RuntimeError(f'Command failed: {args[0]} {args[1]} ({result.returncode})')
    return result.stdout


def inventory():
    return [json.loads(line) for line in run([
        'docker', 'ps', '-a', '--format', '{{json .}}']).splitlines()]


def inspect_owned():
    obj = json.loads(run(['docker', 'inspect', NAME]))[0]
    if obj['Config'].get('Labels', {}).get('si.triparna.jivie.fullsync-lab') != '20261021':
        raise RuntimeError('Container is not owned by this lab')
    actual = {m['Destination']: m for m in obj['Mounts']}
    for suffix, dest in [('data', '/var/www/app/data'),
                         ('plugins', '/var/www/app/plugins'), ('tls', '/etc/nginx/ssl')]:
        if actual[dest].get('Name') != VOLUMES[suffix]:
            raise RuntimeError('Unexpected data mount')
    return obj


def phase(name, action):
    ledger_file = ROOT / 'environment-attempts.json'
    ledger = json.loads(ledger_file.read_text()) if ledger_file.exists() else {}
    entry = ledger.setdefault(name, {'attempts': 0, 'status': 'new'})
    if entry['status'] == 'pass':
        print(json.dumps({'phase': name, 'status': 'previously_passed_skipped'}))
        return
    if entry['attempts'] >= 3:
        raise RuntimeError('Three attempts exhausted; preserved state requires review')
    entry.update(attempts=entry['attempts'] + 1, status='running')
    save(ledger_file, ledger)
    try:
        result = action()
        entry.update(status='pass', result=result)
    except BaseException as error:
        entry.update(status='fail', errorType=type(error).__name__, error=str(error)[:200])
        save(ledger_file, ledger)
        raise
    save(ledger_file, ledger)
    save(EVIDENCE / 'environment-result.json', ledger)
    print(json.dumps({'phase': name, 'status': 'pass', 'attempt': entry['attempts']}))


def up():
    existing = inventory()
    if any(row['Names'] == NAME for row in existing):
        obj = inspect_owned()
        if obj['State']['Running']:
            raise RuntimeError('Owned container already running; inspect prior partial attempt')
        raise RuntimeError('Container exists; preserve and inspect before resuming')
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', PORT))
    all_volumes = set(run(['docker', 'volume', 'ls', '--format', '{{.Name}}']).splitlines())
    if set(VOLUMES.values()) & all_volumes:
        raise RuntimeError('Named lab volumes already exist; preserve and inspect')
    save(EVIDENCE / 'initial-docker-inventory.json', existing)
    image = json.loads(run(['docker', 'image', 'inspect', IMAGE]))[0]
    save(EVIDENCE / 'ownership.json', {'container': NAME, 'volumes': VOLUMES,
         'imageId': image['Id'], 'serverUrl': f'http://127.0.0.1:{PORT}',
         'existingDataCopied': False, 'sourceCopies': False, 'worker': False})
    config = ("<?php\nrequire '/familyhub-dev-config.php';\n"
              "define('FAMILYHUB_ENABLE_CRYPTO_PREVIEW', true);\n"
              "define('FAMILYHUB_ACCOUNT_MAIL_KEY_BASE64', '" +
              __import__('base64').b64encode(secrets.token_bytes(32)).decode() + "');\n"
              "define('FAMILYHUB_SMTP_HOST', '127.0.0.1');\n"
              "define('FAMILYHUB_SMTP_PORT', 2525);\n"
              "define('FAMILYHUB_SMTP_ENCRYPTION', 'none');\n"
              "define('FAMILYHUB_SMTP_ALLOW_LOCAL_PLAINTEXT', true);\n"
              "define('FAMILYHUB_SMTP_FROM', 'lab@capture.invalid');\n")
    (ROOT / 'config-private.php').write_text(config)
    (ROOT / 'config-private.php').chmod(0o600)
    for name in VOLUMES.values():
        run(['docker', 'volume', 'create', '--label', LABEL, name])
    args = ['docker', 'create', '--name', NAME, '--label', LABEL,
            '--restart', 'no', '--publish', f'127.0.0.1:{PORT}:80']
    for suffix, dest in [('data', '/var/www/app/data'),
                         ('plugins', '/var/www/app/plugins'), ('tls', '/etc/nginx/ssl')]:
        args += ['--mount', f'type=volume,src={VOLUMES[suffix]},dst={dest}']
    for src, dest in [(REPO / 'server/plugins/FamilyHub', '/var/www/app/plugins/FamilyHub'),
                      (REPO / 'server/tests', '/familyhub-tests'),
                      (REPO / 'server/dev-config.php', '/familyhub-dev-config.php'),
                      (ROOT / 'config-private.php', '/var/www/app/config.php')]:
        args += ['--mount', f'type=bind,src={src},dst={dest},readonly']
    args += [IMAGE]
    run(args)
    obj = inspect_owned()
    run(['docker', 'start', NAME])
    # Base image starts Alpine maintenance cron; this lab has no scheduled jobs.
    run(['docker', 'exec', NAME, 's6-svc', '-d', '/etc/services.d/cron'])
    deadline = time.monotonic() + 45
    while True:
        try:
            with urllib.request.urlopen(f'http://127.0.0.1:{PORT}/healthcheck.php', timeout=2) as response:
                if response.status == 200:
                    break
        except Exception:
            if time.monotonic() >= deadline:
                raise RuntimeError('Health readiness deadline exhausted')
            time.sleep(1)
    return {'ready': True, 'port': PORT, 'newContainerId': obj['Id'],
            'baseImageMaintenanceCron': 'disabled', 'mailWorker': False}


BOOTSTRAP = r'''<?php
umask(0077);
require '/var/www/app/app/common.php';
if (session_status() === PHP_SESSION_ACTIVE) { session_abort(); }
if (!defined('FAMILYHUB_DEVELOPMENT_MODE') || FAMILYHUB_DEVELOPMENT_MODE !== true) { throw new RuntimeException('Synthetic only'); }
\Kanboard\Plugin\FamilyHub\Schema\CryptoSchema::create($container['db']->getConnection(), false);
$service = new \Kanboard\Plugin\FamilyHub\Model\NativeService($container);
$pdo = $container['db']->getConnection();
$existing = $pdo->query("SELECT COUNT(*) FROM users WHERE username LIKE 'fullsync_%'")->fetchColumn();
if ((int)$existing !== 0) { throw new RuntimeException('Preserve partial bootstrap; synthetic accounts already exist'); }
$prefix = 'fullsync_'.bin2hex(random_bytes(6));
$out = [];
foreach (['owner', 'member'] as $kind) {
    $username = $prefix.'_'.$kind;
    $password = bin2hex(random_bytes(20));
    if (!$container['userModel']->create(['username'=>$username,'password'=>$password,'role'=>'app-user','name'=>'Synthetic full sync '.$kind])) { throw new RuntimeException('Account creation failed'); }
    $session = $service->dispatch('auth.login', ['username'=>$username,'password'=>$password,'deviceName'=>'Full sync lab '.$kind], '', $prefix);
    $bearer = 'Bearer '.$session['token'];
    $service->dispatch('moderation.acceptPolicy', ['policyVersion'=>1], $bearer, $prefix);
    $email = $username.'@capture.invalid';
    $service->dispatch('account.email.request', ['email'=>$email,'language'=>'en','password'=>$password], $bearer, $prefix);
    // Read only this new synthetic mailbox; confirmation still uses the public API.
    $q = $pdo->prepare('SELECT t.id,t.account_id,m.token_cipher FROM familyhub_account_tokens t JOIN familyhub_account_mail m ON m.token_id=t.id WHERE t.account_id=? AND t.purpose=? AND t.consumed_at IS NULL AND t.revoked_at IS NULL');
    $q->execute([$session['user']['accountId'], 'verify']);
    $rows = $q->fetchAll(PDO::FETCH_ASSOC); $q->closeCursor();
    if (count($rows) !== 1) { throw new RuntimeException('Exact synthetic mailbox required'); }
    $row = $rows[0];
    $code = \Kanboard\Plugin\FamilyHub\Model\NativeAccountMailCrypto::decrypt($row['token_cipher'], (new \Kanboard\Plugin\FamilyHub\Model\NativeAccountTokens($container))->aad($row['id'], $row['account_id']));
    $confirmed = $service->dispatch('account.email.confirm', ['token'=>$code], $bearer, $prefix);
    if (($confirmed['verified']??false) !== true) { throw new RuntimeException('Verification did not complete'); }
    $out[$kind] = ['username'=>$username,'password'=>$password,'email'=>$email,'session'=>$session];
}
echo json_encode(['synthetic'=>true,'purpose'=>'local-fullsync-recovery-20261021','serverUrl'=>'http://127.0.0.1:59777','accounts'=>$out], JSON_THROW_ON_ERROR).PHP_EOL;
'''


def bootstrap():
    inspect_owned()
    destination = ROOT / 'fixture.json'
    if destination.exists():
        raise RuntimeError('Fixture exists; bootstrap never duplicates accounts')
    script = ROOT / 'bootstrap-private.php'
    script.write_text(BOOTSTRAP)
    script.chmod(0o600)
    run(['docker', 'cp', str(script), f'{NAME}:/tmp/fullsync-bootstrap.php'])
    raw = run(['docker', 'exec', NAME, 'php', '/tmp/fullsync-bootstrap.php'])
    (ROOT / 'bootstrap-output-private.json').write_text(raw)
    (ROOT / 'bootstrap-output-private.json').chmod(0o600)
    fixture = json.loads(raw)
    if set(fixture['accounts']) != {'owner', 'member'}:
        raise RuntimeError('Unexpected fixture accounts')
    server_ids = {value['session']['serverId'] for value in fixture['accounts'].values()}
    if len(server_ids) != 1 or fixture['serverUrl'] != 'http://127.0.0.1:59777':
        raise RuntimeError('Exact loopback target and shared server identity required')
    fixture['serverId'] = next(iter(server_ids))
    fixture['clientStateDirs'] = {'owner': str(ROOT / 'client-a'), 'member': str(ROOT / 'client-b')}
    save(destination, fixture)
    for sub in ('client-a', 'client-b'):
        (ROOT / sub).mkdir(mode=0o700, exist_ok=True)
    return {'accounts': 2, 'emailVerification': 'request+private-mailbox-read+confirm',
            'cryptoStateCreated': False, 'mailDeliveryClaimed': False}


def status():
    obj = inspect_owned()
    current = inventory()
    baseline = json.loads((EVIDENCE / 'initial-docker-inventory.json').read_text())
    baseline_by_id = {row['ID']: row for row in baseline}
    changed = []
    for row in current:
        old = baseline_by_id.get(row['ID'])
        if old and (row['State'] != old['State'] or row['Image'] != old['Image']):
            changed.append(row['Names'])
    result = {'running': obj['State']['Running'], 'otherContainerStateChanges': changed,
              'ownedVolumes': VOLUMES, 'container': NAME}
    save(EVIDENCE / 'environment-status.json', result)
    print(json.dumps(result))


def stop():
    inspect_owned()
    run(['docker', 'stop', '--time', '20', NAME])
    # Preserve the new data volumes and client state for review. No broad cleanup.
    status()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['up', 'bootstrap', 'status', 'stop'])
    args = parser.parse_args()
    os.umask(0o077)
    ROOT.mkdir(mode=0o700, exist_ok=True)
    ROOT.chmod(0o700)
    if args.action == 'up': phase('server-readiness', up)
    elif args.action == 'bootstrap': phase('two-account-bootstrap', bootstrap)
    elif args.action == 'status': status()
    else: stop()


if __name__ == '__main__':
    main()
