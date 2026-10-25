#!/usr/bin/env python3
"""B-only r9 -> r10 measured preview/editor QA update; never launches an app."""
import argparse,difflib,importlib.util,json,shutil,subprocess
from pathlib import Path
spec=importlib.util.spec_from_file_location('old',Path(__file__).with_name('sync_reliable_export_macos_update.py'))
old=importlib.util.module_from_spec(spec);spec.loader.exec_module(old)
qa=old.qa
PREVIOUS=old.NEW
NEW=qa.ROOT/'build/qa/sync-opening-measurement-20261024'
BUNDLE='si.triparna.jivie.e2eetest.syncb20261024'
NAMESPACE='JivieSyncOpeningQA-20261024-v1'

def once(text,before,after):
    if text.count(before)!=1:raise RuntimeError('Reviewed B-only overlay seam changed')
    return text.replace(before,after,1)

def checked():
    source,plan,evidence=qa.load('b')
    if plan['bundleId']!=BUNDLE or Path(plan['target'])!=Path.home()/'Applications/Jivie Test Sync B.app':raise RuntimeError('Unexpected B identity')
    return source,plan,evidence

def stage():
    qa.PUBLIC=PREVIOUS;source,previous,_=checked()
    if previous.get('revision')!=9:raise RuntimeError('Requires exact installed r9 source')
    evidence=NEW/'b'
    if evidence.exists():raise RuntimeError('Opening stage already attempted; preserve evidence')
    current=qa.paths();prior={r['path']:r['sha256'] for r in previous['original']}
    changed=[p for p in current if prior.get(p)!=qa.digest(qa.ROOT/p)]
    if set(prior)-set(current) or any(not p.startswith('lib/') for p in changed):raise RuntimeError('Removed/non-lib changes need separate review')
    if {'lib/main.dart','lib/organizer/data/collaboration_transport.dart'}.intersection(changed):raise RuntimeError('Isolation bootstrap/transport changed')
    if qa.digest(qa.CA)!=previous['caSha256']:raise RuntimeError('Pinned QA CA changed')
    original=[{'path':p,'sha256':qa.digest(qa.ROOT/p)} for p in current]
    updates={p:(qa.ROOT/p).read_text() for p in changed}
    rel='lib/organizer/data/collaboration_sync_actions.dart';text=(qa.ROOT/rel).read_text()
    text=text.replace('} catch (_) {',"} catch (qaError, qaStack) {\n        qaSyncTrace('sync-caught', qaError, qaStack);")
    text=text.replace('} catch (error) {',"} catch (error, qaStack) {\n        qaSyncTrace('sync-caught', error, qaStack);")
    text=text.replace('on CollaborationException catch (error) {',"on CollaborationException catch (error, qaStack) {\n        qaSyncTrace('sync-api', error, qaStack);")
    if text.count('_syncCompletions.add(lastSyncCompletion!);')!=2:raise RuntimeError('Completion seam changed')
    updates[rel]=text.replace('_syncCompletions.add(lastSyncCompletion!);','qaReliableCompletion(lastSyncCompletion!);\n            _syncCompletions.add(lastSyncCompletion!);')
    rel='lib/organizer/presentation/shared/collaboration_actions.dart'
    text="import '../../data/qa_measured_diagnostics.dart' show qaReliableUi;\n"+(qa.ROOT/rel).read_text()
    updates[rel]=once(text,'  Future<void> _taskEditor({LocalTask? task, String? projectId}) async {',"  Future<void> _taskEditor({LocalTask? task, String? projectId}) async {\n    qaReliableUi('editorEntered');")
    rel='lib/organizer/presentation/organizer_editors.dart'
    text="import '../data/qa_measured_diagnostics.dart' show qaReliableUi;\n"+(qa.ROOT/rel).read_text()
    updates[rel]=once(text,'''  void initState() {
    super.initState();''','''  void initState() {
    super.initState();
    if (widget.kind == OrganizerEditorKind.task) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) qaReliableUi('editorWidgetFirstFrame');
      });
    }''')
    rel='lib/organizer/presentation/inbox/visible_task_target_view.dart';text=(source/rel).read_text()
    updates[rel]=once(text,'''  void initState() {
    super.initState();''','''  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) qaReliableUi('previewWidgetFirstFrame');
    });''')
    rel='macos/Runner/MainFlutterWindow.swift';text=(source/rel).read_text()
    text=once(text,'.appendingPathComponent("JivieSyncReliableQA-v1", isDirectory: true)',f'.appendingPathComponent("{NAMESPACE}", isDirectory: true)')
    updates[rel]=once(text,'guard old.count < 2 else { unavailable = "runLimit"; return }','// One authorized measurement run; extra runs require explicit concrete-failure approval.\n      guard old.count < 3 else { unavailable = "runLimit"; return }')
    evidence.mkdir(parents=True);qa.write(evidence/'previous-source-plan.json',previous)
    qa.write(evidence/'stage-started.json',{'fromRevision':9,'toRevision':10,'variant':'b','namespace':NAMESPACE,'authorizedRuns':1,'hardRunCap':3,'extraRunsOnlyAfterExplicitConcreteFailure':True,'dataReset':False})
    overlay=[];stageDiff=[]
    for rel,value in updates.items():
        target=source/rel;before=target.read_text() if target.exists() else ''
        if target.exists():
            archive=evidence/'prior-source'/rel;archive.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(target,archive)
        target.parent.mkdir(parents=True,exist_ok=True);target.write_text(value)
        upstream=(qa.ROOT/rel).read_text() if (qa.ROOT/rel).exists() else ''
        overlay.extend(difflib.unified_diff(upstream.splitlines(True),value.splitlines(True),fromfile='production/'+rel,tofile='qa/'+rel))
        stageDiff.extend(difflib.unified_diff(before.splitlines(True),value.splitlines(True),fromfile='r9/'+rel,tofile='r10/'+rel))
    if any(qa.digest(qa.ROOT/r['path'])!=r['sha256'] for r in original):raise RuntimeError('Repository source changed during stage')
    extras=[r['path'] for r in previous['frozen'] if r['path'] not in prior]
    frozenPaths=current+[p for p in extras if p not in current]
    plan={**previous,'revision':10,'original':original,'frozen':[{'path':p,'sha256':qa.digest(source/p)} for p in frozenPaths],'openingMeasurement':True,'diagnosticNamespace':NAMESPACE}
    qa.write(evidence/'source-plan.json',plan);qa.write(evidence/'update.json',{'productionDeltas':changed,'modifiedQASourceFiles':list(updates),'authorizedRuns':1,'dataReset':False,'AChanged':False})
    (evidence/'qa-overlay.diff').write_text(''.join(overlay));(evidence/'stage.diff').write_text(''.join(stageDiff))
    print('B-only opening measurement r10 staged; no build/install/launch')

def install():
    qa.PUBLIC=NEW;source,plan,evidence=checked()
    if plan.get('revision')!=10 or not plan.get('openingMeasurement'):raise RuntimeError('Not the authorized opening measurement')
    artifact=json.loads((evidence/'artifact.json').read_text());target=Path(plan['target'])
    lines=subprocess.check_output(['ps','-axo','pid=,command='],text=True).splitlines()
    if any(x.strip().split(maxsplit=1)[-1].startswith(str(target)+'/Contents/MacOS/') for x in lines):raise RuntimeError('B must be quit normally by its operator')
    previous=evidence/'previous-r9.app'
    if previous.exists() or (evidence/'installed.json').exists():raise RuntimeError('Installation already attempted')
    target.rename(previous)
    try:
        qa.run(['ditto',artifact['product'],str(target)],source);qa.run(['codesign','--verify','--deep','--strict',str(target)],source)
    except Exception:
        if target.exists():shutil.rmtree(target)
        previous.rename(target);raise
    qa.write(evidence/'installed.json',{'target':str(target),'revision':10,'previousPackage':str(previous),'dataReset':False,'launched':False,'AChanged':False})
    print('B-only opening measurement r10 installed; not launched')

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('action',choices=['stage','build','install']);args=parser.parse_args()
    if args.action=='stage':stage()
    elif args.action=='install':install()
    else:
        qa.PUBLIC=NEW;_,plan,_=checked()
        if plan.get('revision')!=10 or not plan.get('openingMeasurement'):raise RuntimeError('Not the authorized opening source')
        qa.build('b')
