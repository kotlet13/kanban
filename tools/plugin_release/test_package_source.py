import importlib.util
import json
import tempfile
import unittest
import zipfile
from pathlib import Path

spec = importlib.util.spec_from_file_location('package_source', Path(__file__).with_name('package_source.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
LICENSE = 'MIT License\nCopyright (c) 2026 Example owner\nPermission is hereby granted, free of charge\nTHE SOFTWARE IS PROVIDED "AS IS"\n'


class SourcePackageTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / 'plugin'
        self.source.mkdir()
        (self.source / 'Plugin.php').write_text('<?php class Example {}')
        (self.source / 'LICENSE').write_text(LICENSE)
        self.manifest = self.root / 'manifest.json'
        self.manifest.write_text(json.dumps(['Plugin.php', 'LICENSE']))
        self.output = self.root / 'source.zip'
        self.document = self.root / 'contract.md'
        self.document.write_text('Public deletion contract')
        self.documents = {'docs/account-deletion-contract.md': self.document}

    def build(self):
        return module.package(self.source, self.output, self.manifest, self.documents)

    def refuse(self):
        with self.assertRaises(ValueError):
            self.build()
        self.assertFalse(self.output.exists())

    def test_deterministic_source_and_no_history(self):
        first = self.build()
        with zipfile.ZipFile(self.output) as archive:
            self.assertEqual(set(archive.namelist()), {'FamilyHub/LICENSE', 'FamilyHub/Plugin.php', 'FamilyHub/README.md', 'FamilyHub/docs/account-deletion-contract.md'})
            readme = archive.read('FamilyHub/README.md').decode()
            self.assertIn('AccountDeletionController', readme)
            self.assertNotIn('docs/server/', readme)
        other = self.root / 'second.zip'
        self.assertEqual(first, module.package(self.source, other, self.manifest, self.documents))

    def test_unreviewed_public_document_symlink_and_traversal_refused(self):
        self.document.unlink()
        self.document.symlink_to(self.manifest)
        self.refuse()
        self.documents = {'../escape.md': self.manifest}
        self.refuse()

    def test_unknown_secret_and_git_history_refused(self):
        for name in ('config.php', '.env', 'backup.sql', '.git/config'):
            path = self.source / name
            path.parent.mkdir(exist_ok=True)
            path.write_text('private')
            self.refuse()
            path.unlink()

    def test_file_and_directory_symlinks_refused(self):
        for target in (self.root, self.manifest):
            path = self.source / 'linked'
            path.symlink_to(target)
            self.refuse()
            path.unlink()

    def test_traversal_and_duplicate_manifest_refused(self):
        for names in (['../manifest.json'], ['LICENSE', 'LICENSE'], ['/private/key']):
            self.manifest.write_text(json.dumps(names))
            self.refuse()

    def test_missing_license_and_draft_refused(self):
        for value in ('not licensed', LICENSE.replace('Copyright (c)', 'Owner'), LICENSE + 'DRAFT', LICENSE + 'TriparNA contributors'):
            (self.source / 'LICENSE').write_text(value)
            self.refuse()

    def test_private_key_in_reviewed_source_refused(self):
        (self.source / 'Plugin.php').write_text('-----BEGIN PRIVATE KEY-----')
        self.refuse()

    def test_oversize_refused(self):
        (self.source / 'Plugin.php').write_bytes(b'x' * (module.LIMIT + 1))
        self.refuse()

    def test_existing_output_never_overwritten(self):
        self.output.write_bytes(b'keep')
        with self.assertRaises(ValueError):
            self.build()
        self.assertEqual(self.output.read_bytes(), b'keep')

    def test_output_inside_source_refused(self):
        self.output = self.source / 'source.zip'
        self.refuse()


if __name__ == '__main__':
    unittest.main()
