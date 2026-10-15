#!/usr/bin/env python3
"""Seal exact profiles and only three reviewed PHP changes into private code-patch inputs."""
import argparse,datetime,hashlib,json,os,subprocess,time,zipfile
from pathlib import Path
os.umask(0o077)
D=Path(__file__).resolve().parent;R=D.parents[2]
OLD_PACKAGE_SHA='e6fda75ac4b63c74f70cd2ac00fb6143006cbe111a96a8462e30db9a945a3743'
FILES=['Model/NativePushWorker.php','Model/NativeNotificationPreferences.php','Plugin.php']
PROFILES={'production':('/home/tripar13/jivie.triparna.si','/home/tripar13/private/jivie-production','tripar13_jivieprod','ad56910f-ca2e-41ee-af0d-3f18081497cf'),'test1':('/home/tripar13/jivie-test.triparna.si','/home/tripar13/private/jivie-test','tripar13_jivietest','95c11fe0-916c-48be-a3f6-999732846266')}
def guard(ok,code):
 if not ok:raise RuntimeError(code)
def sha(b):return hashlib.sha256(b).hexdigest()
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('capture',type=Path);p.add_argument('output',type=Path);p.add_argument('--source',type=Path,default=R/'server/plugins/FamilyHub');p.add_argument('--host-work',help='Exact fresh private hosted work directory, if already prepared');p.add_argument('--old-package',type=Path,default=R/'build/release/FamilyHub-0.14.0-upgrade-20261014.zip');a=p.parse_args()
 capture=json.loads(a.capture.read_text());guard(capture['format']=='sound-default-code-patch-capture-v1' and capture['profile']in PROFILES,'capture_profile_format')
 site,base,database,sid=PROFILES[capture['profile']];guard(capture['snapshot']['serverId']==sid and capture['snapshot']['schema']==18,'fixed_profile_identity')
 age=time.time()-datetime.datetime.fromisoformat(capture['createdUtc']).timestamp();guard(-300<=age<=21600,'fresh_capture_required')
 guard(sha(a.old_package.read_bytes())==OLD_PACKAGE_SHA,'immutable_old101_package_sha');old=json.loads((D/'old-manifest.json').read_text());guard(len(old)==101,'old101_manifest')
 new=dict(old);bodies={}
 with zipfile.ZipFile(a.old_package)as z:
  guard(z.testzip()is None and {e.filename[10:]for e in z.infolist()}==set(old),'old_package_entries')
  for name,pin in old.items():guard(sha(z.read('FamilyHub/'+name))==pin,'old_package_file_sha')
  for name in FILES:
   body=(a.source/name).read_bytes();before=z.read('FamilyHub/'+name)
   expected=before.replace(b"'sound' => false",b"'sound' => true")if name.endswith('NativeNotificationPreferences.php')else(before.replace(b"($settings['sound'] ?? false)",b"($settings['sound'] ?? true)")if name.endswith('NativePushWorker.php')else before.replace(b"return '0.14.0'",b"return '0.14.1'"))
   guard(body==expected and body!=before,'exact_three_reviewed_line_changes');bodies[name]=body;new[name]=sha(body)
 out=a.output.absolute();guard(not out.exists()and not out.is_symlink()and not out.resolve().is_relative_to(R),'fresh_private_output_outside_git');out.mkdir(mode=0o700,parents=True);out.chmod(0o700)
 work=a.host_work or base+'/sound-default-0.14.1-'+time.strftime('%Y%m%d-%H%M%S',time.gmtime())
 guard(__import__('re').fullmatch(__import__('re').escape(base)+r'/sound-default-0\.14\.1-[0-9]{8}-[0-9]{6}',work)is not None,'exact_private_host_work')
 pins={'format':'sound-default-code-patch-v1','capture':capture,'oldPackageSha256':OLD_PACKAGE_SHA,'newManifest':new};data=(json.dumps(pins,indent=2)+'\n').encode()
 def write(name,body):
  f=out/name;f.parent.mkdir(mode=0o700,parents=True,exist_ok=True)
  with f.open('xb')as stream:stream.write(body)
  f.chmod(0o600)
 write('pins.json',data);write('deployment.php',("<?php\nconst PATCH_WORK='"+work+"';\nconst PATCH_PINS_SHA='"+sha(data)+"';\n").encode())
 for name in ['common.php','patch.php','run.sh','old-manifest.json']:write(name,(D/name).read_bytes())
 for name,body in bodies.items():write('files/'+name,body)
 print(json.dumps({'privateOutput':str(out),'hostWork':work,'pinsSha256':sha(data),'sourceFiles':101,'changedPhpFiles':FILES,'oldPackageSha256':OLD_PACKAGE_SHA,'newFileHashes':{n:new[n]for n in FILES}}))
if __name__=='__main__':
 try:main()
 except Exception as e:raise SystemExit('Code-patch seal stopped: '+(str(e)if isinstance(e,RuntimeError)else'private_inputs_guard'))
