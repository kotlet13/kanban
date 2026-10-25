#!/usr/bin/env python3
"""Fresh Mac A/B QA identities. No reads or writes of existing app data.

Stage only reviewed sources, then build/install explicitly. The QA transport
can reach only the dedicated loopback server and trusts its specific public CA.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import secrets
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
PUBLIC = ROOT / 'build/qa/sync-redesign-20261024'
PRIVATE = Path.home() / 'Library/Application Support/JivieLocalTest/20261024-sync-redesign'
SDK = Path('/Users/anzenovsak/Dev/flutter')
TEAM = 'CXNM99632B'
CA = PUBLIC / 'server/tls/ca.pem'
INPUTS = ['lib', 'assets', 'macos', 'apple', 'pubspec.yaml', 'pubspec.lock',
          'analysis_options.yaml', 'l10n.yaml', '.metadata', 'ios/Podfile.lock']


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2) + '\n')
    path.chmod(0o600)


def run(args: list[str], cwd: Path, log: Path | None = None) -> str:
    if log:
        with log.open('wb') as output:
            result = subprocess.run(args, cwd=cwd, stdout=output, stderr=subprocess.STDOUT)
        if result.returncode:
            raise RuntimeError(f'{args[0]} failed; see {log}')
        return ''
    return subprocess.check_output(args, cwd=cwd, stderr=subprocess.PIPE, text=True)


def paths() -> list[str]:
    return sorted(set(run(['git', 'ls-files', '--cached', '--others',
        '--exclude-standard', '--', *INPUTS], ROOT).splitlines()))


def stage(letter: str) -> None:
    source = PRIVATE / ('source-' + letter)
    evidence = PUBLIC / letter
    name = 'Jivie Test Sync ' + letter.upper()
    bundle = 'si.triparna.jivie.e2eetest.sync' + letter + '20261024'
    group = TEAM + '.' + bundle
    target = Path.home() / 'Applications' / (name + '.app')
    container = Path.home() / 'Library/Containers' / bundle
    if any(p.exists() or p.is_symlink() for p in (source, target, container, evidence)):
        raise RuntimeError('Fresh QA identity already exists; do not reset it')
    pem = CA.read_text()
    assert pem.count('BEGIN CERTIFICATE') == 1 and 'PRIVATE KEY' not in pem
    source.mkdir(mode=0o700)
    evidence.mkdir(parents=True)
    original = []
    for rel in paths():
        path = ROOT / rel
        if not path.is_file() or path.is_symlink():
            raise RuntimeError('Unexpected source input: ' + rel)
        dest = source / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, dest)
        original.append({'path': rel, 'sha256': digest(path)})

    if any(digest(ROOT / row['path']) != row['sha256'] for row in original):
        raise RuntimeError('Runtime source changed during staging; keep partial source for review')

    def edit(rel: str, before: str, after: str, count: int = 1) -> None:
        path = source / rel
        value = path.read_text()
        if value.count(before) < count:
            raise RuntimeError('QA overlay source changed: ' + rel)
        path.write_text(value.replace(before, after, count))

    edit('lib/organizer/data/local_vault_secure_storage.dart',
         '  mOptions: MacOsOptions(', '  mOptions: MacOsOptions(\n'
         f'    accountName: "{bundle}.secure-storage",\n'
         f'    groupId: "{group}",\n    useDataProtectionKeyChain: true,')
    edit('macos/Runner/Configs/AppInfo.xcconfig', 'PRODUCT_NAME = Jivie',
         'PRODUCT_NAME = ' + name)
    edit('macos/Runner/Configs/AppInfo.xcconfig',
         'PRODUCT_BUNDLE_IDENTIFIER = com.example.kanban',
         f'PRODUCT_BUNDLE_IDENTIFIER = {bundle}\nDEVELOPMENT_TEAM = {TEAM}')
    project = source / 'macos/Runner.xcodeproj/project.pbxproj'
    project.write_text(project.read_text().replace('CODE_SIGN_IDENTITY = "-";',
        'CODE_SIGN_IDENTITY = "Apple Development";').replace(
        'CODE_SIGN_STYLE = Manual;', 'CODE_SIGN_STYLE = Automatic;'))
    info = source / 'macos/Runner/Info.plist'
    value = plistlib.loads(info.read_bytes())
    value.update(CFBundleDisplayName=name, FirebaseMessagingAutoInitEnabled=False,
                 FirebaseAppDelegateProxyEnabled=False, FIREBASE_ANALYTICS_COLLECTION_ENABLED=False)
    value.pop('CFBundleURLTypes', None)
    info.write_bytes(plistlib.dumps(value, sort_keys=False))
    for config in ('Release', 'DebugProfile'):
        entitlement = {'com.apple.application-identifier': group,
            'com.apple.developer.team-identifier': TEAM,
            'com.apple.security.app-sandbox': True,
            'com.apple.security.files.user-selected.read-write': True,
            'com.apple.security.network.client': True,
            'keychain-access-groups': [group]}
        if config == 'DebugProfile':
            entitlement.update({'com.apple.security.cs.allow-jit': True,
                                'com.apple.security.network.server': True})
        (source / f'macos/Runner/{config}.entitlements').write_bytes(plistlib.dumps(entitlement))
    guard = f'''    let expectedBundle = "{bundle}"
    let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    guard Bundle.main.bundleIdentifier == expectedBundle,
          documents?.resolvingSymlinksInPath().standardizedFileURL.path.hasSuffix("/Library/Containers/\\(expectedBundle)/Data/Documents") == true else {{
      fatalError("Isolated sync QA identity failed")
    }}
'''
    edit('macos/Runner/MainFlutterWindow.swift',
         '    let flutterViewController = FlutterViewController()', guard +
         '    let flutterViewController = FlutterViewController()')
    edit('macos/Runner/MainFlutterWindow.swift', '    super.awakeFromNib()',
         '    super.awakeFromNib()\n    self.title = "' + name + '"')
    # No external endpoint is permitted, even if entered manually in this QA app.
    transport = '''
class _RedesignQaClient extends http.BaseClient {
  late final http.Client _client = IOClient(HttpClient(context:
    SecurityContext(withTrustedRoots: false)
      ..setTrustedCertificatesBytes(utf8.encode(r\'''%s\'''))));
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final uri = request.url;
    if (uri.scheme != 'https' || uri.host != '127.0.0.1' ||
        uri.port != 18821 || uri.path != '/index.php') {
      throw StateError('QA endpoint isolation');
    }
    return _client.send(request);
  }
  @override
  void close() => _client.close();
}
''' % pem
    edit('lib/organizer/data/collaboration_transport.dart', "import 'dart:convert';",
         "import 'dart:convert';\nimport 'dart:io' show HttpClient, SecurityContext;\n"
         "import 'package:http/io_client.dart' show IOClient;")
    edit('lib/organizer/data/collaboration_transport.dart',
         "import '../domain/collaboration_models.dart';",
         "import '../domain/collaboration_models.dart';\n" + transport)
    edit('lib/organizer/data/collaboration_transport.dart',
         '_client = client ?? http.Client();', '_client = client ?? _RedesignQaClient();')
    # Bounded QA-only native console bridge. Never records payloads, URLs,
    # tokens, user text or exception messages; the server logs operation timing.
    edit('macos/Runner/MainFlutterWindow.swift',
         '    RegisterGeneratedPlugins(registry: flutterViewController)',
         '''    RegisterGeneratedPlugins(registry: flutterViewController)
    let qaChannel = FlutterMethodChannel(name: "jivie/qa_sync_redesign", binaryMessenger: flutterViewController.engine.binaryMessenger)
    var qaCount = 0
    qaChannel.setMethodCallHandler { call, result in
      if call.method == "trace", let value = call.arguments as? String,
         value.utf8.count <= 8192, qaCount < 128 {
        qaCount += 1
        NSLog("JIVIE_SYNC_QA %@", value)
      }
      result(nil)
    }
''')
    edit('lib/organizer/data/collaboration_transport.dart',
         "import 'dart:async';", "import 'dart:async';\nimport 'package:flutter/services.dart' show MethodChannel;")
    trace = '''
int _qaTraceCount = 0;
void qaSyncTrace(String phase, Object error, StackTrace stack) {
  if (_qaTraceCount++ >= 128) return;
  final candidate = error is CollaborationException ? error.code : error.runtimeType.toString();
  final code = RegExp(r'^[a-zA-Z0-9_]{1,80}$').hasMatch(candidate) ? candidate : 'unclassified';
  final frames = stack.toString().split('\\n').where((line) =>
      line.contains('package:kanban/')).take(10).map((line) =>
      line.length > 400 ? line.substring(0, 400) : line).toList();
  unawaited(const MethodChannel('jivie/qa_sync_redesign').invokeMethod<void>('trace',
      jsonEncode({'phase': phase, 'code': code, 'frames': frames})).catchError((Object _) {}));
}
'''
    transport_path = source / 'lib/organizer/data/collaboration_transport.dart'
    transport_path.write_text(transport_path.read_text() + trace)
    sync_path = source / 'lib/organizer/data/collaboration_sync_actions.dart'
    sync_text = sync_path.read_text()
    sync_text = sync_text.replace('} catch (_) {',
        "} catch (qaError, qaStack) {\n        qaSyncTrace('sync-caught', qaError, qaStack);")
    sync_text = sync_text.replace('} catch (error) {',
        "} catch (error, qaStack) {\n        qaSyncTrace('sync-caught', error, qaStack);")
    sync_text = sync_text.replace('on CollaborationException catch (error) {',
        "on CollaborationException catch (error, qaStack) {\n        qaSyncTrace('sync-api', error, qaStack);")
    sync_path.write_text(sync_text)
    frozen = [{'path': row['path'], 'sha256': digest(source / row['path'])} for row in original]
    write(evidence / 'source-plan.json', {'source': str(source), 'name': name,
        'bundleId': bundle, 'keychainGroup': group, 'keychainService': bundle + '.secure-storage',
        'target': str(target), 'container': str(container), 'original': original,
        'frozen': frozen, 'caSha256': digest(CA), 'oldDataCopied': False})
    credential = PRIVATE / ('account-' + letter + '.json')
    if credential.exists():
        raise RuntimeError('Refuse to replace existing test credentials')
    write(credential, {'username': 'sync_' + letter + '_20261024',
        'email': 'sync-' + letter + '-20261024@jivie.invalid',
        'displayName': 'Sync ' + letter.upper(), 'password': secrets.token_urlsafe(30)})
    print('Fresh QA source staged for ' + letter.upper() + '; no build, launch, or account registration')


def load(letter: str) -> tuple[Path, dict, Path]:
    evidence = PUBLIC / letter
    plan = json.loads((evidence / 'source-plan.json').read_text())
    source = Path(plan['source'])
    for row in plan['frozen']:
        assert digest(source / row['path']) == row['sha256'], row['path']
    return source, plan, evidence


def build(letter: str, *, retry: bool = False) -> None:
    source, plan, evidence = load(letter)
    marker = evidence / 'build-started.json'
    attempt = 1
    if marker.exists():
        if not retry:
            raise RuntimeError('Build already attempted; inspect result before an explicit retry')
        previous = json.loads(marker.read_text())
        attempt = previous.get('attempt', 1) + 1
        if attempt > 3 or (evidence / 'artifact.json').exists():
            raise RuntimeError('Retry budget exhausted or build already succeeded')
        shutil.copyfile(marker, evidence / f'build-attempt{attempt-1}.json')
        shutil.copyfile(evidence / 'build.log', evidence / f'build-attempt{attempt-1}.log')
    if shutil.disk_usage(source).free < 8 * 1024**3:
        raise RuntimeError('Insufficient reserve for isolated native build')
    write(marker, {'sourcePlanSha256': digest(evidence / 'source-plan.json'), 'attempt': attempt})
    lock = digest(source / 'pubspec.lock')
    run([str(SDK / 'bin/flutter'), 'pub', 'get', '--offline'], source, evidence / 'pub-get.log')
    assert digest(source / 'pubspec.lock') == lock, 'Dependency lock changed'
    run([str(SDK / 'bin/flutter'), 'build', 'macos', '--release', '--no-pub'],
        source, evidence / 'build.log')
    product = source / 'build/macos/Build/Products/Release' / (plan['name'] + '.app')
    run(['codesign', '--verify', '--deep', '--strict', str(product)], source)
    info = plistlib.loads((product / 'Contents/Info.plist').read_bytes())
    ent = plistlib.loads(run(['codesign', '-d', '--entitlements', ':-', str(product)], source).encode())
    assert info['CFBundleIdentifier'] == plan['bundleId']
    assert ent['keychain-access-groups'] == [plan['keychainGroup']]
    assert ent['com.apple.security.app-sandbox'] is True
    assert not info.get('CFBundleURLTypes')
    assert not list(product.rglob('GoogleService-Info.plist'))
    load(letter)
    write(evidence / 'artifact.json', {'product': str(product), 'bundleId': plan['bundleId'],
        'executableSha256': digest(product / 'Contents/MacOS' / info['CFBundleExecutable']),
        'aotSha256': digest(product / 'Contents/Frameworks/App.framework/Versions/A/App'),
        'signatureVerified': True, 'installed': False})
    print('Built and verified isolated ' + plan['name'])


def install(letter: str) -> None:
    source, plan, evidence = load(letter)
    artifact = json.loads((evidence / 'artifact.json').read_text())
    target = Path(plan['target'])
    if target.exists() or Path(plan['container']).exists():
        raise RuntimeError('Fresh installation destination already exists; no replacement')
    run(['ditto', artifact['product'], str(target)], source)
    run(['codesign', '--verify', '--deep', '--strict', str(target)], source)
    write(evidence / 'installed.json', {'target': str(target), 'launched': False})
    print('Installed ' + plan['name'] + '; not launched')


if __name__ == '__main__':
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('stage', 'build', 'retry-build', 'install'))
    parser.add_argument('variant', choices=('a', 'b'))
    args = parser.parse_args()
    {'stage': stage, 'build': build, 'retry-build': lambda letter: build(letter, retry=True), 'install': install}[args.action](args.variant)
