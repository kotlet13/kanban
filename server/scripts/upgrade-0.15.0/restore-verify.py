#!/usr/bin/env python3
"""Restore only into a fresh network=none MariaDB10.11.19 container. Never run PHP."""
import argparse,hashlib,json,os,re,stat,subprocess,sys,zipfile
from pathlib import Path,PurePosixPath
os.umask(0o077)
DB=None
SERVER_ID=None
CONTAINER=None
DIAG_ROOT=None

def require(ok,code):
    if not ok:raise RuntimeError(code)
def command(args,data=None):
    p=subprocess.run(args,input=data,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=120)
    if p.returncode:
        # Never retain stderr/query bodies: parse only standard error code and line.
        m=re.search(rb'ERROR ([0-9]+) \(([A-Z0-9]+)\)(?: at line ([0-9]+))?',p.stderr)
        if DIAG_ROOT is not None:
            payload={'commandKind':'docker_inspect' if 'inspect' in args else 'mariadb_client','returnCode':p.returncode,'sqlErrorNumber':int(m[1])if m else None,'sqlState':m[2].decode()if m else None,'dumpLine':int(m[3])if m and m[3]else None}
            with (DIAG_ROOT/'restore-diagnostic.json').open('x')as f:f.write(json.dumps(payload,indent=2)+'\n')
        raise RuntimeError('private_command_failed')
    return p.stdout
def ident(s):
    require(re.fullmatch(r'[A-Za-z0-9_]+',s) is not None,'sql_identifier_guard');return '`'+s+'`'
def digest(b):return hashlib.sha256(b).hexdigest()
def sql(q,database=True):
    args=['docker','exec','-i',CONTAINER,'mariadb','--user=root','--batch','--raw','--skip-column-names']
    if database:args.append(DB)
    return command(args,q.encode()).decode('utf-8')
def private_tree(root):
    out={}
    for p in root.rglob('*'):
        require(not p.is_symlink(),'extracted_symlink_guard')
        if p.is_dir():continue
        require(stat.S_ISREG(p.stat().st_mode) and stat.S_IMODE(p.stat().st_mode)&0o077==0,'extracted_private_file_guard')
        out[p.relative_to(root).as_posix()]={'bytes':p.stat().st_size,'sha256':digest(p.read_bytes())}
    return dict(sorted(out.items()))
def main(argv=None):
    global CONTAINER,DIAG_ROOT,DB,SERVER_ID
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive',type=Path)
    parser.add_argument('--sha256',required=True,help='Exact SHA256 reported by private host export')
    parser.add_argument('--container',required=True,help='Fresh running MariaDB10.11.19 with --network none and no ports')
    parser.add_argument('--private-root',type=Path,default=Path('/Users/anzenovsak/.local/share/jivie/backups/documents19-preupgrade-20261012'))
    args=parser.parse_args(argv);CONTAINER=args.container
    require(re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]{0,127}',CONTAINER) is not None,'container_name_guard')
    require(re.fullmatch(r'[a-f0-9]{64}',args.sha256) is not None,'expected_archive_sha_guard')
    root=args.private_root.absolute();require(not root.is_relative_to(Path(__file__).resolve().parents[3]),'private_root_outside_repo_required');require(root.is_dir() and not root.is_symlink() and root.resolve()==root and stat.S_IMODE(root.stat().st_mode)&0o077==0,'private_root_guard')
    archive=args.archive.absolute();require(archive.is_file() and not archive.is_symlink() and archive.resolve()==archive and root in archive.parents,'private_archive_location_guard')
    require(stat.S_IMODE(archive.stat().st_mode)&0o077==0,'private_archive_permissions_guard')
    require(digest(archive.read_bytes())==args.sha256,'host_archive_sha_guard');DIAG_ROOT=archive.parent
    info=json.loads(command(['docker','inspect',CONTAINER]))[0]
    require(info['HostConfig']['NetworkMode']=='none' and not info['HostConfig']['PortBindings'] and info['Config']['Image']=='mariadb:10.11.19' and len(info['Mounts'])==1 and info['Mounts'][0]['Type']=='volume' and info['Mounts'][0]['Destination']=='/var/lib/mysql' and re.fullmatch(r'[a-f0-9]{64}',info['Mounts'][0]['Name']) is not None,'isolated_fresh_container_guard')
    require(sql("SELECT VERSION();",False).strip().startswith('10.11.19-MariaDB'),'mariadb_version_guard')
    existing=sql("SELECT SCHEMA_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME NOT IN ('information_schema','mysql','performance_schema','sys');",False).splitlines()
    require(not existing,'empty_server_database_guard')
    out=archive.parent/'verified-restore';out.mkdir(mode=0o700)
    with zipfile.ZipFile(archive)as z:
        seen=set();size=0
        for ent in z.infolist():
            p=PurePosixPath(ent.filename)
            require(str(p)==ent.filename and not p.is_absolute() and '..' not in p.parts and '\\' not in ent.filename and ent.filename not in seen,'archive_path_guard')
            require(not ent.is_dir() and stat.S_ISREG(ent.external_attr>>16),'archive_type_guard')
            require(ent.filename in ['database.sql','manifest.json','config.php','root-config.php','root-htaccess','crontab.original'] or ent.filename.startswith('data/') or ent.filename.startswith('source/') or re.fullmatch(r'delivery/[a-f0-9]{64}',ent.filename),'archive_allowlist_guard')
            size+=ent.file_size;require(size<=512*1024*1024 and ent.file_size<=268435456,'archive_size_guard');seen.add(ent.filename)
            target=out/ent.filename;target.parent.mkdir(mode=0o700,parents=True,exist_ok=True)
            with target.open('xb')as f:f.write(z.read(ent))
            target.chmod(0o600)
        require(z.testzip() is None,'archive_crc_guard')
    m=json.loads((out/'manifest.json').read_text());DB=m['database'];SERVER_ID=m['identity']['serverId'];require(DB in ['tripar13_jivieprod','tripar13_jivietest'] and re.fullmatch(r'[a-f0-9-]{36}',SERVER_ID) is not None,'target_identity_guard');require(m['format']=='documents19-preupgrade-backup-v1' and m['database']==DB and m['identity']['serverId']==SERVER_ID and m['identity']['schema']==18 and m['identity']['nativeAccounts']>=1,'documents19_manifest_identity_guard')
    require(all(m['capture'].values()),'capture_proof_guard')
    require(digest((out/'database.sql').read_bytes())==m['databaseSqlSha256'],'sql_hash_guard')
    for name,key in [('config.php','privateConfigSha256'),('root-config.php','rootConfigSha256'),('root-htaccess','rootHtaccessSha256'),('crontab.original','cronSha256')]:
        require(digest((out/name).read_bytes())==m[key],'config_or_marker_hash_guard')
    for path,pin in m['deliveryFiles'].items():
        require(digest((out/'delivery'/digest(path.encode())).read_bytes())==pin['sha256'],'delivery_file_hash_guard')
    require({n:v['sha256'] for n,v in private_tree(out/'source').items()}==m['sourceFiles'] and len(m['sourceFiles'])==101,'restored_source_hash_guard')
    for rel in m['dataDirectories']:
        path=PurePosixPath(rel);require(str(path)==rel and not path.is_absolute() and '..' not in path.parts and '\\' not in rel,'manifest_directory_guard');(out/'data'/rel).mkdir(mode=0o700,parents=True,exist_ok=True)
    actual_dirs=sorted(p.relative_to(out/'data').as_posix()for p in (out/'data').rglob('*')if p.is_dir());require(actual_dirs==m['dataDirectories'],'restored_directory_set_guard')
    actual_files=private_tree(out/'data');require(actual_files==m['dataFiles'] and len(actual_files)==m['dataFilesCount'],'restored_private_data_hash_guard')
    command(['docker','exec','-i',CONTAINER,'mariadb','--user=root'],('CREATE DATABASE '+ident(DB)+' CHARACTER SET utf8mb4;').encode())
    command(['docker','exec','-i',CONTAINER,'mariadb','--user=root',DB],(out/'database.sql').read_bytes())
    tables=sql("SELECT TABLE_NAME FROM information_schema.TABLES WHERE TABLE_SCHEMA=DATABASE() AND TABLE_TYPE='BASE TABLE' ORDER BY TABLE_NAME;").splitlines()
    require(tables==list(m['tables']),'restored_table_set_guard')
    verified={}
    for table in tables:
        expected=m['tables'][table];defs=[line.split('\t') for line in sql('SHOW COLUMNS FROM '+ident(table)+';').splitlines()]
        require([d[0] for d in defs]==expected['columns'] and [d[1] for d in defs]==expected['types'],'restored_column_type_guard')
        cols=expected['columns'];order=expected['order']
        q='SELECT '+','.join("COALESCE(REPLACE(TO_BASE64(CAST("+ident(c)+" AS BINARY)),CHAR(10),''),'@NULL@')" for c in cols)+' FROM '+ident(table)+' ORDER BY '+','.join(map(ident,order))+';'
        output=sql(q);h=hashlib.sha256();count=0
        for line in output.splitlines():
            vals=line.split('\t');require(len(vals)==len(cols),'restored_row_shape_guard');row=dict(zip(cols,[None if v=='@NULL@' else v for v in vals]))
            h.update((json.dumps(row,ensure_ascii=True,separators=(',',':'))+'\n').encode());count+=1
        require(count==expected['rows'] and h.hexdigest()==expected['sha256'],'restored_row_hash_guard')
        # mariadb --batch emits table name + SHOW CREATE text; --raw preserves line breaks.
        create=sql('SHOW CREATE TABLE '+ident(table)+';').split('\t',1)[1].rstrip('\n')
        require(digest(create.encode())==expected['createSha256'],'restored_create_definition_hash_guard')
        verified[table]={'rows':count,'sha256':h.hexdigest()}
    server_id=sql('SELECT server_id FROM familyhub_instance WHERE id=1;').strip();schema=int(sql("SELECT version FROM plugin_schema_versions WHERE plugin='familyhub';").strip())
    require(server_id==SERVER_ID and schema==18,'restored_server_identity_guard')
    accounts=int(sql('SELECT COUNT(*) FROM familyhub_accounts;').strip());devices=int(sql('SELECT COUNT(*) FROM familyhub_devices;').strip())
    require(accounts==m['identity']['nativeAccounts'] and devices==m['identity']['nativeDevices'],'restored_account_and_session_count_guard')
    proof={'format':'documents19-preupgrade-restore-proof-v1','archiveSha256':args.sha256,'sqlSha256':m['databaseSqlSha256'],'serverId':server_id,'schema':schema,'database':'MariaDB 10.11.19','isolatedNetwork':'none','ports':False,'hostBindMounts':False,'onlyAnonymousMysqlVolume':True,'tablesVerified':len(tables),'rowsVerified':sum(v['rows']for v in verified.values()),'privateFilesVerified':len(actual_files),'privateDirectoriesVerified':len(actual_dirs),'everyRowAndFileHashMatches':True,'everyTableDefinitionHashMatches':True,'passwordsAccountsSessionsRecordsPreserved':True,'configHttpsAndCronHashesMatch':True,'deliveryConfigAndKeysMatch':True,'sourceFilesVerified':101,'sourceHashesMatch':True,'applicationOrWorkersStarted':False,'liveHostedDatabaseTouched':False}
    with (archive.parent/'restore-proof.json').open('x')as f:f.write(json.dumps(proof,indent=2)+'\n')
    print(json.dumps(proof))
if __name__=='__main__':
    try:main()
    except Exception as e:
        code=str(e)if isinstance(e,RuntimeError)and re.fullmatch(r'[a-z_]+',str(e))else'private_diagnostic_required'
        print('Documents19 restore stopped: '+code+'; no SQL, credential or private payload printed.',file=sys.stderr);sys.exit(1)
