#!/usr/bin/env python3
"""22 October correction launches; never changes the historical phase ledgers.

Each issue gets at most three external launches, including compile/start errors.
The harness reads historical evidence and writes only the dated correction ledger.
"""
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
import urllib.request

import full_sync_phase_runner as historical_runner
from full_sync_environment import REPO, ROOT, NAME, VOLUMES, inspect_owned, inventory, run, save

DATE = '20261022'
CORRECTION = ROOT / f'corrections-{DATE}'
PUBLIC = REPO / f'build/qa/local-diagnostics/full-sync-lab-20261021/corrections-{DATE}'
TEST = REPO / 'test/organizer/data/e2ee/crypto_full_sync_correction_http_test.dart'
PHP_GUARD = REPO / 'server/tests/scope-access-changes-only-guards.php'
PHP_GUARD_PHASE = 'H7_scope_access_changes_only_guards'
PHASES = ['H4_task_conflict_correction', 'H7_revoked_access_correction']
LEGACY = ['ledger-private.json', 'phase-launch-attempts.json']


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def legacy_hashes():
    return {name: sha(ROOT / name) for name in LEGACY}


def source_manifest():
    manifest = historical_runner.source_manifest()
    entries = manifest['files']
    for path in [Path(__file__).resolve(), TEST, PHP_GUARD]:
        entries[str(path.relative_to(REPO))] = sha(path)
    return {'files': entries, 'sha256': hashlib.sha256(
        json.dumps(entries, sort_keys=True).encode()).hexdigest()}


def validate_target():
    fixture = json.loads((ROOT / 'fixture.json').read_text())
    if (fixture.get('synthetic') is not True or
            fixture.get('purpose') != 'local-fullsync-recovery-20261021' or
            fixture.get('serverUrl') != 'http://127.0.0.1:59777' or
            any(account['session']['serverId'] != fixture['serverId']
                for account in fixture['accounts'].values())):
        raise ValueError('Exact retained synthetic target required')
    if set(fixture['accounts']) != {'owner', 'member'} or len({
            account['session']['user']['accountId'] for account in fixture['accounts'].values()}) != 2:
        raise ValueError('Two original synthetic accounts required')
    return inspect_owned()


def prepare():
    obj = validate_target()
    baseline = CORRECTION / 'baseline-private.json'
    if baseline.exists():
        raise RuntimeError('Dated baseline exists; never replace correction history')
    if obj['State']['Running']:
        raise RuntimeError('Prepare the correction baseline while the owned lab is stopped')
    CORRECTION.mkdir(mode=0o700, parents=True, exist_ok=True)
    before = {'date': DATE, 'purpose': 'retained-H4-H7-corrections',
              'legacyLedgerSha256': legacy_hashes(),
              'fixtureSha256': sha(ROOT / 'fixture.json'),
              'initialClientFileSha256': {str(path.relative_to(ROOT)): sha(path)
                  for actor in ['client-a', 'client-b']
                  for path in [ROOT / actor / 'client.sqlite', ROOT / actor / 'secure.json']},
              'oldContainerStopped': True, 'newAccounts': False, 'databaseClones': False}
    save(baseline, before)
    save(PUBLIC / 'initial-docker-inventory.json', inventory())
    save(PUBLIC / 'correction-isolation.json', {
        'date': DATE, 'container': NAME, 'serverUrl': 'http://127.0.0.1:59777',
        'ownedVolumes': VOLUMES, 'retainedContainerStoppedAtBaseline': True,
        'legacyLedgerSha256': before['legacyLedgerSha256'],
        'oldH4H7CountersUnchanged': True, 'newAccounts': False, 'databaseClones': False})
    print(json.dumps({'prepared': True, 'date': DATE, 'legacyLedgersPreserved': True}))


def check_baseline():
    baseline = json.loads((CORRECTION / 'baseline-private.json').read_text())
    if (baseline['legacyLedgerSha256'] != legacy_hashes() or
            baseline['fixtureSha256'] != sha(ROOT / 'fixture.json')):
        raise RuntimeError('Historical fixture or ledgers changed; preserve and review')
    return baseline


def start_owned():
    obj = validate_target()
    check_baseline()
    if obj['State']['Running']:
        raise RuntimeError('Owned lab already running; no repeated start')
    if (CORRECTION / 'start-result.json').exists():
        raise RuntimeError('A dated start already occurred; preserve and review')
    save(CORRECTION / 'start-result.json', {'status': 'started', 'date': DATE})
    run(['docker', 'start', NAME])
    # Disable the base image maintenance cron; no FamilyHub worker is enabled.
    run(['docker', 'exec', NAME, 's6-svc', '-d', '/etc/services.d/cron'])
    deadline = time.monotonic() + 45
    while True:
        try:
            with urllib.request.urlopen('http://127.0.0.1:59777/healthcheck.php', timeout=2) as response:
                if response.status == 200:
                    break
        except Exception:
            if time.monotonic() >= deadline:
                raise RuntimeError('Owned server readiness deadline exhausted')
            time.sleep(1)
    result = {'status': 'ready', 'date': DATE, 'container': NAME,
              'worker': False, 'maintenanceCronDisabled': True}
    save(CORRECTION / 'start-result.json', result)
    save(PUBLIC / 'start-result.json', result)
    print(json.dumps(result))


def launch(args):
    guard = args.action == 'guard-php'
    if guard:
        args.phase = PHP_GUARD_PHASE
    manifest = source_manifest()
    if args.reviewed_source_sha256 != manifest['sha256']:
        raise ValueError('Exact reviewed correction source digest required')
    if not 30 <= args.timeout_seconds <= 900:
        raise ValueError('Wall deadline must be 30..900 seconds')
    obj = validate_target()
    baseline = check_baseline()
    if not args.offline and not obj['State']['Running']:
        raise RuntimeError('Owned retained HTTP lab is stopped')
    if args.offline and args.phase != 'H4_task_conflict_correction':
        raise ValueError('Only the reviewed H4 local continuation may run offline')
    # A reviewed H7 server correction is allowed on the same read-only source
    # mount. Its exact bytes are bound by the dated reviewed source manifest,
    # while the historical source manifest remains immutable evidence.
    lock = (ROOT / 'phase-launch.lock').open('a')
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    ledger_file = CORRECTION / ('guard-launch-attempts.json' if guard else 'launch-attempts.json')
    launches = json.loads(ledger_file.read_text()) if ledger_file.exists() else {}
    attempts = launches.setdefault(args.phase, [])
    if guard and attempts and attempts[-1].get('status') == 'pass':
        print(json.dumps({'phase': args.phase, 'status': 'previously_passed_skipped'}))
        return
    harness_file = CORRECTION / 'ledger-private.json'
    harness = json.loads(harness_file.read_text()) if harness_file.exists() else {}
    phase = harness.get('phases', {}).get(args.phase, {})
    if phase.get('passed') is True:
        if not attempts or attempts[-1].get('status') != 'pass':
            raise RuntimeError('Source review required for an unverified passed correction')
        print(json.dumps({'phase': args.phase, 'status': 'previously_passed_skipped'}))
        return
    if len(attempts) >= 3:
        raise RuntimeError('Three dated correction launches exhausted for this issue')
    number = len(attempts) + 1
    entry = {'phase': args.phase, 'launch': number, 'status': 'started',
             'date': DATE, 'sourceSha256': manifest['sha256'], 'offline': args.offline,
             'startedAtUtc': datetime.datetime.now(datetime.timezone.utc).isoformat()}
    attempts.append(entry)
    save(ledger_file, launches)  # Count before Flutter compilation or startup.
    folder = CORRECTION / 'launches' / args.phase / f'attempt-{number}'
    folder.mkdir(parents=True, mode=0o700)
    save(folder / 'source-manifest.json', manifest)
    environment = os.environ.copy()
    environment.update(JIVIE_FULLSYNC_HTTP_FIXTURE=str(ROOT / 'fixture.json'),
                       JIVIE_FULLSYNC_PHASE=args.phase,
                       JIVIE_FULLSYNC_CORRECTION_ROOT=str(CORRECTION),
                       JIVIE_FULLSYNC_CORRECTION_OFFLINE='1' if args.offline else '0')
    command = ['/Users/anzenovsak/Dev/flutter/bin/flutter', 'test', '--no-pub',
               '--reporter', 'json', str(TEST)]
    if guard:
        command = ['docker', 'exec', NAME, 'php', '/familyhub-tests/'+PHP_GUARD.name]
    count, terminated, proc = 0, None, None
    start = time.monotonic()
    try:
        proc = subprocess.Popen(command, cwd=REPO, env=environment, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, start_new_session=True)
        selector = selectors.DefaultSelector()
        selector.register(proc.stdout, selectors.EVENT_READ)
        with (folder / 'flutter-private.jsonl').open('wb') as output:
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
                    output.write(data)
                if terminated:
                    break
        if terminated:
            os.killpg(proc.pid, signal.SIGTERM)
            try: proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                os.killpg(proc.pid, signal.SIGKILL)
                proc.wait(timeout=5)
        else:
            proc.wait(timeout=5)
        latest = json.loads(harness_file.read_text()) if harness_file.exists() else {}
        phase = latest.get('phases', {}).get(args.phase, {})
        if guard:
            result = None
            for line in (folder / 'flutter-private.jsonl').read_text(errors='replace').splitlines():
                try: item = json.loads(line)
                except (ValueError, TypeError): continue
                if isinstance(item, dict) and item.get('guard') == 'scope-access-changes-only':
                    result = item
            phase = {'passed': bool(result and result.get('status') == 'pass'
                                    and result.get('checks') == 20)}
            entry['guardChecksPassed'] = result.get('checks') if result else None
        entry.update(exitCode=proc.returncode, termination=terminated,
                     harnessPhasePassed=phase.get('passed') is True,
                     sourceUnchanged=source_manifest()['sha256'] == manifest['sha256'],
                     legacyLedgersUnchanged=legacy_hashes() == baseline['legacyLedgerSha256'])
        entry['status'] = ('pass' if proc.returncode == 0 and not terminated
                           and entry['harnessPhasePassed'] and entry['sourceUnchanged']
                           and entry['legacyLedgersUnchanged'] else 'fail')
        for key in ['code', 'errorType']:
            value = phase.get(key)
            if isinstance(value, str) and len(value) <= 100 and value.replace('_', '').isalnum():
                entry[key] = value
    except BaseException as error:
        entry.update(status='fail', launcherErrorType=type(error).__name__)
        if proc is not None and proc.poll() is None:
            os.killpg(proc.pid, signal.SIGKILL)
            proc.wait(timeout=5)
        raise
    finally:
        entry['legacyLedgersUnchanged'] = legacy_hashes() == baseline['legacyLedgerSha256']
        if not entry['legacyLedgersUnchanged']:
            entry['status'] = 'fail'
        entry.update(elapsedSeconds=round(time.monotonic() - start, 3),
                     outputBytes=min(count, 2097152))
        save(ledger_file, launches)
        save(folder / 'launch-result.json', entry)
        save(PUBLIC / ('guard-launch-summary.json' if guard else 'launch-summary.json'), launches)
    print(json.dumps(entry))
    if entry['status'] != 'pass':
        raise SystemExit(1)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['prepare', 'source', 'start', 'run', 'guard-php'])
    parser.add_argument('--phase', choices=PHASES)
    parser.add_argument('--reviewed-source-sha256')
    parser.add_argument('--offline', action='store_true')
    parser.add_argument('--timeout-seconds', type=int, default=900)
    args = parser.parse_args()
    os.umask(0o077)
    if args.action == 'prepare': prepare()
    elif args.action == 'source':
        manifest = source_manifest()
        print(json.dumps({'sha256': manifest['sha256'], 'files': len(manifest['files'])}))
    elif args.action == 'start': start_owned()
    else:
        if args.action != 'guard-php' and not args.phase: raise ValueError('One explicit correction phase required')
        launch(args)


if __name__ == '__main__':
    main()
