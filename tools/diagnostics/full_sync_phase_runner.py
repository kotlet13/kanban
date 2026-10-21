#!/usr/bin/env python3
"""Launch exactly one reviewed full-sync phase; count before Flutter compilation."""
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

from full_sync_environment import REPO, ROOT, EVIDENCE, inspect_owned, save

TEST = REPO / 'test/organizer/data/e2ee/crypto_full_sync_recovery_http_test.dart'
CONTROL_TEST = REPO / 'test/organizer/data/e2ee/crypto_sync_repository_test.dart'
CONTROL_NAME = 'terminal-only receipt selection never sends unknown or denied work and validates exact ACK'
PHASES = ['bootstrap_crypto', 'bootstrap_scopes_finance', 'bootstrap_share_admission',
          'H1_stale_fullsync', 'H2_lost_applied_response', 'H2_restart_receipt_resume',
          'H3_following_nochange', 'H4_concurrent_task_edits', 'control_terminal_receipts',
          'control_choice_directory_fetch', 'H5_before_send_outage',
          'H5_before_send_restart', 'H6_choice_cas', 'H7_revocation_recovery']
DEPENDENCIES = {
    'bootstrap_crypto': [],
    'bootstrap_scopes_finance': ['bootstrap_crypto'],
    'bootstrap_share_admission': ['bootstrap_scopes_finance'],
    'H1_stale_fullsync': ['bootstrap_share_admission'],
    'H2_lost_applied_response': ['H1_stale_fullsync'],
    'H2_restart_receipt_resume': ['H2_lost_applied_response'],
    'H3_following_nochange': ['H2_restart_receipt_resume'],
    'H4_concurrent_task_edits': ['bootstrap_share_admission'],
    'control_terminal_receipts': [],
    'control_choice_directory_fetch': ['bootstrap_share_admission'],
    'H5_before_send_outage': ['H3_following_nochange'],
    'H5_before_send_restart': ['H5_before_send_outage'],
    # H6 can use the stable H3 base if H5 is blocked; its own scenario guards
    # still require a current, conflict-free manifest before concurrent writes.
    'H6_choice_cas': ['H3_following_nochange'],
    'H7_revocation_recovery': ['H3_following_nochange'],
}


def source_manifest():
    files = [p for folder in [REPO / 'lib', REPO / 'server/plugins/FamilyHub']
             for p in folder.rglob('*') if p.is_file()]
    files += [TEST, CONTROL_TEST, Path(__file__).resolve(),
              REPO / 'tools/diagnostics/full_sync_environment.py',
              REPO / 'pubspec.lock']
    entries = {str(p.relative_to(REPO)): hashlib.sha256(p.read_bytes()).hexdigest()
               for p in sorted(files)}
    digest = hashlib.sha256(json.dumps(entries, sort_keys=True).encode()).hexdigest()
    return {'sha256': digest, 'files': entries}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', action='store_true', help='Print current source digest without launching')
    parser.add_argument('--phase', choices=PHASES)
    parser.add_argument('--reviewed-source-sha256')
    parser.add_argument('--timeout-seconds', type=int, default=900)
    args = parser.parse_args()
    manifest = source_manifest()
    if args.source:
        print(json.dumps({'sha256': manifest['sha256'], 'files': len(manifest['files'])}))
        return
    if not args.phase or args.reviewed_source_sha256 != manifest['sha256']:
        raise ValueError('Explicit selected phase and exact reviewed source digest required')
    if not 30 <= args.timeout_seconds <= 900:
        raise ValueError('Wall deadline must be 30..900 seconds')
    os.umask(0o077)
    fixture_file = ROOT / 'fixture.json'
    fixture = json.loads(fixture_file.read_text())
    if (fixture['synthetic'] is not True or fixture['purpose'] != 'local-fullsync-recovery-20261021'
            or fixture['serverUrl'] != 'http://127.0.0.1:59777'
            or any(a['session']['serverId'] != fixture['serverId'] for a in fixture['accounts'].values())):
        raise ValueError('Exact isolated target identity required')
    if len({a['session']['user']['accountId'] for a in fixture['accounts'].values()}) != 2:
        raise ValueError('Two distinct synthetic accounts required')
    obj = inspect_owned()
    if not obj['State']['Running']:
        raise RuntimeError('Owned isolated server is stopped')
    initial = json.loads((EVIDENCE / 'source-manifest.json').read_text())['pluginFiles']
    if any(manifest['files'].get(key) != value for key, value in initial.items()):
        raise ValueError('Server source changed since isolated environment preparation')
    lock = (ROOT / 'phase-launch.lock').open('a')
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    ledger_file = ROOT / 'phase-launch-attempts.json'
    launches = json.loads(ledger_file.read_text()) if ledger_file.exists() else {}
    harness_file = ROOT / 'ledger-private.json'
    harness = json.loads(harness_file.read_text()) if harness_file.exists() else {}
    control = args.phase == 'control_terminal_receipts'
    if control and launches.get(args.phase, []) and launches[args.phase][-1].get('status') == 'pass':
        print(json.dumps({'phase': args.phase, 'status': 'previously_passed_skipped'}))
        return
    if harness.get('phases', {}).get(args.phase, {}).get('passed') is True:
        previous = launches.get(args.phase, [])
        if (not previous or previous[-1].get('status') != 'pass' or
                previous[-1].get('sourceUnchanged') is False):
            raise RuntimeError('source_review_required: harness passed without a verified external launch')
        print(json.dumps({'phase': args.phase, 'status': 'previously_passed_skipped'}))
        return
    for dependency in DEPENDENCIES[args.phase]:
        if harness.get('phases', {}).get(dependency, {}).get('passed') is not True:
            raise ValueError(f'Prior phase has not passed: {dependency}')
    if args.phase == 'control_choice_directory_fetch':
        h3 = harness.get('phases', {}).get('H3_following_nochange', {})
        if h3.get('attempts') != 2 or h3.get('passed') is True:
            raise ValueError('Focused directory control requires preserved H3 failure after attempt two')
    attempts = launches.setdefault(args.phase, [])
    if len(attempts) >= 3:
        raise RuntimeError('Three external launches exhausted for this phase')
    number = len(attempts) + 1
    entry = {'launch': number, 'status': 'started', 'phase': args.phase,
             'sourceSha256': manifest['sha256'],
             'startedAtUtc': datetime.datetime.now(datetime.timezone.utc).isoformat()}
    attempts.append(entry)
    # This authoritative counter is durable before subprocess creation/compilation.
    save(ledger_file, launches)
    folder = ROOT / 'launches' / args.phase / f'attempt-{number}'
    folder.mkdir(parents=True, mode=0o700)
    save(folder / 'source-manifest.json', manifest)
    log = folder / 'flutter-private.jsonl'
    flutter = '/Users/anzenovsak/Dev/flutter/bin/flutter'
    env = os.environ.copy()
    env['JIVIE_FULLSYNC_HTTP_FIXTURE'] = str(fixture_file)
    env['JIVIE_FULLSYNC_PHASE'] = args.phase
    command = [flutter, 'test', '--no-pub', '--reporter', 'json', str(TEST)]
    if control:
        command = [flutter, 'test', '--no-pub', '--reporter', 'json',
                   str(CONTROL_TEST), '--plain-name', CONTROL_NAME]
    count = 0
    terminated = None
    start = time.monotonic()
    proc = None
    try:
        proc = subprocess.Popen(command, cwd=REPO, env=env, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, start_new_session=True)
        selector = selectors.DefaultSelector()
        selector.register(proc.stdout, selectors.EVENT_READ)
        with log.open('wb') as stream:
            log.chmod(0o600)
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
                    stream.write(data)
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
        entry['exitCode'] = proc.returncode
        entry['termination'] = terminated
        latest = json.loads(harness_file.read_text()) if harness_file.exists() else {}
        phase = latest.get('phases', {}).get(args.phase, {})
        passed = phase.get('passed') is True
        if control:
            selected_ids = set()
            passing_ids = set()
            engine_success = False
            for line in log.read_text(errors='replace').splitlines():
                try: event = json.loads(line)
                except (ValueError, TypeError): continue
                if not isinstance(event, dict): continue
                if event.get('type') == 'testStart' and event.get('test', {}).get('name') == CONTROL_NAME:
                    selected_ids.add(event['test']['id'])
                if (event.get('type') == 'testDone' and event.get('result') == 'success'
                        and event.get('skipped') is not True):
                    passing_ids.add(event.get('testID'))
                if event.get('type') == 'done': engine_success = event.get('success') is True
            passed = engine_success and len(selected_ids) == 1 and selected_ids <= passing_ids
            entry['unitControlPassed'] = passed
        after = source_manifest()
        entry['sourceAfterSha256'] = after['sha256']
        entry['sourceUnchanged'] = after['sha256'] == manifest['sha256']
        entry['status'] = ('pass' if proc.returncode == 0 and passed and not terminated
                           and entry['sourceUnchanged'] else 'fail')
        entry['harnessPhaseEntered'] = bool(phase.get('startedAtUtc'))
        entry['harnessPhasePassed'] = passed
        # Finite fields only; raw Flutter diagnostics remain private.
        for key in ('errorType', 'code'):
            value = phase.get(key)
            if isinstance(value, str) and len(value) <= 100 and value.replace('_', '').isalnum():
                entry[key] = value
    except BaseException as error:
        entry['status'] = 'fail'
        entry['launcherErrorType'] = type(error).__name__
        if proc is not None and proc.poll() is None:
            os.killpg(proc.pid, signal.SIGKILL)
            proc.wait(timeout=5)
        raise
    finally:
        entry['elapsedSeconds'] = round(time.monotonic() - start, 3)
        entry['outputBytes'] = min(count, 2097152)
        save(ledger_file, launches)
        save(EVIDENCE.parent / 'phase-launch-summary.json', launches)
        save(folder / 'launch-result.json', entry)
    print(json.dumps(entry))
    if entry['status'] != 'pass':
        raise SystemExit(1)


if __name__ == '__main__':
    main()
