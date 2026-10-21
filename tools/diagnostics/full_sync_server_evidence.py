#!/usr/bin/env python3
"""Bounded read-only observations of this lab's opaque server state.

Input (private JSON): {scopes:{alias:uuid}, receipts:[{alias,actor,requestId,
requestHash}], records:[{alias,scopeAlias,wireId}]}. IDs and signed bodies are
never copied into the sanitized result. Accounts resolve from the private fixture.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

from full_sync_environment import ROOT, EVIDENCE, NAME, inspect_owned, save

PHP = r'''
$input=json_decode(stream_get_contents(STDIN),true,32,JSON_THROW_ON_ERROR);
$pdo=new PDO('sqlite:file:/var/www/app/data/db.sqlite?mode=ro');
$pdo->setAttribute(PDO::ATTR_ERRMODE,PDO::ERRMODE_EXCEPTION);
$pdo->exec('PRAGMA query_only=ON'); $pdo->exec('PRAGMA busy_timeout=2000');
if((int)$pdo->query('PRAGMA query_only')->fetchColumn()!==1) throw new RuntimeException('Read only required');
function rows($sql,$p=[]){global $pdo;$q=$pdo->prepare($sql);$q->execute($p);$r=$q->fetchAll(PDO::FETCH_ASSOC);$q->closeCursor();return$r;}
$pdo->beginTransaction();
$out=['readOnly'=>true,'opaqueServerOnly'=>true,'scopes'=>[],'receipts'=>[],'records'=>[]];
foreach($input['scopes'] as $alias=>$sid){
 $head=rows('SELECT epoch,access_revision,content_closed,finance_closed,head_hash FROM familyhub_crypto_scope_state WHERE scope_id=?',[$sid]);
 $groups=rows('SELECT p.domain,r.type,r.deleted,COUNT(*) AS recordCount,MIN(r.revision) AS minRevision,MAX(r.revision) AS maxRevision FROM familyhub_crypto_records r JOIN familyhub_crypto_record_positions p ON p.scope_id=r.scope_id AND p.id=r.id WHERE r.scope_id=? GROUP BY p.domain,r.type,r.deleted ORDER BY p.domain,r.type,r.deleted',[$sid]);
 $cursors=rows('SELECT domain,sequence FROM familyhub_crypto_domain_cursors WHERE scope_id=? ORDER BY domain',[$sid]);
 $count=rows('SELECT COUNT(*) AS historyRows,COUNT(DISTINCT id) AS uniqueWireIds FROM familyhub_crypto_record_history WHERE scope_id=?',[$sid])[0];
 $duplicates=rows('SELECT COUNT(*) AS duplicateRevisionGroups FROM (SELECT id,revision,COUNT(*) n FROM familyhub_crypto_record_history WHERE scope_id=? GROUP BY id,revision HAVING COUNT(*)>1)',[$sid])[0];
 $membership=rows('SELECT h.payload FROM familyhub_crypto_scope_heads h JOIN familyhub_crypto_scope_state s ON s.scope_id=h.scope_id AND s.head_hash=h.head_hash WHERE s.scope_id=?',[$sid]);
 $roles=[];
 if(count($membership)===1){$p=json_decode($membership[0]['payload'],true,34,JSON_THROW_ON_ERROR);foreach(($p['members']??[]) as $member){$accountAlias=array_search($member['accountId']??null,$input['accounts'],true);if($accountAlias!==false){$roles[$accountAlias]=array_intersect_key($member,array_flip(['role','contentRole','financeRole','manageKeys']));}}}
 $sqlMembership=[];foreach($input['accounts'] as $accountAlias=>$accountId){$sqlMembership[$accountAlias]=rows('SELECT active,role FROM familyhub_members WHERE scope_id=? AND account_id=?',[$sid,$accountId]);}
 $out['scopes'][$alias]=['head'=>$head,'groups'=>$groups,'cursors'=>$cursors,'history'=>$count,'duplicates'=>$duplicates,'currentMembershipRoles'=>$roles,'sqlMembership'=>$sqlMembership];
}
foreach($input['receipts'] as $r){
 $found=rows('SELECT status,request_hash,response,authorization FROM familyhub_crypto_receipts WHERE account_id=? AND request_id=?',[$input['accounts'][$r['actor']],$r['requestId']]);
 $entry=['alias'=>$r['alias'],'count'=>count($found)];
 if(count($found)===1){$v=$found[0];$body=json_decode($v['response'],true,34,JSON_THROW_ON_ERROR);$entry+=['status'=>(int)$v['status'],'requestHashMatches'=>hash_equals($r['requestHash'],$v['request_hash']),'responseSha256'=>hash('sha256',$v['response']),'authorizationSha256'=>hash('sha256',$v['authorization']),'applied'=>($body['status']??null)==='applied'];}
 $out['receipts'][]=$entry;
}
foreach($input['records'] as $r){
 $sid=$input['scopes'][$r['scopeAlias']];
 $found=rows('SELECT type,revision,deleted,sequence,epoch,authorization FROM familyhub_crypto_records WHERE scope_id=? AND id=?',[$sid,$r['wireId']]);
 $entry=['alias'=>$r['alias'],'count'=>count($found),'history'=>rows('SELECT revision,sequence,domain,record_proof_hash FROM familyhub_crypto_record_history WHERE scope_id=? AND id=? ORDER BY revision LIMIT 129',[$sid,$r['wireId']])];
 if(count($entry['history'])>128) throw new RuntimeException('History evidence limit exceeded');
 if(count($found)===1){$v=$found[0];$a=$v['authorization'];unset($v['authorization']);$entry+=['current'=>$v,'authorizationSha256'=>hash('sha256',$a)];}
 $out['records'][]=$entry;
}
$pdo->rollBack();echo json_encode($out,JSON_THROW_ON_ERROR).PHP_EOL;
'''


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('request', type=Path)
    parser.add_argument('--label', required=True)
    parser.add_argument('--ledger', action='store_true',
                        help='Read known harness ledger schema directly')
    args = parser.parse_args()
    if not re.fullmatch(r'[a-z][a-z0-9-]{0,63}', args.label):
        raise ValueError('Finite evidence label required')
    source = args.request.resolve()
    if not source.is_relative_to(ROOT.resolve()) or source.stat().st_size > (2097152 if args.ledger else 65536):
        raise ValueError('Bounded private lab request required')
    request = json.loads(source.read_text())
    fixture = json.loads((ROOT / 'fixture.json').read_text())
    if (fixture['synthetic'] is not True or
            fixture['purpose'] != 'local-fullsync-recovery-20261021' or
            fixture['serverUrl'] != 'http://127.0.0.1:59777' or
            any(a['session']['serverId'] != fixture['serverId'] for a in fixture['accounts'].values())):
        raise ValueError('Exact isolated target identity required')
    if args.ledger:
        ledger = request
        request = {'scopes': {key: ledger[key] for key in ('parent', 'child') if key in ledger},
                   'receipts': [], 'records': []}
        def wire_id(scope_id, source_kind, canonical_id, domain):
            context = {'version': 2, 'serverId': fixture['serverId'],
                       'scopeId': scope_id, 'domain': domain,
                       'sourceKind': source_kind, 'canonicalId': canonical_id}
            raw = bytearray(hashlib.sha256(b'JivieRecordAddress/v2\n' +
                json.dumps(context, sort_keys=True, separators=(',', ':')).encode()).digest()[:16])
            raw[6] = (raw[6] & 15) | 128
            raw[8] = (raw[8] & 63) | 128
            h = raw.hex()
            return f'{h[:8]}-{h[8:12]}-{h[12:16]}-{h[16:20]}-{h[20:]}'
        for key, scope, kind, domain in [('accountId', 'parent', 'finance_records', 'finance'),
                                         ('entryId', 'parent', 'finance_records', 'finance'),
                                         ('taskId', 'child', 'records', 'content')]:
            if key in ledger and scope in request['scopes']:
                request['records'].append({'alias': key.removesuffix('Id'), 'scopeAlias': scope,
                    'wireId': wire_id(ledger[scope], kind, ledger[key], domain)})
        if 'child' in ledger:
            h = hashlib.sha256(('JivieReservedRecord/v2\n' + fixture['serverId'] + ':' +
                               ledger['child'] + ':financeAccountChoices').encode()).hexdigest()
            canonical = f'{h[:8]}-{h[8:12]}-4{h[13:16]}-a{h[17:20]}-{h[20:32]}'
            request['records'].append({'alias': 'account_choices', 'scopeAlias': 'child',
                'wireId': wire_id(ledger['child'], 'finance_account_choices', canonical, 'finance')})
        if ledger.get('lostRequestId') and ledger.get('lostRequestHash'):
            request['receipts'].append({'alias': 'lost_response', 'actor': ledger.get('lostActor', 'owner'),
                'requestId': ledger['lostRequestId'], 'requestHash': ledger['lostRequestHash']})
    inspect_owned()
    scopes, receipts, records = (request.get(key, default) for key, default in
                                [('scopes', {}), ('receipts', []), ('records', [])])
    if len(scopes) > 16 or len(receipts) > 32 or len(records) > 64:
        raise ValueError('Evidence query limit exceeded')
    uuid = re.compile(r'[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}')
    alias_pattern = re.compile(r'[A-Za-z][A-Za-z0-9_-]{0,63}')
    def identifier(value):
        if not isinstance(value, str) or not uuid.fullmatch(value):
            raise ValueError('UUID required')
    for alias, sid in scopes.items():
        if not alias_pattern.fullmatch(alias): raise ValueError('Alias required')
        identifier(sid)
    for item in receipts:
        if not alias_pattern.fullmatch(item['alias']) or item['actor'] not in ('owner', 'member'):
            raise ValueError('Finite receipt alias and actor required')
        identifier(item['requestId'])
        if not re.fullmatch(r'[0-9a-f]{64}', item['requestHash']):
            raise ValueError('Request SHA256 required')
    for item in records:
        if not alias_pattern.fullmatch(item['alias']) or item['scopeAlias'] not in scopes:
            raise ValueError('Finite record/scope alias required')
        identifier(item['wireId'])
    private_input = {'scopes': scopes, 'receipts': receipts, 'records': records,
                     'accounts': {key: value['session']['user']['accountId']
                                  for key, value in fixture['accounts'].items()}}
    result = subprocess.run(['docker', 'exec', '-i', NAME, 'php', '-r', PHP],
                            input=json.dumps(private_input), capture_output=True,
                            text=True, timeout=15, check=False)
    if result.returncode or len(result.stdout) > 65536:
        save(ROOT / f'{args.label}-server-evidence-error-private.json',
             {'returncode': result.returncode, 'stderr': result.stderr[:16384]})
        raise RuntimeError('Bounded read-only server evidence failed; private error preserved')
    output = json.loads(result.stdout)
    destination = EVIDENCE / f'{args.label}-server-evidence.json'
    if destination.exists():
        raise RuntimeError('Evidence label already exists; preserve prior observation')
    save(destination, output)
    print(json.dumps({'status': 'captured', 'output': str(destination),
                      'scopes': len(scopes), 'receipts': len(receipts), 'records': len(records)}))


if __name__ == '__main__':
    main()
