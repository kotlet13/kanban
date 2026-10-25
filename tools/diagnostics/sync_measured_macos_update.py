#!/usr/bin/env python3
"""One separately authorized measured r6 -> r7 update of the same QA A/B apps.

The old updater, budget, and evidence remain unchanged. No app is launched and
no container, credential, Keychain item, server or other QA app is accessed.
"""
import argparse
import difflib
import importlib.util
import json
import shutil
import subprocess
from pathlib import Path

spec = importlib.util.spec_from_file_location('qa', Path(__file__).with_name('sync_redesign_macos.py'))
qa = importlib.util.module_from_spec(spec)
spec.loader.exec_module(qa)
OLD = qa.PUBLIC
NEW = qa.ROOT / 'build/qa/sync-measured-continuation-20261024'


def once(text, old, new):
    if text.count(old) != 1:
        raise RuntimeError('Reviewed QA overlay seam changed')
    return text.replace(old, new, 1)


def stage(letter):
    source, previous, _ = qa.load(letter)
    if previous.get('revision') != 6:
        raise RuntimeError('Measured continuation requires exact previous revision 6')
    evidence = NEW / letter
    if evidence.exists():
        raise RuntimeError('Measured staging already attempted; preserve evidence for review')
    current = qa.paths()
    old = {row['path']: row['sha256'] for row in previous['original']}
    changed = [p for p in current if old.get(p) != qa.digest(qa.ROOT / p)]
    if set(old) - set(current) or any(not p.startswith('lib/') for p in changed):
        raise RuntimeError('Removed/non-lib inputs require separate review')
    if 'lib/main.dart' in changed or qa.digest(qa.CA) != previous['caSha256']:
        raise RuntimeError('QA bootstrap or pinned CA changed')
    original = [{'path': p, 'sha256': qa.digest(qa.ROOT / p)} for p in current]
    updates = {p: (qa.ROOT / p).read_text() for p in changed}

    # Rebase only the existing pinned endpoint client and bounded error bridge
    # onto CURRENT transport, preserving its single-attempt scheduling API.
    rel = 'lib/organizer/data/collaboration_transport.dart'
    prior = (source / rel).read_text()
    client = prior[prior.index('class _RedesignQaClient'):prior.index('class CollaborationApiException')]
    trace = prior[prior.index('int _qaTraceCount = 0;'):].replace(
        ' : error is FormatException ? error.message.toString()', '')
    text = (qa.ROOT / rel).read_text()
    text = "import 'e2ee/crypto_sync_repository.dart' show CryptoAuthorityPending;\nimport 'dart:io' show HttpClient, SecurityContext;\nimport 'package:http/io_client.dart' show IOClient;\nimport 'package:flutter/services.dart' show MethodChannel;\n" + text
    text = once(text, 'class CollaborationApiException', client + 'class CollaborationApiException')
    text = once(text, '_client = client ?? http.Client();', '_client = client ?? _RedesignQaClient();')
    if 'implements CollaborationTransport, CollaborationSingleAttemptTransport' not in text:
        raise RuntimeError('Current single-attempt transport API missing')
    updates[rel] = text + '\n' + trace

    rel = 'lib/organizer/data/collaboration_sync_actions.dart'
    text = (qa.ROOT / rel).read_text()
    text = text.replace('} catch (_) {', "} catch (qaError, qaStack) {\n        qaSyncTrace('sync-caught', qaError, qaStack);")
    text = text.replace('} catch (error) {', "} catch (error, qaStack) {\n        qaSyncTrace('sync-caught', error, qaStack);")
    text = text.replace('on CollaborationException catch (error) {', "on CollaborationException catch (error, qaStack) {\n        qaSyncTrace('sync-api', error, qaStack);")
    updates[rel] = text

    rel = 'lib/organizer/presentation/shared/create_space_dialog.dart'
    updates[rel] = "import '../../data/collaboration_transport.dart' show qaSyncTrace;\n" + (qa.ROOT / rel).read_text().replace('} catch (error) {', "} catch (error, qaStack) {\n      qaSyncTrace('create-space', error, qaStack);")
    rel = 'lib/organizer/data/e2ee/crypto_invitation_autoapproval.dart'
    updates[rel] = once((qa.ROOT / rel).read_text(), '} catch (error) {', "} catch (error, qaStack) {\n        qaSyncTrace('foreground-invitation', error, qaStack);")

    # New optional observer callbacks serialize only explicitly selected safe
    # fields. They cannot affect request scheduling, policy or acknowledgement.
    rel = 'lib/organizer/state/collaboration_provider.dart'
    text = (qa.ROOT / rel).read_text()
    text = "import '../data/account_work_coordinator.dart';\nimport '../data/collaboration_sync_diagnostics.dart';\nimport '../data/qa_measured_diagnostics.dart';\n" + text
    updates[rel] = once(text, '        ownsDatabase: false,', '        ownsDatabase: false,\n        accountWork: AccountWorkCoordinator(clock: clock, onEvent: qaMeasuredWork),\n        syncDiagnostics: CollaborationSyncDiagnostics(onEvent: qaMeasuredSync),')
    updates['lib/organizer/data/qa_measured_diagnostics.dart'] = '''import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'account_work_coordinator.dart';
import 'collaboration_sync_diagnostics.dart';

final _qaClock = Stopwatch()..start();
final _qaRun = DateTime.now().toUtc().toIso8601String();
int _qaWorkEvents = 0, _qaWorkBytes = 0, _qaSyncEvents = 0, _qaSyncBytes = 0;
void _emit(Map<String, Object?> event, {required bool sync}) {
  try {
    final value = jsonEncode({'run':_qaRun, 'ms': _qaClock.elapsedMilliseconds, ...event});
    final size = utf8.encode(value).length;
    if (sync) {
      if (_qaSyncEvents >= 64 || _qaSyncBytes + size > 8192) return;
      _qaSyncEvents++; _qaSyncBytes += size;
    } else {
      if (_qaWorkEvents >= 192 || _qaWorkBytes + size > 24576) return;
      _qaWorkEvents++; _qaWorkBytes += size;
    }
    unawaited(const MethodChannel('jivie/qa_sync_redesign')
      .invokeMethod<void>('event', value).catchError((Object _) {}));
  } catch (_) {}
}
void qaMeasuredWork(AccountWorkEvent e) => _emit({
  'phase':'accountWork', 'event':e.event.name, 'kind':e.kind.name,
  'priority':e.priority.name,
  'op':AccountWorkCoordinator.readOperations.contains(e.operation) ? e.operation : 'mutationOrUnknown',
  'active':e.activeReads, 'pending':e.pendingReads,
  'waitMs':e.queueWait.inMilliseconds,
}, sync:false);
void qaMeasuredSync(CollaborationSyncDiagnostic e) => _emit({
  'phase':'sync', 'event':e.kind.name, 'scopes':e.scopeCount,
  'content':e.contentScopeCount, 'finance':e.financeScopeCount,
  'fallback':e.recoveryFallback?.name,
}, sync:true);
'''
    rel = 'macos/Runner/MainFlutterWindow.swift'
    text = (source / rel).read_text()
    text = once(text, '    var qaCount = 0', '    var qaCount = 0\n    var qaEventCount = 0\n    var qaEventBytes = 0')
    updates[rel] = once(text, '      result(nil)\n    }\n\n    let vaultChannel', '''      if call.method == "event", let value = call.arguments as? String,
         qaEventCount < 256, qaEventBytes + value.utf8.count <= 32768 {
        qaEventCount += 1
        qaEventBytes += value.utf8.count
        NSLog("JIVIE_SYNC_QA_EVENT %@", value)
      }
      result(nil)
    }

    let vaultChannel''')
    rel = 'lib/organizer/presentation/recovery/account_protection_completion.dart'
    text = "import '../../data/collaboration_transport.dart' show qaSyncTrace;\n" + (qa.ROOT / rel).read_text()
    updates[rel] = once(text, 'Future<bool> finishAccountProtection(', '''Future<bool> finishAccountProtection(
  BuildContext context, AccountCryptoV2Workflow account,
) async {
  try { return await _qaFinishAccountProtection(context, account); }
  catch (error, stack) { qaSyncTrace('protection-finish', error, stack); rethrow; }
}

Future<bool> _qaFinishAccountProtection(''')

    evidence.mkdir(parents=True)
    qa.write(evidence / 'previous-source-plan.json', previous)
    qa.write(evidence / 'stage-started.json', {'fromRevision': 6, 'toRevision': 7, 'budget': 'new measured continuation; old STOP3 retained'})
    diffs = []
    for rel, value in updates.items():
        path = source / rel
        if path.exists():
            archive = evidence / 'prior-source' / rel
            archive.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, archive)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(value)
        upstream = (qa.ROOT / rel).read_text() if (qa.ROOT / rel).exists() else ''
        if value != upstream:
            diffs.extend(difflib.unified_diff(upstream.splitlines(True), value.splitlines(True), fromfile='repo/' + rel, tofile='qa/' + rel))
    if any(qa.digest(qa.ROOT / row['path']) != row['sha256'] for row in original):
        raise RuntimeError('Repository inputs changed during stage; preserve partial source')
    frozen = [{'path': p, 'sha256': qa.digest(source / p)} for p in current]
    for p in updates:
        if p not in current:
            frozen.append({'path': p, 'sha256': qa.digest(source / p)})
    plan = {**previous, 'revision': 7, 'original': original, 'frozen': frozen,
            'measuredContinuation': True, 'oldEvidence': str(OLD / letter)}
    qa.write(evidence / 'source-plan.json', plan)
    qa.write(evidence / 'update.json', {'changed': changed, 'overlays': list(updates), 'dataReset': False, 'oldBudgetChanged': False})
    (evidence / 'overlay.diff').write_text(''.join(diffs))
    print('Measured r7 source staged for ' + letter.upper() + '; build/install require separate source GO')


def install(letter):
    qa.PUBLIC = NEW
    source, plan, evidence = qa.load(letter)
    if plan.get('revision') != 7 or not plan.get('measuredContinuation'):
        raise RuntimeError('Not the separately approved measured revision')
    artifact = json.loads((evidence / 'artifact.json').read_text())
    target = Path(plan['target'])
    processes = subprocess.check_output(['ps', '-axo', 'command'], text=True)
    if str(target / 'Contents/MacOS') in processes:
        raise RuntimeError('QA app must be quit normally by its operator')
    old = evidence / 'previous-r6.app'
    if old.exists() or (evidence / 'installed.json').exists():
        raise RuntimeError('Measured installation already attempted')
    target.rename(old)
    try:
        qa.run(['ditto', artifact['product'], str(target)], source)
        qa.run(['codesign', '--verify', '--deep', '--strict', str(target)], source)
    except Exception:
        if target.exists():
            shutil.rmtree(target)
        old.rename(target)
        raise
    qa.write(evidence / 'installed.json', {'target': str(target), 'revision': 7, 'dataReset': False, 'previousPackage': str(old), 'launched': False})
    print('Measured r7 installed under unchanged QA identity ' + letter.upper() + '; not launched')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['stage', 'build', 'install'])
    parser.add_argument('variant', choices=['a', 'b'])
    args = parser.parse_args()
    if args.action == 'stage':
        stage(args.variant)
    else:
        qa.PUBLIC = NEW
        {'build': qa.build, 'install': install}[args.action](args.variant)
