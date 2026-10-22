#!/usr/bin/env python3
"""Finite isolated L1/L2 launches; count before compilation, never auto retry."""
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

from sync_resolution_cost_environment import REPO, ROOT, NAME, inspect_owned, save

TEST = REPO / 'test/organizer/data/e2ee/crypto_sync_resolution_cost_http_test.dart'
PUBLIC = REPO / 'build/qa/local-diagnostics/sync-resolution-cost-20261022'


def source_manifest():
    paths = [*sorted((REPO / 'lib').rglob('*.dart')),
             *sorted(p for p in (REPO / 'server/plugins/FamilyHub').rglob('*') if p.is_file()),
             TEST, Path(__file__).resolve(),
             REPO / 'tools/diagnostics/sync_resolution_cost_environment.py',
             REPO / 'test/organizer/data/collaboration_repository_test.dart',
             REPO / 'pubspec.yaml', REPO / 'pubspec.lock',
             REPO / 'server/dev-config.php']
    files = {str(p.relative_to(REPO)): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
    return {'files': files, 'sha256': hashlib.sha256(json.dumps(files, sort_keys=True).encode()).hexdigest()}


def validate_target():
    fixture = json.loads((ROOT / 'fixture.json').read_text())
    keys = {f'{scenario}_{actor}' for scenario in ['L1', 'L2'] for actor in ['owner', 'member']}
    accounts = fixture.get('accounts', {})
    if (fixture.get('synthetic') is not True or
            fixture.get('purpose') != 'local-sync-resolution-cost-20261022' or
            fixture.get('serverUrl') != 'http://127.0.0.1:59778' or set(accounts) != keys or
            len({a['session']['user']['accountId'] for a in accounts.values()}) != 4 or
            any(a['session']['serverId'] != fixture['serverId'] for a in accounts.values()) or
            any(fixture['clientStateDirs'][k] != str(ROOT / k) for k in keys)):
        raise RuntimeError('Exact new four-account isolated fixture required')
    obj = inspect_owned()
    if not obj['State']['Running']:
        raise RuntimeError('Owned new local HTTP lab must be running')
    ports = obj['HostConfig']['PortBindings']
    if ports != {'80/tcp': [{'HostIp': '127.0.0.1', 'HostPort': '59778'}]}:
        raise RuntimeError('Exact loopback binding required')


def launch(args):
    manifest = source_manifest()
    if args.reviewed_source_sha256 != manifest['sha256']:
        raise RuntimeError('Exact reviewed source digest required')
    if not 30 <= args.timeout_seconds <= 900:
        raise ValueError('Deadline must be 30..900 seconds')
    validate_target()
    lock = (ROOT / 'launch.lock').open('a')
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    ledger_file = ROOT / 'launch-attempts.json'
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
    folder = ROOT / 'launches' / args.scenario / f'attempt-{number}'
    folder.mkdir(mode=0o700, parents=True)
    save(folder / 'source-manifest.json', manifest)
    env = os.environ.copy()
    env.update(JIVIE_SYNC_GAPS_FIXTURE=str(ROOT / 'fixture.json'),
               JIVIE_SYNC_GAPS_SCENARIO=args.scenario)
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
                     substeps={k: {f: v[f] for f in ['passed', 'attempts', 'code', 'errorType'] if f in v}
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
    parser.add_argument('action', choices=['source', 'run'])
    parser.add_argument('--scenario', choices=['L1', 'L2'])
    parser.add_argument('--reviewed-source-sha256')
    parser.add_argument('--timeout-seconds', type=int, default=900)
    args = parser.parse_args()
    os.umask(0o077)
    if args.action == 'source':
        manifest = source_manifest()
        print(json.dumps({'sha256': manifest['sha256'], 'files': len(manifest['files'])}))
    else:
        if not args.scenario:
            raise ValueError('One explicit scenario required')
        launch(args)


if __name__ == '__main__':
    main()
