#!/usr/bin/env python3
"""Explicit manual-session-only bounded metadata capture. No URLs, bodies, headers or identities."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import time

import mobile_server_upgrade_20261024 as host

MAX_BYTES = 262144
LOG = '/tmp/jivie-mobile-safe-http-20261024.log'


def guard():
    result = json.loads((host.PUBLIC / 'upgrade-result.json').read_text())
    if result.get('ready') is not True: raise RuntimeError('Reviewed mobile target is not ready')
    owned = host.owned()
    if not owned['gateway']['running']: raise RuntimeError('Owned gateway is not running')
    original = (host.LIVE / 'gateway-tls.conf').read_bytes()
    if original != (host.PRIVATE / 'server-before/gateway-tls.conf').read_bytes() or original.count(b'  access_log off;') != 1:
        raise RuntimeError('Unexpected retained gateway logging configuration')
    return owned, original


def capture(seconds):
    before, original = guard()
    name = host.NAMES['gateway']
    config = host.LIVE / 'gateway-tls.conf'
    patched = original.replace(b'  access_log off;', b"  log_format qa_metadata '$time_iso8601 $request_method $status $request_time $body_bytes_sent';\n  access_log " + LOG.encode() + b' qa_metadata;')
    def write(data):
        with config.open('wb') as file:
            file.write(data); file.flush(); os.fsync(file.fileno())
        for _ in range(20):
            if host.run(['docker', 'exec', name, 'cat', '/gateway.conf']) == data: return
            time.sleep(0.1)
        raise RuntimeError('Gateway source bind did not converge')
    signal.signal(signal.SIGTERM, lambda *_: (_ for _ in ()).throw(KeyboardInterrupt()))
    signal.signal(signal.SIGINT, lambda *_: (_ for _ in ()).throw(KeyboardInterrupt()))
    stop_reason = 'deadline'
    started = time.monotonic()
    try:
        host.run(['docker', 'exec', name, 'sh', '-c', ': > ' + LOG])
        write(patched)
        host.run(['docker', 'exec', name, 'nginx', '-c', '/gateway.conf', '-t'])
        host.run(['docker', 'exec', name, 'nginx', '-c', '/gateway.conf', '-s', 'reload'])
        while time.monotonic() - started < seconds:
            size = int(host.run(['docker', 'exec', name, 'stat', '-c', '%s', LOG]).decode())
            if size >= MAX_BYTES:
                stop_reason = 'byte-cap'
                break
            time.sleep(min(1, max(0, seconds - (time.monotonic() - started))))
    finally:
        write(original)
        host.run(['docker', 'exec', name, 'nginx', '-c', '/gateway.conf', '-t'])
        host.run(['docker', 'exec', name, 'nginx', '-c', '/gateway.conf', '-s', 'reload'])
    raw = host.run(['docker', 'exec', name, 'cat', LOG])
    lines = raw[:MAX_BYTES].decode('ascii', errors='strict').splitlines()
    if len(raw) > MAX_BYTES and lines: lines.pop()  # Only complete bounded lines.
    pattern = re.compile(r'\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d[+-]\d\d:\d\d [A-Z]+ \d{3} \d+\.\d+ \d+')
    if any(not pattern.fullmatch(line) for line in lines): raise RuntimeError('Unexpected metadata; raw output withheld')
    after = host.owned()
    if before != after or config.read_bytes() != original: raise RuntimeError('Capture did not restore the original gateway state')
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    folder = host.PUBLIC / 'manual-captures' / stamp
    folder.mkdir(mode=0o700, parents=True)
    (folder / 'http-metadata.log').write_text('\n'.join(lines) + '\n')
    host.save(folder / 'result.json', {'status': 'captured', 'elapsedSeconds': round(time.monotonic() - started, 3),
        'stopReason': stop_reason, 'lines': len(lines), 'savedBytes': sum(len(line) + 1 for line in lines),
        'configurationRestored': True, 'serviceIdentityStartStateUnchanged': True,
        'fields': ['time', 'method', 'status', 'duration', 'responseBytes'], 'businessRequestsByAgent': 0})
    print(json.dumps({'capture': str(folder), 'lines': len(lines), 'configurationRestored': True}))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['prepare', 'capture'])
    parser.add_argument('--user-manual-session-active', action='store_true')
    parser.add_argument('--seconds', type=int, default=120)
    args = parser.parse_args()
    os.umask(0o077)
    if args.action == 'prepare':
        _, original = guard()
        ready = {'prepared': True, 'captureStarted': False, 'secondsMaximum': 180, 'savedBytesMaximum': MAX_BYTES,
                 'requiresExplicitActiveUserSessionFlag': True, 'gatewayConfigSha256': hashlib.sha256(original).hexdigest(),
                 'fields': ['time', 'method', 'status', 'duration', 'responseBytes'],
                 'excludes': ['requestURI', 'requestBody', 'headers', 'tokens', 'keys', 'accountIds', 'plaintextContent']}
        host.save(host.PUBLIC / 'diagnostics-ready.json', ready)
        print(json.dumps(ready))
    else:
        if not args.user_manual_session_active or not 1 <= args.seconds <= 180:
            parser.error('Explicit active user manual session and seconds1..180 required')
        capture(args.seconds)


if __name__ == '__main__': main()
