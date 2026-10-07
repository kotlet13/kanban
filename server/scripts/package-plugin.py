#!/usr/bin/env python3
"""Build a deterministic source-only cPanel upload archive without development config/data."""
from pathlib import Path
import hashlib
import zipfile

server = Path(__file__).resolve().parents[1]
source = server / 'plugins' / 'FamilyHub'
destination = server / 'dist'
destination.mkdir(exist_ok=True)
archive = destination / 'FamilyHub-0.6.0.zip'
with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as package:
    for path in sorted(source.rglob('*')):
        if path.is_file():
            entry = zipfile.ZipInfo(str(Path('FamilyHub') / path.relative_to(source)), (2026, 10, 4, 0, 0, 0))
            entry.compress_type = zipfile.ZIP_DEFLATED
            entry.external_attr = 0o100644 << 16
            package.writestr(entry, path.read_bytes())
digest = hashlib.sha256(archive.read_bytes()).hexdigest()
checksum = destination / (archive.name + '.sha256')
checksum.write_text(f'{digest}  {archive.name}\n')
print(f'{archive}\nSHA256 {digest}')
