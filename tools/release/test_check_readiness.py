import contextlib
import io
import json
import struct
import tempfile
import unittest
import zlib
from pathlib import Path
from unittest.mock import patch

import check_readiness as tool


def png(size=2, alpha=255, color=6):
    def chunk(tag, data):
        return struct.pack('>I', len(data)) + tag + data + struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff)
    pixel = bytes((15, 20, 30, alpha)) if color == 6 else bytes((15, 20, 30))
    other = bytes((30, 40, 50, alpha)) if color == 6 else bytes((30, 40, 50))
    row = b'\0' + pixel + other * (size - 1)
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', size, size, 8, color, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(row * size)) + chunk(b'IEND', b'')


class ReadinessTests(unittest.TestCase):
    def test_real_png_pixels_crc_and_opacity(self):
        with tempfile.TemporaryDirectory() as temp:
            icon = Path(temp) / 'icon.png'
            icon.write_bytes(png())
            tool.read_png(icon, 2, opaque=True)
            with self.assertRaises(ValueError):
                tool.read_png(icon, 3)
            icon.write_bytes(png(alpha=0))
            with self.assertRaises(ValueError):
                tool.read_png(icon, 2, opaque=True)
            icon.write_bytes(png()[:-1])
            with self.assertRaises(ValueError):
                tool.read_png(icon, 2)
            corrupted = bytearray(png())
            corrupted[-5] ^= 1
            icon.write_bytes(corrupted)
            with self.assertRaises(ValueError):
                tool.read_png(icon, 2)

    def test_png_header_without_pixels_is_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            icon = Path(temp) / 'icon.png'
            icon.write_bytes(png()[:33])
            with self.assertRaises(ValueError):
                tool.read_png(icon, 2)

    def test_rgb_icon_does_not_need_alpha_channel(self):
        with tempfile.TemporaryDirectory() as temp:
            icon = Path(temp) / 'icon.png'
            icon.write_bytes(png(color=2))
            tool.read_png(icon, 2, opaque=True)

    def test_public_url_rejects_placeholders_and_embedded_credentials(self):
        for url in (None, 'http://company.org/privacy', 'https://example.com/privacy', 'https://host.invalid/privacy', 'https://user:secret@company.org/privacy', 'https://127.0.0.1/privacy', 'https://company.org/privacy?token=secret'):
            with self.subTest(url=url):
                self.assertFalse(tool.public_url(url))
        self.assertTrue(tool.public_url('https://company.org/privacy'))

    def test_listing_limits_count_keyword_bytes_and_both_languages(self):
        listing = json.loads((tool.ROOT / 'docs/release/STORE_LISTINGS.json').read_text())
        self.assertTrue(tool.validate_listings(listing))
        listing['locales']['sl']['keywords'] = 'č' * 51
        self.assertFalse(tool.validate_listings(listing))
        listing['locales']['sl']['keywords'] = 'opravila'
        listing['locales']['en']['short_description'] = 'a' * 81
        self.assertFalse(tool.validate_listings(listing))

    def test_empty_attestations_cannot_pass_and_strings_are_not_booleans(self):
        with tempfile.TemporaryDirectory() as temp:
            failures = tool.input_checks({'controller_identity_confirmed': 'true'}, Path(temp), 'all')
            self.assertIn('controller_identity_confirmed', failures)
            self.assertIn('account_deletion_app_and_server_verified', failures)
            self.assertIn('Choose remote_push_enabled explicitly for this build', failures)

    def test_optional_push_does_not_require_firebase_but_enabled_push_does(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            data = json.loads((Path(tool.__file__).parent / 'release_inputs.example.json').read_text())
            data = {key: True if isinstance(value, bool) else value for key, value in data.items()}
            for field in ('privacy_policy_url', 'support_url', 'account_deletion_url'):
                data[field] = 'https://company.org/' + field
            data['remote_push_enabled'] = False
            self.assertEqual(tool.input_checks(data, root, 'ios'), [])
            data['remote_push_enabled'] = True
            self.assertIn('Public Firebase client configuration absent (contents not read)', tool.input_checks(data, root, 'ios'))

    def test_unknown_input_fields_do_not_echo_secrets(self):
        with tempfile.TemporaryDirectory() as temp:
            failures = tool.input_checks({'private_key': 'sensitive-sentinel'}, Path(temp), 'all')
            self.assertNotIn('sensitive-sentinel', str(failures))
            self.assertEqual(len(failures), 1)

    def test_signing_credential_argument_is_rejected_without_opening(self):
        output = io.StringIO()
        with patch.object(tool, 'source_checks', return_value=[]), patch.object(Path, 'read_text', side_effect=AssertionError('must not read secrets')), contextlib.redirect_stdout(output):
            result = tool.main(['--inputs', '/private/jivie-key.properties'])
        self.assertEqual(result, 1)
        self.assertNotIn('/private', output.getvalue())

    def test_old_id_and_debug_signing_are_caught_in_source(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            gradle = root / 'android/app/build.gradle.kts'
            gradle.parent.mkdir(parents=True)
            gradle.write_text('applicationId = "com.takndev.kanbanconnect"\nnamespace = "com.takndev.kanbanconnect"\ntargetSdk = 35\nsigningConfig = signingConfigs.getByName("debug")')
            failures = tool.source_checks(root)
            self.assertIn('Android application ID / namespace', failures)
            self.assertIn('Android release signing uses release keys', failures)
            self.assertIn('Android separate signing input and release guard', failures)
            self.assertIn('Android target API (36 or later)', failures)


if __name__ == '__main__':
    unittest.main()
