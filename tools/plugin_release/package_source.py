#!/usr/bin/env python3
"""Create a reviewed FamilyHub source ZIP; never publishes or copies Git history."""
import argparse
import hashlib
import json
import re
import stat
import zipfile
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = Path(__file__).with_name('source_manifest.json')
PUBLIC_README = Path(__file__).with_name('PUBLIC_README.md')
PUBLIC_DOCUMENTS = {'docs/account-deletion-contract.md': ROOT / 'docs/server/account-deletion-contract.md'}
LIMIT = 2 * 1024 * 1024


def collect(source, manifest):
    if source.is_symlink() or not source.is_dir():
        raise ValueError('Source must be a real plugin directory')
    names = json.loads(manifest.read_text())
    if not isinstance(names, list) or len(names) != len(set(names)):
        raise ValueError('Invalid source manifest')
    for name in names:
        path = PurePosixPath(name)
        if not isinstance(name, str) or path.is_absolute() or '..' in path.parts or str(path) != name:
            raise ValueError('Invalid source manifest path')
    actual = set()
    for path in source.rglob('*'):
        if path.is_symlink():
            raise ValueError('Symlinks refused')
        if path.is_dir():
            continue
        if not stat.S_ISREG(path.stat().st_mode):
            raise ValueError('Nonregular files refused')
        actual.add(path.relative_to(source).as_posix())
    if actual != set(names):
        raise ValueError('Unreviewed or missing source files; review manifest first')
    result = {}
    for name in sorted(names):
        path = source / name
        if path.stat().st_size > LIMIT:
            raise ValueError('Oversized source file')
        data = path.read_bytes()
        if len(data) > LIMIT:
            raise ValueError('Oversized source file')
        text = data.decode('utf-8')
        if '\x00' in text or re.search(r'-----BEGIN (?:[A-Z]+ )?PRIVATE KEY-----|"type"\s*:\s*"service_account"|\b(?:sk-proj-|ghp_)[A-Za-z0-9]{20,}', text):
            raise ValueError('Credential-like content refused; values not printed')
        result[name] = data
    license_text = result.get('LICENSE', b'').decode('utf-8')
    if not all(part in license_text for part in ('MIT License', 'Copyright (c)', 'Permission is hereby granted, free of charge', 'THE SOFTWARE IS PROVIDED "AS IS"')) or re.search(r'(?i)draft|TODO|placeholder|contributors', license_text):
        raise ValueError('A confirmed MIT license is required')
    return result


def package(source, destination, manifest=MANIFEST, public_documents=PUBLIC_DOCUMENTS):
    # Validate every input before opening a new artifact. Existing outputs are never replaced.
    if source.resolve() in destination.resolve().parents or destination.resolve() == source.resolve():
        raise ValueError('Output must be outside plugin source')
    entries = collect(source, manifest)
    # The standalone public README is reviewed separately. It replaces references
    # to development files in the private application repository; PHP is unchanged.
    entries['README.md'] = PUBLIC_README.read_bytes()
    # Explicitly reviewed public contract only; no recursive application docs copy.
    for name, path in public_documents.items():
        relative = PurePosixPath(name)
        if relative.is_absolute() or '..' in relative.parts or str(relative) != name or name in entries:
            raise ValueError('Invalid public document destination')
        if path.is_symlink() or not path.is_file() or path.stat().st_size > LIMIT:
            raise ValueError('Public document must be a bounded regular file')
        data = path.read_bytes()
        text = data.decode('utf-8')
        if '\x00' in text or re.search(r'-----BEGIN (?:[A-Z]+ )?PRIVATE KEY-----|"type"\s*:\s*"service_account"|\b(?:sk-proj-|ghp_)[A-Za-z0-9]{20,}', text):
            raise ValueError('Credential-like public document refused')
        entries[name] = data
    if destination.exists() or destination.with_suffix(destination.suffix + '.sha256').exists():
        raise ValueError('Output already exists')
    destination.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(destination, 'x', zipfile.ZIP_DEFLATED) as archive:
        for name, data in sorted(entries.items()):
            entry = zipfile.ZipInfo('FamilyHub/' + name, (2026, 10, 7, 0, 0, 0))
            entry.compress_type = zipfile.ZIP_DEFLATED
            entry.external_attr = 0o100644 << 16
            archive.writestr(entry, data)
    digest = hashlib.sha256(destination.read_bytes()).hexdigest()
    with destination.with_suffix(destination.suffix + '.sha256').open('x') as checksum:
        checksum.write(digest + '  ' + destination.name + '\n')
    return digest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=ROOT / 'server/plugins/FamilyHub')
    parser.add_argument('--output', type=Path, default=ROOT / 'build/release/FamilyHub-source.zip')
    args = parser.parse_args()
    try:
        digest = package(args.source, args.output)
    except (ValueError, OSError, UnicodeError, TypeError, KeyError):
        print('Source package refused: review files, manifest and confirmed MIT license. No source values printed.')
        return 1
    print('Created reviewed source ZIP. SHA256 ' + digest)
    print('No Git history, publishing, deployment or production data operation performed.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
