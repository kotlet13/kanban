#!/usr/bin/env python3
"""One QA-only r8 -> r9 native Save-panel diagnostic export update."""
import argparse,difflib,importlib.util,json,shutil,subprocess
from pathlib import Path
spec=importlib.util.spec_from_file_location('reliable',Path(__file__).with_name('sync_reliable_macos_update.py'))
r=importlib.util.module_from_spec(spec);spec.loader.exec_module(r)
qa=r.qa
PREVIOUS=r.NEW
NEW=PREVIOUS/'r9'

def stage(letter):
    qa.PUBLIC=PREVIOUS
    source,previous,_=qa.load(letter)
    if previous.get('revision')!=8:raise RuntimeError('Requires exact reliable r8')
    evidence=NEW/letter
    if evidence.exists():raise RuntimeError('R9 stage already attempted')
    rel='macos/Runner/MainFlutterWindow.swift';path=source/rel;text=path.read_text()
    text=r.once(text,'class MainFlutterWindow: NSWindow {','''class MainFlutterWindow: NSWindow {
  private var qaExportMonitor: Any?
  deinit {
    if let monitor = qaExportMonitor { NSEvent.removeMonitor(monitor) }
  }''')
    text=r.once(text,'    let vaultChannel = FlutterMethodChannel', '''    qaExportMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let window = self,
        event.modifierFlags.intersection([.command, .shift, .option, .control]) == [.command, .shift],
        event.charactersIgnoringModifiers?.lowercased() == "d" else { return event }
      let panel = NSSavePanel()
      panel.title = "Export QA diagnostics"
      panel.nameFieldStringValue = "run-\\(qaSink.run).ndjson"
      panel.canCreateDirectories = true
      panel.beginSheetModal(for: window) { response in
        if response == .OK, let destination = panel.url { _ = qaSink.export(to: destination) }
      }
      return nil
    }

    let vaultChannel = FlutterMethodChannel''')
    marker='\nimport Foundation\nimport CoreFoundation\n'
    offset=text.index(marker)
    text=text[:offset]+'\n'+(qa.ROOT/'tools/diagnostics/qa_reliable_sink_export.swift').read_text()
    evidence.mkdir(parents=True)
    qa.write(evidence/'previous-source-plan.json',previous)
    qa.write(evidence/'stage-started.json',{'fromRevision':8,'toRevision':9,'change':'user-mediated diagnostic export only'})
    old=evidence/'prior-source'/rel;old.parent.mkdir(parents=True);shutil.copyfile(path,old)
    path.write_text(text)
    plan={**previous,'revision':9,'reliableExport':True,'frozen':[{'path':row['path'],'sha256':qa.digest(source/row['path'])} for row in previous['frozen']]}
    qa.write(evidence/'source-plan.json',plan)
    (evidence/'native-overlay.diff').write_text(''.join(difflib.unified_diff(old.read_text().splitlines(True),text.splitlines(True),fromfile='r8/'+rel,tofile='r9/'+rel)))
    print('R9 native diagnostic export staged '+letter.upper()+'; no build/install/launch')

def install(letter):
    qa.PUBLIC=NEW;source,plan,evidence=qa.load(letter)
    if plan.get('revision')!=9 or not plan.get('reliableExport'):raise RuntimeError('Requires exact r9 export')
    artifact=json.loads((evidence/'artifact.json').read_text());target=Path(plan['target'])
    lines=subprocess.check_output(['ps','-axo','pid=,command='],text=True).splitlines()
    if any(x.strip().split(maxsplit=1)[-1].startswith(str(target)+'/Contents/MacOS/') for x in lines):raise RuntimeError('Operator must quit QA app normally')
    old=evidence/'previous-r8.app'
    if old.exists() or (evidence/'installed.json').exists():raise RuntimeError('Install already attempted')
    target.rename(old)
    try:
        qa.run(['ditto',artifact['product'],str(target)],source);qa.run(['codesign','--verify','--deep','--strict',str(target)],source)
    except Exception:
        if target.exists():shutil.rmtree(target)
        old.rename(target);raise
    qa.write(evidence/'installed.json',{'target':str(target),'revision':9,'previousPackage':str(old),'dataReset':False,'launched':False})
    print('R9 diagnostic export installed '+letter.upper()+'; not launched')

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('action',choices=['stage','build','install']);parser.add_argument('variant',choices=['a','b']);args=parser.parse_args()
    if args.action=='stage':stage(args.variant)
    else:
        qa.PUBLIC=NEW
        {'build':qa.build,'install':install}[args.action](args.variant)
