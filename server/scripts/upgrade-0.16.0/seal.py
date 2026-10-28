#!/usr/bin/env python3
"""Seal fresh production19 pins and exact current private source for schema23."""
from pathlib import Path
import argparse,datetime,hashlib,json,os,stat,time,zipfile,io
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
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('capture',type=Path);p.add_argument('output',type=Path);a=p.parse_args()
 m=json.loads(a.capture.read_text());guard(m['format']=='crypto23-capture-v1'and m['schema']==19,'capture_format')
 age=time.time()-datetime.datetime.fromisoformat(m['capturedUtc']).timestamp();guard(0<=age<=21600,'fresh_capture_required')
 profiles={'production':('jivie.triparna.si','jivie-production','tripar13_jivieprod','ad56910f-ca2e-41ee-af0d-3f18081497cf'),'test1':('jivie-test.triparna.si','jivie-test','tripar13_jivietest','95c11fe0-916c-48be-a3f6-999732846266')};guard(m['profile']in profiles,'reviewed_profile_guard')
 host,private,db,sid=profiles[m['profile']];guard(m['site']=='/home/tripar13/'+host and m['base']=='/home/tripar13/private/'+private and m['database']==db and m['serverId']==sid and m['config']==m['site']+'/config.php'and m['data']==m['base']+'/data','exact_profile_identity_guard')
 guard(m.get('preflight',{}).get('zipArchive')is True and m['preflight'].get('privateDataModes')is True and m['preflight'].get('cryptoRuntime',{}).get('signRoundtrip')is True,'fresh_capture_preflight_guard')
 old=json.loads((D/'old-source-manifest.json').read_text());guard(len(old)==107 and m['oldSource']==old,'exact_old015_107_source_required')
 out=a.output.absolute();guard(not out.exists()and not out.is_symlink(),'fresh_private_output');guard(not out.resolve().is_relative_to(R)and not out.resolve().is_relative_to(Path('/tmp')),'output_outside_repo_required')
 source=R/'server/plugins/FamilyHub';new={};buff=io.BytesIO()
 with zipfile.ZipFile(buff,'w',zipfile.ZIP_DEFLATED)as z:
  for path in sorted(source.rglob('*')):
   guard(not path.is_symlink(),'source_symlink');
   if path.is_dir():continue
   guard(stat.S_ISREG(path.stat().st_mode),'source_regular_file');body=path.read_bytes();name=path.relative_to(source).as_posix();guard(len(body)<=2097152,'source_size')
   ent=zipfile.ZipInfo('FamilyHub/'+name,(2026,10,28,0,0,0));ent.external_attr=0o100644<<16;ent.compress_type=zipfile.ZIP_DEFLATED;z.writestr(ent,body);new[name]=sha(body)
 # Retain public notice and update the same eight hosted contract paths explicitly.
 extra={'NOTICE.md':R/'tools/plugin_release/PUBLIC_NOTICE.md'}
 for name in ['account-deletion-contract.md','spaces-api-contract.md','linked-payments-api-contract.md','email-invitation-api-contract.md','space-sharing-api-contract.md','moderation-api-contract.md','ideas-api-contract.md','scope-lifecycle-api-contract.md']:extra['docs/'+name]=R/'docs/server'/name
 with zipfile.ZipFile(buff,'a',zipfile.ZIP_DEFLATED)as z:
  for name,path in sorted(extra.items()):
   guard(path.is_file()and not path.is_symlink()and name not in new,'public_contract_file');body=path.read_bytes();ent=zipfile.ZipInfo('FamilyHub/'+name,(2026,10,28,0,0,0));ent.external_attr=0o100644<<16;ent.compress_type=zipfile.ZIP_DEFLATED;z.writestr(ent,body);new[name]=sha(body)
 guard(len(new)>=191 and b"return '0.16.0'"in(source/'Plugin.php').read_bytes(),'version016_required')
 guard(b'const VERSION = 23;'in(source/'Schema/Mysql.php').read_bytes(),'schema23_source_required')
 oracle=json.loads((D/'schema-oracle.json').read_text());guard(len(oracle['newTables'])==127 and oracle['beforeCount']==98 and oracle['afterCount']==225,'schema_oracle_guard')
 out.mkdir(mode=0o700,parents=True);out.chmod(0o700)
 def write(name,b):
  with(out/name).open('xb')as f:f.write(b)
  (out/name).chmod(0o600)
 manifest=(json.dumps({'old':old,'new':dict(sorted(new.items()))},indent=2,sort_keys=True)+'\n').encode();archive=buff.getvalue();write('source-manifests.json',manifest);write('FamilyHub-0.16.0-source.zip',archive)
 work=m['base']+'/upgrade-0.16.0-'+time.strftime('%Y%m%d-%H%M%S',time.gmtime())
 vals={'SITE':m['site'],'BASE':m['base'],'WORK':work,'CONFIG':m['config'],'DATA':m['data'],'BACKUPS':m['base']+'/backups','CONFIG_SHA':m['configPin']['sha256'],'CONFIG_ENABLED_SHA':m['enabledConfigSha256'],'CONFIG_MODE':m['configPin']['mode'],'HTACCESS_SHA':m['htaccessPin']['sha256'],'MANIFEST':work+'/source-manifests.json','MANIFEST_SHA':sha(manifest),'SERVER_ID':m['serverId'],'DB_EXPECTED':m['database'],'ARCHIVE':work+'/FamilyHub-0.16.0-source.zip','ARCHIVE_SHA':sha(archive),'SOURCE_COUNT':len(new),'PUBLIC_URL':'https://'+host,'DELIVERY_FILES':m['deliveryFiles'],'DELIVERY_CONSTANTS_SHA':m['deliveryConstantsSha256'],'CRON_SHA':m['cronSha256'],'SCHEMA_ORACLE_SHA':sha((D/'schema-oracle.json').read_bytes())}
 write('deployment.php',('<?php\n// Fresh exact deployment pins; contains no credential values.\n'+''.join('const '+k+'='+php(v)+';\n'for k,v in vals.items())).encode())
 for name in ['backup.php','upgrade.php','maintenance.php','maintenance-guards.php','delivery-guards.php','operate.sh','crypto-runtime.php','crypto-config.php','schema-guards.php','schema-oracle.json','abort.php','abort.sh','public-check.php']:write(name,(D/name).read_bytes())
 write('capture.json',a.capture.read_bytes());print(json.dumps({'privateOutput':str(out),'hostWork':work,'sourceFiles':len(new),'oldHostedSourceFiles':107,'packageSha256':vals['ARCHIVE_SHA'],'manifestSha256':vals['MANIFEST_SHA']}))
if __name__=='__main__':
 try:main()
 except Exception as e:raise SystemExit('Seal stopped: '+(str(e)if isinstance(e,RuntimeError)else'private_inputs_guard'))
