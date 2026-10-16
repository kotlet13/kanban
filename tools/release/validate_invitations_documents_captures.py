#!/usr/bin/env python3
"""Validate genuine current Android screenshots and copy an ordered Play gallery.

No compositing, scaling, cropping or text overlays are performed.
"""
import hashlib
import json
import shutil
import zipfile
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
CAPTURES = ROOT/'build/qa/invitations-documents-store-20261016'
QA = ROOT/'build/qa/invitations-documents-release-20261016'
BASELINE = ROOT/'build/qa/upgrade-store-20261015/android-phone'
SCENES = ['01-pulse','02-planner','03-calendar','04-ideas','05-projects','06-shopping','07-garden','08-finances','09-spreadsheet','10-invitation']
GALLERY = ['01-pulse','02-planner','04-ideas','09-spreadsheet','05-projects','06-shopping','07-garden','08-finances']


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    freeze = json.loads((QA/'source-input-manifest.json').read_text())
    assert freeze['version'] == '1.10.0+30'
    for row in freeze['files']:
        assert digest(ROOT/row['path']) == row['sha256'], 'Current runtime differs from AAB: '+row['path']
    rows, gallery = [], []
    for locale in ['sl','en']:
        for scene in SCENES:
            path = CAPTURES/'android-phone'/locale/f'{scene}.png'
            with Image.open(path) as image:
                assert image.format == 'PNG' and image.size == (720,1280)
                image.load()
                if 'A' in image.getbands():
                    assert image.getchannel('A').getextrema() == (255,255)
                assert any(a != b for a,b in image.convert('RGB').getextrema())
            old = BASELINE/locale/f'{scene}.png'
            row = {'locale':locale,'scene':scene,'path':str(path.relative_to(ROOT)),'width':720,'height':1280,'bytes':path.stat().st_size,'sha256':digest(path),'samePixelsFileAsPrevious':old.exists() and digest(old)==digest(path)}
            rows.append(row)
        for index,scene in enumerate(GALLERY,1):
            source = CAPTURES/'android-phone'/locale/f'{scene}.png'
            destination = CAPTURES/'play-gallery'/locale/f'jivie-1.10-android-{locale}-{index:02d}-{scene[3:]}.png'
            destination.parent.mkdir(parents=True,exist_ok=True)
            shutil.copy2(source,destination)
            assert digest(source)==digest(destination)
            gallery.append({'locale':locale,'position':index,'scene':scene,'path':str(destination.relative_to(ROOT)),'sha256':digest(destination)})
    assert len(rows)==20 and len({r['sha256'] for r in rows})==20
    manifest = {'version':freeze['version'],'runtimeInputSha256':freeze['aggregateSha256'],'runtimeInputCount':len(freeze['files']),'captureKind':'current real Flutter widgets with isolated synthetic memory fixtures','physicalDeviceCapture':False,'pixelsEdited':False,'androidOnly':True,'galleryOrder':GALLERY,'gallery':gallery,'files':rows,'harnesses':[{'path':str(p.relative_to(ROOT)),'sha256':digest(p)} for p in sorted((ROOT/'tools/release').glob('*capture_test.dart')) if p.name.startswith(('upgrade_','invitations_documents'))]}
    for path in [CAPTURES/'manifest.json', ROOT/'docs/release/INVITATIONS_DOCUMENTS_1_10_SCREENSHOTS.json']:
        path.write_text(json.dumps(manifest,indent=2)+'\n')
    output=ROOT/'build/releases/Jivie-1.10.0+30-android-store-screenshots.zip'
    assert not output.exists(), 'Never replace an already prepared release ZIP'
    with zipfile.ZipFile(output,'w',zipfile.ZIP_DEFLATED) as archive:
        archive.write(CAPTURES/'manifest.json','manifest.json')
        for row in gallery:
            source=ROOT/row['path']
            archive.write(source,f"{row['locale']}/{source.name}")
    with zipfile.ZipFile(output) as archive:
        assert len(archive.namelist())==17 and archive.testzip() is None
    print(json.dumps({'captures':20,'galleryImages':16,'archive':str(output),'sha256':digest(output),'runtimeMatchesAab':True}))


if __name__ == '__main__':
    main()
