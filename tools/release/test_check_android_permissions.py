import tempfile
import unittest
from pathlib import Path

import check_android_permissions as tool


class AndroidPermissionTests(unittest.TestCase):
    def check(self, body):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'manifest.xml'
            path.write_text(
                '<manifest xmlns:android="http://schemas.android.com/apk/res/android" '
                'xmlns:tools="http://schemas.android.com/tools" '
                'package="si.triparna.jivie">' + body + '</manifest>'
            )
            return tool.check_manifest(path)

    def test_notifications_and_network_remain_allowed(self):
        self.assertEqual(self.check(''.join(
            f'<uses-permission android:name="android.permission.{name}"/>'
            for name in ('INTERNET', 'ACCESS_NETWORK_STATE', 'POST_NOTIFICATIONS',
                         'VIBRATE', 'WAKE_LOCK', 'RECEIVE_BOOT_COMPLETED')
        )), [])

    def test_every_broad_permission_is_blocked(self):
        for name in tool.BROAD_STORAGE_PERMISSIONS:
            with self.subTest(permission=name):
                self.assertEqual(self.check(
                    f'<uses-permission android:name="{name}"/>'
                ), [name])

    def test_older_android_limit_does_not_exempt_storage_access(self):
        name = 'android.permission.READ_EXTERNAL_STORAGE'
        self.assertEqual(self.check(
            f'<uses-permission android:name="{name}" android:maxSdkVersion="32"/>'
        ), [name])

    def test_sdk_23_permission_variant_is_checked(self):
        name = 'android.permission.READ_MEDIA_IMAGES'
        self.assertEqual(self.check(
            f'<uses-permission-sdk-23 android:name="{name}"/>'
        ), [name])

    def test_source_manifest_cannot_masquerade_as_final(self):
        with self.assertRaises(ValueError):
            self.check('<uses-permission android:name="android.permission.READ_MEDIA_IMAGES" '
                       'tools:node="remove"/>')


if __name__ == '__main__':
    unittest.main()
