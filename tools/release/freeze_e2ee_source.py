#!/usr/bin/env python3
"""Hash the complete current E2EE source set; never run tests or copy secrets.

Default prints a compact plan. --write creates an immutable manifest only after
root declares the shared freeze. --verify rediscovers paths, including newly
untracked source, and fails on additions, removals, modes or byte changes.
"""
from __future__ import annotations

import argparse
import fnmatch
import hashlib
import json
import os
from pathlib import Path
import stat
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOTS = (
    "lib", "test", "integration_test", "assets", "fonts", "web",
    "android", "ios", "macos", "windows", "linux", "native", "server", "tools",
)
REQUIRED = {"pubspec.yaml", "pubspec.lock", "lib/main.dart", "server/plugins/FamilyHub/Schema/CryptoSchema.php", "server/tests/run-crypto-freeze-matrix.py"}
ROOT_CONFIG = {"pubspec.yaml", "pubspec.lock", "analysis_options.yaml", "l10n.yaml", ".metadata", ".gitignore"}
# Firebase CLIENT configuration is not an admin/service-account credential.
# Only these known local client config hashes are included even if gitignored.
CLIENT_CONFIG = (
    "android/app/google-services.json",
    "android/app/src/main/res/values/firebase_config.xml",
    "ios/Runner/GoogleService-Info.plist",
    "macos/Runner/GoogleService-Info.plist",
)
EXCLUDED_PARTS = {
    ".git", ".dart_tool", ".gradle", ".idea", ".pub-cache", ".pub", "build",
    "Pods", "Carthage", "ephemeral", "DerivedData", "xcuserdata", "node_modules",
    "__pycache__", "coverage", "private", "credentials", "secrets", "logs",
}
SECRET_NAMES = (
    ".env", ".env.*", "*.p8", "*.p12", "*.pfx", "*.pem", "*.key", "*.jks",
    "*.keystore", "*.mobileprovision", "*service-account*.json", "*firebase-adminsdk*.json",
    "key.properties", "jivie-key.properties", "local.properties", "config.php",
    "*.sqlite", "*.sqlite-*", "*.db", "*.db-*", "*.log", "*.pyc", ".DS_Store",
)
NON_SOURCE_DOC = {".md", ".pdf", ".docx", ".drawio"}


def public_source(name: str) -> bool:
    path = Path(name)
    if path.is_absolute() or ".." in path.parts:
        return False
    if any(part in EXCLUDED_PARTS for part in path.parts):
        return False
    if name not in ROOT_CONFIG and (not path.parts or path.parts[0] not in SOURCE_ROOTS):
        return False
    if path.suffix.lower() in NON_SOURCE_DOC:
        return False
    return not any(fnmatch.fnmatch(path.name.lower(), pattern.lower()) for pattern in SECRET_NAMES)


def discover() -> list[str]:
    # Git only supplies paths: tracked modifications and new untracked files
    # both participate. No HEAD-only or fixed per-module file list is used.
    output = subprocess.check_output(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"], cwd=ROOT,
    )
    names = {os.fsdecode(item) for item in output.split(b"\0") if item}
    # Discover all Dart source explicitly too, even if a local ignore rule was
    # accidentally broad. Generated/build/private directories remain excluded.
    for folder in ("lib", "test", "integration_test"):
        base = ROOT / folder
        if base.exists():
            for here, directories, files in os.walk(base, followlinks=False):
                directories[:] = [d for d in directories if d not in EXCLUDED_PARTS]
                for name in files:
                    if name.endswith(".dart"):
                        names.add((Path(here) / name).relative_to(ROOT).as_posix())
    names.update(name for name in CLIENT_CONFIG if (ROOT / name).is_file())
    return sorted(name for name in names if public_source(name) and (ROOT / name).exists())


def snapshot() -> dict:
    entries = []
    names = discover()
    if REQUIRED - set(names):
        raise ValueError("Missing required source/config input: " + ", ".join(sorted(REQUIRED - set(names))))
    for platform in ("android", "ios", "macos", "windows", "linux"):
        if not any(name.startswith(platform + "/") for name in names):
            raise ValueError("Missing platform source: " + platform)
    for name in names:
        path = ROOT / name
        before = path.lstat()
        if not stat.S_ISREG(before.st_mode):
            raise ValueError("Nonregular source input: " + name)
        digest = hashlib.sha256()
        with path.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
        after = path.lstat()
        if (before.st_size, before.st_mtime_ns, before.st_mode) != (after.st_size, after.st_mtime_ns, after.st_mode):
            raise ValueError("Source changed while hashing: " + name)
        entries.append({"path": name, "sha256": digest.hexdigest(), "bytes": after.st_size,
                        "executable": bool(after.st_mode & 0o111)})
    canonical = json.dumps(entries, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()
    return {"format": "jivie-e2ee-shared-source-freeze-v1", "root": str(ROOT),
            "headProvenanceOnly": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
            "sourceRoots": list(SOURCE_ROOTS), "entries": entries,
            "aggregateSha256": hashlib.sha256(canonical).hexdigest(),
            "scope": "Working-tree source/config hashes; includes untracked source; excludes docs/build/private credentials/logs; no runtime result"}


def compact(data: dict) -> dict:
    counts = {}
    for item in data["entries"]:
        part = item["path"].split("/", 1)[0]
        counts[part] = counts.get(part, 0) + 1
    return {"files": len(data["entries"]), "byRoot": counts,
            "aggregateSha256": data["aggregateSha256"], "runtimeExecuted": False}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--write", type=Path, help="Create only after shared SOURCE READY; never overwrite")
    group.add_argument("--verify", type=Path, help="Rediscover entire source set against an existing manifest")
    args = parser.parse_args()
    current = snapshot()
    if args.write:
        # Detect any concurrent edits/additions while constructing the baseline.
        second = snapshot()
        if current["entries"] != second["entries"]:
            raise ValueError("Source changed during freeze; no manifest created")
        args.write.parent.mkdir(parents=True, exist_ok=True)
        descriptor = os.open(args.write, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "w") as stream:
            json.dump(current, stream, ensure_ascii=False, indent=2)
            stream.write("\n")
        print(json.dumps({"state": "FROZEN_SOURCE_ONLY", **compact(current)}))
        return 0
    if args.verify:
        expected = json.loads(args.verify.read_text())
        if expected.get("format") != current["format"]:
            raise ValueError("Unknown freeze manifest")
        old = {entry["path"]: entry for entry in expected["entries"]}
        new = {entry["path"]: entry for entry in current["entries"]}
        changed = sorted(name for name in old.keys() & new.keys() if old[name] != new[name])
        added, removed = sorted(new.keys() - old.keys()), sorted(old.keys() - new.keys())
        print(json.dumps({"state": "UNCHANGED" if not (changed or added or removed) else "CHANGED",
                          "changedCount": len(changed), "addedCount": len(added), "removedCount": len(removed),
                          "changed": changed[:20], "added": added[:20], "removed": removed[:20],
                          "detailsTruncated": max(len(changed), len(added), len(removed)) > 20,
                          **compact(current)}))
        return int(bool(changed or added or removed))
    print(json.dumps({"state": "PLAN_NOT_FROZEN", **compact(current),
                      "next": "Wait for root shared freeze declaration, then --write; run --verify before and after each assigned representative"}))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(2)
