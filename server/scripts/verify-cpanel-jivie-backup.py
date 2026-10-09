#!/usr/bin/env python3
"""Private staging backup verification. No application or delivery workers run."""
import argparse, base64, hashlib, json, os, re, stat, subprocess, sys, zipfile
from pathlib import Path, PurePosixPath
CONTAINER = None
DB = 'tripar13_jivietest'
os.umask(0o077)
def require(ok, code):
    if not ok: raise RuntimeError(code)
def command(args, data=None):
    r = subprocess.run(args, input=data, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120)
    require(r.returncode == 0, 'private_command_failed')
    return r.stdout

def sql(query):
    return command(['docker','exec','-i',CONTAINER,'mariadb','--user=root','--batch','--raw','--skip-column-names',DB], query.encode()).decode()
def identifier(name):
    require(re.fullmatch(r'[A-Za-z0-9_]+',name) is not None,'identifier_guard')
    return '`'+name+'`'
def digest(data): return hashlib.sha256(data).hexdigest()
def private_inventory(directory):
    # PHP ksort orders complete relative keys; pathlib orders individual path parts.
    entries={p.relative_to(directory).as_posix():digest(p.read_bytes()) for p in directory.rglob('*') if p.is_file()}
    return dict(sorted(entries.items()))
def php_json(value):
    return json.dumps(value,indent=4,ensure_ascii=True,separators=(',', ': '))+'\n'
def base64_rows(table,names,order,where=''):
    columns=','.join("COALESCE(REPLACE(TO_BASE64(CAST("+identifier(n)+" AS BINARY)),CHAR(10),''),'@NULL@')" for n in names)
    output=sql('SELECT '+columns+' FROM '+identifier(table)+where+' ORDER BY '+','.join(map(identifier,order))+';')
    rows=[]
    for line in output.splitlines():
        values=line.split('\t');require(len(values)==len(names),'row_shape')
        rows.append(dict(zip(names,[None if v=='@NULL@' else v for v in values])))
    return rows

def decoded_rows(table,names,order,integer_columns=()):
    result=[]
    for row in base64_rows(table,names,order):
        result.append({k:None if v is None else int(base64.b64decode(v)) if k in integer_columns else base64.b64decode(v).decode() for k,v in row.items()})
    return result

def main(argv=None):
    global CONTAINER
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path)
    parser.add_argument('--container', required=True, help='Fresh MariaDB 10.11.19 container with network=none and no ports')
    parser.add_argument('--private-root', type=Path, default=Path('/Users/anzenovsak/.local/share/jivie/backups'))
    args=parser.parse_args(argv)
    require(re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]{0,127}',args.container) is not None,'container_name_guard')
    CONTAINER=args.container
    archive=args.archive.absolute()
    require(not archive.is_symlink() and archive.resolve()==archive,'private_archive_symlink_guard')
    private_root=args.private_root.resolve()
    require(private_root.is_dir() and stat.S_IMODE(private_root.stat().st_mode)&0o077==0,'private_root_permissions')
    require(private_root in archive.parents and archive.is_file() and not archive.is_symlink(),'private_archive_location')
    require(stat.S_IMODE(archive.stat().st_mode)&0o077==0,'private_archive_permissions')
    out=archive.parent/'verified-restore';out.mkdir(mode=0o700)
    info=json.loads(command(['docker','inspect',CONTAINER]))[0]
    require(info['HostConfig']['NetworkMode']=='none' and not info['HostConfig']['PortBindings'] and info['Config']['Image']=='mariadb:10.11.19','isolated_container_guard')
    with zipfile.ZipFile(archive) as package:
        require(package.testzip() is None,'zip_crc')
        seen=set(); total=0
        for entry in package.infolist():
            path=PurePosixPath(entry.filename)
            require(not path.is_absolute() and '..' not in path.parts and str(path)==entry.filename and entry.filename not in seen and '\\' not in entry.filename,'zip_path_guard')
            require(stat.S_ISREG(entry.external_attr>>16) or entry.is_dir(),'zip_type_guard')
            total+=entry.file_size;require(total<=256*1024*1024,'backup_size_guard');seen.add(entry.filename)
            target=out/entry.filename
            if entry.is_dir():target.mkdir(mode=0o700,parents=True,exist_ok=True)
            else:
                target.parent.mkdir(mode=0o700,parents=True,exist_ok=True)
                with target.open('xb') as f:f.write(package.read(entry))
                target.chmod(0o600)
    state=json.loads((out/'state.json').read_text());before=state['before']
    dump=out/'backup/database.sql';require(digest(dump.read_bytes())==state['sqlSha'],'sql_sha')
    private=out/'backup/private'
    inventory=private_inventory(private)
    private_sha=digest(php_json(inventory).encode())
    require(private_sha==state['privateSha'],'private_tree_sha')
    command(['docker','exec','-i',CONTAINER,'mariadb','--user=root'], ('CREATE DATABASE '+identifier(DB)+' CHARACTER SET utf8mb4;').encode())
    command(['docker','exec','-i',CONTAINER,'mariadb','--user=root',DB],dump.read_bytes())
    actual_tables=sql("SELECT TABLE_NAME FROM information_schema.TABLES WHERE TABLE_SCHEMA=DATABASE() AND TABLE_TYPE='BASE TABLE' ORDER BY TABLE_NAME;").splitlines()
    require(actual_tables==list(before['tables']),'table_names')
    tables={}
    for table in actual_tables:
        defs=[line.split('\t') for line in sql('SHOW COLUMNS FROM '+identifier(table)+';').splitlines()]
        names=[d[0] for d in defs];require(names==before['tables'][table]['columns'],'column_names')
        keys=[d[0] for d in defs if d[3]=='PRI']; order=keys or names
        rows=base64_rows(table,names,order," WHERE plugin<>'familyhub'" if table=='plugin_schema_versions' else '')
        h=hashlib.sha256()
        for row in rows:h.update((json.dumps(row,ensure_ascii=True,separators=(',',':')).replace('/','\\/')+'\n').encode())
        tables[table]={'columns':names,'rows':len(rows),'sha256':h.hexdigest()}
        require(tables[table]==before['tables'][table],'restored_table_hash')
    schema=int(sql("SELECT version FROM plugin_schema_versions WHERE plugin='familyhub';").strip())
    server_id=sql('SELECT server_id FROM familyhub_instance WHERE id=1;').strip()
    accounts=decoded_rows('familyhub_accounts',['user_id','account_id'],['user_id'],['user_id'])
    users=decoded_rows('users',['id','password'],['id'],['id'])
    enrollment_defs=[line.split('\t') for line in sql('SHOW COLUMNS FROM familyhub_enrollment;').splitlines()]
    enrollment_names=[d[0] for d in enrollment_defs]
    enrollment_integers=[d[0] for d in enrollment_defs if re.match(r'(tinyint|smallint|mediumint|int|integer|bigint)\b',d[1])]
    enrollment=decoded_rows('familyhub_enrollment',enrollment_names,['id'],enrollment_integers)
    restored={'schema':schema,'serverId':server_id,'accountHash':digest(php_json(accounts).encode()),'passwordHash':digest(php_json(users).encode()),'enrollmentHash':digest(php_json(enrollment).encode()),'bootstrapClosed':bool(accounts),'tables':tables}
    require(restored==before,'restored_identity_snapshot')
    proof={'verifiedInIsolatedLocalDb':True,'sqlSha':state['sqlSha'],'privateSha':private_sha,'serverId':server_id,'restoredSnapshot':restored,'restoredPrivateInventory':inventory}
    with (archive.parent/'restore-proof.json').open('x') as f:f.write(php_json(proof))
    evidence={'isolatedNetwork':'none','database':'MariaDB 10.11.19','sqlSha':state['sqlSha'],'privateSha':private_sha,'archiveSha':digest(archive.read_bytes()),'schema':schema,'serverId':server_id,'tablesVerified':len(tables),'rowsVerified':sum(t['rows'] for t in tables.values()),'privateFilesVerified':len(inventory),'accountPasswordEnrollmentUnchanged':True,'applicationAndWorkersStarted':False}
    with (archive.parent/'restore-evidence.json').open('x') as f:f.write(php_json(evidence))
    print(json.dumps(evidence))
if __name__ == '__main__':
    try: main()
    except Exception as error:
        code = str(error) if isinstance(error, RuntimeError) and re.fullmatch(r'[a-z_]+', str(error)) else 'private_diagnostic_required'
        print('Private backup verification stopped: '+code+'; no private values printed.',file=sys.stderr)
        sys.exit(1)
