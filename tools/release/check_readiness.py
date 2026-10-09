#!/usr/bin/env python3
"""Offline Jivie source/release-input checks. Never opens signing or server secrets."""
import argparse
import json
import plistlib
import re
import struct
import sys
import zlib
from pathlib import Path
from urllib.parse import urlsplit
from xml.etree import ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
APP_ID = 'si.triparna.jivie'
VERSION = '1.1.10+13'
ANDROID_NS = '{http://schemas.android.com/apk/res/android}'


def read_png(path, size, opaque=False):
    """Validate complete, bounded 8-bit noninterlaced PNGs and pixel opacity."""
    if path.stat().st_size > 16 * 1024 * 1024:
        raise ValueError('Oversized PNG')
    data = path.read_bytes()
    if len(data) > 16 * 1024 * 1024 or data[:8] != b'\x89PNG\r\n\x1a\n':
        raise ValueError('Invalid PNG')
    offset, header, compressed, palette, transparency, ended = 8, None, bytearray(), None, None, False
    while offset < len(data):
        if offset + 12 > len(data):
            raise ValueError('Truncated PNG')
        length = struct.unpack('>I', data[offset:offset + 4])[0]
        tag = data[offset + 4:offset + 8]
        payload = data[offset + 8:offset + 8 + length]
        next_offset = offset + 12 + length
        if next_offset > len(data) or zlib.crc32(tag + payload) & 0xffffffff != struct.unpack('>I', data[next_offset - 4:next_offset])[0]:
            raise ValueError('PNG CRC mismatch')
        if header is None and tag != b'IHDR':
            raise ValueError('Missing PNG header')
        if tag == b'IHDR':
            if header is not None or length != 13:
                raise ValueError('Invalid PNG header')
            header = struct.unpack('>IIBBBBB', payload)
        elif tag == b'IDAT':
            compressed.extend(payload)
        elif tag == b'PLTE':
            palette = payload
        elif tag == b'tRNS':
            transparency = payload
        elif tag == b'IEND':
            if length or next_offset != len(data):
                raise ValueError('Invalid PNG end')
            ended = True
            break
        offset = next_offset
    if not ended or not header:
        raise ValueError('Incomplete PNG')
    width, height, depth, color, compression, filtering, interlace = header
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}.get(color)
    if (width, height) != (size, size) or size > 2048 or depth != 8 or not channels or compression or filtering or interlace:
        raise ValueError('Wrong size or unsupported PNG encoding')
    stride = width * channels
    expected = height * (stride + 1)
    decoder = zlib.decompressobj()
    raw = decoder.decompress(compressed, expected + 1)
    if len(raw) != expected or not decoder.eof or decoder.unused_data or decoder.unconsumed_tail:
        raise ValueError('Invalid PNG pixels')
    previous = bytearray(stride)
    colors = set()
    for y in range(height):
        start = y * (stride + 1)
        mode = raw[start]
        if mode > 4:
            raise ValueError('Invalid PNG filter')
        row = bytearray(raw[start + 1:start + 1 + stride])
        for i in range(stride):
            left = row[i - channels] if i >= channels else 0
            above = previous[i]
            upper_left = previous[i - channels] if i >= channels else 0
            prediction = left + above - upper_left
            distances = [abs(prediction - value) for value in (left, above, upper_left)]
            paeth = (left, above, upper_left)[distances.index(min(distances))]
            addition = (0, left, above, (left + above) // 2, paeth)[mode]
            row[i] = (row[i] + addition) & 255
        for i in range(0, stride, channels):
            pixel = bytes(row[i:i + channels])
            alpha = pixel[-1] if color in (4, 6) else 255
            if color == 3:
                index = pixel[0]
                if palette is None or len(palette) % 3 or index * 3 + 3 > len(palette):
                    raise ValueError('Invalid PNG palette')
                alpha = transparency[index] if transparency is not None and index < len(transparency) else 255
                pixel = palette[index * 3:index * 3 + 3]
            elif transparency is not None and color in (0, 2):
                values = tuple(struct.unpack('>' + 'H' * channels, transparency))
                if tuple(pixel) == values:
                    alpha = 0
            if opaque and alpha != 255:
                raise ValueError('Transparent app icon')
            if len(colors) < 2:
                colors.add(pixel)
        previous = row
    if len(colors) < 2:
        raise ValueError('Blank single-color app icon')


def source_checks(root):
    failures = []

    def check(name, action):
        try:
            if not action():
                failures.append(name)
        except (ValueError, KeyError, TypeError, AttributeError, OverflowError, OSError, ET.ParseError, plistlib.InvalidFileException, struct.error, zlib.error):
            failures.append(name)

    gradle_path = root / 'android/app/build.gradle.kts'
    try:
        gradle = gradle_path.read_text() if gradle_path.is_file() else ''
    except OSError:
        gradle = ''
    check('Android application ID / namespace', lambda: re.findall(r'\bapplicationId\s*=\s*"([^"\n]+)"', gradle) == [APP_ID] and re.findall(r'\bnamespace\s*=\s*"([^"\n]+)"', gradle) == [APP_ID] and 'applicationIdSuffix' not in gradle and 'productFlavors' not in gradle)
    check('Android target API (36 or later)', lambda: any(int(v) >= 36 for v in re.findall(r'\btargetSdk\s*=\s*(\d+)', gradle)))
    check('Android separate signing input and release guard', lambda: 'jivie-key.properties' in gradle and not re.search(r'rootProject\.file\("key\.properties"\)', gradle) and 'validateReleaseSigning' in gradle and 'preReleaseBuild' in gradle and 'dependsOn(validateReleaseSigning)' in gradle and 'GradleException' in gradle and all(k in gradle for k in ('storeFile', 'storePassword', 'keyAlias', 'keyPassword', APP_ID)) and 'if (!hasReleaseSigning)' in gradle and 'keystoreProperties.getProperty("applicationId") != jivieApplicationId' in gradle and 'releaseKeystoreFile?.isFile != true' in gradle)
    check('Android release signing uses release keys', lambda: 'signingConfig = signingConfigs.getByName("release")' in gradle and not re.search(r'signingConfig\s*=.*(?:getByName|findByName)\("debug"\)', gradle))

    def android_label():
        app = ET.parse(root / 'android/app/src/main/AndroidManifest.xml').getroot().find('application')
        return app is not None and app.get(ANDROID_NS + 'label') == 'Jivie' and app.get(ANDROID_NS + 'icon') == '@mipmap/ic_launcher'

    check('Android label and launcher reference', android_label)
    check('Android MainActivity package', lambda: re.search(r'^package\s+' + re.escape(APP_ID) + r'\s*$', (root / 'android/app/src/main/kotlin/si/triparna/jivie/MainActivity.kt').read_text(), re.M) is not None)
    for density, size in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)]:
        check(f'Android {density} icon', lambda density=density, size=size: read_png(root / f'android/app/src/main/res/mipmap-{density}/ic_launcher.png', size) is None)

    def ios_identity():
        project = (root / 'ios/Runner.xcodeproj/project.pbxproj').read_text()
        blocks = re.findall(r'buildSettings\s*=\s*\{(.*?)\};', project, re.S)
        ids = []
        for block in blocks:
            if re.search(r'INFOPLIST_FILE\s*=\s*"?Runner/Info\.plist"?;', block):
                ids.extend(re.findall(r'PRODUCT_BUNDLE_IDENTIFIER\s*=\s*"?([^;"\n]+)"?;', block))
        all_ids = re.findall(r'PRODUCT_BUNDLE_IDENTIFIER\s*=\s*"?([^;"\n]+)"?;', project)
        return len(ids) >= 3 and set(v.strip() for v in ids) == {APP_ID} and set(v.strip() for v in all_ids) <= {APP_ID, APP_ID + '.RunnerTests'}

    check('iOS Runner bundle identifiers', ios_identity)

    def ios_label():
        with (root / 'ios/Runner/Info.plist').open('rb') as handle:
            info = plistlib.load(handle)
        return info.get('CFBundleDisplayName') == 'Jivie' and info.get('CFBundleName') == 'Jivie'

    check('iOS display / bundle name', ios_label)

    def ios_icons():
        folder = root / 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
        images = json.loads((folder / 'Contents.json').read_text())['images']
        if not images or not any(v.get('idiom') == 'ios-marketing' and v.get('size') == '1024x1024' for v in images):
            return False
        for icon in images:
            filename = icon['filename']
            if Path(filename).name != filename:
                return False
            dimensions = icon['size'].split('x')
            if len(dimensions) != 2 or dimensions[0] != dimensions[1]:
                return False
            pixels = float(dimensions[0]) * float(icon['scale'].removesuffix('x'))
            if not pixels.is_integer():
                return False
            read_png(folder / filename, int(pixels), opaque=True)
        return True

    check('iOS app icons, catalog sizes, opacity and pixels', ios_icons)
    check('Current Jivie release version', lambda: re.search(r'^version:\s*' + re.escape(VERSION) + r'\s*$', (root / 'pubspec.yaml').read_text(), re.M) is not None)
    for locale in ('sl', 'en'):
        check(f'{locale} app title', lambda locale=locale: json.loads((root / f'lib/l10n/app_{locale}.arb').read_text()).get('organizerAppName') == 'Jivie')
    check('SL/EN store listing limits', lambda: validate_listings(json.loads((root / 'docs/release/STORE_LISTINGS.json').read_text())))
    return failures


def validate_listings(data):
    if not isinstance(data, dict) or data.get('price') != 'free' or data.get('version') != VERSION:
        return False
    for locale in ('sl', 'en'):
        listing = data['locales'][locale]
        for key, limit in [('name', 30), ('subtitle', 30), ('short_description', 80), ('promotional_text', 170), ('description', 4000)]:
            value = listing[key]
            if not isinstance(value, str) or not value.strip() or len(value) > limit:
                return False
        if listing['name'] != 'Jivie' or len(listing['keywords'].encode('utf-8')) > 100:
            return False
    return True


def public_url(value):
    if not isinstance(value, str):
        return False
    url = urlsplit(value)
    host = (url.hostname or '').lower()
    return bool(url.scheme == 'https' and '.' in host and not url.username and not url.password and not url.query and not url.fragment and host not in ('example.com', 'example.org', 'example.net', 'localhost') and not host.endswith(('.example', '.invalid', '.test', '.localhost')) and not re.fullmatch(r'[\d.]+', host) and not any(c.isspace() for c in value))


def input_checks(data, root, platform):
    """Inputs are public URLs and attestations, never private signing material."""
    failures = []
    if not isinstance(data, dict):
        return ['Release inputs must be a public JSON object']
    # Unknown fields are rejected so this file cannot become a secret repository.
    schema = json.loads((Path(__file__).parent / 'release_inputs.example.json').read_text())
    if set(data) - set(schema):
        return ['Unknown release-input fields; use the public template (no secrets)']
    for field in ('privacy_policy_url', 'support_url', 'account_deletion_url'):
        if not public_url(data.get(field)):
            failures.append(field)
    common = ('controller_identity_confirmed', 'store_accounts_verified', 'name_rights_reviewed', 'privacy_inventory_reviewed', 'account_deletion_app_and_server_verified', 'review_access_verified', 'store_screenshots_verified', 'backup_roundtrip_verified')
    android = ('physical_android_verified', 'android_upload_signing_verified', 'android_aab_and_16kb_verified')
    ios = ('physical_ios_verified', 'ios_distribution_signing_verified', 'ios_archive_privacy_manifest_verified', 'ios_current_sdk_verified')
    fields = list(common) + (list(android) if platform in ('all', 'android') else []) + (list(ios) if platform in ('all', 'ios') else [])
    for field in fields:
        if data.get(field) is not True:
            failures.append(field)
    if platform in ('all', 'android') and not (root / 'android/jivie-key.properties').is_file():
        failures.append('Private Android Jivie signing input absent (contents not read)')
    remote = data.get('remote_push_enabled')
    if type(remote) is not bool:
        failures.append('Choose remote_push_enabled explicitly for this build')
    elif remote:
        if not (root / '.firebase/client.json').is_file():
            failures.append('Public Firebase client configuration absent (contents not read)')
        if platform in ('all', 'android') and not (root / 'android/app/src/main/res/values/firebase_config.xml').is_file():
            failures.append('Native Android Firebase configuration absent (contents not read)')
        push_fields = ['firebase_client_and_server_project_verified', 'physical_remote_push_verified']
        if platform in ('all', 'ios'):
            push_fields.append('apns_production_verified')
        for field in push_fields:
            if data.get(field) is not True:
                failures.append(field)
    return failures


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=ROOT)
    parser.add_argument('--code-only', action='store_true', help='Source checks only; never declares a release ready')
    parser.add_argument('--inputs', type=Path, help='Public checklist JSON; never pass a credential file')
    parser.add_argument('--platform', choices=('all', 'android', 'ios'), default='all', help='Release attestations to require; source checks always cover both platforms')
    args = parser.parse_args(argv)
    failures = source_checks(args.root)
    if not args.code_only:
        if args.inputs is None:
            failures.append('Release inputs missing; copy the public template and record verified evidence')
        elif args.inputs.name.endswith(('.properties', '.p8', '.jks', '.keystore', '.plist')) or 'service-account' in args.inputs.name or 'firebase-adminsdk' in args.inputs.name:
            failures.append('Credential input refused; provide only the public checklist JSON')
        else:
            try:
                # Explicit public input; no path, values or parse error is echoed.
                if args.inputs.stat().st_size > 32 * 1024:
                    raise ValueError('Oversized inputs')
                failures.extend(input_checks(json.loads(args.inputs.read_text()), args.root, args.platform))
            except (OSError, ValueError, TypeError):
                failures.append('Release-input JSON missing or invalid; contents not printed')
    for failure in failures:
        print('BLOCKED: ' + failure)
    if failures:
        print('Preparation incomplete. No build, upload, network request or secret inspection performed.')
        return 1
    print('Source checks passed.' if args.code_only else 'Source checks and recorded attestations passed; independently verify signed artifacts and store review.')
    print('This is not a store approval, device test, signing verification or name/domain clearance.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
