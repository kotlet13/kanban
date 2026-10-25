#!/usr/bin/env python3
"""One approved r7 -> r8 QA diagnostics-only update; no application launch."""
import argparse,difflib,importlib.util,json,shutil,subprocess,re
from pathlib import Path
spec=importlib.util.spec_from_file_location('measured',Path(__file__).with_name('sync_measured_macos_update.py'))
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
qa=m.qa
PREVIOUS=m.NEW
NEW=qa.ROOT/'build/qa/sync-diagnostics-reliable-20261024'

def once(text,old,new):return m.once(text,old,new)

def tagged_calls(text,prefix):
    pattern=re.compile(r"(?:access\.account\.directory\.call|account\.directory\.call|_scopeCall|call)\(\s*'(crypto2\.(?:directory\.status|scope\.headGet|account\.status))'")
    changes=[]
    for match in pattern.finditer(text):
        start=match.start();opening=text.index('(',start);depth=1;quote=None;escape=False;end=opening+1
        while depth:
            c=text[end]
            if quote:
                if escape:escape=False
                elif c=='\\':escape=True
                elif c==quote:quote=None
            elif c in "'\"":quote=c
            elif c=='(':depth+=1
            elif c==')':depth-=1
            end+=1
        op=match.group(1).split('.')[-1]
        line=text.count('\n',0,start)+1
        site=f'{prefix}.{op}.site{line}'
        changes.append((start,end,"qaReliableTagged('"+site+"', () => "+text[start:end]+')'))
    for start,end,value in reversed(changes):text=text[:start]+value+text[end:]
    return text

def stage(letter):
    qa.PUBLIC=PREVIOUS
    source,previous,_=qa.load(letter)
    if previous.get('revision')!=7:raise RuntimeError('Requires exact measured r7')
    evidence=NEW/letter
    if evidence.exists():raise RuntimeError('Reliable stage already attempted')
    if any(qa.digest(qa.ROOT/r['path'])!=r['sha256'] for r in previous['original']):raise RuntimeError('Repository runtime changed; new review needed')
    updates={}
    rel='lib/organizer/data/qa_measured_diagnostics.dart'
    updates[rel]=(qa.ROOT/'tools/diagnostics/qa_reliable_diagnostics.dart').read_text()
    rel='lib/organizer/data/account_work_coordinator.dart'
    updates[rel]=(source/rel).read_text()+'''
Map<String,Object> qaReliableWorkContext() {
  final job=Zone.current[AccountWorkCoordinator._jobZone] as _Job?;
  return {'kind':job?.kind.name ?? 'unspecified','job':job?.ordinal ?? 0};
}
'''
    rel='lib/organizer/data/collaboration_transport.dart'
    text=(source/rel).read_text().replace("import 'package:flutter/services.dart' show MethodChannel;\n",'')
    text="import 'qa_measured_diagnostics.dart';\nimport 'account_work_coordinator.dart' show qaReliableWorkContext;\n"+text
    text=once(text,"    final encoded = jsonEncode({'v': 1, 'op': operation, 'params': params});", "    final qaFrames=qaReliableFrames(StackTrace.current);\n    final qaWork=qaReliableWorkContext();\n    final qaSite=qaReliableSite();\n    final encoded = jsonEncode({'v': 1, 'op': operation, 'params': params});")
    text=once(text,'          onAttempt?.call(operation);','          qaReliableRequest(operation,qaFrames,qaWork,qaSite);\n          onAttempt?.call(operation);')
    begin=text.index("  unawaited(const MethodChannel('jivie/qa_sync_redesign').invokeMethod<void>('trace',")
    end=text.index('\n}',begin)
    text=text[:begin]+"  qaReliableError(phase,code,frames);"+text[end:]
    updates[rel]=text
    rel='lib/organizer/data/collaboration_repository.dart'
    updates[rel]="import 'qa_measured_diagnostics.dart' show qaReliableCompletion;\n"+(source/rel).read_text()
    rel='lib/organizer/data/collaboration_sync_actions.dart'
    text=(source/rel).read_text()
    assert text.count('_syncCompletions.add(lastSyncCompletion!);')==2
    updates[rel]=text.replace('_syncCompletions.add(lastSyncCompletion!);','qaReliableCompletion(lastSyncCompletion!);\n            _syncCompletions.add(lastSyncCompletion!);')
    for rel,prefix in [('lib/organizer/data/e2ee/session_crypto_access.dart','session'),('lib/organizer/data/e2ee/crypto_scoped_authority.dart','scopedAuthority'),('lib/organizer/data/e2ee/account_directory_repository.dart','directory'),('lib/organizer/data/e2ee/scope_crypto_manager.dart','scopeManager')]:
        updates[rel]="import '../qa_measured_diagnostics.dart' show qaReliableTagged;\n"+tagged_calls((source/rel).read_text(),prefix)
    rel='macos/Runner/MainFlutterWindow.swift'
    text=(source/rel).read_text()
    text=once(text,'    let flutterViewController = FlutterViewController()', '''    let qaRoot=URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      .appendingPathComponent("JivieSyncReliableQA-v1", isDirectory: true)
      .appendingPathComponent(expectedBundle, isDirectory: true)
    let qaSink=QAReliableSink(root:qaRoot,app:expectedBundle.contains("synca20261024") ? "A" : "B")
    let flutterViewController = FlutterViewController()''')
    start=text.index('    let qaChannel = FlutterMethodChannel')
    end=text.index('    let vaultChannel',start)
    text=text[:start]+'''    let qaChannel = FlutterMethodChannel(name: "jivie/qa_sync_redesign", binaryMessenger: flutterViewController.engine.binaryMessenger)
    qaChannel.setMethodCallHandler { call,result in
      if call.method == "reliableEvent" { result(qaSink.event(call.arguments)); return }
      if call.method == "ackProof" { qaSink.acknowledge(call.arguments); result(nil); return }
      result(FlutterMethodNotImplemented)
    }

'''+text[end:]
    updates[rel]=text+'\n'+(qa.ROOT/'tools/diagnostics/qa_reliable_sink.swift').read_text()
    rel='lib/organizer/presentation/all_spaces/all_spaces_page.dart'
    text="import '../../data/qa_measured_diagnostics.dart' show qaReliableUi;\n"+(source/rel).read_text()
    updates[rel]=once(text,'  Future<void> _open(AllSpacesRow row) async {','  Future<void> _open(AllSpacesRow row) async {\n    qaReliableUi(\'rowOpenEntered\');')
    rel='lib/organizer/presentation/all_spaces/all_spaces_rows.dart'
    text="import '../../data/qa_measured_diagnostics.dart';\n"+(source/rel).read_text()
    text=once(text,'              onTap: onOpen,',"              onTap: () { qaReliableUi('rowBodyTap'); onOpen(); },")
    text=once(text,'                onPressed: onSource,',"                onPressed: () { qaReliableUi('sourceArrowTap'); onSource(); },")
    start=text.index('bool allSpacesSourceIsCurrent(');end=text.index('Future<void> openAllSpacesRow(',start)
    body=text[start:end]
    for state,label in [('personalState','personal'),('sharedState','shared')]:
        body=body.replace(state+'.isLoading',"qaReliableFail("+state+".isLoading,"+state+".valueOrNull!=null?'"+label+"LoadingRetained':'"+label+"LoadingEmpty')")
        body=body.replace(state+'.hasError',"qaReliableFail("+state+".hasError,'"+label+"Error')")
    body=body.replace('return personal != null &&',"if (personal == null) qaReliableUi('personalMissing');\n  return personal != null &&\n      qaReliablePass(")
    body=body.replace('      );',"      ),'sourceNoLongerCurrent');")
    text=text[:start]+body+text[end:]
    updates[rel]=text
    rel='lib/organizer/presentation/inbox/visible_task_target_view.dart'
    text="import '../../data/qa_measured_diagnostics.dart';\n"+(source/rel).read_text()
    text=once(text,') async {\n  if (!await activateLocalNotificationTarget',") async {\n  qaReliableUi('visibleTaskEntered');\n  if (!await activateLocalNotificationTarget")
    text=once(text,'!await activateLocalNotificationTarget(context, ref, target)',"!qaReliablePass(await activateLocalNotificationTarget(context, ref, target),'activateLocalTargetFailed')")
    text=once(text,'!context.mounted ||',"!qaReliablePass(context.mounted,'unmounted') ||")
    text=text.replace('isCurrent?.call() == false',"qaReliableFail(isCurrent?.call() == false,'sourceChanged')")
    for before,after in [("_openingTasks[navigator] == true","qaReliableFail(_openingTasks[navigator] == true,'openingAlready')"),("target.records.length != 1","qaReliableFail(target.records.length != 1,'recordCountInvalid')"),("target.records.single.type != 'task'","qaReliableFail(target.records.single.type != 'task','recordTypeInvalid')"),("target.inboxIds.isNotEmpty","qaReliableFail(target.inboxIds.isNotEmpty,'inboxPresent')"),("!_taskIsVisible(ref, target)","!qaReliablePass(_taskIsVisible(ref, target),'taskNotVisible')")]:text=once(text,before,after)
    text=once(text,'  try {\n    await showDialog<void>(',"  try {\n    qaReliableUi('previewWillShow');\n    await showDialog<void>(")
    text=once(text,'    _openingTasks[navigator] = false;',"    qaReliableUi('previewClosed');\n    _openingTasks[navigator] = false;")
    start=text.index('bool _taskIsVisible(');end=text.index('class _VisibleTaskContent',start)
    body=text[start:end]
    for state,label in [('personalState','visiblePersonal'),('sharedState','visibleShared')]:
        body=body.replace(state+'.isLoading',"qaReliableFail("+state+".isLoading,"+state+".valueOrNull!=null?'"+label+"LoadingRetained':'"+label+"LoadingEmpty')")
        body=body.replace(state+'.hasError',"qaReliableFail("+state+".hasError,'"+label+"Error')")
    body=body.replace('if (personal == null)',"if (!qaReliablePass(personal != null,'visiblePersonalMissing'))")
    # Keep promotion: the diagnostic helper does not promote nullable variables.
    body=body.replace("if (!qaReliablePass(personal != null,'visiblePersonalMissing')) return false;", "if (personal == null) { qaReliableUi('visiblePersonalMissing'); return false; }")
    body=body.replace('if (state == null || !_taskScopeAccessible(state, target)) return false;',"if (state == null || !_taskScopeAccessible(state, target)) { qaReliableUi('visibleScopeAccessDenied'); return false; }")
    text=text[:start]+body+text[end:]
    updates[rel]=text
    evidence.mkdir(parents=True)
    qa.write(evidence/'previous-source-plan.json',previous)
    qa.write(evidence/'stage-started.json',{'fromRevision':7,'toRevision':8,'budget':'reliable diagnostics; old STOP3 retained'})
    diffs=[]
    for rel,value in updates.items():
        path=source/rel;archive=evidence/'prior-source'/rel;archive.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(path,archive)
        path.write_text(value)
        upstream=(qa.ROOT/rel).read_text() if (qa.ROOT/rel).exists() else ''
        diffs.extend(difflib.unified_diff(upstream.splitlines(True),value.splitlines(True),fromfile='repo/'+rel,tofile='qa/'+rel))
    plan={**previous,'revision':8,'reliableDiagnostics':True,'frozen':[{'path':r['path'],'sha256':qa.digest(source/r['path'])} for r in previous['frozen']]}
    qa.write(evidence/'source-plan.json',plan);qa.write(evidence/'update.json',{'overlays':list(updates),'dataReset':False})
    (evidence/'overlay.diff').write_text(''.join(diffs))
    print('Reliable QA r8 staged '+letter.upper()+'; no build/install/launch')

def install(letter):
    qa.PUBLIC=NEW;source,plan,evidence=qa.load(letter)
    if plan.get('revision')!=8 or not plan.get('reliableDiagnostics'):raise RuntimeError('Requires reliable revision8')
    artifact=json.loads((evidence/'artifact.json').read_text());target=Path(plan['target'])
    lines=subprocess.check_output(['ps','-axo','pid=,command='],text=True).splitlines()
    if any(x.strip().split(maxsplit=1)[-1].startswith(str(target)+'/Contents/MacOS/') for x in lines):raise RuntimeError('Operator must quit QA app normally')
    old=evidence/'previous-r7.app'
    if old.exists() or (evidence/'installed.json').exists():raise RuntimeError('Install already attempted')
    target.rename(old)
    try:
        qa.run(['ditto',artifact['product'],str(target)],source);qa.run(['codesign','--verify','--deep','--strict',str(target)],source)
    except Exception:
        if target.exists():shutil.rmtree(target)
        old.rename(target);raise
    qa.write(evidence/'installed.json',{'target':str(target),'revision':8,'previousPackage':str(old),'dataReset':False,'launched':False})
    print('Reliable QA r8 installed '+letter.upper()+'; not launched')

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('action',choices=['stage','build','install']);parser.add_argument('variant',choices=['a','b']);args=parser.parse_args()
    if args.action=='stage':stage(args.variant)
    else:
        qa.PUBLIC=NEW
        {'build':qa.build,'install':install}[args.action](args.variant)
