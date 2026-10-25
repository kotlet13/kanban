#!/usr/bin/env python3
"""Fresh, loopback-only QA environment. Never reuses or deletes old QA data.

Secrets and TLS private keys stay outside the repository. Preparation is separate
from starting containers so the reviewed backend can be frozen before testing.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import secrets
import shutil
import socket
import subprocess


REPO = Path(__file__).resolve().parents[2]
NAME = "jivie-sync-redesign-20261024"
PUBLIC = REPO / "build/qa/sync-redesign-20261024"
SERVER = PUBLIC / "server"
PRIVATE = Path.home() / "Library/Application Support/JivieLocalTest/20261024-sync-redesign"
TEMPLATE = REPO / "build/qa/jivie-mac-sharing-test-20261019/server"
LABEL = "si.triparna.jivie.sync-redesign"
PORTS = (18820, 18821, 18822)
IMAGE = "sha256:94a3aa6b7a82cb515539382e918df16bf40133aef01b643895419db18d7626c3"
MAIL_IMAGE = "axllent/mailpit@sha256:94f6b70c1436defae6799d9ac7ff0eeff9540465b842026d5cdb018f1c0234ea"


def run(args: list[str], timeout: int = 60) -> str:
    result = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
    if result.returncode:
        PRIVATE.mkdir(parents=True, exist_ok=True, mode=0o700)
        write(PRIVATE / "last-command-error.json", {
            "tool": args[0], "returncode": result.returncode,
            "stdout": result.stdout[-16384:], "stderr": result.stderr[-16384:],
        })
        raise RuntimeError(f"{args[0]} failed; private diagnostic retained")
    return result.stdout


def write(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2) + "\n")
    temporary.chmod(0o600)
    temporary.replace(path)


def inventory() -> list[dict]:
    return [json.loads(line) for line in run([
        "docker", "ps", "-a", "--format", "{{json .}}",
    ]).splitlines()]


def plugin_manifest() -> dict:
    entries = []
    for path in sorted((SERVER / "FamilyHub").rglob("*")):
        if path.is_file():
            entries.append({"path": path.relative_to(SERVER).as_posix(),
                            "sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
    return {"files": entries, "aggregate": hashlib.sha256(
        json.dumps(entries, sort_keys=True).encode()).hexdigest()}


def prepare() -> None:
    # No resume through an unknown partial state, and no overwrite of old data.
    if SERVER.exists() or PRIVATE.exists():
        raise RuntimeError("Fresh destination already exists; inspect it without resetting")
    before = inventory()
    if any(row["Names"].startswith(NAME + "-") for row in before):
        raise RuntimeError("Fresh project name is already in use")
    volumes = run(["docker", "volume", "ls", "--format", "{{.Name}}"])
    if any(line.startswith(NAME + "_") for line in volumes.splitlines()):
        raise RuntimeError("Fresh volume name is already in use")
    for port in PORTS:
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", port))
    for image in (IMAGE, MAIL_IMAGE):
        run(["docker", "image", "inspect", image])
    PRIVATE.mkdir(parents=True, mode=0o700)
    os.chmod(PRIVATE, 0o700)
    (SERVER / "tls").mkdir(parents=True)
    (SERVER / "logs").mkdir(mode=0o700)
    write(PUBLIC / "initial-container-inventory.json", before)
    for filename in ("start-container.sh", "app-nginx.conf", "qa-index.php"):
        shutil.copyfile(TEMPLATE / filename, SERVER / filename)
    shutil.copyfile(TEMPLATE / "metadata-operations.json", SERVER / "metadata-operations.json")
    operations = json.loads((SERVER / "metadata-operations.json").read_text())
    if "account.changes" not in operations:
        operations.append("account.changes")
    write(SERVER / "metadata-operations.json", operations)
    config = (TEMPLATE / "config.php").read_text()
    config = config.replace("127.0.0.1:18811", "127.0.0.1:18821")
    config = config.replace("// QA-only backend e2910f9; original36139e8 provenance retained separately; no production configuration.",
                            "// Fresh sync redesign QA; no production configuration.")
    (SERVER / "config.php").write_text(config)
    bootstrap = (TEMPLATE / "bootstrap.php").read_text().replace(
        "New isolated native Mac sharing test36139e8", "Fresh sync redesign QA 20261024")
    (SERVER / "bootstrap.php").write_text(bootstrap)
    gateway = (TEMPLATE / "gateway.conf").read_text()
    (SERVER / "gateway.conf").write_text(gateway)
    secret_values = {"accountMailKeyBase64": base64.b64encode(secrets.token_bytes(32)).decode(),
                     "adminPassword": secrets.token_urlsafe(32)}
    private_php = "<?php\nreturn [\n" + "".join(
        f"    '{key}' => '{value}',\n" for key, value in secret_values.items()) + "];\n"
    (PRIVATE / "secrets.php").write_text(private_php)
    (PRIVATE / "secrets.php").chmod(0o600)
    for args in (
        ["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "90",
         "-subj", "/CN=Jivie Sync Redesign Local QA CA", "-keyout", str(PRIVATE / "ca.key"),
         "-out", str(SERVER / "tls/ca.pem"), "-addext", "basicConstraints=critical,CA:TRUE"],
        ["openssl", "req", "-new", "-newkey", "rsa:2048", "-nodes",
         "-subj", "/CN=localhost", "-keyout", str(PRIVATE / "server.key"),
         "-out", str(PRIVATE / "server.csr")],
    ):
        run(args)
    (PRIVATE / "server.ext").write_text(
        "subjectAltName=DNS:localhost,IP:127.0.0.1\n"
        "basicConstraints=critical,CA:FALSE\nextendedKeyUsage=serverAuth\n")
    run(["openssl", "x509", "-req", "-in", str(PRIVATE / "server.csr"),
         "-CA", str(SERVER / "tls/ca.pem"), "-CAkey", str(PRIVATE / "ca.key"),
         "-set_serial", str(secrets.randbits(128)), "-days", "90",
         "-extfile", str(PRIVATE / "server.ext"), "-out", str(SERVER / "tls/server.crt")])
    for path in PRIVATE.iterdir():
        if path.is_file():
            path.chmod(0o600)
    compose = (TEMPLATE / "compose.yaml").read_text()
    compose = compose.replace("jivie-mac-sharing-test-20261019", NAME)
    compose = compose.replace("20261019-sharing", "20261024-sync-redesign")
    compose = compose.replace("20261024-sync-redesign/tls/server.key", "20261024-sync-redesign/server.key")
    for old, new in (("18810", "18820"), ("18811", "18821"), ("18812", "18822")):
        compose = compose.replace(old, new)
    # Let Docker allocate networks rather than colliding with another project's subnet.
    compose = compose.replace("    ipam:\n      config:\n        - subnet: 10.231.20.0/24\n", "")
    compose = compose.replace("    ipam:\n      config:\n        - subnet: 10.231.19.0/24\n", "")
    compose = compose.replace("  restart: unless-stopped", "  restart: 'no'")
    compose = compose.replace("    restart: unless-stopped", "    restart: 'no'")
    compose = compose.replace("  image:", "  labels:\n    " + LABEL + ": '20261024'\n  image:", 1)
    compose = compose.replace("    image:", "    labels:\n      " + LABEL + ": '20261024'\n    image:")
    compose = compose.replace("  restart: 'no'", "  logging:\n    driver: json-file\n    options: {max-size: '2m', max-file: '2'}\n  restart: 'no'", 1)
    (SERVER / "compose.yaml").write_text(compose)
    shutil.copytree(REPO / "server/plugins/FamilyHub", SERVER / "FamilyHub")
    write(PUBLIC / "server-source-manifest.json", plugin_manifest())
    run(["docker", "compose", "-f", str(SERVER / "compose.yaml"), "config", "--quiet"])
    write(PUBLIC / "environment.json", {"project": NAME, "status": "prepared_not_started",
          "url": "https://127.0.0.1:18821/", "mailUrl": "http://127.0.0.1:18822/",
          "privateRoot": str(PRIVATE), "existingDataCopied": False,
          "oldEnvironmentsChanged": False, "phonesTouched": False})
    print("Fresh QA prepared; containers not started; credentials retained privately.")


def stage_server() -> None:
    if any(row["Names"].startswith(NAME + "-") for row in inventory()):
        raise RuntimeError("Stage allowed only before fresh containers exist")
    state = json.loads((PUBLIC / "environment.json").read_text())
    if state["status"] != "prepared_not_started":
        raise RuntimeError("Unknown environment state")
    target = SERVER / "FamilyHub"
    if target.is_symlink() or target.parent != SERVER:
        raise RuntimeError("Unexpected source staging path")
    # This directory is disposable source only, never a Docker data volume.
    shutil.rmtree(target)
    shutil.copytree(REPO / "server/plugins/FamilyHub", target)
    write(PUBLIC / "server-source-manifest.json", plugin_manifest())
    operations = json.loads((SERVER / "metadata-operations.json").read_text())
    operations = sorted(set(operations) | {
        "account.changes", *["crypto2.scope.recordPolicy." + action
        for action in ("prepare", "stage", "activate", "status", "baseline")]
    })
    write(SERVER / "metadata-operations.json", operations)
    print("Fresh server source staged; existing data and environments untouched.")


def up() -> None:
    expected = json.loads((PUBLIC / "server-source-manifest.json").read_text())
    if expected != plugin_manifest():
        raise RuntimeError("Staged server source changed; review and record new manifest first")
    for row in inventory():
        if row["Names"].startswith(NAME + "-"):
            details = json.loads(run(["docker", "inspect", row["ID"]]))[0]
            if details["Config"]["Labels"].get(LABEL) != "20261024":
                raise RuntimeError("Unexpected container ownership")
    run(["docker", "compose", "-f", str(SERVER / "compose.yaml"), "up", "-d"], timeout=60)
    print("Started only the fresh redesign QA project; no old data reused or removed.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("prepare", "stage", "up"))
    args = parser.parse_args()
    {"prepare": prepare, "stage": stage_server, "up": up}[args.action]()
