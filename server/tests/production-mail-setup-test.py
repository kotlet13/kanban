"""Filesystem and cron safety checks; never connects to SMTP or a database."""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import types
import unittest

SOURCE = Path(__file__).resolve().parents[1] / 'scripts/production-mail/setup.py'


class ProductionMailSetupTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        root = Path(self.temp.name).resolve()
        spec = importlib.util.spec_from_file_location('mail_setup_fixture', SOURCE)
        self.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.module)
        m = self.module
        m.BASE = root / 'private/production'
        m.ROOT = root / 'webroot'
        m.WORK = m.BASE / 'install/smtp-20261014'
        m.FEATURE = m.BASE / 'familyhub-config.php'
        m.PASSWORD = m.BASE / 'smtp-password.txt'
        m.KEY = m.BASE / 'account-mail.key'
        m.SMTP = m.BASE / 'smtp-config.php'
        m.CANDIDATE = m.WORK / 'familyhub-config.candidate.php'
        m.STATE = m.WORK / 'state.json'
        m.AUTH = m.WORK / 'auth-proof.json'
        for p in [m.BASE.parent, m.BASE, m.BASE / 'install', m.BASE / 'logs']:
            p.mkdir(mode=0o700)
        (m.ROOT / 'vendor').mkdir(parents=True)
        (m.ROOT / 'vendor/autoload.php').touch()
        self.before_feature = b"<?php\ndefine('FAMILYHUB_ENABLE_NATIVE_API',true);\n"
        m.EXPECTED = hashlib.sha256(self.before_feature).hexdigest()
        m.write_new(m.FEATURE, self.before_feature)
        m.write_new(m.BASE / 'config.php', b'protected existing configuration')
        # A different installation's account-mail worker must remain allowed.
        self.before_cron = b'* * * * * php /other/site/plugins/FamilyHub/cli/account-mail.php\n'
        self.cron = self.before_cron

        def command(args, **kwargs):
            if args == ['crontab', '-l']:
                return types.SimpleNamespace(stdout=self.cron)
            if args[0] == 'crontab':
                self.cron = Path(args[1]).read_bytes()
                return types.SimpleNamespace(stdout=b'')
            if args[0] == m.PHP and args[1] == '-l':
                return types.SimpleNamespace(stdout=b'')
            raise AssertionError('Unexpected subprocess')

        m.subprocess = types.SimpleNamespace(run=command)

    def tearDown(self):
        self.temp.cleanup()

    def authenticated(self):
        m = self.module
        m.PASSWORD.write_bytes(b'synthetic-fixture-password')
        state = json.loads(m.STATE.read_bytes())
        m.write_new(m.AUTH, json.dumps(dict(authenticated=True, verifiedTls=True,
                    smtpSha=state['smtpSha'], passwordStamp=m.password_stamp())).encode())

    def test_changed_feature_refuses_before_writing(self):
        m = self.module
        m.FEATURE.write_bytes(b'changed production feature')
        with self.assertRaisesRegex(RuntimeError, 'production_feature_requires_review'):
            m.run('prepare')
        self.assertFalse(m.WORK.exists())
        self.assertEqual(self.cron, self.before_cron)

    def test_unowned_destination_refuses(self):
        m = self.module
        m.write_new(m.KEY, b'existing-key')
        with self.assertRaisesRegex(RuntimeError, 'unowned_destination_exists'):
            m.run('prepare')
        self.assertEqual(m.KEY.read_bytes(), b'existing-key')
        self.assertFalse(m.WORK.exists())

    def test_prepare_keeps_live_configuration_and_cron(self):
        m = self.module
        m.run('prepare')
        self.assertEqual(m.FEATURE.read_bytes(), self.before_feature)
        self.assertEqual(self.cron, self.before_cron)
        self.assertEqual((m.WORK / 'crontab.before').read_bytes(), self.before_cron)
        self.assertEqual((m.WORK / 'familyhub-config.before.php').read_bytes(), self.before_feature)
        self.assertEqual(m.PASSWORD.stat().st_size, 0)
        m.private(m.SMTP)
        m.private(m.KEY)

    def test_missing_password_prevents_activation(self):
        m = self.module
        m.run('prepare')
        with self.assertRaisesRegex(RuntimeError, 'password_missing_or_empty'):
            m.run('activate')
        self.assertEqual(self.cron, self.before_cron)
        self.assertEqual(m.FEATURE.read_bytes(), self.before_feature)

    def test_changed_cron_refuses_without_overwrite(self):
        m = self.module
        m.run('prepare')
        self.authenticated()
        self.cron += b'# independently added job\n'
        changed = self.cron
        with self.assertRaisesRegex(RuntimeError, 'crontab_changed_since_prepare'):
            m.run('activate')
        self.assertEqual(self.cron, changed)
        self.assertEqual(m.FEATURE.read_bytes(), self.before_feature)

    def test_changed_candidate_refuses_without_activation(self):
        m = self.module
        m.run('prepare')
        self.authenticated()
        m.CANDIDATE.write_bytes(b'wrong candidate')
        with self.assertRaisesRegex(RuntimeError, 'candidate_changed'):
            m.run('activate')
        self.assertEqual(self.cron, self.before_cron)

    def test_activation_preserves_old_cron_and_replay_keeps_key(self):
        m = self.module
        m.run('prepare')
        self.authenticated()
        key = m.KEY.read_bytes()
        m.run('activate')
        self.assertTrue(self.cron.startswith(self.before_cron))
        self.assertEqual(self.cron.count(b'# jivie-production-account-mail'), 1)
        self.assertEqual(self.cron.count(b'# jivie-production-delivery'), 1)
        self.assertEqual(m.FEATURE.read_bytes(), self.before_feature +
                         f"\nrequire '{m.SMTP}';\n".encode())
        m.run('activate')
        self.assertEqual(m.KEY.read_bytes(), key)
        self.assertEqual(json.loads(m.STATE.read_bytes())['phase'], 'active')


if __name__ == '__main__':
    unittest.main()
