#!/usr/bin/env python3
"""Read-only orchestration of fresh synthetic tests in the three existing local fixtures."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import os
import re
import subprocess

root = Path(__file__).resolve().parents[2]
output = root / 'build/qa/space-sharing'
output.mkdir(parents=True, exist_ok=True)
output.chmod(0o700)
fixtures = {
    'sqlite': 'kanban-familyhub-dev-kanboard-1',
    'mysql': 'kanban-familyhub-mysqltest-kanboard-1',
    'mariadb': 'kanban-familyhub-mariadbtest-kanboard-1',
}
suites = [
    'space-sharing-integration', 'native-integration', 'spaces-integration',
    'email-invitation-integration', 'organization-integration', 'finance-integration',
    'finance-planning-integration', 'linked-payments-integration',
    'collaboration-integration', 'reminder-archive-integration',
    'deletion-integration', 'deletion-negative', 'personal-integration',
    'push-integration', 'account-integration', 'scope-rate-integration',
    'session-renewal-integration',
]

def run_fixture(entry):
    driver, container = entry
    count = 0
    for suite in suites:
        result = subprocess.run(['docker', 'exec', container, 'php',
                                 f'/familyhub-tests/{suite}.php'],
                                capture_output=True, text=True)
        path = output / f'{driver}-{suite}.log'
        path.write_text(result.stdout + result.stderr)
        path.chmod(0o600)
        if result.returncode:
            print(f'FAIL {driver} {suite}; see {path}', flush=True)
            return False
        lines = [line for line in result.stdout.splitlines() if line.startswith(('PASS:', 'PASS '))]
        summaries = [re.search(r'^(?:PASS:|SUCCESS|PASSED) (\d+)\b', line) for line in result.stdout.splitlines()]
        totals = [match for match in summaries if match]
        checks = int(totals[-1].group(1)) if totals else len(lines)
        count += checks
        print(f'PASS {driver} {suite}: {checks}', flush=True)
    print(f'PASS {driver} TOTAL: {count} checks across {len(suites)} suites', flush=True)
    return True

with ThreadPoolExecutor(max_workers=3) as pool:
    results = list(pool.map(run_fixture, fixtures.items()))
raise SystemExit(0 if all(results) else 1)
