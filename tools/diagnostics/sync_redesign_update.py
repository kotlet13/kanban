#!/usr/bin/env python3
"""Update only the two owned redesign QA apps; retain their containers and keys."""
import argparse
import importlib.util
import json
import shutil
import subprocess
from pathlib import Path

spec = importlib.util.spec_from_file_location('qa', Path(__file__).with_name('sync_redesign_macos.py'))
qa = importlib.util.module_from_spec(spec)
spec.loader.exec_module(qa)


def sync_trace(text):
    return (text.replace('} catch (_) {', "} catch (qaError, qaStack) {\n        qaSyncTrace('sync-caught', qaError, qaStack);")
        .replace('} catch (error) {', "} catch (error, qaStack) {\n        qaSyncTrace('sync-caught', error, qaStack);")
        .replace('on CollaborationException catch (error) {', "on CollaborationException catch (error, qaStack) {\n        qaSyncTrace('sync-api', error, qaStack);"))


def stage(letter):
    source, plan, evidence = qa.load(letter)
    revision = plan.get('revision', 1) + 1
    # r6 is the third and final native request-limit continuation after reviewed
    # read-coalescing fixes. Original invitation and queued work stay unchanged.
    # Unrelated STOP3 tests remain stopped; no fourth rate-limit attempt.
    if revision > 6:
        raise RuntimeError('Bounded native update budget exhausted')
    archive = evidence / ('revision-' + str(revision - 1))
    archive.mkdir()
    for name in ('source-plan.json', 'artifact.json', 'installed.json', 'build-started.json', 'build.log'):
        if (evidence / name).exists():
            shutil.copyfile(evidence / name, archive / name)
    old = {r['path']: r for r in plan['original']}
    current = qa.paths()
    changed = [p for p in current if p not in old or qa.digest(qa.ROOT / p) != old[p]['sha256']]
    if any(not p.startswith('lib/') for p in changed):
        raise RuntimeError('Non-Dart update requires separate review')
    protected = {'lib/main.dart', 'lib/organizer/data/collaboration_transport.dart'}
    if protected.intersection(changed):
        raise RuntimeError('QA isolation overlay changed upstream')
    for rel in changed:
        target = source / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        value = (qa.ROOT / rel).read_text()
        if rel.endswith('/collaboration_sync_actions.dart'):
            value = sync_trace(value)
        target.write_text(value)
    # A bounded diagnostic catches the actual creation failure at its UI seam.
    rel = 'lib/organizer/presentation/shared/create_space_dialog.dart'
    path = source / rel
    text = (qa.ROOT / rel).read_text()
    text = "import '../../data/collaboration_transport.dart' show qaSyncTrace;\n" + text
    text = text.replace('} catch (error) {', "} catch (error, qaStack) {\n      qaSyncTrace('create-space', error, qaStack);")
    path.write_text(text)
    # Automatic approval deliberately keeps the UI quiet on failure. Capture
    # only the sanitized code/allowed frames at that catch seam in this QA app.
    rel = 'lib/organizer/data/e2ee/crypto_invitation_autoapproval.dart'
    path = source / rel
    text = (qa.ROOT / rel).read_text()
    needle = '} catch (error) {'
    if text.count(needle) != 1:
        raise RuntimeError('Automatic approval diagnostic seam changed')
    path.write_text(text.replace(needle,
        "} catch (error, qaStack) {\n        qaSyncTrace('foreground-invitation', error, qaStack);"))
    transport = source / 'lib/organizer/data/collaboration_transport.dart'
    text = transport.read_text()
    if "show CryptoAuthorityPending" not in text:
        text = "import 'e2ee/crypto_sync_repository.dart' show CryptoAuthorityPending;\n" + text
        text = text.replace("error is CollaborationException ? error.code : error.runtimeType.toString()",
            "error is CollaborationException ? error.code : error is CryptoAuthorityPending ? error.reason : error is FormatException ? error.message.toString() : error.runtimeType.toString()")
        transport.write_text(text)
    plan['revision'] = revision
    plan['original'] = [{'path': p, 'sha256': qa.digest(qa.ROOT / p)} for p in current]
    plan['frozen'] = [{'path': p, 'sha256': qa.digest(source / p)} for p in current]
    qa.write(evidence / 'source-plan.json', plan)
    qa.write(evidence / ('update-' + str(revision) + '.json'), {'changed': changed, 'diagnostics': ['lib/organizer/presentation/shared/create_space_dialog.dart', rel], 'dataReset': False})
    for name in ('artifact.json', 'build-started.json'):
        (evidence / name).unlink(missing_ok=True)
    print('Staged reviewed deltas only for ' + letter.upper())


def install(letter):
    source, plan, evidence = qa.load(letter)
    artifact = json.loads((evidence / 'artifact.json').read_text())
    target = Path(plan['target'])
    processes = subprocess.check_output(['ps', '-axo', 'command'], text=True)
    if str(target / 'Contents/MacOS') in processes:
        raise RuntimeError('Quit the QA app normally before replacement')
    old = evidence / ('previous-r' + str(plan['revision'] - 1) + '.app')
    if old.exists():
        raise RuntimeError('Previous package already archived')
    old.parent.mkdir(parents=True, exist_ok=True)
    target.rename(old)
    try:
        qa.run(['ditto', artifact['product'], str(target)], source)
        qa.run(['codesign', '--verify', '--deep', '--strict', str(target)], source)
    except Exception:
        if target.exists():
            shutil.rmtree(target)
        old.rename(target)
        raise
    qa.write(evidence / 'installed.json', {'target': str(target), 'revision': plan['revision'], 'dataReset': False, 'previousPackage': str(old)})
    print('Updated same QA identity ' + letter.upper() + '; container and Keychain untouched')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['stage', 'build', 'install'])
    parser.add_argument('variant', choices=['a', 'b'])
    args = parser.parse_args()
    {'stage': stage, 'build': qa.build, 'install': install}[args.action](args.variant)
