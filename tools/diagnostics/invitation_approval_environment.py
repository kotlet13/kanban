#!/usr/bin/env python3
"""New owner-only local lab. Reuses infrastructure, never existing data or test entrypoints."""
import argparse
import json
import os
from pathlib import Path
import secrets

import invitation_preauthorization_environment as infrastructure

REPO = infrastructure.REPO
ROOT = Path('/tmp/jivie-invitation-approval-lab-20261023')
EVIDENCE = REPO / 'build/qa/local-diagnostics/invitation-approval-20261023/environment'
NAME = 'jivie-invitation-approval-lab-20261023'
PORT = 59780
LABEL_KEY = 'si.triparna.jivie.invitation-approval'
VOLUMES = {suffix: f'{NAME}-{suffix}' for suffix in ('data', 'plugins', 'tls')}
CONTINUATION_EVIDENCE = REPO / 'build/qa/local-diagnostics/invitation-approval-continuation-20261024/environment'
save = infrastructure.save
run = infrastructure.run


def inspect_owned():
    obj = json.loads(run(['docker', 'inspect', NAME]))[0]
    if obj['Config'].get('Labels', {}).get(LABEL_KEY) != '20261023':
        raise RuntimeError('Not the owned approval lab')
    mounts = {m['Destination']: m for m in obj['Mounts']}
    for suffix, dest in [('data', '/var/www/app/data'), ('plugins', '/var/www/app/plugins'), ('tls', '/etc/nginx/ssl')]:
        if mounts[dest].get('Name') != VOLUMES[suffix]:
            raise RuntimeError('Unexpected owned lab volume')
    if obj['HostConfig']['PortBindings'] != {'80/tcp': [{'HostIp': '127.0.0.1', 'HostPort': str(PORT)}]}:
        raise RuntimeError('Exact new loopback binding required')
    return obj


# Every function above/below executes with this lab's distinct names and paths.
# The historical helper main/bootstrap is never called.
for key, value in {'ROOT': ROOT, 'EVIDENCE': EVIDENCE, 'NAME': NAME, 'PORT': PORT,
                   'LABEL': LABEL_KEY + '=20261023', 'VOLUMES': VOLUMES,
                   'inspect_owned': inspect_owned}.items():
    setattr(infrastructure, key, value)


def bootstrap():
    inspect_owned()
    destination = ROOT / 'fixture.json'
    if destination.exists():
        raise RuntimeError('Preserve existing fixture; never bootstrap twice')
    source = infrastructure.BOOTSTRAP.replace('invitepreauth_', 'inviteapproval_')
    source = source.replace("['L1_owner', 'L1_member', 'L2_owner', 'L2_member']", "['owner']")
    source = source.replace('local-invitation-preauthorization-20261023', 'local-invitation-approval-20261023')
    source = source.replace('127.0.0.1:59779', '127.0.0.1:59780')
    script = ROOT / 'bootstrap-private.php'
    script.write_text(source)
    script.chmod(0o600)
    run(['docker', 'cp', str(script), f'{NAME}:/tmp/invitation-approval-bootstrap.php'])
    raw = run(['docker', 'exec', NAME, 'php', '/tmp/invitation-approval-bootstrap.php'])
    (ROOT / 'bootstrap-output-private.json').write_text(raw)
    (ROOT / 'bootstrap-output-private.json').chmod(0o600)
    fixture = json.loads(raw)
    if set(fixture['accounts']) != {'owner'} or fixture['serverUrl'] != f'http://127.0.0.1:{PORT}':
        raise RuntimeError('Only the new owner may exist before Send')
    fixture['serverId'] = fixture['accounts']['owner']['session']['serverId']
    suffix = secrets.token_hex(6)
    fixture['newRecipient'] = {'username': 'inviteapproval_recipient_' + suffix,
                              'password': secrets.token_hex(20),
                              'email': 'inviteapproval_recipient_' + suffix + '@capture.invalid'}
    fixture['clientStateDirs'] = {actor: str(ROOT / actor) for actor in ('owner', 'member')}
    save(destination, fixture)
    for actor in ('owner', 'member'):
        (ROOT / actor).mkdir(mode=0o700, exist_ok=True)
    return {'accountsCreated': 1, 'recipientExistsBeforeSend': False,
            'emailVerification': 'owner request/private captured mailbox/confirm',
            'cryptoStateCreated': False, 'mailDeliveryClaimed': False}


def continuation_status():
    obj = inspect_owned()
    baseline = json.loads((CONTINUATION_EVIDENCE / 'initial-docker-inventory.json').read_text())
    old = {row['Names']: row for row in baseline}
    current = {row['Names']: row for row in infrastructure.inventory()}
    changed = [name for name in sorted(set(old) | set(current)) if name != NAME and
               (name not in old or name not in current or
                any(old[name][field] != current[name][field] for field in ('ID', 'State', 'Image')))]
    result = {'running': obj['State']['Running'], 'otherContainerStateOrImageChanges': changed,
              'ownedVolumes': VOLUMES, 'container': NAME, 'baselineDate': '20261024'}
    save(CONTINUATION_EVIDENCE / 'environment-status.json', result)
    print(json.dumps(result))


def resume_continuation():
    obj = inspect_owned()
    if obj['State']['Running']:
        raise RuntimeError('Preserve the already running environment; do not assume this run owns its start')
    baseline_path = CONTINUATION_EVIDENCE / 'initial-docker-inventory.json'
    if baseline_path.exists():
        raise RuntimeError('Preserve existing continuation environment baseline')
    with __import__('socket').socket() as sock:
        sock.bind(('127.0.0.1', PORT))
    save(baseline_path, infrastructure.inventory())
    ownership = json.loads((EVIDENCE / 'ownership.json').read_text())
    if obj['Image'] != ownership['imageId']:
        raise RuntimeError('Owned lab image changed since the retained STOP3')
    mounts = {mount['Destination']: mount for mount in obj['Mounts']}
    for source, destination in [(REPO / 'server/plugins/FamilyHub', '/var/www/app/plugins/FamilyHub'),
                                (REPO / 'server/tests', '/familyhub-tests')]:
        mount = mounts.get(destination, {})
        if (mount.get('Type') != 'bind' or mount.get('RW') is not False or
                mount.get('Source', '').removeprefix('/host_mnt') != str(source)):
            raise RuntimeError('Exact retained read-only source binds required')
    save(CONTINUATION_EVIDENCE / 'ownership.json', {
        'containerId': obj['Id'], 'imageId': obj['Image'], 'volumes': VOLUMES,
        'serverUrl': f'http://127.0.0.1:{PORT}', 'retainedStoppedState': True,
        'bootstrap': False, 'newAccounts': False, 'sourceCopies': False})
    run(['docker', 'start', NAME])
    result = infrastructure.ready_existing()
    save(CONTINUATION_EVIDENCE / 'readiness.json', result)
    continuation_status()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['up', 'resume-readiness', 'bootstrap', 'refresh-source', 'status', 'stop',
                                         'resume-continuation-20261024', 'continuation-status-20261024', 'stop-continuation-20261024'])
    args = parser.parse_args()
    os.umask(0o077)
    ROOT.mkdir(mode=0o700, exist_ok=True)
    ROOT.chmod(0o700)
    if args.action == 'resume-continuation-20261024': resume_continuation()
    elif args.action == 'continuation-status-20261024': continuation_status()
    elif args.action == 'stop-continuation-20261024':
        inspect_owned()
        run(['docker', 'stop', '--time', '20', NAME])
        continuation_status()
    elif args.action == 'up': infrastructure.phase('server-readiness', infrastructure.up)
    elif args.action == 'resume-readiness': infrastructure.phase('server-readiness', infrastructure.ready_existing)
    elif args.action == 'bootstrap': infrastructure.phase('owner-only-bootstrap', bootstrap)
    elif args.action == 'refresh-source':
        digest = __import__('hashlib').sha256(json.dumps(infrastructure.plugin_source_manifest(), sort_keys=True).encode()).hexdigest()
        infrastructure.phase('source-refresh-' + digest, infrastructure.refresh_source)
    elif args.action == 'status': infrastructure.status()
    else: infrastructure.stop()


if __name__ == '__main__':
    main()
