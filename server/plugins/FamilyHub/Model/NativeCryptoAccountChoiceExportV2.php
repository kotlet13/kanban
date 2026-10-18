<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** Closed complete-set variant of the existing account-choice export. Public
 * evidence contains salted commitments; raw account values stay encrypted. */
class NativeCryptoAccountChoiceExportV2 extends NativeDatabase
{
    protected $cryptoAccess=true;
    public const VARIANT='accountChoiceSelection';
    private function hash($v){if(!is_string($v)||!preg_match('/^[a-f0-9]{64}$/D',$v))throw new NativeError('crypto_account_choices_hash');return $v;}
    private function digest($v){return NativeCryptoV2Codec::hash((object)$v);}
    private function decode($proof){[$b]=NativeCryptoCodec::decode($proof);return $b;}
    private function scopes(){return new NativeCryptoScopeV2($this->container,$this->bearer,$this->ip);}
    private function row($table,$hash){$r=$this->one('SELECT * FROM familyhub_crypto_export_'.$table.'_v2 WHERE hash=?',[$this->hash($hash)]);if(!$r)throw new NativeError('crypto_export_missing',404);return $r;}
    private function own($head,$actor){$this->scopes()->currentAuthorReference($head,$actor);$d=(new NativeCryptoDirectoryV2($this->container))->current($actor['user']['account_id']);if(!$d)throw new NativeError('crypto_member_directory_pending',409);return $d;}
    private function target($p,$actor,$manager=false,$writer=false){$sid=$this->uuid($p['targetScopeId']);$s=$this->scope($sid,$actor['user']['id']);$h=$this->scopes()->current($sid);if(!$h||$h['head_hash']!==$p['targetHeadHash'])throw new NativeError('crypto_scope_head_changed',409);if($manager)$this->scopes()->manager($h,$s,$actor);else $this->scopes()->author($sid,$h['head_hash'],(int)$h['epoch'],(int)$s['effective_access_revision'],$actor,'finance',$writer);return [$s,$h];}
    private function context($p){
        foreach(['serverId','sourceScopeId','targetScopeId'] as $k)$this->uuid($p[$k]??null);
        foreach(['sourceHeadHash','targetHeadHash','selectionHash'] as $k)$this->hash($p[$k]??null);
        if($p['version']!==2||$p['variant']!==self::VARIANT||$p['purpose']!=='financeAccountChoice'||$p['serverId']!==$this->serverId()||!is_int($p['selectionCount'])||$p['selectionCount']<0||$p['selectionCount']>5000)throw new NativeError('crypto_account_choices_context');
        if(array_key_exists('capture3Context',$p)){
            $x=$p['capture3Context'];$this->fields($x,['version','purpose','serverId','source','target','childBinding']);
            if($x['version']!==3||$x['purpose']!=='financeAccountChoice'||$x['serverId']!==$p['serverId'])throw new NativeError('crypto_account_choices_capture_context');
            foreach(['source','target'] as $side){$v=$x[$side];$this->fields($v,['migrationId','captureId','accountId','sourceInventoryRoot','scopeId','membershipHeadHash']);foreach(['migrationId','captureId','accountId','scopeId'] as $k)$this->uuid($v[$k]);foreach(['sourceInventoryRoot','membershipHeadHash'] as $k)$this->hash($v[$k]);if($v['scopeId']!==$p[$side.'ScopeId']||$v['membershipHeadHash']!==$p[$side.'HeadHash'])throw new NativeError('crypto_account_choices_capture_context');}
            $b=$x['childBinding'];$this->fields($b,['bindingId','scopeId','domain','sourceCommitment']);$this->uuid($b['bindingId']);$this->hash($b['sourceCommitment']);
            if($b['scopeId']!==$p['targetScopeId']||$b['domain']!=='finance'||$x['source']['migrationId']!==$x['target']['migrationId']||$x['source']['accountId']!==$p['accountId'])throw new NativeError('crypto_account_choices_capture_context');
            return;
        }
        $this->hash($p['sourceRecordRoot']??null);$c=$p['sourceCheckpoint'];$this->fields($c,['proofHash','sequence','manifestHash']);$this->hash($c['proofHash']);$this->hash($c['manifestHash']);if(!is_int($c['sequence'])||$c['sequence']<0||$c['sequence']>9007199254740991)throw new NativeError('crypto_account_choices_checkpoint');
    }
    private function capturedSource($b,$actor,$head){
        $x=$b['capture3Context'];
        foreach(['source','target'] as $side){$v=$x[$side];$capture=$this->one('SELECT * FROM familyhub_crypto_captures_v3 WHERE migration_id=? AND account_id=?',[$v['migrationId'],$v['accountId']]);if(!$capture||$capture['state']!=='sealed'||$capture['capture_id']!==$v['captureId']||$capture['inventory_root']!==$v['sourceInventoryRoot'])throw new NativeError('crypto_account_choices_capture_pending',409);$h=$this->scopes()->current($v['scopeId']);if(!$h)throw new NativeError('crypto_account_choices_capture_head',409);$body=$this->scopes()->body($h);if($h['head_hash']!==$v['membershipHeadHash']||(int)$h['epoch']!==1||$body['previousHeadHash']!==str_repeat('0',64)||($body['accessIntentProof']??null)!==null||($body['financePolicyIntentProof']??null)!==null)throw new NativeError('crypto_account_choices_capture_head',409);}
        $s=$x['source'];$t=$x['target'];$binding=$x['childBinding'];
        $bound=$this->one('SELECT source_commitment FROM familyhub_crypto_capture_sources_v3 WHERE migration_id=? AND account_id=? AND binding_id=? AND scope_id=? AND domain=?',[$t['migrationId'],$t['accountId'],$binding['bindingId'],$t['scopeId'],'finance']);if(!$bound||$bound['source_commitment']!==$binding['sourceCommitment'])throw new NativeError('crypto_account_choices_capture_binding',409);
        $target=$this->one('SELECT kind,parent_scope_id FROM familyhub_scopes WHERE id=?',[$t['scopeId']]);if(!$target||$target['kind']!=='project'||$target['parent_scope_id']!==$s['scopeId'])throw new NativeError('crypto_export_target_invalid',403);
        $members=$this->scopes()->body($head)['members'];$eligible=[];$owner=null;
        foreach($members as $member)if(in_array($member['financeRole'],['read','write'],true)){$eligible[]=$member['accountId'];if($member['role']==='owner')$owner=$member['accountId'];}
        sort($eligible,SORT_STRING);if(($owner??($eligible[0]??null))!==$actor['user']['account_id'])throw new NativeError('crypto_account_choices_capture_source',403);
        $count=$this->one("SELECT COUNT(*) AS n FROM familyhub_finance_records WHERE scope_id=? AND type='financeAccount' AND deleted=0",[$s['scopeId']]);
        if((int)$count['n']!==$b['selectionCount'])throw new NativeError('crypto_account_choices_source_set_changed',409);
        // This remains an issuer-attested derivation. Complete independent FILE
        // enumeration and both final publications authenticate the companion.
    }
    private function source($b,$actor,$records=null){
        $this->context($b);$sid=$b['sourceScopeId'];$scope=$this->scope($sid,$actor['user']['id']);$head=$this->scopes()->current($sid);
        if(!$head||$head['head_hash']!==$b['sourceHeadHash'])throw new NativeError('crypto_export_source_changed',409);
        $this->scopes()->author($sid,$head['head_hash'],(int)$head['epoch'],(int)$scope['effective_access_revision'],$actor,'finance',false);
        if(array_key_exists('capture3Context',$b)){$this->capturedSource($b,$actor,$head);return;}
        $this->scopes()->assertCurrentMembership($scope,$head);NativeCryptoScopeCreationV2::guardBusiness($this->pdo,$sid);
        $target=$this->one('SELECT parent_scope_id,kind FROM familyhub_scopes WHERE id=?',[$b['targetScopeId']]);$targetHead=$this->scopes()->current($b['targetScopeId']);
        if(!$target||$target['kind']!=='project'||$target['parent_scope_id']!==$sid||!$targetHead||$targetHead['head_hash']!==$b['targetHeadHash'])throw new NativeError('crypto_export_target_invalid',403);
        $c=$b['sourceCheckpoint'];
        $checkpoint=$this->one("SELECT * FROM familyhub_crypto_domain_checkpoints WHERE scope_id=? AND domain='finance' AND head_hash=? AND sequence=?",[$sid,$head['head_hash'],$c['sequence']]);
        if(!$checkpoint||$checkpoint['manifest_hash']!==$c['manifestHash'])throw new NativeError('crypto_account_choices_checkpoint_changed',409);
        $attestation=$this->one("SELECT authorization FROM familyhub_crypto_domain_attestations WHERE scope_id=? AND domain='finance' AND head_hash=? AND sequence=? AND proof_hash=?",[$sid,$head['head_hash'],$c['sequence'],$c['proofHash']]);
        if(!$attestation)throw new NativeError('crypto_account_choices_checkpoint_changed',409);
        $actual=[];foreach($this->iterate("SELECT r.id,r.authorization,p.domain AS position_domain FROM familyhub_crypto_records r LEFT JOIN familyhub_crypto_record_positions p ON p.scope_id=r.scope_id AND p.id=r.id WHERE r.scope_id=? AND r.type='financeAccount' AND r.deleted=0 ORDER BY r.id",[$sid]) as $r){
            // Do not silently omit a live account whose domain position is absent
            // or inconsistent: this proof must cover the complete source set.
            if($r['position_domain']!=='finance')throw new NativeError('crypto_account_choices_source_set_changed',409);
            if(count($actual)>=5000)throw new NativeError('crypto_account_choices_capacity',409);$proof=json_decode($r['authorization'],true,34,JSON_THROW_ON_ERROR);$actual[]=['id'=>$r['id'],'recordProofHash'=>$this->digest($proof['recordProof'])];
        }
        $historic=[];$inventory=hash_init('sha256');$inventoryCount=0;$inventoryBytes=0;
        foreach($this->iterate("SELECT h.id,h.revision,h.record_proof_hash,h.sequence,h.epoch,h.record_proof FROM familyhub_crypto_record_history h WHERE h.scope_id=? AND h.domain='finance' AND h.sequence<=? AND NOT EXISTS(SELECT 1 FROM familyhub_crypto_record_history n WHERE n.scope_id=h.scope_id AND n.domain=h.domain AND n.id=h.id AND n.sequence<=? AND n.revision>h.revision) ORDER BY h.id",[$sid,$c['sequence'],$c['sequence']]) as $row){
            $inventoryCount++;$inventoryBytes+=strlen($row['record_proof']);
            if($inventoryCount>50000||$inventoryBytes>67108864)throw new NativeError('crypto_account_choices_capacity',409);
            $rp=json_decode($row['record_proof'],true,34,JSON_THROW_ON_ERROR);$rb=$this->decode($rp);
            if($this->digest($rp)!==$row['record_proof_hash'])throw new NativeError('crypto_account_choices_checkpoint_changed',409);
            hash_update($inventory,NativeCryptoCodec::canonical((object)['id'=>$row['id'],'revision'=>(int)$row['revision'],'recordProofHash'=>$row['record_proof_hash'],'sequence'=>(int)$row['sequence'],'recordEpoch'=>(int)$row['epoch']])."\n");
            if($rb['type']==='financeAccount'&&!$rb['deleted'])$historic[]=['id'=>$row['id'],'recordProofHash'=>$row['record_proof_hash']];
        }
        if($inventoryCount!==(int)$checkpoint['record_count']||hash_final($inventory)!==$c['manifestHash']||NativeCryptoCodec::canonical($historic)!==NativeCryptoCodec::canonical($actual))throw new NativeError('crypto_account_choices_source_set_changed',409);
        $root=hash('sha256',"JivieFinanceAccountChoiceSource/v2\n".NativeCryptoCodec::canonical($actual));
        if(count($actual)!==$b['selectionCount']||$root!==$b['sourceRecordRoot']||$records!==null&&NativeCryptoCodec::canonical($records)!==NativeCryptoCodec::canonical($actual))throw new NativeError('crypto_account_choices_source_set_changed',409);
    }
    private function proof($proof,$actor,$key,$certificate=false){[$b,$bytes,$signature]=NativeCryptoCodec::decode($proof);$fields=['version','operation','variant','purpose','serverId','sourceScopeId','sourceHeadHash','targetScopeId','targetHeadHash','selectionCount','selectionHash','accountId','deviceId','authorDirectoryHeadHash','deviceSnapshotHash'];$fields=array_merge($fields,array_key_exists('capture3Context',$b)?['capture3Context']:['sourceCheckpoint','sourceRecordRoot']);if($certificate)$fields=array_merge($fields,['offerHash','delegationHash','bridge']);$this->fields($b,$fields);$this->context($b);$own=$this->own($b['authorDirectoryHeadHash'],$actor);if($b['operation']!==($certificate?'crypto2.exports.certificate':'crypto2.exports.offer')||$b['accountId']!==$actor['user']['account_id']||$b['deviceId']!==$actor['device']['id']||$b['deviceSnapshotHash']!==$own['device_snapshot_hash'])throw new NativeError('crypto_account_choices_author',403);NativeCryptoV2Codec::verify($bytes,$signature,$key,$certificate?"JivieE2EE/scopedExport/v2\n":"JivieE2EE/exportOffer/v2\n");return $b;}
    /** Online availability of an already signed derivation. This checks the
     * relevant current account/proof set; unrelated expenses do not expire it. */
    public function available($certificate,$actor)
    {
        $b=$this->decode($certificate);$this->context($b);
        $issuer=$this->one('SELECT user_id FROM familyhub_accounts WHERE account_id=?',[$b['accountId']]);
        if(!$issuer)throw new NativeError('crypto_export_issuer_changed',409);
        $issuerActor=['user'=>['id'=>$issuer['user_id'],'account_id'=>$b['accountId']],'device'=>['id'=>$b['deviceId']]];
        $this->own($b['authorDirectoryHeadHash'],$issuerActor);$this->source($b,$issuerActor);
        return true;
    }
    public function replayAccess($op,$p,$actor)
    {
        if($op==='crypto2.exports.delegate')return;
        $b=$this->decode($p[$op==='crypto2.exports.propose'?'selectionProof':'certificateProof']);$this->context($b);
        if($b['accountId']!==$actor['user']['account_id'])throw new NativeError('permission_revoked',403);
        $scope=$this->scope($b['sourceScopeId'],$actor['user']['id']);$head=$this->scopes()->current($b['sourceScopeId']);
        if(!$head)throw new NativeError('crypto_scope_head_missing',409);
        $this->scopes()->author($b['sourceScopeId'],$head['head_hash'],(int)$head['epoch'],(int)$scope['effective_access_revision'],$actor,'finance',false);
    }
    public function read($op,$p,$actor)
    {
        if(in_array($op,['crypto2.exports.delegation.directory','crypto2.exports.recipient.directory'],true)){
            $this->fields($p,['variant','delegationHash'],['afterGeneration','limit']);
            $delegation=$this->row('delegations',$p['delegationHash']);$proof=json_decode($delegation['authorization'],true,64,JSON_THROW_ON_ERROR);$command=$this->decode($proof);$d=$command['payload'];
            $offer=$this->row('offers',$delegation['offer_hash']);$b=$this->decode(json_decode($offer['authorization'],true,64,JSON_THROW_ON_ERROR));
            if(!isset($b['capture3Context'])||$b['accountId']!==$actor['user']['account_id'])throw new NativeError('permission_revoked',403);
            $this->source($b,$actor);
            $target=$this->scopes()->current($b['targetScopeId']);if(!$target||$target['head_hash']!==$b['targetHeadHash'])throw new NativeError('crypto_scope_head_changed',409);
            $members=array_values(array_filter($this->scopes()->body($target)['members'],static fn($m)=>$m['accountId']===$command['accountId']&&$m['manageKeys']));if(count($members)!==1)throw new NativeError('permission_revoked',403);
            $account=$op==='crypto2.exports.delegation.directory'?$command['accountId']:$d['bridgeRecipient']['accountId'];
            if($op==='crypto2.exports.recipient.directory'&&$account!==$b['capture3Context']['target']['accountId'])throw new NativeError('crypto_account_choices_recipient_changed',409);
            $current=(new NativeCryptoDirectoryV2($this->container))->current($account);if(!$current)throw new NativeError('crypto_member_directory_pending',409);
            $after=$p['afterGeneration']??0;$limit=$p['limit']??20;if(!is_int($after)||$after<0||$after>(int)$current['generation']||!is_int($limit)||$limit<1||$limit>20)throw new NativeError('invalid_cursor');
            $rows=$this->many('SELECT generation,authorization FROM familyhub_crypto_directory WHERE account_id=? AND generation>? AND generation<=? ORDER BY generation LIMIT '.($limit+1),[$account,$after,$current['generation']]);$page=array_slice($rows,0,$limit);
            $out=['accountId'=>$account,'generation'=>(int)$current['generation'],'headHash'=>$current['head_hash'],'snapshotHash'=>$current['snapshot_hash'],'deviceSnapshotHash'=>$current['device_snapshot_hash'],'proofs'=>array_map(static fn($r)=>json_decode($r['authorization'],true,64,JSON_THROW_ON_ERROR),$page),'hasMore'=>count($rows)>$limit,'nextGeneration'=>$page?(int)end($page)['generation']:$after];if(strlen(json_encode($out,JSON_THROW_ON_ERROR))>1250000)throw new NativeError('crypto_directory_page_too_large',413);return $out;
        }
        if($op==='crypto2.exports.delegation.forOffer'){
            $this->fields($p,['variant','scopeId','offerHash'],['includeOffer']);if(isset($p['includeOffer'])&&$p['includeOffer']!==true)throw new NativeError('validation_error');$offer=$this->row('offers',$p['offerHash']);$b=$this->decode(json_decode($offer['authorization'],true,34,JSON_THROW_ON_ERROR));$this->context($b);
            if($p['variant']!==self::VARIANT||$p['scopeId']!==$b['targetScopeId'])throw new NativeError('permission_revoked',403);
            if($b['accountId']===$actor['user']['account_id'])$this->source($b,$actor);else{try{$this->target($b,$actor,true);}catch(NativeError $e){if($e->status!==403)throw $e;$this->target($b,$actor,false,!isset($b['capture3Context']));$recipient=false;foreach($this->many('SELECT authorization FROM familyhub_crypto_export_delegations_v2 WHERE offer_hash=?',[$p['offerHash']]) as $r){$d=$this->decode(json_decode($r['authorization'],true,34,JSON_THROW_ON_ERROR));if(($d['payload']['variant']??null)===self::VARIANT&&$d['payload']['bridgeRecipient']['accountId']===$actor['user']['account_id']&&$d['payload']['bridgeRecipient']['deviceId']===$actor['device']['id'])$recipient=true;}if(!$recipient)throw new NativeError('permission_revoked',403);}}
            $valid=[];foreach($this->many('SELECT authorization FROM familyhub_crypto_export_delegations_v2 WHERE offer_hash=? ORDER BY hash',[$p['offerHash']]) as $r){$proof=json_decode($r['authorization'],true,34,JSON_THROW_ON_ERROR);$d=$this->decode($proof);if(($d['payload']['variant']??null)!==self::VARIANT||$d['payload']['selectionHash']!==$b['selectionHash'])continue;$valid[]=$proof;if(count($valid)>1)throw new NativeError('crypto_export_delegation_ambiguous',409);}
            return ['authorization'=>$valid?$valid[0]:null]+(!empty($p['includeOffer'])?['offerAuthorization'=>json_decode($offer['authorization'],true,34,JSON_THROW_ON_ERROR)]:[]);
        }
        if($op!=='crypto2.exports.offers')throw new NativeError('unsupported_operation',404);
        $this->fields($p,['variant','scopeId','stage'],['afterHash','limit','captureId']);$sid=$this->uuid($p['scopeId']);$head=$this->scopes()->current($sid);if(!$head)throw new NativeError('crypto_scope_head_missing',409);
        if($p['variant']!==self::VARIANT||!in_array($p['stage'],['offers','certificates'],true))throw new NativeError('validation_error');
        $scope=$this->scope($sid,$actor['user']['id']);if($p['stage']==='offers')$this->scopes()->manager($head,$scope,$actor);else $this->scopes()->author($sid,$head['head_hash'],(int)$head['epoch'],(int)$scope['effective_access_revision'],$actor,'finance',!isset($p['captureId']));
        if(isset($p['captureId'])){$this->uuid($p['captureId']);$capture=$this->one("SELECT authorization FROM familyhub_crypto_captures_v3 WHERE capture_id=? AND account_id=? AND state='sealed'",[$p['captureId'],$actor['user']['account_id']]);if(!$capture)throw new NativeError('crypto_account_choices_capture_target',409);}
        $after=$p['afterHash']??'';if($after!=='')$this->hash($after);$limit=$p['limit']??20;if(!is_int($limit)||$limit<1||$limit>20)throw new NativeError('validation_error');
        $table=$p['stage']==='offers'?'offers':'certificates';$scopeColumn=$table==='offers'?'target_scope_id':'scope_id';$headColumn=$table==='offers'?'target_head_hash':'head_hash';
        $rows=$this->many('SELECT hash,authorization FROM familyhub_crypto_export_'.$table.'_v2 WHERE '.$scopeColumn.'=? AND '.$headColumn.'=? AND hash>? '.($table==='offers'?'AND expires_at>'.time().' ':'').'ORDER BY hash LIMIT '.($limit+1),[$sid,$head['head_hash'],$after]);$items=[];$scanned=$after;
        foreach(array_slice($rows,0,$limit) as $r){$scanned=$r['hash'];$proof=json_decode($r['authorization'],true,34,JSON_THROW_ON_ERROR);$b=$this->decode($proof);if(($b['variant']??null)!==self::VARIANT)continue;if(isset($p['captureId'])&&($b['capture3Context']['target']['captureId']??null)!==$p['captureId'])continue;if($table==='certificates'&&$b['bridge']['recipient']['accountId']!==$actor['user']['account_id'])continue;$items[]=['hash'=>$r['hash'],'authorization'=>$proof];}
        $out=['items'=>$items,'hasMore'=>count($rows)>$limit,'nextAfterHash'=>$scanned];if(strlen(json_encode($out,JSON_THROW_ON_ERROR))>1250000)throw new NativeError('crypto_account_choices_capacity',409);return $out;
    }
    public function write($op,$p,$actor,$proof,$command,$key){
        if($op==='crypto2.exports.propose'){
            $this->fields($p,['variant','selectionProof']);if($p['variant']!==self::VARIANT)throw new NativeError('crypto_account_choices_shape');
            $b=$this->proof($p['selectionProof'],$actor,$key);$this->source($b,$actor);$hash=$this->digest($p['selectionProof']);
            if(!$this->one('SELECT hash FROM familyhub_crypto_export_offers_v2 WHERE hash=?',[$hash]))$this->change('INSERT INTO familyhub_crypto_export_offers_v2 VALUES(?,?,?,?,?,?,?,?,?,?)',[$hash,$b['sourceScopeId'],'',$command['requestId'],$b['targetScopeId'],$b['targetHeadHash'],$actor['user']['account_id'],json_encode($p['selectionProof'],JSON_THROW_ON_ERROR),time(),time()+1800]);
            return ['offerHash'=>$hash];
        }
        if($op==='crypto2.exports.delegate'){
            $this->fields($p,['variant','offerHash','scopeId','membershipHeadHash','expectedAccessRevision','authorDirectoryHeadHash','delegationId','selectionHash','issuerAccountId','issuerDirectoryHeadHash','issuerRootSigningKeyBase64','issuerRootEncryptionKeyBase64','issuerIdentityEpochId','issuerDeviceSnapshotHash','bridgeRecipient']);
            $offer=$this->row('offers',$p['offerHash']);$b=$this->decode(json_decode($offer['authorization'],true,34,JSON_THROW_ON_ERROR));$this->context($b);[$scope,$head]=$this->target($b,$actor,true);$this->own($p['authorDirectoryHeadHash'],$actor);$this->uuid($p['delegationId']);
            if($p['variant']!==self::VARIANT||(int)$offer['expires_at']<=time()||$p['scopeId']!==$b['targetScopeId']||$p['membershipHeadHash']!==$b['targetHeadHash']||$p['expectedAccessRevision']!==(int)$scope['effective_access_revision']||$p['selectionHash']!==$b['selectionHash']||$p['issuerAccountId']!==$b['accountId'])throw new NativeError('crypto_account_choices_delegation',409);
            $issuer=(new NativeCryptoDirectoryV2($this->container))->current($p['issuerAccountId']);if(!$issuer||$issuer['device_snapshot_hash']!==$p['issuerDeviceSnapshotHash']||$issuer['identity_epoch_id']!==$p['issuerIdentityEpochId'])throw new NativeError('crypto_export_issuer_changed',409);
            if(isset($b['capture3Context'])){
                $this->scopes()->currentAuthorReference($p['issuerDirectoryHeadHash'],['user'=>['account_id'=>$b['accountId']],'device'=>['id'=>$b['deviceId']]]);
            }elseif($issuer['head_hash']!==$p['issuerDirectoryHeadHash'])throw new NativeError('crypto_export_issuer_changed',409);
            $snapshot=json_decode($issuer['snapshot'],true,34,JSON_THROW_ON_ERROR);if($snapshot['rootSigningKeyBase64']!==$p['issuerRootSigningKeyBase64']||$snapshot['rootEncryptionKeyBase64']!==$p['issuerRootEncryptionKeyBase64'])throw new NativeError('crypto_export_issuer_changed',409);
            $recipient=$p['bridgeRecipient'];$this->fields($recipient,['accountId','deviceId','directoryHeadHash','deviceSnapshotHash','encryptionPublicKeyBase64']);$member=array_values(array_filter($this->scopes()->body($head)['members'],fn($m)=>$m['accountId']===$recipient['accountId']&&in_array($m['financeRole'],isset($b['capture3Context'])?['read','write']:['write'],true)));if(count($member)!==1)throw new NativeError('finance_forbidden',403);
            $rd=(new NativeCryptoDirectoryV2($this->container))->current($recipient['accountId']);if(!$rd||$rd['head_hash']!==$recipient['directoryHeadHash']||$rd['device_snapshot_hash']!==$recipient['deviceSnapshotHash'])throw new NativeError('crypto_export_recipient_changed',409);$rs=json_decode($rd['snapshot'],true,34,JSON_THROW_ON_ERROR);$device=(new NativeCryptoDirectoryV2($this->container))->device($rs,$recipient['deviceId']);if(!$device||$device['revokedGeneration']!==null||$device['encryptionKeyBase64']!==$recipient['encryptionPublicKeyBase64'])throw new NativeError('crypto_export_recipient_changed',409);
            $hash=$this->digest($proof);if(!$this->one('SELECT hash FROM familyhub_crypto_export_delegations_v2 WHERE hash=?',[$hash]))$this->change('INSERT INTO familyhub_crypto_export_delegations_v2 VALUES(?,?,?,?,?,?)',[$hash,$b['targetScopeId'],$b['targetHeadHash'],$p['offerHash'],$b['accountId'],json_encode($proof,JSON_THROW_ON_ERROR)]);return ['delegationHash'=>$hash];
        }
        if($op!=='crypto2.exports.certify')throw new NativeError('unsupported_operation',404);
        $this->fields($p,['variant','offerHash','delegationHash','certificateProof']);$offer=$this->row('offers',$p['offerHash']);$delegation=$this->row('delegations',$p['delegationHash']);$b=$this->proof($p['certificateProof'],$actor,$key,true);$original=$this->decode(json_decode($offer['authorization'],true,34,JSON_THROW_ON_ERROR));$d=$this->decode(json_decode($delegation['authorization'],true,34,JSON_THROW_ON_ERROR));$dp=$d['payload'];
        $compare=$b;unset($compare['offerHash'],$compare['delegationHash'],$compare['bridge']);$compare['operation']='crypto2.exports.offer';
        if($p['variant']!==self::VARIANT||(int)$offer['expires_at']<=time()||$offer['issuer_account_id']!==$actor['user']['account_id']||$delegation['offer_hash']!==$p['offerHash']||$b['offerHash']!==$p['offerHash']||$b['delegationHash']!==$p['delegationHash']||$dp['selectionHash']!==$b['selectionHash']||NativeCryptoCodec::canonical((object)$compare)!==NativeCryptoCodec::canonical((object)$original))throw new NativeError('crypto_account_choices_certificate',409);
        $this->source($b,$actor);$manager=$this->one('SELECT user_id FROM familyhub_accounts WHERE account_id=?',[$d['accountId']]);if(!$manager)throw new NativeError('permission_revoked',403);$managerActor=['user'=>['id'=>$manager['user_id'],'account_id'=>$d['accountId']],'device'=>['id'=>$d['deviceId']]];[$scope,$head]=$this->target($b,$managerActor,true);$this->own($dp['authorDirectoryHeadHash'],$managerActor);if($dp['expectedAccessRevision']!==(int)$scope['effective_access_revision'])throw new NativeError('crypto_access_changed',409);
        $bridge=$b['bridge'];$this->fields($bridge,['recipient','requestId','sealedDisclosureBase64','ciphertextHash']);$cipher=base64_decode($bridge['sealedDisclosureBase64'],true);if($bridge['recipient']!==$dp['bridgeRecipient']||$bridge['requestId']!==$command['requestId']||$cipher===false||strlen($cipher)<48||strlen($cipher)>1048576||base64_encode($cipher)!==$bridge['sealedDisclosureBase64']||hash('sha256',$cipher)!==$this->hash($bridge['ciphertextHash']))throw new NativeError('crypto_account_choices_bridge',403);
        $hash=$this->digest($p['certificateProof']);if(!$this->one('SELECT hash FROM familyhub_crypto_export_certificates_v2 WHERE hash=?',[$hash]))$this->change('INSERT INTO familyhub_crypto_export_certificates_v2 VALUES(?,?,?,?,?,?,?,?,?)',[$hash,$b['targetScopeId'],$b['targetHeadHash'],$p['offerHash'],$p['delegationHash'],(isset($b['capture3Context'])?0:$b['sourceCheckpoint']['sequence']),$b['selectionHash'],json_encode($p['certificateProof'],JSON_THROW_ON_ERROR),$b['accountId']]);return ['certificateHash'=>$hash];
    }
}
