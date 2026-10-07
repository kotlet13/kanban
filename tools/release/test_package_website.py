import importlib.util
import tempfile
import unittest
import zipfile
from pathlib import Path

spec = importlib.util.spec_from_file_location('package_website', Path(__file__).with_name('package_website.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class StaticPackageTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / 'public'
        self.source.mkdir()
        (self.source / 'index.html').write_text('<!doctype html><title>Jivie</title>')
        self.output = self.root / 'website.zip'

    def refuse(self):
        with self.assertRaises(ValueError):
            module.package(self.source, self.output)
        self.assertFalse(self.output.exists())

    def test_cpanel_root_and_deterministic_zip(self):
        (self.source / 'help').mkdir()
        (self.source / 'help/index.html').write_text('<title>Help</title>')
        (self.source / '.htaccess').write_text('Options -Indexes\n')
        first = module.package(self.source, self.output)
        with zipfile.ZipFile(self.output) as archive:
            self.assertIn('index.html', archive.namelist())
            self.assertIn('help/index.html', archive.namelist())
            self.assertTrue(all(not n.startswith(('/', '../', 'public/')) for n in archive.namelist()))
        self.assertEqual(first, module.package(self.source, self.root / 'other.zip'))

    def test_non_static_and_sensitive_paths_refused(self):
        for name in ('app.py', 'config.php', 'copy.bak', 'backup.txt', 'credentials.js', '.env', '.git/config'):
            path = self.source / name
            path.parent.mkdir(exist_ok=True)
            path.write_text('private')
            self.refuse()
            path.unlink()

    def test_file_and_directory_symlinks_refused(self):
        for target in (self.root, self.source / 'index.html'):
            path = self.source / 'linked.html'
            path.symlink_to(target)
            self.refuse()
            path.unlink()

    def test_missing_root_index_refused(self):
        (self.source / 'index.html').unlink()
        self.refuse()

    def test_secret_content_in_allowed_extension_refused(self):
        (self.source / 'key.txt').write_text('-----BEGIN PRIVATE KEY-----')
        self.refuse()

    def test_oversized_source_refused(self):
        (self.source / 'large.txt').write_bytes(b'x' * (module.MAX_FILE + 1))
        self.refuse()

    def test_existing_artifact_preserved(self):
        self.output.write_bytes(b'keep')
        with self.assertRaises(ValueError):
            module.package(self.source, self.output)
        self.assertEqual(self.output.read_bytes(), b'keep')

    def test_output_inside_source_and_traversal_into_source_refused(self):
        for output in (self.source / 'package.zip', self.source / 'help/../package.zip'):
            self.output = output
            self.refuse()


if __name__ == '__main__':
    unittest.main()
