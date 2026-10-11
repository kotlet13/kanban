#!/usr/bin/env python3
"""Check a final, decoded Android manifest for unnecessary storage access."""
import argparse
from pathlib import Path
import xml.etree.ElementTree as ET

ANDROID = '{http://schemas.android.com/apk/res/android}'
TOOLS = '{http://schemas.android.com/tools}'
BROAD_STORAGE_PERMISSIONS = {
    'android.permission.READ_EXTERNAL_STORAGE',
    'android.permission.WRITE_EXTERNAL_STORAGE',
    'android.permission.MANAGE_EXTERNAL_STORAGE',
    'android.permission.READ_MEDIA_IMAGES',
    'android.permission.READ_MEDIA_VIDEO',
    'android.permission.READ_MEDIA_AUDIO',
    'android.permission.READ_MEDIA_VISUAL_USER_SELECTED',
}


def check_manifest(path):
    root = ET.parse(path).getroot()
    if root.tag != 'manifest' or not root.get('package'):
        raise ValueError('A final decoded manifest with an application ID is required')
    if any(key.startswith(TOOLS) for node in root.iter() for key in node.attrib):
        raise ValueError('Source merge directives remain; inspect the final merged manifest')
    permissions = {
        node.get(ANDROID + 'name', '')
        for node in root
        if node.tag in ('uses-permission', 'uses-permission-sdk-23')
    }
    return sorted(permissions & BROAD_STORAGE_PERMISSIONS)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('manifest', type=Path)
    args = parser.parse_args(argv)
    try:
        unexpected = check_manifest(args.manifest)
    except (OSError, ET.ParseError, ValueError) as error:
        print('BLOCKED: Cannot verify final Android manifest: ' + str(error))
        return 1
    if unexpected:
        print('BLOCKED: Broad storage/media permissions: ' + ', '.join(unexpected))
        return 1
    print('PASS: No broad storage/media permissions in final Android manifest.')
    print('This does not replace a device test of file picking, opening or sharing.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
