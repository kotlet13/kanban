#!/usr/bin/env python3
"""Reproducible synthetic HTTP registration smoke; no Google connection or real keys."""
from pathlib import Path
import base64
import json
import os
import subprocess
import tempfile
import uuid

repo = Path(__file__).resolve().parents[2]
image = "kanboard/kanboard:v1.2.54@sha256:8df6c4339134b6c196da9a262daa42ab8ce395f528a48d4a3dd7038c296f34c1"
name = "familyhub-push-http-" + uuid.uuid4().hex[:10]
evidence = repo / "build/qa/firebase-preparation/server-push-http.log"
evidence.parent.mkdir(parents=True, exist_ok=True)

with tempfile.TemporaryDirectory(prefix="familyhub-fcm-http-") as folder:
    root = Path(folder)
    key = root / "key.pem"
    subprocess.run(["openssl", "genpkey", "-algorithm", "RSA", "-pkeyopt", "rsa_keygen_bits:2048", "-out", str(key)], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    credential = root / "credential.json"
    credential.write_text(json.dumps({"type": "service_account", "project_id": "synthetic-fcm", "client_email": "synthetic@synthetic-fcm.iam.gserviceaccount.com", "token_uri": "https://oauth2.googleapis.com/token", "private_key": key.read_text()}))
    credential.chmod(0o600)
    config = root / "config.php"
    config.write_text("<?php\ndefine('DB_DRIVER','sqlite');define('DEBUG',false);define('LOG_DRIVER','system');define('FAMILYHUB_DEVELOPMENT_MODE',true);define('FAMILYHUB_DEVELOPMENT_ENVIRONMENT',true);define('FAMILYHUB_ENABLE_NATIVE_API',true);define('FAMILYHUB_ENABLE_FCM',true);define('FAMILYHUB_PUBLIC_ROOT','/var/www');define('FAMILYHUB_FCM_PROJECT_ID','synthetic-fcm');define('FAMILYHUB_FCM_SERVICE_ACCOUNT_FILE','/tmp/familyhub-credential.json');define('FAMILYHUB_PUSH_KEY_BASE64','" + base64.b64encode(os.urandom(32)).decode() + "');\n")
    config.chmod(0o600)
    try:
        subprocess.run(["docker", "run", "-d", "--rm", "--network", "none", "--name", name, "--mount", "type=bind,src=" + str(repo / "server/plugins/FamilyHub") + ",dst=/var/www/app/plugins/FamilyHub,readonly", "--mount", "type=bind,src=" + str(repo / "server/tests") + ",dst=/familyhub-tests,readonly", image], check=True, stdout=subprocess.DEVNULL)
        for source, destination in [(credential, "/tmp/familyhub-credential.json"), (config, "/var/www/app/config.php")]:
            subprocess.run(["docker", "cp", str(source), name + ":" + destination], check=True, stdout=subprocess.DEVNULL)
        subprocess.run(["docker", "exec", name, "chown", "nginx:nginx", "/tmp/familyhub-credential.json", "/var/www/app/config.php"], check=True)
        subprocess.run(["docker", "exec", name, "chmod", "600", "/tmp/familyhub-credential.json", "/var/www/app/config.php"], check=True)
        subprocess.run(["docker", "exec", name, "curl", "--fail", "--silent", "--retry", "10", "--retry-connrefused", "--retry-delay", "1", "http://127.0.0.1/index.php?controller=NativeApiController&action=handle&plugin=FamilyHub", "-H", "Content-Type: application/json", "-d", '{"v":1,"op":"capabilities","params":{}}'], check=True, stdout=subprocess.DEVNULL)
        with evidence.open("w") as output:
            evidence.chmod(0o600)
            subprocess.run(["docker", "exec", name, "php", "/familyhub-tests/push-http-smoke.php"], check=True, stdout=output, stderr=subprocess.STDOUT)
        print("Configured HTTP smoke PASS; ephemeral network-none container removed")
    finally:
        subprocess.run(["docker", "rm", "-f", name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
