<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** Closed active-data cleanup. Signed/component/backup evidence is retained as
 * declared by policy4; this never rewrites history into a signed tombstone. */
class NativeCryptoScopeDeletionV2 extends NativeDatabase
{
    public function preview($p,$actor){return (new NativeCryptoScopeDeletionAuthorityV2($this->container,$this->bearer,$this->ip))->preview($p,$actor);}
    public function status($p,$actor){return (new NativeCryptoScopeDeletionAuthorityV2($this->container,$this->bearer,$this->ip))->status($p,$actor);}
    public function delete($p,$actor,$proof,$command){return (new NativeCryptoScopeDeletionAuthorityV2($this->container,$this->bearer,$this->ip))->delete($p,$actor,$proof,$command);}
    public function head($p,$actor){return (new NativeCryptoScopeDeletionAuthorityV2($this->container,$this->bearer,$this->ip))->head($p,$actor);}
    public function directory($p,$actor){return (new NativeCryptoScopeDeletionAuthorityV2($this->container,$this->bearer,$this->ip))->directory($p,$actor);}
    public function cleanupPending($sid)
    {
        if($this->one('SELECT path_hash FROM familyhub_scope_deletion_files WHERE scope_id=? LIMIT 1',[$sid]))return true;
        foreach($this->iterate('SELECT id FROM familyhub_attachments WHERE scope_id=?',[$sid]) as $r){if($this->one('SELECT storage_key FROM familyhub_document_cleanup WHERE storage_key=?',[hash('sha256',$sid.':'.$r['id'])]))return true;}
        return false;
    }
    public function retainedLegacySources($sid)
    {
        if($this->one('SELECT binding_id FROM familyhub_crypto_capture_sources_v3 WHERE scope_id=? LIMIT 1',[$sid]))return true;
        $state=$this->one('SELECT migration_id FROM familyhub_crypto_scopes WHERE scope_id=?',[$sid]);
        return $state&&!empty($state['migration_id'])&&(bool)$this->one('SELECT migration_id FROM familyhub_crypto_migration_portions_v2 WHERE migration_id=? LIMIT 1',[$state['migration_id']]);
    }
    public function erasePrivateData($sid){return $this->eraseActiveData($sid,false);}
    public function eraseActiveData($sid,$retainHistory)
    {
        // Reuse the existing transactional scrub + durable physical cleanup
        // queue. Nothing is unlinked before the surrounding SQL commit.
        (new NativeAttachmentService($this->container))->removeScope($sid);
        foreach($this->many('SELECT board_id,sha256 FROM familyhub_idea_assets WHERE scope_id=?',[$sid]) as $asset){
            if($retainHistory){$path='familyhub/ideas/'.hash('sha256',$sid.':'.$asset['board_id']).'/'.$asset['sha256'];$hash=hash('sha256',$path);if(!$this->one('SELECT path_hash FROM familyhub_scope_deletion_files WHERE scope_id=? AND path_hash=?',[$sid,$hash]))$this->change('INSERT INTO familyhub_scope_deletion_files VALUES(?,?,?)',[$sid,$hash,$path]);}
        }
        // Migration blob chunks have no scope column and must be removed using
        // the exact selected blob identity before its descriptor disappears.
        foreach($this->many('SELECT migration_id,id FROM familyhub_crypto_migration_blobs_v2 WHERE scope_id=?',[$sid]) as $b){
            $this->change('DELETE FROM familyhub_crypto_migration_blob_chunks_v2 WHERE migration_id=? AND blob_id=?',[$b['migration_id'],$b['id']]);
        }
        if($retainHistory){
            foreach($this->many('SELECT * FROM familyhub_crypto_records WHERE scope_id=?',[$sid]) as $r){
                $auth=json_decode($r['authorization'],true,34,JSON_THROW_ON_ERROR);[$body]=NativeCryptoCodec::decode($auth['recordProof']);
                $position=$this->one('SELECT sequence FROM familyhub_crypto_record_positions WHERE scope_id=? AND id=?',[$sid,$r['id']]);if(!$position){throw new NativeError('crypto_record_position_missing',503);}
                if(!$this->one('SELECT revision FROM familyhub_crypto_record_history WHERE scope_id=? AND id=? AND revision=?',[$sid,$r['id'],(int)$r['revision']])){
                    $this->change('INSERT INTO familyhub_crypto_record_history VALUES(?,?,?,?,?,?,?,?,?)',[$sid,$r['id'],(int)$r['revision'],(int)$position['sequence'],(int)$r['epoch'],$body['domain'],NativeCryptoV2Codec::hash((object)$auth['recordProof']),json_encode($auth['recordProof'],JSON_THROW_ON_ERROR),json_encode($auth['batchCommitment'],JSON_THROW_ON_ERROR)]);
                }
            }
        }
        foreach([
            'familyhub_crypto_blob_chunks_v2','familyhub_crypto_blobs_v2',
            'familyhub_crypto_blob_chunks','familyhub_crypto_blobs',
            'familyhub_crypto_record_history','familyhub_crypto_records',
            'familyhub_crypto_record_positions','familyhub_crypto_domain_cursors','familyhub_crypto_unique_refs',
            'familyhub_crypto_grant_entries_v2','familyhub_crypto_grant_states_v2','familyhub_crypto_grants','familyhub_crypto_domain_keys',
            'familyhub_crypto_reminders_v2','familyhub_crypto_scheduling_uses_v2','familyhub_crypto_scheduling_use_proofs_v2',
            'familyhub_crypto_migration_blobs_v2','familyhub_crypto_migration_stage_records_v2',
            'familyhub_attachment_chunks','familyhub_document_requests',
            'familyhub_idea_assets','familyhub_idea_report_assets',
            'familyhub_payment_events','familyhub_payment_projections','familyhub_payment_cash',
            'familyhub_finance_audit','familyhub_finance_records','familyhub_records',
            'familyhub_operations','familyhub_finance_operations',
        ] as $table){if($retainHistory&&in_array($table,['familyhub_crypto_record_history','familyhub_crypto_migration_stage_records_v2'],true)){continue;}$this->change('DELETE FROM '.$table.' WHERE scope_id=?',[$sid]);}
        $this->change("UPDATE familyhub_attachments SET deleted=1,name='',mime='',size=0,sha256='',received=0,complete=0,created_at=0,owner_account_id='',owner_device_id='',updated_at=? WHERE scope_id=?",[time(),$sid]);
        $this->change("UPDATE familyhub_tables SET deleted=1,title='',cells='{}',lease_hash=NULL,lease_nonce=NULL,lease_account_id=NULL,lease_device_id=NULL,lease_name=NULL,lease_expires=0 WHERE scope_id=?",[$sid]);
        $this->change('UPDATE familyhub_scopes SET documents_sequence=documents_sequence+1 WHERE id=?',[$sid]);
        // Mixed component batches, account archives, signed closures/heads and
        // digest streams can remain necessary for a surviving sibling's proof.
        $this->change('UPDATE familyhub_scopes SET deleted_at=?,name=?,owner_id=0 WHERE id=?',[time(),'Deleted encrypted scope',$sid]);
        $this->change('DELETE FROM familyhub_members WHERE scope_id=?',[$sid]);
        $this->change('DELETE FROM familyhub_personal_scopes WHERE scope_id=?',[$sid]);
    }
}
