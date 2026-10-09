"""Synthetic guards; no Docker command or real backup is read."""
import importlib.util
import json
import os
from pathlib import Path
import stat
import tempfile
import unittest
from unittest.mock import patch
import zipfile

spec = importlib.util.spec_from_file_location('verifier', Path(__file__).parents[1] / 'scripts/verify-cpanel-jivie-backup.py')
v = importlib.util.module_from_spec(spec)
spec.loader.exec_module(v)

class VerifyBackupGuards(unittest.TestCase):
    def fixture(self, root, entry='state.json', mode=stat.S_IFREG | 0o600):
        private = Path(root).resolve() / 'private'
        private.mkdir(mode=0o700)
        archive = private / 'backup.zip'
        with zipfile.ZipFile(archive, 'x') as z:
            info = zipfile.ZipInfo(entry)
            info.create_system = 3
            info.external_attr = mode << 16
            z.writestr(info, '{}')
        archive.chmod(0o600)
        return private, archive

    def run_guard(self, root, expected, **kwargs):
        private, archive = self.fixture(root, kwargs.pop('entry', 'state.json'), kwargs.pop('mode', stat.S_IFREG | 0o600))
        info = {'HostConfig': {'NetworkMode': 'none', 'PortBindings': None}, 'Config': {'Image': 'mariadb:10.11.19'}}
        for key, value in kwargs.items():
            info['Config' if key == 'Image' else 'HostConfig'][key] = value
        with patch.object(v, 'command', return_value=json.dumps([info]).encode()) as cmd:
            with self.assertRaisesRegex(RuntimeError, expected):
                v.main([str(archive), '--container', 'synthetic-restore', '--private-root', str(private)])
            self.assertEqual(cmd.call_count, 1)

    def test_network_required_none(self):
        with tempfile.TemporaryDirectory() as root: self.run_guard(root, 'isolated_container_guard', NetworkMode='bridge')
    def test_ports_rejected(self):
        with tempfile.TemporaryDirectory() as root: self.run_guard(root, 'isolated_container_guard', PortBindings={'3306': []})
    def test_image_is_fixed(self):
        with tempfile.TemporaryDirectory() as root: self.run_guard(root, 'isolated_container_guard', Image='mariadb:latest')
    def test_traversal_rejected(self):
        with tempfile.TemporaryDirectory() as root: self.run_guard(root, 'zip_path_guard', entry='../escape')
    def test_absolute_rejected(self):
        with tempfile.TemporaryDirectory() as root: self.run_guard(root, 'zip_path_guard', entry='/escape')
    def test_windows_path_rejected(self):
        with tempfile.TemporaryDirectory() as root: self.run_guard(root, 'zip_path_guard', entry='backup\\escape')
    def test_symlink_entry_rejected(self):
        with tempfile.TemporaryDirectory() as root: self.run_guard(root, 'zip_type_guard', mode=stat.S_IFLNK | 0o777)
    def test_device_entry_rejected(self):
        with tempfile.TemporaryDirectory() as root: self.run_guard(root, 'zip_type_guard', mode=stat.S_IFCHR | 0o600)
    def test_archive_group_access_rejected(self):
        with tempfile.TemporaryDirectory() as root:
            private, archive = self.fixture(root)
            archive.chmod(0o640)
            with patch.object(v, 'command') as cmd:
                with self.assertRaisesRegex(RuntimeError, 'private_archive_permissions'):
                    v.main([str(archive), '--container', 'synthetic-restore', '--private-root', str(private)])
                cmd.assert_not_called()
    def test_archive_symlink_rejected(self):
        with tempfile.TemporaryDirectory() as root:
            private, archive = self.fixture(root)
            link = private / 'link.zip'
            link.symlink_to(archive)
            with patch.object(v, 'command') as cmd:
                with self.assertRaisesRegex(RuntimeError, 'private_archive_symlink_guard'):
                    v.main([str(link), '--container', 'synthetic-restore', '--private-root', str(private)])
                cmd.assert_not_called()

    def test_inventory_sorts_complete_relative_keys_like_php(self):
        with tempfile.TemporaryDirectory() as root:
            private = Path(root).resolve()
            (private / 'name').mkdir()
            (private / 'name' / 'inside').write_bytes(b'synthetic nested')
            (private / 'name-file').write_bytes(b'synthetic adjacent')
            self.assertEqual(list(v.private_inventory(private)), ['name-file', 'name/inside'])
            self.assertNotEqual([p.relative_to(private).as_posix() for p in sorted(private.rglob('*')) if p.is_file()], list(v.private_inventory(private)))

if __name__ == '__main__': unittest.main()
