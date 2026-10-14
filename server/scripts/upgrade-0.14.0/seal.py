#!/usr/bin/env python3
"""Seal fresh host pins plus immutable source package into a private per-host helper directory."""
from pathlib import Path
import argparse,hashlib,json,os,re,stat,subprocess,time,zipfile
os.umask(0o077)
D=Path(__file__).resolve().parent;R=D.parents[2]
def guard(ok,code):
 if not ok:raise RuntimeError(code)
def sha(b):return hashlib.sha256(b).hexdigest()
def php(v):
 if isinstance(v,str):return "'"+v.replace('\\','\\\\').replace("'","\\'")+"'"
 if isinstance(v,int):return str(v)
 if isinstance(v,dict):return '['+','.join(php(k)+'=>'+php(x)for k,x in v.items())+']'
 raise RuntimeError('pin_type_guard')
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('capture',type=Path);p.add_argument('package',type=Path);p.add_argument('output',type=Path);p.add_argument('--baseline-repo',type=Path,default=Path('/Users/anzenovsak/Git/kanban_family_hub'));a=p.parse_args()
 m=json.loads(a.capture.read_text());guard(m['format']=='lifecycle18-capture-v1' and m['schema']==17,'capture_format')
 age=time.time()-__import__('datetime').datetime.fromisoformat(m['capturedUtc']).timestamp();guard(0<=age<=21600,'fresh_capture_required')
 guard(m['profile']in ['production','test1'],'reviewed_profile_guard')
 profiles={'production':('jivie.triparna.si','jivie-production','tripar13_jivieprod','ad56910f-ca2e-41ee-af0d-3f18081497cf'),'test1':('jivie-test.triparna.si','jivie-test','tripar13_jivietest','95c11fe0-916c-48be-a3f6-999732846266')}
 host,private,db,sid=profiles[m['profile']];guard(m['site']=='/home/tripar13/'+host and m['base']=='/home/tripar13/private/'+private and m['database']==db and m['serverId']==sid and m['config']==m['site']+'/config.php' and m['data']==m['base']+'/data','exact_profile_identity_guard')
 out=a.output.absolute();guard(not out.exists() and not out.is_symlink(),'fresh_private_output')
 guard(not out.resolve().is_relative_to(R) and not out.resolve().is_relative_to(Path('/tmp')),'output_outside_repo_required')
 old=json.loads((R/'server/scripts/reviewer-test1/source-manifests.json').read_text())['new'];guard(len(old)==96,'baseline96')
 commit=subprocess.check_output(['git','-C',str(a.baseline_repo),'rev-parse','v0.13.0^{commit}'],text=True).strip();guard(commit=='7571d1be1554255f6b702e6fe895af2b3b9ee81a','immutable_baseline_commit')
 for name,pin in old.items():
  if not (name.endswith('.php') or name=='LICENSE'):continue
  body=subprocess.check_output(['git','-C',str(a.baseline_repo),'show','v0.13.0:'+name]);guard(sha(body)==pin,'published_baseline_hash')
 guard(m['oldSource']==old,'live_baseline96_required')
 source=json.loads((R/'tools/plugin_release/source_manifest.json').read_text());names=set(source)|{n for n in old if not (n.endswith('.php') or n=='LICENSE')}|{'docs/scope-lifecycle-api-contract.md'}
 with zipfile.ZipFile(a.package)as z:
  guard(z.testzip()is None,'package_crc');new={};seen=set()
  for ent in z.infolist():
   guard(ent.filename.startswith('FamilyHub/') and stat.S_ISREG(ent.external_attr>>16),'package_type')
   name=ent.filename[10:];guard(name in names and name not in seen and len(z.read(ent))<=2097152,'package_allowlist');seen.add(name);new[name]=sha(z.read(ent))
   expected=(R/'tools/plugin_release/PUBLIC_README.md') if name=='README.md' else ((R/'docs/server'/name[5:]) if name.startswith('docs/') else R/'server/plugins/FamilyHub'/name)
   guard(not expected.is_symlink() and expected.is_file() and sha(expected.read_bytes())==new[name],'frozen_current_source_or_public_contract_hash')
  guard(seen==names,'package_exact_manifest');guard(b"return '0.14.0'" in z.read('FamilyHub/Plugin.php'),'version014_required')
 out.mkdir(mode=0o700,parents=True);out.chmod(0o700)
 def write(name,b):
  with(out/name).open('xb')as f:f.write(b)
  (out/name).chmod(0o600)
 manifest=(json.dumps({'old':old,'new':dict(sorted(new.items()))},indent=2,sort_keys=True)+'\n').encode();write('source-manifests.json',manifest);write('FamilyHub-0.14.0-source.zip',a.package.read_bytes())
 work=m['base']+'/upgrade-0.14.0-'+time.strftime('%Y%m%d-%H%M%S',time.gmtime())
 vals={'SITE':m['site'],'BASE':m['base'],'WORK':work,'CONFIG':m['config'],'DATA':m['data'],'BACKUPS':m['base']+'/backups','CONFIG_SHA':m['configPin']['sha256'],'CONFIG_MODE':m['configPin']['mode'],'HTACCESS_SHA':m['htaccessPin']['sha256'],'MANIFEST':work+'/source-manifests.json','MANIFEST_SHA':sha(manifest),'SERVER_ID':m['serverId'],'DB_EXPECTED':m['database'],'ARCHIVE':work+'/FamilyHub-0.14.0-source.zip','ARCHIVE_SHA':sha(a.package.read_bytes()),'SOURCE_COUNT':len(new),'PUBLIC_URL':'https://'+m['site'].split('/')[-1],'DELIVERY_FILES':m['deliveryFiles'],'DELIVERY_CONSTANTS_SHA':m['deliveryConstantsSha256'],'CRON_SHA':m['cronSha256']}
 write('deployment.php',('<?php\n// Fresh exact deployment pins; contains no credential values.\n'+''.join('const '+k+'='+php(v)+';\n'for k,v in vals.items())).encode())
 for name in ['backup.php','upgrade.php','maintenance.php','maintenance-guards.php','delivery-guards.php','operate.sh']:write(name,(D/name).read_bytes())
 write('capture.json',a.capture.read_bytes());print(json.dumps({'privateOutput':str(out),'hostWork':work,'sourceFiles':len(new),'packageSha256':vals['ARCHIVE_SHA'],'manifestSha256':vals['MANIFEST_SHA'],'baselineCommit':commit}))
if __name__=='__main__':
 try:main()
 except Exception as e:raise SystemExit('Seal stopped: '+(str(e)if isinstance(e,RuntimeError)else'private_inputs_guard'))
