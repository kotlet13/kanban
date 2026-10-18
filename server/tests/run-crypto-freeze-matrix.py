#!/usr/bin/env python3
"""One explicit final matrix; default only plans. No sum of overlapping suites."""
import argparse
import hashlib
import json
import pathlib
import re
import subprocess
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parents[2]
TESTS = pathlib.Path(__file__).resolve().parent
CONTAINERS = {
    "sqlite": "familyhub-crypto-tests-sqlite-1",
    "mariadb": "familyhub-crypto-mariadb-app-1",
    "mysql": "familyhub-crypto-mysql-app-1",
}
# Server boundary suites may include earlier fixtures. Counts are cumulative for
# EACH suite, never independent totals. Actual Flutter HTTP is a separate gate.
# Importing leaf suites retain their base assertions; do not run those bases
# separately. Pure vectors and SQLite-memory checks are not three-driver SQL
# evidence. The incompatible v1 prototype and JSON-vector generator are excluded.
SUITES = [
    "crypto-account-deletion-v2.php",
    "crypto-business-parity-v3-vectors.php",
    "crypto-capture-inbox-state-v3.php",
    "crypto-capture-legacy-v3-vectors.php",
    "crypto-capture-v3-vectors.php",
    "crypto-codec-vectors.php",
    "crypto-fence-states.php",
    "crypto-invitation-mail-fence.php",
    "crypto-invitation-migration-stage-v3.php",
    "crypto-migration-commitments-v3-vectors.php",
    "crypto-migration-generation-prefix-v3.php",
    "crypto-migration-receipts-v3.php",
    "crypto-notification-migration-stage-v3.php",
    "crypto-notification-migration-v3-vectors.php",
    "crypto-project-relocation-nonowner-v2.php",
    "crypto-project-relocation-prepare-v2.php",
    "crypto-project-relocation-v2-vectors.php",
    "crypto-schema-preservation.php",
    "crypto-scope-deletion-v2.php",
    "crypto-structure-set-v3-vectors.php",
    "crypto-worker-fence-fairness.php",
    "crypto2-access-cancel-integration.php",
    "crypto2-access-consequences-integration.php",
    "crypto2-access-many-integration.php",
    "crypto2-access-member-remove-integration.php",
    "crypto2-access-policy-integration.php",
    "crypto2-access-policy2-integration.php",
    "crypto2-access-project-policy-integration.php",
    "crypto2-address-vectors.php",
    "crypto2-boundary.php",
    "crypto2-checkpoint-history-integration.php",
    "crypto2-deletion-boundary-integration.php",
    "crypto2-export-batch-integration.php",
    "crypto2-export-evidence-integration.php",
    "crypto2-finance-policy-integration.php",
    "crypto2-key-contribution-integration.php",
    "crypto2-leave-helper-integration.php",
    "crypto2-leave-integration.php",
    "crypto2-lifecycle-integration.php",
    "crypto2-membership-limit-integration.php",
    "crypto2-migration-attest-integration.php",
    "crypto2-migration-integration.php",
    "crypto2-migration-origin-tag-integration.php",
    "crypto2-migration-provenance-vectors.php",
    "crypto2-moderation-availability-integration.php",
    "crypto2-moderation-own-receipt-integration.php",
    "crypto2-moderation-quota-integration.php",
    "crypto2-moderation-retention-integration.php",
    "crypto2-notification-integration.php",
    "crypto2-origin-author-integration.php",
    "crypto2-protection-integration.php",
    "crypto2-rebind-integration.php",
    "crypto2-scheduling-use-integration.php",
    "crypto2-scope-observation-integration.php",
    "crypto2-scoped-directory-prefix-integration.php",
    "crypto2-security-mail-integration.php",
]
# Bind completed representative evidence before clearing these freeze gates,
# not skipped tests that may silently turn into a green release matrix.
# Closed HTTP evidence: tools/release/e2ee_representatives.json binds inline31,
# retained36b/38-41, relocation43-46, combined47->61 and valid use3 64->65.
# This does not assert a new final-source PHP matrix or P0/P8 release approval.
PENDING_GATES = []


def source_snapshot():
    # Include the runner, bootstrap and test fixtures, and rediscover the whole
    # set at completion so additions/removals cannot escape the freeze check.
    files = list((ROOT / "server/plugins/FamilyHub").rglob("*.php"))
    files += [p for p in TESTS.rglob("*") if p.is_file()
              and p.suffix in {".php", ".py", ".json"}]
    return {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(set(files))}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true", help="Run only after source freeze and runner coordination")
    parser.add_argument("--databases", nargs="+", choices=list(CONTAINERS), default=list(CONTAINERS))
    parser.add_argument("--suite", action="append", help="Exact explicit subset; default full frozen list")
    parser.add_argument("--output", type=pathlib.Path, default=ROOT / "build/qa/e2ee-source-upgrade/final-matrix")
    args = parser.parse_args()
    args.output = args.output.resolve()
    suites = args.suite or SUITES
    missing = [s for s in suites if not re.fullmatch(r"[a-z0-9-]+\.php", s) or not (TESTS / s).is_file()]
    if missing:
        parser.error("Missing exact suites: " + ", ".join(missing))
    plan = {"databases": args.databases, "suites": suites, "pendingFreezeGates": PENDING_GATES,
            "counts": "per-suite cumulative; overlapping fixture counts are never summed",
            "http": "not executed by this PHP matrix; requires separately frozen actual Flutter evidence"}
    if not args.run:
        print(json.dumps(plan, indent=2))
        return 0
    args.output.mkdir(parents=True, exist_ok=True)
    source_hashes = source_snapshot()
    (args.output / "source-hashes.json").write_text(json.dumps(source_hashes, indent=2) + "\n")
    results = []
    for database in args.databases:
        for suite in suites:
            log = args.output / f"{database}-{suite.removesuffix('.php')}.log"
            started = time.monotonic()
            command = ["docker", "exec", "-u", "nginx", "-e", "JIVIE_CRYPTO_FREEZE_SYNTHETIC=1",
                       CONTAINERS[database], "php", "/familyhub-tests/crypto-freeze-isolated.php", suite]
            with log.open("wb") as stream:
                try:
                    process = subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT, timeout=600, check=False)
                    status = process.returncode
                except subprocess.TimeoutExpired:
                    status = 124
            content = log.read_text(errors="replace")
            errors = bool(re.search(r"Fatal error|Uncaught|^FAIL:|^ERROR", content, re.MULTILINE))
            summaries = [line for line in content.splitlines() if re.search(r"\b(PASS|SUCCESS)\b", line)]
            result = {"database": database, "suite": suite, "exitCode": status,
                      "passed": status == 0 and not errors and bool(summaries),
                      "elapsedSeconds": round(time.monotonic() - started, 2), "log": str(log.relative_to(ROOT)),
                      "cumulativeSummary": summaries[-1] if summaries else None,
                      "suiteSourceSha256": hashlib.sha256((TESTS / suite).read_bytes()).hexdigest()}
            results.append(result)
            print(f"{database} {suite}: {'PASS' if result['passed'] else 'FAIL'}", flush=True)
            (args.output / "summary.json").write_text(json.dumps({"plan": plan, "results": results}, indent=2) + "\n")
    final_hashes = source_snapshot()
    changed = sorted(name for name in source_hashes.keys() & final_hashes.keys()
                     if source_hashes[name] != final_hashes[name])
    added = sorted(final_hashes.keys() - source_hashes.keys())
    removed = sorted(source_hashes.keys() - final_hashes.keys())
    (args.output / "source-hashes-final.json").write_text(json.dumps(final_hashes, indent=2) + "\n")
    (args.output / "summary.json").write_text(json.dumps({"plan": plan, "results": results,
        "sourceChanged": changed, "sourceAdded": added, "sourceRemoved": removed}, indent=2) + "\n")
    print("Per-suite results saved; no overlapping count total is claimed.")
    if changed or added or removed or not all(r["passed"] for r in results):
        return 1
    if PENDING_GATES and not args.suite:
        print("INCOMPLETE: mandatory final gates remain listed; no final freeze PASS.")
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
