#!/usr/bin/env python3
"""Guarded SMTP configuration for the existing Jivie production site only."""
import base64
import hashlib
import json
import os
from pathlib import Path
import secrets
import stat
import subprocess
import sys

BASE = Path('/home/tripar13/private/jivie-production')
ROOT = Path('/home/tripar13/jivie.triparna.si')
PHP = '/opt/alt/php84/usr/bin/php'
WORK = BASE / 'install/smtp-20261014'
FEATURE = BASE / 'familyhub-config.php'
EXPECTED = '8b95f016af472cf681ceba92978ac959df9d945bfb810926567990ee4977f797'
PASSWORD = BASE / 'smtp-password.txt'
KEY = BASE / 'account-mail.key'
SMTP = BASE / 'smtp-config.php'
CANDIDATE = WORK / 'familyhub-config.candidate.php'
STATE = WORK / 'state.json'
AUTH = WORK / 'auth-proof.json'


def guard(condition, code):
    if not condition:
        raise RuntimeError(code)


def private(path, directory=False):
    info = path.lstat()
    guard(not path.is_symlink() and path.resolve() == path,
          'noncanonical_private_path')
    guard(info.st_uid == os.getuid() and stat.S_IMODE(info.st_mode) ==
          (0o700 if directory else 0o600), 'private_permissions_or_owner')
    guard(stat.S_ISDIR(info.st_mode) if directory else stat.S_ISREG(info.st_mode),
          'private_file_type')


def digest(data):
    return hashlib.sha256(data).hexdigest()


def write_new(path, data):
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, 'wb') as stream:
        stream.write(data)
        stream.flush()
        os.fsync(stream.fileno())
    private(path)


def crontab():
    result = subprocess.run(['crontab', '-l'], capture_output=True, check=True)
    return result.stdout


def password_stamp():
    private(PASSWORD)
    info = PASSWORD.stat()
    guard(0 < info.st_size <= 4096, 'password_missing_or_empty')
    return dict(device=info.st_dev, inode=info.st_ino, size=info.st_size,
                modified=int(info.st_mtime))


def expected_cron(before):
    guard(str(ROOT / 'plugins/FamilyHub/cli/account-mail.php').encode() not in before and
          str(ROOT / 'plugins/FamilyHub/cli/delivery.php').encode() not in before and
          b'jivie-production-account-mail' not in before and
          b'jivie-production-delivery' not in before, 'mail_worker_already_exists')
    lines = []
    for name, script in [('account-mail', 'account-mail'), ('delivery', 'delivery')]:
        lines.append('* * * * * /usr/bin/flock -n '
                     f'{BASE}/logs/{name}.lock {PHP} '
                     f'{ROOT}/plugins/FamilyHub/cli/{script}.php --limit=20 '
                     f'>> {BASE}/logs/{name}.log 2>&1 '
                     f'# jivie-production-{name}\n')
    return before + (b'\n' if before and not before.endswith(b'\n') else b'') + ''.join(lines).encode()


def run(mode):
    os.umask(0o077)
    for path in [BASE.parent, BASE, BASE / 'install', BASE / 'logs']:
        private(path, True)
    private(FEATURE)
    guard(ROOT.resolve() == ROOT and ROOT.is_dir() and
          (ROOT / 'vendor/autoload.php').is_file(), 'production_root_guard')
    guard(mode in ['check', 'prepare', 'activate'], 'unknown_mode')

    if STATE.exists():
        private(WORK, True)
        private(STATE)
        state = json.loads(STATE.read_bytes())
        for path, field in [(SMTP, 'smtpSha'), (KEY, 'keySha')]:
            private(path)
            guard(digest(path.read_bytes()) == state[field], 'prepared_file_changed')
        private(PASSWORD)
        current = FEATURE.read_bytes()
        if state['phase'] == 'active':
            guard(digest(current) == state['candidateSha'], 'active_feature_changed')
            guard(digest(crontab()) == state['afterCronSha'], 'active_cron_changed')
            print(json.dumps(dict(phase='active', sender='admin@jivie.triparna.si')))
            return
        guard(state['phase'] == 'prepared' and digest(current) == EXPECTED,
              'feature_or_state_changed')
        private(CANDIDATE)
        guard(digest(CANDIDATE.read_bytes()) == state['candidateSha'], 'candidate_changed')
        if mode != 'activate':
            print(json.dumps(dict(phase='prepared', smtpActive=False,
                                  passwordPresent=PASSWORD.stat().st_size > 0)))
            return
        stamp = password_stamp()
        private(AUTH)
        proof = json.loads(AUTH.read_bytes())
        guard(proof.get('authenticated') is True and proof.get('verifiedTls') is True
              and proof.get('passwordStamp') == stamp
              and proof.get('smtpSha') == state['smtpSha'], 'fresh_auth_proof_required')
        before = crontab()
        guard(digest(before) == state['beforeCronSha'], 'crontab_changed_since_prepare')
        after = expected_cron(before)
        cron_candidate = WORK / 'crontab.candidate'
        write_new(cron_candidate, after)
        for name in ['account-mail', 'delivery']:
            log = BASE / 'logs' / (name + '.log')
            guard(not log.exists(), 'new_log_already_exists')
            write_new(log, b'')
        subprocess.run(['crontab', str(cron_candidate)], check=True, capture_output=True)
        guard(crontab() == after, 'installed_cron_mismatch_manual_review_required')
        # Workers are installed while SMTP is still off; activation is atomic.
        os.replace(CANDIDATE, FEATURE)
        private(FEATURE)
        state.update(phase='active', afterCronSha=digest(after))
        new_state = WORK / 'state.active.json'
        write_new(new_state, (json.dumps(state, indent=2) + '\n').encode())
        os.replace(new_state, STATE)
        print(json.dumps(dict(phase='active', sender='admin@jivie.triparna.si',
                              cronPreserved=True, mailWorkersAdded=2,
                              noMessagesSent=True)))
        return

    guard(mode != 'activate', 'prepare_required')
    current = FEATURE.read_bytes()
    guard(digest(current) == EXPECTED, 'production_feature_requires_review')
    for path in [WORK, KEY, SMTP, PASSWORD]:
        guard(not path.exists() and not path.is_symlink(), 'unowned_destination_exists')
    private(BASE / 'config.php')
    before_cron = crontab()
    expected_cron(before_cron)
    if mode == 'check':
        print(json.dumps(dict(phase='checked', featureMatches=True,
                              smtpActive=False, noChanges=True)))
        return
    WORK.mkdir(mode=0o700)
    private(WORK, True)
    write_new(WORK / 'familyhub-config.before.php', current)
    write_new(WORK / 'config.before.php', (BASE / 'config.php').read_bytes())
    write_new(WORK / 'crontab.before', before_cron)
    write_new(PASSWORD, b'')
    key = base64.b64encode(secrets.token_bytes(32)) + b'\n'
    write_new(KEY, key)
    smtp = ("<?php\n// Production only. Password and encryption key stay private.\n"
            "define('FAMILYHUB_SMTP_HOST', 'cp-21.controlpanel.si');\n"
            "define('FAMILYHUB_SMTP_PORT', 465);\n"
            "define('FAMILYHUB_SMTP_ENCRYPTION', 'ssl');\n"
            "define('FAMILYHUB_SMTP_FROM', 'admin@jivie.triparna.si');\n"
            "define('FAMILYHUB_SMTP_USERNAME', 'admin@jivie.triparna.si');\n"
            f"define('FAMILYHUB_SMTP_PASSWORD', rtrim(file_get_contents('{PASSWORD}'), \"\\r\\n\"));\n"
            f"define('FAMILYHUB_ACCOUNT_MAIL_KEY_BASE64', trim(file_get_contents('{KEY}')));\n"
            "define('FAMILYHUB_PUBLIC_URL', 'https://jivie.triparna.si/');\n").encode()
    write_new(SMTP, smtp)
    candidate = current + f"\nrequire '{SMTP}';\n".encode()
    write_new(CANDIDATE, candidate)
    for path in [SMTP, CANDIDATE]:
        subprocess.run([PHP, '-l', str(path)], check=True, capture_output=True)
    state = dict(phase='prepared', smtpSha=digest(smtp), keySha=digest(key),
                 candidateSha=digest(candidate), beforeCronSha=digest(before_cron))
    write_new(STATE, (json.dumps(state, indent=2) + '\n').encode())
    print(json.dumps(dict(phase='prepared', backupVerified=
                         (WORK / 'familyhub-config.before.php').read_bytes() == current
                         and (WORK / 'config.before.php').read_bytes() == (BASE / 'config.php').read_bytes()
                         and (WORK / 'crontab.before').read_bytes() == before_cron,
                         privateModesVerified=True, smtpActive=False,
                         passwordPresent=False, noMessagesSent=True)))


if __name__ == '__main__':
    try:
        guard(len(sys.argv) == 2, 'usage_check_prepare_activate')
        run(sys.argv[1])
    except Exception as error:
        # Suppress subprocess output and arbitrary exception details: no secrets.
        code = str(error) if type(error) is RuntimeError else 'setup_failed'
        print(json.dumps(dict(ok=False, error=code)), file=sys.stderr)
        sys.exit(1)
