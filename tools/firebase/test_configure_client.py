import json
import os
import plistlib
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
import configure_client as tool

API = 'AIza' + 'A' * 35

def config(platform='android', identifier='com.takndev.kanbanconnect', project='fixture-project'):
    return dict(project=project, sender='123456789', api=API, app=f'1:123456789:{platform}:abcdef1234567890', identifier=identifier)

class ConfigurationTests(unittest.TestCase):
    def test_authoritative_current_identifiers(self):
        self.assertEqual(tool.application_identifiers(), ('com.takndev.kanbanconnect', 'com.example.kanban'))

    def test_changed_identifier_is_read_without_hardcoded_client_rejection(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            gradle = root / 'android/app/build.gradle.kts'
            gradle.parent.mkdir(parents=True)
            gradle.write_text('applicationId = "org.example.family"')
            project = root / 'ios/Runner.xcodeproj/project.pbxproj'
            project.parent.mkdir(parents=True)
            project.write_text('buildSettings = { INFOPLIST_FILE = Runner/Info.plist; PRODUCT_BUNDLE_IDENTIFIER = org.example.family; };')
            self.assertEqual(tool.application_identifiers(root), ('org.example.family', 'org.example.family'))
            project.write_text(project.read_text() + 'buildSettings = { INFOPLIST_FILE = Runner/Info.plist; PRODUCT_BUNDLE_IDENTIFIER = org.other.family; };')
            with self.assertRaises(ValueError): tool.application_identifiers(root)

    def test_downloaded_android_and_ios_inputs(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            c = config()
            android = root / 'google-services.json'
            android.write_text(json.dumps({'project_info': {'project_id': c['project'], 'project_number': c['sender']}, 'client': [{'client_info': {'mobilesdk_app_id': c['app'], 'android_client_info': {'package_name': c['identifier']}}, 'api_key': [{'current_key': c['api']}]}]}))
            self.assertEqual(tool.android(android), c)
            c = config('ios', 'com.example.kanban')
            ios = root / 'GoogleService-Info.plist'
            ios.write_bytes(plistlib.dumps({'PROJECT_ID': c['project'], 'GCM_SENDER_ID': c['sender'], 'API_KEY': c['api'], 'GOOGLE_APP_ID': c['app'], 'BUNDLE_ID': c['identifier']}))
            self.assertEqual(tool.ios(ios), c)
            android.write_text(json.dumps({'type': 'service_account', 'private_key': 'synthetic-sensitive'}))
            with self.assertRaises(ValueError): tool.android(android)

    def test_native_resources_and_no_sensitive_output(self):
        with tempfile.TemporaryDirectory() as temp:
            target = tool.generate(config(), config('ios', 'com.example.kanban'), temp)
            data = json.loads(target.read_text())
            self.assertEqual(data['FIREBASE_PROJECT_ID'], 'fixture-project')
            xml = Path(temp, 'android/app/src/main/res/values/firebase_config.xml').read_text()
            for key in ('google_app_id', 'gcm_defaultSenderId', 'google_api_key', 'project_id'):
                self.assertIn(key, xml)
            self.assertNotIn('private_key', target.read_text())

    def test_mismatched_project_and_partial_ios_run_do_not_overwrite(self):
        with tempfile.TemporaryDirectory() as temp:
            target = tool.generate(config(), output_dir=temp)
            original = target.read_bytes()
            with self.assertRaises(ValueError): tool.generate(config(), config('ios', 'com.example.kanban', 'other-project'), temp)
            with self.assertRaises(ValueError): tool.generate(ios_config=config('ios', 'com.example.kanban'), output_dir=temp)
            self.assertEqual(target.read_bytes(), original)

    def test_transaction_rolls_back_first_file_if_second_replace_fails(self):
        with tempfile.TemporaryDirectory() as temp:
            target = tool.generate(config(), output_dir=temp)
            original = target.read_bytes()
            real_replace = os.replace
            calls = 0
            def fail_second(a, b):
                nonlocal calls
                calls += 1
                if calls == 2: raise OSError('synthetic disk error')
                return real_replace(a, b)
            with patch.object(tool.os, 'replace', side_effect=fail_second):
                with self.assertRaises(OSError): tool.generate(config(project='changed-project'), output_dir=temp)
            self.assertEqual(target.read_bytes(), original)

    def test_invalid_project_app_sender_and_identifier_rejected(self):
        for field, value in [('project', 'invalid-'), ('app', '1:987654321:android:abcdef1234567890'), ('api', 'private-key'), ('identifier', 'wrong.app')]:
            with self.subTest(field=field):
                data = config(); data[field] = value
                with self.assertRaises(ValueError): tool.validate(data, 'android', 'com.takndev.kanbanconnect')

if __name__ == '__main__': unittest.main()
