#!/usr/bin/env python3
"""One bounded synthetic Flutter diagnostic run; never retains raw output."""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import selectors
import signal
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
PREFIX = 'JIVIE_DIAGNOSTIC '
STAGES = {'setup', 'incoming_verify', 'owner_receipt', 'owner_replay',
          'current_pull', 'current_wire_open', 'current_head_check', 'journal_immutable', 'scenario_result'}
CASES = {'diagnostic production choice continuation ' + case: case for case in
         ['conflict_stale', 'applied_stale', 'pending_unknown', 'conflict_current']}
TYPES = {'FormatException', 'StateError', 'TypeError', 'CryptoAuthorityPending',
         'CryptoDirectoryException', 'CollaborationException', 'TestFailure',
         'TimeoutException', 'AssertionError', 'other'}


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(path: Path, value) -> None:
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')
    path.chmod(0o600)


def codes_from_source(root: Path) -> set[str]:
    # Only exact fixed error literals; never persist a substring of a message.
    return {code for p in (root / 'lib').rglob('*.dart') for code in re.findall(
        r"['\"]((?:crypto|directory|sync|policy|sharing)_[a-z0-9_]+)['\"]",
        p.read_text())}


def safe_stack(value, root: Path) -> list[dict]:
    """Keep source locations/symbols, discard arbitrary non-frame text."""
    if not isinstance(value, str):
        return []
    frames = []
    # Dart VM, package:test and compiler source formats.
    location = re.compile(r'((?:package:|dart:)[A-Za-z0-9_./-]+\.dart|'
                          r'(?:lib|test)/[A-Za-z0-9_./-]+\.dart|'
                          r'(?:file://)?/[^\s()]+\.dart)(?::(\d+))?(?::(\d+))?')
    for line in value.splitlines():
        if '<asynchronous suspension>' in line or re.fullmatch(r'=+ asynchronous gap =+', line.strip()):
            frames.append({'async_gap': True})
            continue
        match = location.search(line)
        if not match:
            continue
        path = match[1]
        if path.startswith(('package:', 'dart:')):
            source = path
        elif path.startswith(('lib/', 'test/')):
            source = path
        else:
            raw = Path(path.removeprefix('file://'))
            try:
                source = str(raw.relative_to(root))
            except ValueError:
                # External absolute paths are not copied into the artifact.
                continue
            if not source.startswith(('lib/', 'test/')):
                continue
        frame = {'source': source}
        if match[2]:
            frame['line'] = int(match[2])
        if match[3]:
            frame['column'] = int(match[3])
        symbol = re.match(r'^\s*#\d+\s+([A-Za-z_$][A-Za-z0-9_.$<>]*)', line)
        if symbol:
            frame['symbol'] = symbol[1]
        # package:test's terse reporter uses spaces before line/column/symbol.
        terse = re.match(r'\s+(\d+):(\d+)\s+([A-Za-z_$][A-Za-z0-9_.$<>]*)', line[match.end():])
        if terse:
            frame.update(line=int(terse[1]), column=int(terse[2]), symbol=terse[3])
        frames.append(frame)
    return frames


def diagnostic(value, root: Path, codes: set[str]):
    if not isinstance(value, dict) or value.get('version') != 1:
        return None
    if value.get('stage') not in STAGES or value.get('outcome') not in {'entered', 'passed', 'failed'}:
        return None
    item = {'origin': 'harness_stage', 'stage': value['stage'], 'outcome': value['outcome']}
    if 'code' in value:
        item['code'] = value['code'] if isinstance(value['code'], str) and value['code'] in codes else 'other'
    if 'errorType' in value:
        item['origin'] = 'harness_caught_error'
        item['errorType'] = value['errorType'] if value['errorType'] in TYPES else 'other'
    if 'stack' in value:
        item['stack_frames'] = safe_stack(value['stack'], root)
    return item


class Capture:
    def __init__(self, root, codes):
        self.root, self.codes = root, codes
        self.events = []
        self.passed = self.failed = self.skipped = self.started = 0
        self.escaping = 0
        self.protocol_rejected = self.unstructured = 0
        self.done = None
        self.compile_marker = False
        self.test_ids = set()
        self.case_by_test = {}
        self.case_results = {}

    def associate(self, item, event):
        identifier = event.get('testID')
        if type(identifier) is int:
            item['testID'] = identifier
            if identifier in self.case_by_test:
                item['scenario'] = self.case_by_test[identifier]
        return item

    def line(self, line):
        self.compile_marker |= bool(re.search(r'\bError:|Compilation failed|Failed to compile', line))
        try:
            event = json.loads(line)
        except (ValueError, TypeError):
            self.unstructured += 1
            if re.search(r'\bError:', line):
                frames = safe_stack(line, self.root)
                if frames:
                    category = 'type_mismatch' if re.search(r"can't be assigned|isn't a subtype|not assignable", line) else \
                        'undefined_symbol' if re.search(r"isn't defined|Undefined name|not found", line) else \
                        'syntax' if re.search(r'Expected |Unexpected token', line) else 'other'
                    self.events.append({'origin': 'compiler_diagnostic', 'category': category, 'stack_frames': frames})
            return
        if not isinstance(event, dict):
            self.unstructured += 1
            return
        kind = event.get('type')
        if kind == 'print':
            message = event.get('message')
            if isinstance(message, str) and message.startswith(PREFIX):
                try:
                    item = diagnostic(json.loads(message[len(PREFIX):]), self.root, self.codes)
                except (ValueError, TypeError):
                    item = None
                if item:
                    self.events.append(self.associate(item, event))
                else:
                    self.protocol_rejected += 1
        elif kind == 'testStart':
            test = event.get('test', {})
            name = test.get('name', '')
            if isinstance(name, str) and not name.startswith('loading '):
                self.test_ids.add(test.get('id'))
                self.started += 1
                if name in CASES:
                    self.case_by_test[test.get('id')] = CASES[name]
        elif kind == 'testDone' and event.get('testID') in self.test_ids:
            if event.get('hidden'):
                self.started -= 1
                self.test_ids.remove(event['testID'])
            elif event.get('skipped'):
                self.skipped += 1
            elif event.get('result') == 'success':
                self.passed += 1
            else:
                self.failed += 1
            if event['testID'] in self.case_by_test:
                self.case_results[self.case_by_test[event['testID']]] = event.get('result') if not event.get('skipped') else 'skipped'
        elif kind == 'error':
            self.escaping += 1
            message = event.get('error', '')
            error_type = next((t for t in sorted(TYPES) if isinstance(message, str) and
                               re.match(r'^' + re.escape(t) + r'\b', message)), 'other')
            if error_type == 'other' and isinstance(message, str) and message.startswith('Bad state:'):
                error_type = 'StateError'
            # Accept a whole fixed code only, not a token found inside a payload.
            code = message.removeprefix(error_type + ': ').strip() if isinstance(message, str) else ''
            self.events.append(self.associate({'origin': 'escaping_test_error', 'errorType': error_type,
                                'code': code if code in self.codes else 'other',
                                'stack_frames': safe_stack(event.get('stackTrace'), self.root)}, event))
        elif kind == 'done':
            self.done = event.get('success') is True

    def classification(self, reason, returncode, source_changed):
        if reason:
            return reason
        if source_changed:
            return 'source_changed_during_run'
        if self.protocol_rejected:
            return 'diagnostic_protocol_error'
        if returncode or self.failed or self.escaping:
            return 'compile_error' if self.compile_marker and not self.started else 'test_failure'
        if self.done is not True or not self.started or self.skipped:
            return 'incomplete_not_pass'
        scenarios = self.scenarios()
        if len(scenarios) != 4 or any(x['classification'] == 'UNVERIFIED' for x in scenarios.values()):
            return 'incomplete_scenarios_not_pass'
        return 'synthetic_reproduction_and_controls_confirmed'

    def scenarios(self):
        results = {}
        for case in CASES.values():
            events = [x for x in self.events if x.get('scenario') == case]
            terminal = all(any(x.get('stage') == stage and x.get('outcome') == 'passed' for x in events)
                           for stage in ['journal_immutable', 'scenario_result'])
            failures = [x for x in events if x['origin'] == 'harness_caught_error' and x.get('outcome') == 'failed']
            verified = self.case_results.get(case) == 'success' and terminal
            classification = 'UNVERIFIED'
            if verified and case in {'conflict_stale', 'applied_stale'} and len(failures) == 1 and failures[0].get('code') == 'crypto_account_choices_head_changed' and failures[0].get('stack_frames'):
                classification = 'REPRODUCED_EXPECTED_FAILURE'
            elif verified and case == 'pending_unknown' and len(failures) == 1 and failures[0].get('code') == 'crypto_business_delivery_pending' and failures[0].get('stack_frames'):
                classification = 'PENDING_GUARD_CONFIRMED'
            elif verified and case == 'conflict_current' and not failures:
                classification = 'MATCHING_HEAD_CONTROL_PASS'
            results[case] = {'classification': classification, 'engine_result': self.case_results.get(case),
                             'terminal_stage_evidence': terminal}
        return results


def run(args):
    os.umask(0o077)
    root = ROOT
    test = (root / args.test).resolve()
    if not test.is_relative_to(root / 'test') or not test.is_file() or test.suffix != '.dart':
        raise ValueError('test must be an existing Dart file below test/')
    if not re.fullmatch(r'[a-z][a-z0-9-]{0,63}', args.scenario):
        raise ValueError('scenario must be a stable lowercase slug; do not rename to reset attempts')
    sdk = Path(args.flutter_sdk).resolve()
    flutter = sdk / 'bin/flutter'
    if not flutter.is_file() or not (root / '.dart_tool/package_config.json').is_file():
        raise ValueError('existing Flutter SDK and package configuration required; runner never resolves dependencies')
    if not 10 <= args.wall_timeout <= 600 or not 1 <= args.max_output_mib <= 8:
        raise ValueError('wall timeout must be 10..600s and output cap 1..8MiB')
    scenario = root / 'build/qa/local-diagnostics' / args.scenario
    scenario.mkdir(parents=True, exist_ok=True)
    # Atomic directory allocation counts a compile failure/interruption as an attempt.
    attempt = None
    for number in range(1, 4):
        candidate = scenario / f'attempt-{number}'
        try:
            candidate.mkdir()
        except FileExistsError:
            continue
        attempt = candidate
        break
    if attempt is None:
        raise ValueError('three-attempt limit reached; no process started')
    paths = sorted(set([*root.joinpath('lib').rglob('*.dart'), *root.joinpath('test').rglob('*.dart'),
                        root / 'pubspec.yaml', root / 'pubspec.lock', root / '.dart_tool/package_config.json',
                        Path(__file__).resolve()]))
    manifest = [{'path': str(p.relative_to(root)), 'sha256': sha(p)} for p in paths]
    codes = codes_from_source(root)
    command = [str(flutter), 'test', '--no-pub', '--machine', '--concurrency=1',
               '--timeout=45s', str(test.relative_to(root))]
    if args.plain_name:
        command.extend(['--plain-name', args.plain_name])
    environment = {k: os.environ[k] for k in ['HOME', 'PATH', 'TMPDIR', 'LANG', 'LC_ALL', 'USER', 'LOGNAME'] if k in os.environ}
    environment.update({'CI': 'true', 'FLUTTER_SUPPRESS_ANALYTICS': 'true', 'DART_SUPPRESS_ANALYTICS': 'true'})
    save(attempt / 'manifest.json', {'label': 'synthetic-local-not-native-not-phone-state',
         'started_utc': dt.datetime.now(dt.timezone.utc).isoformat(), 'attempt': number,
         'attempt_limit': 3, 'command': command, 'wall_timeout_seconds': args.wall_timeout,
         'output_limit_bytes': args.max_output_mib * 1024 ** 2, 'source_files': manifest,
         'environment_names_only': sorted(environment), 'python': platform.python_version(),
         'platform': platform.system(), 'machine': platform.machine(),
         'sdk_files': [{'path': str(p.relative_to(sdk)), 'sha256': sha(p)} for p in
                       [flutter, sdk / 'bin/cache/flutter.version.json', sdk / 'bin/cache/dart-sdk/bin/dart']],
         'raw_output_retained': False, 'phone_or_server_actions_by_runner': False})
    capture = Capture(root, codes)
    started = time.monotonic()
    reason = None
    total = 0
    proc = None
    try:
        proc = subprocess.Popen(command, cwd=root, env=environment, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, start_new_session=True)
        selector = selectors.DefaultSelector()
        for stream in [proc.stdout, proc.stderr]:
            os.set_blocking(stream.fileno(), False)
            selector.register(stream, selectors.EVENT_READ, bytearray())
        while selector.get_map():
            if time.monotonic() - started > args.wall_timeout:
                reason = 'wall_timeout'
                break
            for key, _ in selector.select(timeout=0.2):
                data = os.read(key.fileobj.fileno(), 65536)
                if not data:
                    if key.data:
                        capture.line(key.data.decode('utf-8', errors='replace'))
                    selector.unregister(key.fileobj)
                    continue
                total += len(data)
                if total > args.max_output_mib * 1024 ** 2:
                    reason = 'output_limit'
                    break
                key.data.extend(data)
                while b'\n' in key.data:
                    end = key.data.index(b'\n')
                    capture.line(bytes(key.data[:end]).decode('utf-8', errors='replace'))
                    del key.data[:end + 1]
                if len(key.data) > 262144:
                    reason = 'line_limit'
                    break
            if reason:
                break
        selector.close()
    except KeyboardInterrupt:
        reason = 'interrupted'
    except Exception:
        reason = 'runner_infrastructure_error'
    finally:
        if proc is not None:
            if not reason and proc.poll() is None:
                try:
                    proc.wait(timeout=max(0.01, min(5, args.wall_timeout - (time.monotonic() - started))))
                except subprocess.TimeoutExpired:
                    reason = 'process_exit_timeout'
            if reason or proc.poll() is None:
                try:
                    os.killpg(proc.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
                try:
                    proc.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    try:
                        os.killpg(proc.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
            proc.wait()
    try:
        source_changed = any(not (root / row['path']).is_file() or sha(root / row['path']) != row['sha256'] for row in manifest)
    except OSError:
        source_changed = True
        reason = reason or 'runner_infrastructure_error'
    result = {'classification': capture.classification(reason, proc.returncode if proc else None, source_changed),
              'label': 'synthetic-local-not-native-not-phone-state', 'attempt': number, 'attempt_limit': 3,
              'elapsed_seconds': round(time.monotonic() - started, 3),
              'finished_utc': dt.datetime.now(dt.timezone.utc).isoformat(),
              'process_exit_code': proc.returncode if proc else None, 'source_changed': source_changed,
              'tests': {'started': capture.started, 'passed': capture.passed, 'failed': capture.failed, 'skipped': capture.skipped},
              'escaping_test_errors': capture.escaping, 'diagnostic_protocol_rejected': capture.protocol_rejected,
              'discarded_non_machine_lines': capture.unstructured, 'observed_output_bytes': total,
              'raw_output_retained': False, 'native_or_app_sync_pass_claim': False,
              'scenarios': capture.scenarios(),
              'events': capture.events}
    save(attempt / 'result.json', result)
    print(json.dumps({'artifact_directory': str(attempt), 'classification': result['classification'],
                      'tests': result['tests'], 'attempt': number, 'escaping_test_errors': capture.escaping}))
    return 0 if result['classification'] == 'synthetic_reproduction_and_controls_confirmed' else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--test', required=True, help='One NEW synthetic harness below test/. No automatic retries.')
    parser.add_argument('--scenario', required=True, help='Stable issue/scenario slug; persistent maximum three attempts.')
    parser.add_argument('--flutter-sdk', default='/Users/anzenovsak/Dev/flutter')
    parser.add_argument('--plain-name', help='Optional literal Flutter test name selector.')
    parser.add_argument('--wall-timeout', type=int, default=180)
    parser.add_argument('--max-output-mib', type=int, default=2)
    args = parser.parse_args()
    try:
        return run(args)
    except (ValueError, OSError) as error:
        print(json.dumps({'classification': 'preflight_not_launched', 'reason': type(error).__name__}), file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
