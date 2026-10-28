#!/usr/bin/env python3
"""Seal one read-only schema23 production capture. No secrets or hosting calls."""
from pathlib import Path
import argparse,datetime,hashlib,json,os,time
os.umask(0o077)
D=Path(__file__).resolve().parent;R=D.parents[2]
def require(v,code):
    if not v:raise RuntimeError(code)
def sha(b):return hashlib.sha256(b).hexdigest()
def php(v):
    if isinstance(v,str):return "'"+v.replace('\\','\\\\').replace("'","\\'")+"'"
    if isinstance(v,bool):return 'true' if v else 'false'
    if isinstance(v,int):return str(v)
    if isinstance(v,list):return '['+','.join(php(x) for x in v)+']'
    if isinstance(v,dict):return '['+','.join(php(k)+'=>'+php(x) for k,x in v.items())+']'
    raise RuntimeError('unsupported_pin_type')
def main():
    p=argparse.ArgumentParser();p.add_argument('capture',type=Path);p.add_argument('output',type=Path);a=p.parse_args();m=json.loads(a.capture.read_text())
    require(m['format']=='fresh-reset23-capture-v1' and m['schema']==23,'capture_version');age=time.time()-datetime.datetime.fromisoformat(m['capturedUtc']).timestamp();require(0<=age<=21600,'fresh_capture')
    profiles={'production':('jivie.triparna.si','jivie-production','tripar13_jivieprod','ad56910f-ca2e-41ee-af0d-3f18081497cf'),'test1':('jivie-test.triparna.si','jivie-test','tripar13_jivietest','95c11fe0-916c-48be-a3f6-999732846266')};host,private,db,sid=profiles[m['profile']]
    require(m['site']=='/home/tripar13/'+host and m['base']=='/home/tripar13/private/'+private and m['database']==db and m['serverId']==sid and m['config']==m['site']+'/config.php' and m['data']==m['base']+'/data','fixed_target')
    require(m['htaccessPin']['mode']==0o644,'reviewed_https_mode644');require(len(m['users'])==3 and all(u['role']=='app-user' and isinstance(u['id'],int) for u in m['users']),'exact_three_nonadmin_accounts')
    source={p.relative_to(R/'server/plugins/FamilyHub').as_posix():sha(p.read_bytes()) for p in sorted((R/'server/plugins/FamilyHub').rglob('*')) if p.is_file() and not p.is_symlink()}
    extra={'NOTICE.md':R/'tools/plugin_release/PUBLIC_NOTICE.md'}
    for name in ['account-deletion-contract.md','spaces-api-contract.md','linked-payments-api-contract.md','email-invitation-api-contract.md','space-sharing-api-contract.md','moderation-api-contract.md','ideas-api-contract.md','scope-lifecycle-api-contract.md']:extra['docs/'+name]=R/'docs/server'/name
    source.update({name:sha(p.read_bytes()) for name,p in extra.items()});source=dict(sorted(source.items()));require(source==m['oldSource'] and len(source)==200,'exact_reviewed_current200_source')
    defs=m['definitions'];require(len(defs)==225 and len([t for t in defs if t.startswith('familyhub_')])==177,'exact_table_counts')
    oracle=json.loads((R/'server/scripts/upgrade-0.16.0/schema-oracle.json').read_text())
    for name,expected in oracle['newTables'].items():require(defs.get(name)==expected['create'],'independent_crypto_table_oracle')
    for name,expected in oracle['changedHistorical'].items():require(defs.get(name)==expected['after']['create'],'independent_changed_table_oracle')
    out=a.output.absolute();require(not out.exists() and not out.resolve().is_relative_to(R) and not out.resolve().is_relative_to(Path('/tmp')),'fresh_private_output');out.mkdir(parents=True,mode=0o700);out.chmod(0o700)
    def write(name,data):
        with (out/name).open('xb') as f:f.write(data)
        (out/name).chmod(0o600)
    manifest=(json.dumps({'old':source,'new':source},sort_keys=True,indent=2)+'\n').encode();definitions=(json.dumps(defs,sort_keys=True,indent=2)+'\n').encode();write('source-manifests.json',manifest);write('schema-definitions.json',definitions)
    work=m['base']+'/fresh-reset23-'+time.strftime('%Y%m%d-%H%M%S',time.gmtime())
    values={'SITE':m['site'],'BASE':m['base'],'WORK':work,'CONFIG':m['config'],'DATA':m['data'],'BACKUPS':m['base']+'/backups','CONFIG_SHA':m['configPin']['sha256'],'CONFIG_ENABLED_SHA':m['configPin']['sha256'],'CONFIG_MODE':m['configPin']['mode'],'HTACCESS_SHA':m['htaccessPin']['sha256'],'MANIFEST':work+'/source-manifests.json','MANIFEST_SHA':sha(manifest),'SERVER_ID':sid,'DB_EXPECTED':db,'SOURCE_COUNT':200,'PUBLIC_URL':'https://'+host,'DELIVERY_FILES':m['deliveryFiles'],'DELIVERY_CONSTANTS_SHA':m['deliveryConstantsSha256'],'CRON_SHA':m['cronSha256'],'SCHEMA_DEFINITIONS_SHA':sha(definitions),'TARGET_USERS':m['users']}
    write('deployment.php',('<?php\n// Fresh reset pins; hashes, paths and selected user identities only.\n'+''.join('const '+k+'='+php(v)+';\n' for k,v in values.items())).encode())
    for name in ['backup-library.php','backup.php','reset.php','ResetDatabase.php','InventoryFiles.php','maintenance.php','maintenance-guards.php','delivery-guards.php','public-check.php','operate.sh']:write(name,(D/name).read_bytes())
    write('capture.json',a.capture.read_bytes());print(json.dumps({'privateOutput':str(out),'hostWork':work,'helperHashes':{p.name:sha(p.read_bytes()) for p in sorted(out.iterdir())}}))
if __name__=='__main__':
    try:main()
    except Exception as e:raise SystemExit('Fresh reset seal stopped: '+(str(e) if isinstance(e,RuntimeError) else 'private_input_guard'))
