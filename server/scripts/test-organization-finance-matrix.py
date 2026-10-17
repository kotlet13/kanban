#!/usr/bin/env python3
"""Run synthetic finance4 and affected regression suites in existing dev fixtures."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
SUITES = (
    'organization-finance-integration', 'finance-planning-integration',
    'finance-integration', 'linked-payments-integration',
    'scope-lifecycle-integration', 'space-sharing-integration',
    'spaces-integration', 'deletion-integration',
)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sqlite-container', default='familyhub-documents-tests-sqlite-1')
    parser.add_argument('--mariadb-container', default='familyhub-documents-tests-mariadb-1')
    parser.add_argument('--mysql-container', default='familyhub-documents-mysql-mariadb-1')
    parser.add_argument('--output', type=Path, default=ROOT / 'build/qa/organization-finance-20261017')
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    args.output.chmod(0o700)
    fixtures = {
        'sqlite': args.sqlite_container,
        'mariadb': args.mariadb_container,
        'mysql': args.mysql_container,
    }

    def run_fixture(item):
        driver, container = item
        results = []
        for suite in SUITES:
            result = subprocess.run(
                ['docker', 'exec', container, 'php', f'/familyhub-tests/{suite}.php'],
                capture_output=True, text=True,
            )
            log = args.output / f'{driver}-{suite}.log'
            log.write_text(result.stdout + result.stderr)
            log.chmod(0o600)
            summaries = re.findall(r'^(?:PASS:|SUCCESS|PASSED) (\d+)\b', result.stdout, re.M)
            checks = int(summaries[-1]) if summaries else len(re.findall(r'^PASS:', result.stdout, re.M))
            evidence = {'driver': driver, 'suite': suite, 'passed': result.returncode == 0, 'checks': checks}
            results.append(evidence)
            print(json.dumps(evidence), flush=True)
        return results

    with ThreadPoolExecutor(max_workers=3) as pool:
        evidence = sum(pool.map(run_fixture, fixtures.items()), [])
    summary = args.output / 'summary.json'
    summary.write_text(json.dumps(evidence, indent=2) + '\n')
    summary.chmod(0o600)
    return 0 if all(row['passed'] for row in evidence) else 1


if __name__ == '__main__':
    raise SystemExit(main())
