#!/usr/bin/env python3
"""Package a static cPanel document root locally; never uploads or deploys."""
import argparse
import hashlib
import re
import stat
import zipfile
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parents[2]
EXTENSIONS = {'.html', '.css', '.js', '.png', '.svg', '.ico', '.webp', '.txt', '.xml'}
TEXT_EXTENSIONS = {'.html', '.css', '.js', '.svg', '.txt', '.xml'}
MAX_FILE = 10 * 1024 * 1024
MAX_TOTAL = 50 * 1024 * 1024


def collect(source):
    if source.is_symlink() or not source.is_dir():
        raise ValueError('A real static source directory is required')
    entries = {}
    total = 0
    for path in sorted(source.rglob('*')):
        relative = path.relative_to(source).as_posix()
        parts = PurePosixPath(relative).parts
        if any(part.startswith('.') and part != '.htaccess' for part in parts):
            raise ValueError('Hidden source files or directories refused')
        if path.is_symlink():
            raise ValueError('Symlinks refused')
        if path.is_dir():
            continue
        if not stat.S_ISREG(path.stat().st_mode):
            raise ValueError('Nonregular file refused')
        if path.name != '.htaccess' and path.suffix.lower() not in EXTENSIONS:
            raise ValueError('Non-static file refused')
        if re.search(r'(?i)(?:^|[-_.])(?:secret|credentials?|config|backup|private|service-account|firebase-adminsdk)(?:[-_.]|$)', path.name):
            raise ValueError('Sensitive filename refused')
        if path.stat().st_size > MAX_FILE:
            raise ValueError('Oversized static file')
        data = path.read_bytes()
        total += len(data)
        if len(data) > MAX_FILE or total > MAX_TOTAL:
            raise ValueError('Oversized static package')
        if path.suffix.lower() in TEXT_EXTENSIONS or path.name == '.htaccess':
            text = data.decode('utf-8')
            if '\x00' in text or re.search(r'-----BEGIN (?:[A-Z]+ )?PRIVATE KEY-----|"type"\s*:\s*"service_account"|\b(?:sk-proj-|ghp_)[A-Za-z0-9]{20,}', text):
                raise ValueError('Credential-like content refused')
        entries[relative] = data
    if 'index.html' not in entries:
        raise ValueError('Document root index.html is required')
    return entries


def package(source, output):
    if source.resolve() in output.resolve().parents or source.resolve() == output.resolve():
        raise ValueError('Output must be outside source tree')
    checksum = output.with_suffix(output.suffix + '.sha256')
    if output.exists() or checksum.exists():
        raise ValueError('Existing output is never overwritten')
    entries = collect(source)
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, 'x', zipfile.ZIP_DEFLATED) as archive:
        for name, data in entries.items():
            entry = zipfile.ZipInfo(name, (2026, 10, 7, 0, 0, 0))
            entry.compress_type = zipfile.ZIP_DEFLATED
            entry.external_attr = 0o100644 << 16
            archive.writestr(entry, data)
    digest = hashlib.sha256(output.read_bytes()).hexdigest()
    with checksum.open('x') as handle:
        handle.write(digest + '  ' + output.name + '\n')
    return digest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=ROOT / 'website/public')
    parser.add_argument('--output', type=Path, default=ROOT / 'build/releases/jivie-website.zip')
    args = parser.parse_args()
    try:
        digest = package(args.source, args.output)
    except (ValueError, OSError, UnicodeError):
        print('Static package refused: review source paths, types and contents. Values not printed.')
        return 1
    print('Created static document-root ZIP. SHA256 ' + digest)
    print('No upload, deployment or production data operation performed.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
