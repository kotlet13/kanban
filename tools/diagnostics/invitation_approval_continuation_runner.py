#!/usr/bin/env python3
"""Finite isolated new-account approval launches; count before compilation, never auto retry."""
import argparse
import datetime
import fcntl
import hashlib
import json
import os
from pathlib import Path
import selectors
import signal
import subprocess
import time

from invitation_approval_environment import REPO, ROOT, NAME, inspect_owned, save

TEST = REPO / 'test/organizer/data/e2ee/crypto_invitation_approval_http_test.dart'
PUBLIC = REPO / 'build/qa/local-diagnostics/invitation-approval-continuation-20261024'


def source_manifest():
    paths = [*sorted((REPO / 'lib').rglob('*.dart')),
             *sorted(p for p in (REPO / 'server/plugins/FamilyHub').rglob('*') if p.is_file()),
             TEST, Path(__file__).resolve(),
             REPO / 'tools/diagnostics/invitation_approval_runner.py',
             REPO / 'test/organizer/data/e2ee/crypto_inherited_automatic_review_journal_test.dart',
             REPO / 'test/organizer/data/e2ee/crypto_checkpoint_publish_boundary_test.dart',
             REPO / 'test/organizer/data/e2ee/crypto_invitation_restart_selection_test.dart',
             REPO / 'tools/diagnostics/invitation_approval_environment.py',
             REPO / 'tools/diagnostics/invitation_preauthorization_environment.py',
             REPO / 'server/tests/invitation-approval-fixture.php',
             REPO / 'test/organizer/data/collaboration_repository_test.dart',
             REPO / 'pubspec.yaml', REPO / 'pubspec.lock',
             REPO / 'server/dev-config.php']
    files = {str(p.relative_to(REPO)): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
    return {'files': files, 'sha256': hashlib.sha256(json.dumps(files, sort_keys=True).encode()).hexdigest()}


def validate_target():
    fixture = json.loads((ROOT / 'fixture.json').read_text())
    accounts = fixture.get('accounts', {})
    if (fixture.get('synthetic') is not True or
            fixture.get('purpose') != 'local-invitation-approval-20261023' or
            fixture.get('serverUrl') != 'http://127.0.0.1:59780' or
            set(accounts) not in ({'owner'}, {'owner', 'member'}) or
            any(a['session']['serverId'] != fixture['serverId'] for a in accounts.values()) or
            any(fixture['clientStateDirs'][k] != str(ROOT / k) for k in ('owner', 'member'))):
        raise RuntimeError('Exact owned new-account approval fixture required')
    obj = inspect_owned()
    if not obj['State']['Running']:
        raise RuntimeError('Owned new local HTTP lab must be running')
    if obj['HostConfig']['PortBindings'] != {'80/tcp': [{'HostIp': '127.0.0.1', 'HostPort': '59780'}]}:
        raise RuntimeError('Exact loopback binding required')


BASELINE = ROOT / 'continuation-baseline-20261024-private.json'
HISTORY = ROOT / 'approval-ledger-private.json'


def original_authorizations(history, fixture):
    import sqlite3
    result = {}
    for key, actor, action, request in [
        ('send', 'owner', None, history['originalSendRequestId']),
        ('parentActivation', 'owner', None, history['lostActivation']['requestId']),
        ('accept', 'member', 'accept:' + history['invitationId'], None),
    ]:
        client = Path(fixture['clientStateDirs'][actor]) / 'client.sqlite'
        connection = sqlite3.connect(client.as_uri() + '?mode=ro', uri=True)
        try:
            if action:
                rows = connection.execute('SELECT i.intent_id,i.state,i.authorization FROM crypto_membership_action_keys a JOIN crypto_membership_intents i ON i.partition=a.partition AND i.scope_id=a.scope_id AND i.intent_id=a.request_id WHERE a.scope_id=? AND a.action_key=?', (history['scope'], action)).fetchall()
            else:
                rows = connection.execute('SELECT intent_id,state,authorization FROM crypto_membership_intents WHERE scope_id=? AND intent_id=?', (history['scope'], request)).fetchall()
            if len(rows) != 1 or rows[0][1] != 'confirmed':
                raise RuntimeError('Exact original confirmed authorization required: ' + key)
            result[key] = {'requestId': rows[0][0], 'proofHash': hashlib.sha256(rows[0][2]).hexdigest()}
        finally:
            connection.close()
    expected = {'send': history['originalSendProofHash'], 'parentActivation': history['lostActivation']['requestHash'], 'accept': history['acceptanceProofHash']}
    if any(result[key]['proofHash'] != value for key, value in expected.items()):
        raise RuntimeError('Original signed authorization changed before continuation')
    return result


def verify_baseline():
    baseline = json.loads(BASELINE.read_text())
    if hashlib.sha256(HISTORY.read_bytes()).hexdigest() != baseline['historicalLedgerSha256']:
        raise RuntimeError('Historical STOP3 ledger changed')
    if hashlib.sha256((ROOT / 'launch-attempts.json').read_bytes()).hexdigest() != baseline['historicalLaunchLedgerSha256']:
        raise RuntimeError('Historical launch budget changed')
    history = json.loads(HISTORY.read_text())
    fixture = json.loads((ROOT / 'fixture.json').read_text())
    if original_authorizations(history, fixture) != baseline['originalAuthorizations']:
        raise RuntimeError('Original signed authorization changed')
    return True


def prepare_continuation():
    if BASELINE.exists():
        verify_baseline()
        print(json.dumps({'status': 'prepared_baseline_retained'}))
        return
    history = json.loads(HISTORY.read_text())
    launches = json.loads((ROOT / 'launch-attempts.json').read_text())['approval']
    fixture = json.loads((ROOT / 'fixture.json').read_text())
    terminal_path = ROOT / 'terminal-readonly-summary-private.json'
    terminal = json.loads(terminal_path.read_text())
    if (len(launches) != 3 or any(row['status'] != 'fail' for row in launches) or
            history.get('passed') is True or terminal['mainStatus'] != 'STOP3' or
            terminal['server']['invitation']['state'] != 'consumed' or
            terminal['server']['child']['hasRecipient'] is not False or
            history['steps']['foreground_lost_activation_ack']['passed'] is not True or
            history['steps']['restart_owner_foreground_autoapproval'].get('passed') is True or
            set(fixture['accounts']) != {'owner', 'member'}):
        raise RuntimeError('Exact retained STOP3 pending-child baseline required')
    obj = inspect_owned()
    if obj['State']['Running']:
        raise RuntimeError('Preflight requires the retained stopped lab')
    baseline = {'renewedAuthorizationDate': '20261024', 'historicalLedgerSha256': hashlib.sha256(HISTORY.read_bytes()).hexdigest(),
                'historicalLaunchLedgerSha256': hashlib.sha256((ROOT / 'launch-attempts.json').read_bytes()).hexdigest(),
                'terminalSnapshotSha256': hashlib.sha256(terminal_path.read_bytes()).hexdigest(),
                'originalAuthorizations': original_authorizations(history, fixture),
                'serverBaseline': terminal['server'], 'containerId': obj['Id'], 'imageId': obj['Image'],
                'forbiddenRepetition': ['Send', 'register', 'accept', 'parentActivation', 'lostACK'],
                'newBudget': 3}
    save(BASELINE, baseline)
    save(PUBLIC / 'baseline-summary.json', {key: baseline[key] for key in ['renewedAuthorizationDate', 'historicalLedgerSha256', 'historicalLaunchLedgerSha256', 'terminalSnapshotSha256', 'originalAuthorizations', 'containerId', 'imageId', 'forbiddenRepetition', 'newBudget']})
    print(json.dumps({'status': 'prepared', 'originalProofs': len(baseline['originalAuthorizations']), 'historicalLaunches': len(launches), 'containerRunning': False}))


def launch(args):
    manifest = source_manifest()
    if args.reviewed_source_sha256 != manifest['sha256']:
        raise RuntimeError('Exact reviewed source digest required')
    if not 30 <= args.timeout_seconds <= 900:
        raise ValueError('Deadline must be 30..900 seconds')
    validate_target()
    verify_baseline()
    lock = (ROOT / 'launch.lock').open('a')
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    ledger_file = ROOT / 'continuation-launch-attempts-20261024.json'
    launches = json.loads(ledger_file.read_text()) if ledger_file.exists() else {}
    attempts = launches.setdefault(args.scenario, [])
    result_file = ROOT / f'{args.scenario}-ledger-private.json'
    prior = json.loads(result_file.read_text()) if result_file.exists() else {}
    if prior.get('passed') is True:
        if not attempts or attempts[-1].get('status') != 'pass':
            raise RuntimeError('Unverified passed state requires review; never silently skip')
        print(json.dumps({'scenario': args.scenario, 'status': 'previously_passed_skipped'}))
        return
    if len(attempts) >= 3:
        raise RuntimeError('Three launches exhausted for this scenario; preserve and stop')
    number = len(attempts) + 1
    entry = {'scenario': args.scenario, 'attempt': number, 'status': 'started',
             'sourceSha256': manifest['sha256'],
             'startedAtUtc': datetime.datetime.now(datetime.timezone.utc).isoformat()}
    attempts.append(entry)
    save(ledger_file, launches)  # Authoritative budget includes compiler/start failures.
    folder = ROOT / 'continuation-launches-20261024' / args.scenario / f'attempt-{number}'
    folder.mkdir(mode=0o700, parents=True)
    save(folder / 'source-manifest.json', manifest)
    env = os.environ.copy()
    env.update(JIVIE_INVITATION_APPROVAL_FIXTURE=str(ROOT / 'fixture.json'), JIVIE_INVITATION_APPROVAL_CONTINUATION='20261024')
    command = ['/Users/anzenovsak/Dev/flutter/bin/flutter', 'test', '--no-pub',
               '--reporter', 'json', str(TEST)]
    proc, count, terminated = None, 0, None
    start = time.monotonic()
    try:
        proc = subprocess.Popen(command, cwd=REPO, env=env, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, start_new_session=True)
        selector = selectors.DefaultSelector()
        selector.register(proc.stdout, selectors.EVENT_READ)
        with (folder / 'flutter-private.jsonl').open('wb') as out:
            while selector.get_map():
                if time.monotonic() - start >= args.timeout_seconds:
                    terminated = 'wall_timeout'
                    break
                for key, _ in selector.select(timeout=0.5):
                    data = os.read(key.fileobj.fileno(), 65536)
                    if not data:
                        selector.unregister(key.fileobj)
                        continue
                    count += len(data)
                    if count > 2097152:
                        terminated = 'output_limit'
                        break
                    out.write(data)
                if terminated:
                    break
        if terminated:
            os.killpg(proc.pid, signal.SIGTERM)
            try:
                proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                os.killpg(proc.pid, signal.SIGKILL)
                proc.wait(timeout=5)
        else:
            proc.wait(timeout=5)
        latest = json.loads(result_file.read_text()) if result_file.exists() else {}
        steps = latest.get('steps', {})
        entry.update(exitCode=proc.returncode, termination=terminated,
                     harnessPassed=latest.get('passed') is True,
                     sourceUnchanged=source_manifest()['sha256'] == manifest['sha256'],
                     preparationSource=latest.get('preparationSource'),
                     continuationSummary=latest.get('continuationSummary'),
                     checkpoint=latest.get('checkpoint'),
                     historicalLedgerUnchanged=verify_baseline(),
                     substeps={k: {f: v[f] for f in ['passed', 'attempts', 'code', 'errorType', 'inheritedPassed', 'sourceScenario', 'sourceStep'] if f in v}
                               for k, v in steps.items()},
                     actualHttp429=sum(c.get('status') == 429 for v in steps.values() for c in v.get('calls', [])))
        entry['status'] = 'pass' if (proc.returncode == 0 and not terminated and
                                    entry['harnessPassed'] and entry['sourceUnchanged']) else 'fail'
    except BaseException as error:
        entry.update(status='fail', launcherErrorType=type(error).__name__)
        if proc is not None and proc.poll() is None:
            os.killpg(proc.pid, signal.SIGKILL)
            proc.wait(timeout=5)
        raise
    finally:
        entry.update(elapsedSeconds=round(time.monotonic() - start, 3), outputBytes=min(count, 2097152))
        save(ledger_file, launches)
        save(folder / 'launch-result.json', entry)
        # Freeze each private harness outcome before another bounded launch.
        if result_file.exists():
            save(folder / 'harness-outcome-private.json', json.loads(result_file.read_text()))
        save(PUBLIC / 'launch-summary.json', launches)
    print(json.dumps(entry))
    if entry['status'] != 'pass':
        raise SystemExit(1)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['source', 'prepare', 'run'])
    parser.add_argument('--scenario', choices=['continuation-20261024'])
    parser.add_argument('--reviewed-source-sha256')
    parser.add_argument('--timeout-seconds', type=int, default=900)
    args = parser.parse_args()
    os.umask(0o077)
    if args.action == 'source':
        manifest = source_manifest()
        print(json.dumps({'sha256': manifest['sha256'], 'files': len(manifest['files'])}))
    elif args.action == 'prepare':
        prepare_continuation()
    else:
        if not args.scenario:
            raise ValueError('One explicit scenario required')
        launch(args)


if __name__ == '__main__':
    main()
