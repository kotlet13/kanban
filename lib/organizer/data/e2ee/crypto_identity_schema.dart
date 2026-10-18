/// Additive schema 11. Secret rows are protected by the physical vault and are
/// excluded from ordinary JSON evidence/exports; recovery grants stay separate.
const cryptoIdentitySchema = <String>[
  '''CREATE TABLE IF NOT EXISTS crypto_directory_event_index (
    partition TEXT NOT NULL,account_id TEXT NOT NULL,generation INTEGER NOT NULL,operation TEXT NOT NULL,
    PRIMARY KEY(partition,account_id,generation))''',
  '''CREATE TABLE IF NOT EXISTS crypto_directory_replay_staging (
    partition TEXT NOT NULL,run_id TEXT NOT NULL,account_id TEXT NOT NULL,generation INTEGER NOT NULL,
    head_hash TEXT NOT NULL,previous_head_hash TEXT NOT NULL,command_hash TEXT NOT NULL,authorization BLOB NOT NULL,
    PRIMARY KEY(partition,run_id,generation))''',
  '''CREATE TABLE IF NOT EXISTS crypto_restore_record_anchors (
    partition TEXT NOT NULL,scope_id TEXT NOT NULL,domain TEXT NOT NULL,record_id TEXT NOT NULL,
    revision INTEGER NOT NULL,proof_hash TEXT NOT NULL,wire TEXT NOT NULL,
    PRIMARY KEY(partition,scope_id,domain,record_id))''',
  '''CREATE TABLE IF NOT EXISTS crypto_restore_scoped_directories (
    partition TEXT NOT NULL,scope_id TEXT NOT NULL,head_hash TEXT NOT NULL,account_id TEXT NOT NULL,
    directory_head_hash TEXT NOT NULL,entries BLOB NOT NULL,
    PRIMARY KEY(partition,scope_id,head_hash,account_id,directory_head_hash))''',

  'CREATE TABLE IF NOT EXISTS crypto_restore_anchor_journal(partition TEXT NOT NULL,evidence_digest TEXT NOT NULL,kind TEXT NOT NULL,identity TEXT NOT NULL,previous_value TEXT,value TEXT NOT NULL,state TEXT NOT NULL,PRIMARY KEY(partition,evidence_digest,kind,identity))',
  'CREATE TABLE IF NOT EXISTS crypto_invitation_deliveries(partition TEXT NOT NULL,request_id TEXT NOT NULL,token TEXT NOT NULL,PRIMARY KEY(partition,request_id))',
  'CREATE TABLE IF NOT EXISTS crypto_invitation_drafts(partition TEXT NOT NULL,action_id TEXT NOT NULL,payload TEXT NOT NULL,token TEXT,PRIMARY KEY(partition,action_id))',
  'CREATE TABLE IF NOT EXISTS crypto_document_actions(partition TEXT NOT NULL,request_id TEXT NOT NULL,operation TEXT NOT NULL,request_hash TEXT NOT NULL,intent TEXT NOT NULL,result TEXT,PRIMARY KEY(partition,request_id))',
  'CREATE TABLE IF NOT EXISTS crypto_document_jobs(partition TEXT NOT NULL,scope_id TEXT NOT NULL,id TEXT NOT NULL,record_id TEXT NOT NULL,operation_id TEXT NOT NULL,kind TEXT NOT NULL,descriptor TEXT NOT NULL,state TEXT NOT NULL,source_hash TEXT NOT NULL,PRIMARY KEY(partition,id),UNIQUE(partition,scope_id,record_id,operation_id))',
  'CREATE TABLE IF NOT EXISTS crypto_document_chunks(partition TEXT NOT NULL,id TEXT NOT NULL,offset INTEGER NOT NULL,cipher BLOB NOT NULL,PRIMARY KEY(partition,id,offset))',
  'CREATE TABLE IF NOT EXISTS crypto_document_uploads(partition TEXT NOT NULL,scope_id TEXT NOT NULL,id TEXT NOT NULL,metadata TEXT NOT NULL,received INTEGER NOT NULL,state TEXT NOT NULL,PRIMARY KEY(partition,id))',
  'CREATE TABLE IF NOT EXISTS crypto_document_upload_chunks(partition TEXT NOT NULL,id TEXT NOT NULL,offset INTEGER NOT NULL,bytes BLOB NOT NULL,PRIMARY KEY(partition,id,offset))',
  'CREATE TABLE IF NOT EXISTS crypto_document_cache(partition TEXT NOT NULL,id TEXT NOT NULL,descriptor_hash TEXT NOT NULL,bytes BLOB NOT NULL,PRIMARY KEY(partition,id))',
  '''CREATE TABLE IF NOT EXISTS crypto_scope_review_records (
    partition TEXT NOT NULL,scope_id TEXT NOT NULL,review_id TEXT NOT NULL,
    domain TEXT NOT NULL,record_id TEXT NOT NULL,wire TEXT NOT NULL,descriptor BLOB NOT NULL,
    PRIMARY KEY(partition,scope_id,review_id,domain,record_id))''',
  '''CREATE TABLE IF NOT EXISTS crypto_identity_secrets (
    partition TEXT NOT NULL, device_id TEXT NOT NULL,
    signing_secret BLOB NOT NULL, encryption_secret BLOB NOT NULL,
    signing_public TEXT NOT NULL, encryption_public TEXT NOT NULL,
    phase TEXT NOT NULL, prepared_recovery BLOB, encrypted_root BLOB NOT NULL,
    identity_epoch_id TEXT, PRIMARY KEY(partition, device_id))''',
  '''CREATE TABLE IF NOT EXISTS crypto_directory_pins (
    partition TEXT NOT NULL, server_id TEXT NOT NULL, account_id TEXT NOT NULL,
    root_signing_public TEXT NOT NULL, root_encryption_public TEXT NOT NULL,
    fingerprint TEXT NOT NULL, min_generation INTEGER NOT NULL,
    head_hash TEXT NOT NULL, snapshot_hash TEXT NOT NULL,
    device_snapshot_hash TEXT NOT NULL, identity_epoch_id TEXT NOT NULL,
    trust_state TEXT NOT NULL, PRIMARY KEY(partition, account_id))''',
  '''CREATE TABLE IF NOT EXISTS crypto_directory_entries (
    partition TEXT NOT NULL, account_id TEXT NOT NULL, generation INTEGER NOT NULL,
    head_hash TEXT NOT NULL, previous_head_hash TEXT NOT NULL, command_hash TEXT NOT NULL,
    authorization BLOB NOT NULL, PRIMARY KEY(partition, account_id, generation),
    UNIQUE(partition, account_id, head_hash))''',
  '''CREATE TABLE IF NOT EXISTS crypto_directory_snapshots (
    partition TEXT NOT NULL, account_id TEXT NOT NULL, head_hash TEXT NOT NULL,
    generation INTEGER NOT NULL, snapshot_hash TEXT NOT NULL,
    device_snapshot_hash TEXT NOT NULL, snapshot BLOB NOT NULL,
    PRIMARY KEY(partition, account_id, head_hash))''',
  '''CREATE TABLE IF NOT EXISTS crypto_trusted_identities (
    partition TEXT NOT NULL, server_id TEXT NOT NULL, account_id TEXT NOT NULL,
    root_signing_public TEXT NOT NULL, root_encryption_public TEXT NOT NULL,
    fingerprint TEXT NOT NULL, verification_method TEXT NOT NULL,
    compared_head_hash TEXT, compared_generation INTEGER,
    PRIMARY KEY(partition, server_id, account_id))''',
  '''CREATE TABLE IF NOT EXISTS crypto_scope_heads (
    partition TEXT NOT NULL, scope_id TEXT NOT NULL, head_hash TEXT NOT NULL,
    generation INTEGER NOT NULL, epoch INTEGER NOT NULL, epoch_id TEXT NOT NULL,
    previous_head_hash TEXT NOT NULL, body BLOB NOT NULL, authorization BLOB NOT NULL,
    PRIMARY KEY(partition, scope_id, head_hash))''',
  '''CREATE TABLE IF NOT EXISTS crypto_scope_keys (
    partition TEXT NOT NULL, scope_id TEXT NOT NULL, domain TEXT NOT NULL,
    epoch INTEGER NOT NULL, epoch_id TEXT NOT NULL, key_id TEXT NOT NULL,
    key_bytes BLOB NOT NULL, scope_head_hash TEXT NOT NULL, grant BLOB NOT NULL,
    recovery_wrapping_durable INTEGER NOT NULL, write_ready INTEGER NOT NULL,
    PRIMARY KEY(partition, scope_id, domain, epoch_id, key_id))''',
  '''CREATE TABLE IF NOT EXISTS crypto_identity_requests (
    partition TEXT NOT NULL, request_id TEXT NOT NULL, operation TEXT NOT NULL,
    stage TEXT NOT NULL, authorization BLOB NOT NULL,
    receipt BLOB, retired INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY(partition, request_id))''',
  '''CREATE TABLE IF NOT EXISTS crypto_membership_intents (
    partition TEXT NOT NULL, scope_id TEXT NOT NULL, intent_id TEXT NOT NULL,
    state TEXT NOT NULL, payload BLOB NOT NULL, authorization BLOB,
    PRIMARY KEY(partition, scope_id, intent_id))''',
  '''CREATE TABLE IF NOT EXISTS crypto_scope_closures (
    partition TEXT NOT NULL, scope_id TEXT NOT NULL, domain TEXT NOT NULL,
    epoch INTEGER NOT NULL, candidate_head_hash TEXT NOT NULL, manifest_hash TEXT NOT NULL,
    history_basis TEXT NOT NULL, authorization BLOB NOT NULL, descriptors BLOB NOT NULL,
    PRIMARY KEY(partition,scope_id,domain,epoch,candidate_head_hash))''',
  '''CREATE TABLE IF NOT EXISTS crypto_membership_action_keys (
    partition TEXT NOT NULL,scope_id TEXT NOT NULL,action_key TEXT NOT NULL,
    request_id TEXT NOT NULL,PRIMARY KEY(partition,scope_id,action_key),
    UNIQUE(partition,request_id))''',
  '''CREATE TABLE IF NOT EXISTS crypto_export_drafts (
    partition TEXT NOT NULL, scope_id TEXT NOT NULL, action_id TEXT NOT NULL,
    payload TEXT NOT NULL, PRIMARY KEY(partition,scope_id,action_id))''',
];
