#!/usr/bin/env python3
"""Seal current per-host evidence and exact reviewed0.15 source into a fresh private deployment."""
from pathlib import Path
import argparse,datetime,hashlib,json,os,re,stat,subprocess,time,zipfile
os.umask(0o077)
D=Path(__file__).resolve().parent;R=D.parents[2]
OLD_PACKAGE_SHA='e6fda75ac4b63c74f70cd2ac00fb6143006cbe111a96a8462e30db9a945a3743'
BASELINE_COMMIT='59119dc594f941cada5ede73435c1d9a2fda990c'
CONTRACTS={'docs/'+n for n in ['account-deletion-contract.md','spaces-api-contract.md','linked-payments-api-contract.md','email-invitation-api-contract.md','space-sharing-api-contract.md','moderation-api-contract.md','ideas-api-contract.md','scope-lifecycle-api-contract.md']}
def guard(ok,code):
 if not ok:raise RuntimeError(code)
def sha(b):return hashlib.sha256(b).hexdigest()
def php(v):
 if isinstance(v,str):return "'"+v.replace('\\','\\\\').replace("'","\\'")+"'"
 if isinstance(v,int):return str(v)
 if isinstance(v,dict):return '['+','.join(php(k)+'=>'+php(x)for k,x in v.items())+']'
 raise RuntimeError('pin_type_guard')
def baseline(package,repo):
 guard(sha(package.read_bytes())==OLD_PACKAGE_SHA,'immutable_old101_package_sha')
 old=json.loads((R/'server/scripts/sound-default-0.14.1/old-manifest.json').read_text());guard(len(old)==101,'baseline101')
 commit=subprocess.check_output(['git','-C',str(repo),'rev-parse','v0.14.1^{commit}'],text=True).strip();guard(commit==BASELINE_COMMIT,'immutable_baseline0141_commit')
 with zipfile.ZipFile(package)as z:
  guard(z.testzip()is None and {e.filename for e in z.infolist()}=={'FamilyHub/'+n for n in old},'immutable_old_package_entries')
  for name,pin in list(old.items()):
   body=z.read('FamilyHub/'+name);guard(sha(body)==pin,'old_package_manifest_hash')
   if name=='Model/NativeNotificationPreferences.php':body=body.replace(b"'sound' => false",b"'sound' => true")
   elif name=='Model/NativePushWorker.php':body=body.replace(b"($settings['sound'] ?? false)",b"($settings['sound'] ?? true)")
   elif name=='Plugin.php':body=body.replace(b"return '0.14.0'",b"return '0.14.1'")
   old[name]=sha(body)
   if name.endswith('.php')or name=='LICENSE':
    public=subprocess.check_output(['git','-C',str(repo),'show',BASELINE_COMMIT+':'+name]);guard(public==body,'immutable_public0141_php_license_hash')
 return old

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('capture',type=Path);p.add_argument('package',type=Path);p.add_argument('output',type=Path);p.add_argument('--baseline-repo',type=Path,default=Path('/Users/anzenovsak/Git/kanban_family_hub'));p.add_argument('--old-package',type=Path,default=R/'build/release/FamilyHub-0.14.0-upgrade-20261014.zip');a=p.parse_args()
 m=json.loads(a.capture.read_text());guard(m['format']=='documents19-capture-v1'and m['schema']==18,'capture_format')
 age=time.time()-datetime.datetime.fromisoformat(m['capturedUtc']).timestamp();guard(0<=age<=21600,'fresh_capture_required')
 profiles={'production':('jivie.triparna.si','jivie-production','tripar13_jivieprod','ad56910f-ca2e-41ee-af0d-3f18081497cf'),'test1':('jivie-test.triparna.si','jivie-test','tripar13_jivietest','95c11fe0-916c-48be-a3f6-999732846266')};guard(m['profile']in profiles,'reviewed_profile_guard')
 host,private,db,sid=profiles[m['profile']];guard(m['site']=='/home/tripar13/'+host and m['base']=='/home/tripar13/private/'+private and m['database']==db and m['serverId']==sid and m['config']==m['site']+'/config.php'and m['data']==m['base']+'/data','exact_profile_identity_guard')
 guard(m.get('preflight',{}).get('zipArchive')is True and m['preflight'].get('privateDataModes')is True,'fresh_capture_preflight_guard')
 old=baseline(a.old_package,a.baseline_repo);guard(m['oldSource']==old,'live_baseline101_with_exact_three0141_patches_required')
 out=a.output.absolute();guard(not out.exists()and not out.is_symlink(),'fresh_private_output');guard(not out.resolve().is_relative_to(R)and not out.resolve().is_relative_to(Path('/tmp')),'output_outside_repo_required')
 source=json.loads((R/'tools/plugin_release/source_manifest.json').read_text());names=set(source)|CONTRACTS|{'NOTICE.md'}
 guard({'DOCUMENTS_API.md','Model/NativeAttachmentService.php','Model/NativeDocumentService.php','Model/NativeTableService.php','Schema/DocumentsSchema.php'}<=set(source),'reviewed_documents_allowlist_required')
 with zipfile.ZipFile(a.package)as z:
  guard(z.testzip()is None,'package_crc');new={};seen=set()
  for ent in z.infolist():
   guard(ent.filename.startswith('FamilyHub/')and stat.S_ISREG(ent.external_attr>>16),'package_type');name=ent.filename[10:]
   guard(name in names and name not in seen and len(z.read(ent))<=2097152,'package_allowlist');seen.add(name);new[name]=sha(z.read(ent))
   if name=='NOTICE.md':
    expected_body=subprocess.check_output(['git','-C',str(a.baseline_repo),'show',BASELINE_COMMIT+':NOTICE.md'])
    guard(sha(expected_body)==new[name],'immutable_public_notice_hash')
   else:
    expected=(R/'tools/plugin_release/PUBLIC_README.md')if name=='README.md'else((R/'docs/server'/name[5:])if name.startswith('docs/')else R/'server/plugins/FamilyHub'/name)
    guard(not expected.is_symlink()and expected.is_file()and sha(expected.read_bytes())==new[name],'frozen_current_source_or_public_contract_hash')
  guard(seen==names,'package_exact_manifest');guard(b"return '0.15.0'"in z.read('FamilyHub/Plugin.php'),'version015_required')
 out.mkdir(mode=0o700,parents=True);out.chmod(0o700)
 def write(name,b):
  with(out/name).open('xb')as f:f.write(b)
  (out/name).chmod(0o600)
 manifest=(json.dumps({'old':old,'new':dict(sorted(new.items()))},indent=2,sort_keys=True)+'\n').encode();write('source-manifests.json',manifest);write('FamilyHub-0.15.0-source.zip',a.package.read_bytes())
 work=m['base']+'/upgrade-0.15.0-'+time.strftime('%Y%m%d-%H%M%S',time.gmtime())
 vals={'SITE':m['site'],'BASE':m['base'],'WORK':work,'CONFIG':m['config'],'DATA':m['data'],'BACKUPS':m['base']+'/backups','CONFIG_SHA':m['configPin']['sha256'],'CONFIG_MODE':m['configPin']['mode'],'HTACCESS_SHA':m['htaccessPin']['sha256'],'MANIFEST':work+'/source-manifests.json','MANIFEST_SHA':sha(manifest),'SERVER_ID':m['serverId'],'DB_EXPECTED':m['database'],'ARCHIVE':work+'/FamilyHub-0.15.0-source.zip','ARCHIVE_SHA':sha(a.package.read_bytes()),'SOURCE_COUNT':len(new),'PUBLIC_URL':'https://'+host,'DELIVERY_FILES':m['deliveryFiles'],'DELIVERY_CONSTANTS_SHA':m['deliveryConstantsSha256'],'CRON_SHA':m['cronSha256'],'DOCUMENT_TABLES_SHA':sha((D/'document-tables.php').read_bytes())}
 write('deployment.php',('<?php\n// Fresh exact deployment pins; contains no credential values.\n'+''.join('const '+k+'='+php(v)+';\n'for k,v in vals.items())).encode())
 for name in ['backup.php','upgrade.php','maintenance.php','maintenance-guards.php','delivery-guards.php','operate.sh','abort.php','abort.sh','document-tables.php']:write(name,(D/name).read_bytes())
 write('capture.json',a.capture.read_bytes());print(json.dumps({'privateOutput':str(out),'hostWork':work,'sourceFiles':len(new),'oldHostedSourceFiles':101,'packageSha256':vals['ARCHIVE_SHA'],'manifestSha256':vals['MANIFEST_SHA'],'baselineCommit':BASELINE_COMMIT}))
if __name__=='__main__':
 try:main()
 except Exception as e:raise SystemExit('Seal stopped: '+(str(e)if isinstance(e,RuntimeError)else'private_inputs_guard'))
