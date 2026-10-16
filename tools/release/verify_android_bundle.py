#!/usr/bin/env python3
"""Local artifact checks; never print client keys or signing properties."""
import hashlib
import json
import re
import shutil
import struct
import subprocess
import zipfile
from pathlib import Path
import xml.etree.ElementTree as ET

import argparse
parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path, required=True)
parser.add_argument('--qa', type=Path, required=True)
parser.add_argument('--artifact', type=Path, required=True)
parser.add_argument('--previous', type=Path, required=True)
args = parser.parse_args()
ROOT, QA, ARTIFACT, PREVIOUS = args.source.resolve(), args.qa.resolve(), args.artifact.resolve(), args.previous.resolve()
JAVA = Path('/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin')
BUNDLETOOL = Path('/Users/anzenovsak/Git/kanban/build/qa/garden-release/bundletool-all-1.18.3.jar')

def run(*args):
    result = subprocess.run([str(a) for a in args], capture_output=True, text=True)
    if result.returncode:
        # Arguments and tool output need not be included in any raised error.
        raise RuntimeError('Artifact verification tool failed')
    return result.stdout + result.stderr

def bundle(*args):
    return run(JAVA / 'java', '-jar', BUNDLETOOL, *args, f'--bundle={ARTIFACT}')

source_manifest = json.loads((QA / 'source-input-manifest.json').read_text())
for row in source_manifest['files']:
    assert hashlib.sha256((ROOT / row['path']).read_bytes()).hexdigest() == row['sha256'], 'Frozen source file changed: ' + row['path']
for path, expected in source_manifest['configurationHashes'].items():
    assert hashlib.sha256((ROOT / path).read_bytes()).hexdigest() == expected, 'Frozen private configuration changed'
assert not ARTIFACT.exists(), 'Never replace a release artifact'
shutil.copy2(ROOT / 'build/app/outputs/bundle/release/app-release.aab', ARTIFACT)
sha = hashlib.sha256(ARTIFACT.read_bytes()).hexdigest()
ARTIFACT.with_suffix('.aab.sha256').write_text(f'{sha}  {ARTIFACT.name}\n')
manifest = bundle('dump', 'manifest')
(QA / 'android-release-manifest.xml').write_text(manifest)
config_raw = bundle('dump', 'config')
(QA / 'android-release-bundle-config.json').write_text(config_raw)
config = json.loads(config_raw)
assert config['optimizations']['uncompressNativeLibraries']['alignment'] == 'PAGE_ALIGNMENT_16K'
validation = bundle('validate')
(QA / 'android-release-bundle-validation.txt').write_text(validation)
signature = run(JAVA / 'jarsigner', '-verify', ARTIFACT)
assert 'jar verified.' in signature
(QA / 'android-release-signature-verify.txt').write_text(signature)
cert = run(JAVA / 'keytool', '-printcert', '-jarfile', ARTIFACT)
previous_cert = run(JAVA / 'keytool', '-printcert', '-jarfile', PREVIOUS)
fingerprint = re.search(r'SHA256:\s*(\S+)', cert).group(1)
assert fingerprint == re.search(r'SHA256:\s*(\S+)', previous_cert).group(1)
(QA / 'android-release-upload-certificate.txt').write_text(cert)

tree = ET.fromstring(manifest)
android = '{http://schemas.android.com/apk/res/android}'
assert tree.attrib['package'] == 'si.triparna.jivie'
assert tree.attrib[android + 'versionCode'] == '30'
assert tree.attrib[android + 'versionName'] == '1.10.0'
assert tree.find('application').attrib.get(android + 'debuggable', 'false') == 'false'
assert tree.find('application').attrib[android + 'enableOnBackInvokedCallback'] == 'true'
uses_sdk = tree.find('uses-sdk')
assert uses_sdk.attrib[android + 'minSdkVersion'] == '24'
assert uses_sdk.attrib[android + 'targetSdkVersion'] == '36'

# Verify the native public client identity against the already submitted AAB29.
# No client-config, signing-properties, keystore or credential file is opened.
def previous_bundle(*args):
    return run(JAVA / 'java', '-jar', BUNDLETOOL, *args, f'--bundle={PREVIOUS}')

previous_tree = ET.fromstring(previous_bundle('dump', 'manifest'))
permissions = sorted(node.attrib[android + 'name'] for node in tree.findall('uses-permission'))
previous_permissions = sorted(node.attrib[android + 'name'] for node in previous_tree.findall('uses-permission'))
removed_permissions = sorted(set(previous_permissions) - set(permissions))
added_permissions = sorted(set(permissions) - set(previous_permissions))
expected_removed = []
assert removed_permissions == expected_removed and not added_permissions, 'Unexpected permission difference from AAB29'
assert len(permissions) == 8, 'Other eight permissions must remain'
assert 'com.crazecoder.openfile' not in manifest, 'Old openfile FileProvider remains'
share = [node for node in tree.find('application').findall('provider') if node.attrib.get(android + 'name') == 'dev.fluttercommunity.plus.share.ShareFileProvider']
assert len(share) == 1
assert share[0].attrib[android + 'authorities'] == 'si.triparna.jivie.flutter.share_provider'
assert share[0].attrib[android + 'exported'] == 'false' and share[0].attrib[android + 'grantUriPermissions'] == 'true'
run('python3', ROOT / 'tools/release/check_android_permissions.py', QA / 'android-release-manifest.xml')
(QA / 'android-release-permission-diff.json').write_text(json.dumps({'previousVersionCode': 29, 'removed': removed_permissions, 'added': added_permissions, 'preserved': permissions, 'oldOpenfileProviderAbsent': True, 'sharePlusFileProviderPreserved': True}, indent=2) + '\n')
(QA / 'android-release-permissions.json').write_text(json.dumps(permissions, indent=2) + '\n')

project_resource = bundle('dump', 'resources', '--resource=string/project_id', '--values')
assert 'jivie-e928a' in project_resource
assert project_resource == previous_bundle('dump', 'resources', '--resource=string/project_id', '--values')
(QA / 'android-release-firebase-project.txt').write_text(project_resource)
for resource_name in ('google_app_id', 'gcm_defaultSenderId'):
    current = bundle('dump', 'resources', f'--resource=string/{resource_name}', '--values')
    assert current == previous_bundle('dump', 'resources', f'--resource=string/{resource_name}', '--values')

native = []
with zipfile.ZipFile(ARTIFACT) as archive:
    assert archive.testzip() is None
    with zipfile.ZipFile(PREVIOUS) as previous_archive:
        for name in archive.namelist():
            if name.endswith('/libflutter.so'):
                assert hashlib.sha256(archive.read(name)).digest() == hashlib.sha256(previous_archive.read(name)).digest(), 'Flutter engine differs from submitted AAB29'
    assert not any('.firebase' in n or n.endswith('/client.json') for n in archive.namelist())
    # Inspect archive names and bytes without exposing file content or credentials.
    forbidden_names = re.compile(r'(?:service[-_]?account|jivie-key\.properties|\.(?:p8|jks|keystore)$)', re.I)
    private_pem = re.compile(rb'-----BEGIN (?:RSA |EC |ENCRYPTED )?PRIVATE KEY-----[\r\n]+[A-Za-z0-9+/=\r\n]{64,}-----END (?:RSA |EC |ENCRYPTED )?PRIVATE KEY-----')
    account_type = re.compile(rb'"type"\s*:\s*"service_account"')
    account_key = re.compile(rb'"private_key"\s*:\s*"-----BEGIN ')
    for member in archive.infolist():
        assert not forbidden_names.search(member.filename), 'Private configuration filename found'
        contents = archive.read(member)
        assert not private_pem.search(contents), 'Private key material found'
        assert not account_type.search(contents), 'Service-account credential found'
        assert not account_key.search(contents), 'Service-account private key found'
    for name in archive.namelist():
        if not name.endswith('.so') or '/lib/' not in name:
            continue
        data = archive.read(name)
        assert data[:4] == b'\x7fELF'
        if name.endswith('/libapp.so'):
            assert b'jivie-e928a' in data, 'Dart AOT Firebase project literal absent'
        elf64 = data[4] == 2
        little = data[5] == 1
        byteorder = '<' if little else '>'
        if not elf64:
            native.append({'path': name, 'elfBits': 32, 'required64BitAlignment': False})
            continue
        header = struct.unpack_from(byteorder + 'HHIQQQIHHHHHH', data, 16)
        phoff, phentsize, phnum = header[4], header[8], header[9]
        load_alignments = []
        for index in range(phnum):
            ph = struct.unpack_from(byteorder + 'IIQQQQQQ', data, phoff + index * phentsize)
            if ph[0] != 1:
                continue
            offset, address, alignment = ph[2], ph[3], ph[7]
            assert alignment >= 16384 and offset % 16384 == address % 16384
            load_alignments.append(alignment)
        assert load_alignments
        native.append({'path': name, 'elfBits': 64, 'loadSegmentAlignments': load_alignments,
            'verified16KiB': True})
    abi_set = {row['path'].split('/')[2] for row in native}
    assert abi_set == {'arm64-v8a', 'armeabi-v7a', 'x86_64'}
    verified64 = sum(row['elfBits'] == 64 for row in native)
    assert verified64 == 8
(QA / 'android-release-native-alignment.json').write_text(json.dumps(native, indent=2) + '\n')
evidence = {
    'artifact': str(ARTIFACT), 'sourceBaseCommit': source_manifest['baseCommit'],
    'sourceState': 'frozen release source; see source-input-manifest.json',
    'sourceInputManifest': str(QA / 'source-input-manifest.json'),
    'sourceInputAggregateSha256': source_manifest['aggregateSha256'],
    'sourceFreezeVerified': True,
    'sha256': sha, 'bytes': ARTIFACT.stat().st_size,
    'package': 'si.triparna.jivie', 'versionName': '1.10.0', 'versionCode': 30,
    'minSdk': 24, 'targetSdk': 36, 'signed': True,
    'permissions': permissions, 'permissionDiffComparedToPreviousAab29': True, 'removedPermissions': removed_permissions, 'addedPermissions': added_permissions, 'oldOpenfileProviderAbsent': True, 'sharePlusFileProviderPreserved': True,
    'flutterEngineByteIdenticalToPreviousAab29': True, 'existingDedicatedUploadCertificateMatched': True, 'certificateSha256': fingerprint,
    'bundleValidation': True, 'zipCrcValid': True, 'native64BitLibraries16kbVerified': verified64,
    'nativeAbis': sorted(abi_set), 'bundleNativeAlignment': 'PAGE_ALIGNMENT_16K',
    'nativeFirebaseResourcesPresent': True, 'nativeFirebaseClientIdentityMatched': True,
    'firebaseResourceIdentityComparedToPreviousAab29': True,
    'androidBackInvokedCallbackEnabled': True,
    'dartAotFirebaseProjectLiteralPresentInAllAbis': True,
    'privateSigningOrServiceAccountArtifactsAbsent': True, 'privateKeyMaterialAbsent': True,
    'firebaseClientJsonBundledAsAsset': False, 'firebaseProject': 'jivie-e928a',
    'physicalDefaultSoundUpdateVerified': False, 'storeUploadPerformed': False,
    'internalInactiveVerified': False, 'publicSubmittedVerified': False,
}
(QA / 'android-release-artifact-evidence.json').write_text(json.dumps(evidence, indent=2) + '\n')
ARTIFACT.chmod(0o444)
ARTIFACT.with_suffix('.aab.sha256').chmod(0o444)
print(json.dumps({'artifact':str(ARTIFACT),'sha256':sha,'bytes':ARTIFACT.stat().st_size,'bundleValidation':True,'sameCertificate':True,'permissions':len(permissions),'native64BitLibraries16kbVerified':verified64}))
