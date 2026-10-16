#!/usr/bin/env python3
"""Freeze all current public Android/runtime inputs and exact private config hashes.

Git HEAD is provenance only: uncommitted and untracked public source is included.
Configuration bytes are copied privately, never printed or embedded in a diff.
"""
import argparse
import hashlib
import json
import re
import shutil
import subprocess
from pathlib import Path


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--qa', type=Path, required=True)
    parser.add_argument('--previous-manifest', type=Path, required=True)
    parser.add_argument('--version', required=True)
    args = parser.parse_args()
    root, qa = args.root.resolve(), args.qa.resolve()
    destination = qa / 'source'
    assert not destination.exists(), 'Never replace frozen release source'
    assert re.search(r'^version:\s*' + re.escape(args.version) + r'\s*$', (root / 'pubspec.yaml').read_text(), re.M)
    previous = json.loads(args.previous_manifest.read_text())
    head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip()
    candidates = subprocess.check_output(['git', 'ls-files', '-z', '--cached', '--others', '--exclude-standard'], cwd=root).decode().split('\0')
    roots = ('lib/', 'android/', 'ios/', 'macos/', 'assets/', 'fonts/', 'test/', 'tools/', 'docs/release/')
    paths = sorted({p for p in candidates if (p.startswith(roots) or p in {'pubspec.yaml', 'pubspec.lock', 'l10n.yaml', 'analysis_options.yaml', 'README.md'}) and (root / p).is_file()})
    assert not any((root / p).is_symlink() for p in paths)
    public = [p for p in paths if p.startswith(('lib/', 'android/', 'ios/', 'macos/', 'assets/', 'fonts/')) or p in {'pubspec.yaml', 'pubspec.lock', 'l10n.yaml', 'analysis_options.yaml'}]
    rows = [{'path': p, 'sha256': digest(root / p)} for p in public]
    configurations = {p: digest(root / p) for p in previous['configurationHashes']}
    assert configurations == previous['configurationHashes'], 'Configuration changed since previous AAB'
    locks = {p: digest(root / p) for p in previous['locks']}
    assert locks == previous['locks'], 'Dependency locks changed since previous AAB'
    old = {r['path']: r['sha256'] for r in previous['files']}
    native = {r['path']: r['sha256'] for r in rows if r['path'].startswith(('android/', 'ios/', 'macos/'))}
    assert native == {p:h for p,h in old.items() if p.startswith(('android/', 'ios/', 'macos/'))}, 'Native inputs changed'
    qa.mkdir(parents=True, exist_ok=True)
    destination.mkdir(mode=0o700)
    for p in paths + list(configurations):
        target = destination / p
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(root / p, target)
        if p in configurations:
            target.chmod(0o600)
    for row in rows:
        assert digest(root / row['path']) == row['sha256'] == digest(destination / row['path']), 'Source changed during freeze'
    for p,h in configurations.items():
        assert digest(root / p) == h == digest(destination / p)
    aggregate = hashlib.sha256(''.join(r['sha256']+'  '+r['path']+'\n' for r in rows).encode()).hexdigest()
    runtime = [r for r in rows if r['path'].startswith(('lib/', 'assets/', 'fonts/')) or r['path'] in {'pubspec.yaml', 'pubspec.lock', 'l10n.yaml'}]
    manifest = {'baseCommit':head, 'version':args.version, 'state':'Authorized complete working-tree snapshot; HEAD alone is not the source provenance', 'aggregateSha256':aggregate, 'files':rows, 'runtimeFiles':runtime, 'configurationHashes':configurations, 'locks':locks, 'source':str(destination)}
    for path in [qa/'source-input-manifest.json', qa/'android/source-input-manifest.json']:
        path.parent.mkdir(parents=True,exist_ok=True)
        assert not path.exists()
        path.write_text(json.dumps(manifest,indent=2)+'\n')
    diff = subprocess.check_output(['git','diff','--binary','HEAD','--',*public],cwd=root)
    (qa/'public-runtime-head.diff').write_bytes(diff)
    comparison = {'previousVersion':previous['version'],'version':args.version,
        'changed':[p for p in public if p in old and digest(root/p) != old[p]],
        'added':[p for p in public if p not in old], 'removed':[p for p in old if p not in public],
        'nativeInputsIdentical':True,'dependencyLocksIdentical':True,'privateConfigurationHashesIdentical':True,
        'headDiffSha256':hashlib.sha256(diff).hexdigest(), 'baseCommit':head,
        'allSnapshotFiles':[{'path':p,'sha256':digest(destination/p)} for p in paths]}
    (qa / ('source-diff-from-' + previous['version'].split('+')[1] + '.json')).write_text(json.dumps(comparison,indent=2)+'\n')
    print(json.dumps({'source':str(destination),'files':len(rows),'runtimeFiles':len(runtime),'aggregateSha256':aggregate,'changed':len(comparison['changed']),'added':len(comparison['added']),'removed':len(comparison['removed']),'nativeLocksConfigurationIdentical':True}))


if __name__ == '__main__':
    main()
