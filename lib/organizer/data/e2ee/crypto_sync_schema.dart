import 'crypto_identity_schema.dart';

/// Additive schema11. These rows are inside the encrypted installation vault.
/// Exact signed requests and received proofs are retained independently of
/// mutable UI projections, legacy outboxes, and account/device key material.
const cryptoSyncSchema = <String>[
  ...cryptoIdentitySchema,
  '''CREATE TABLE crypto_capture_runs (
    partition TEXT NOT NULL,root_scope_id TEXT NOT NULL,capture_id TEXT NOT NULL,
    migration_id TEXT NOT NULL,key_id TEXT NOT NULL,component_id TEXT NOT NULL,
    journal TEXT NOT NULL,PRIMARY KEY(partition,root_scope_id),UNIQUE(partition,capture_id))''',
  '''CREATE TABLE crypto_capture_sources (
    partition TEXT NOT NULL,capture_id TEXT NOT NULL,binding_id TEXT NOT NULL,
    context TEXT NOT NULL,typed_row TEXT NOT NULL,binding TEXT NOT NULL,
    PRIMARY KEY(partition,capture_id,binding_id),UNIQUE(partition,capture_id,context))''',
  '''CREATE TABLE crypto_capture_keys (
    partition TEXT NOT NULL,capture_id TEXT NOT NULL,migration_id TEXT NOT NULL,
    key_id TEXT NOT NULL,key_bytes BLOB,context TEXT NOT NULL,envelopes TEXT,
    state TEXT NOT NULL CHECK(state IN ('draft','wrapped')),
    PRIMARY KEY(partition,capture_id),UNIQUE(partition,key_id))''',
  '''CREATE TABLE crypto_migration_witnesses (
    partition TEXT NOT NULL,binding_id TEXT NOT NULL,context TEXT NOT NULL,
    descriptor TEXT,PRIMARY KEY(partition,binding_id))''',
  '''CREATE TABLE crypto_migration_file_objects (
    partition TEXT NOT NULL,binding_id TEXT NOT NULL,context TEXT NOT NULL,
    descriptor TEXT,PRIMARY KEY(partition,binding_id))''',
  '''CREATE TABLE crypto_legacy_inventory_certificates (
    partition TEXT NOT NULL,certificate_hash TEXT NOT NULL,header TEXT NOT NULL,
    manifest_root TEXT NOT NULL,authorization TEXT NOT NULL,event_authorization TEXT NOT NULL,
    complete INTEGER NOT NULL CHECK(complete IN (0,1)),
    PRIMARY KEY(partition,certificate_hash))''',
  '''CREATE TABLE crypto_legacy_inventory_rows (
    partition TEXT NOT NULL,certificate_hash TEXT NOT NULL,scope_id TEXT NOT NULL,
    receipt_kind TEXT NOT NULL,legacy_id TEXT NOT NULL,legacy_device_id TEXT NOT NULL,
    binding_id TEXT NOT NULL,source_commitment TEXT NOT NULL,
    PRIMARY KEY(partition,certificate_hash,scope_id,receipt_kind,legacy_id,legacy_device_id),
    UNIQUE(partition,certificate_hash,binding_id))''',
  '''CREATE TABLE crypto_domain_inventory_rows (
    partition TEXT NOT NULL,snapshot_id TEXT NOT NULL,record_id TEXT NOT NULL,
    revision INTEGER NOT NULL,proof_hash TEXT NOT NULL,sequence INTEGER NOT NULL,record_epoch INTEGER NOT NULL,
    PRIMARY KEY(partition,snapshot_id,record_id))''',
  '''CREATE TABLE crypto_domain_checkpoints (
    partition TEXT NOT NULL,scope_id TEXT NOT NULL,domain TEXT NOT NULL,head_hash TEXT NOT NULL,
    epoch INTEGER NOT NULL,access_revision INTEGER NOT NULL,sequence INTEGER NOT NULL,
    manifest_hash TEXT NOT NULL,record_count INTEGER NOT NULL,snapshot_id TEXT NOT NULL,
    authorization TEXT NOT NULL,history_basis TEXT NOT NULL,
    PRIMARY KEY(partition,scope_id,domain,head_hash,sequence))''',

  '''CREATE TABLE crypto_business_history_jobs (
    partition TEXT NOT NULL,scope_id TEXT NOT NULL,domain TEXT NOT NULL,record_id TEXT NOT NULL,
    target_revision INTEGER NOT NULL,target_hash TEXT NOT NULL,next_revision INTEGER NOT NULL,next_hash TEXT NOT NULL,complete INTEGER NOT NULL,
    PRIMARY KEY(partition,scope_id,domain,record_id,target_revision,target_hash))''',
  '''CREATE TABLE crypto_business_history_proofs (
    partition TEXT NOT NULL,scope_id TEXT NOT NULL,domain TEXT NOT NULL,record_id TEXT NOT NULL,
    revision INTEGER NOT NULL,proof_hash TEXT NOT NULL,wire TEXT NOT NULL,history_basis TEXT NOT NULL,
    PRIMARY KEY(partition,scope_id,domain,record_id,revision,proof_hash))''',
  '''CREATE TABLE crypto_business_history_restore_links (
    partition TEXT NOT NULL,scope_id TEXT NOT NULL,domain TEXT NOT NULL,record_id TEXT NOT NULL,
    target_revision INTEGER NOT NULL,target_hash TEXT NOT NULL,anchor_revision INTEGER NOT NULL,anchor_hash TEXT NOT NULL,
    PRIMARY KEY(partition,scope_id,domain,record_id,target_revision,target_hash,anchor_revision,anchor_hash))''',
  '''CREATE TABLE crypto_business_history_payloads (
    partition TEXT NOT NULL,scope_id TEXT NOT NULL,domain TEXT NOT NULL,record_id TEXT NOT NULL,
    revision INTEGER NOT NULL,proof_hash TEXT NOT NULL,previous_hash TEXT NOT NULL,raw_payload TEXT,record_body TEXT NOT NULL,
    PRIMARY KEY(partition,scope_id,domain,record_id,revision,proof_hash))''',
  '''CREATE TABLE crypto_business_addresses (
    partition TEXT NOT NULL,scope_id TEXT NOT NULL,domain TEXT NOT NULL,source_kind TEXT NOT NULL,
    canonical_id TEXT NOT NULL,wire_id TEXT NOT NULL,type TEXT NOT NULL,
    PRIMARY KEY(partition,scope_id,source_kind,canonical_id),UNIQUE(partition,scope_id,wire_id))''',
  '''CREATE TABLE crypto_business_records (
    partition TEXT NOT NULL,scope_id TEXT NOT NULL,domain TEXT NOT NULL,id TEXT NOT NULL,
    type TEXT NOT NULL,crypto_revision INTEGER NOT NULL,legacy_revision INTEGER NOT NULL DEFAULT 0,
    record_proof_hash TEXT NOT NULL,deleted INTEGER NOT NULL,raw_payload TEXT,
    projection TEXT NOT NULL,history_basis TEXT NOT NULL,
    revision_namespace TEXT NOT NULL DEFAULT 'crypto' CHECK(revision_namespace IN ('crypto','legacy','relocation')),
    PRIMARY KEY(partition,scope_id,domain,id))''',
  '''CREATE TABLE crypto_business_scope_descriptors (
    partition TEXT NOT NULL,scope_id TEXT NOT NULL,descriptor TEXT NOT NULL,
    source_proof_hash TEXT NOT NULL,PRIMARY KEY(partition,scope_id))''',
  '''CREATE TABLE crypto_business_requests (
    partition TEXT NOT NULL,operation_id TEXT NOT NULL,scope_id TEXT NOT NULL,domain TEXT NOT NULL,
    request_hash TEXT NOT NULL,request_id TEXT NOT NULL,record_id TEXT NOT NULL,
    PRIMARY KEY(partition,operation_id),UNIQUE(partition,request_id))''',
  '''CREATE TABLE crypto_archive_jobs (
    partition TEXT NOT NULL,migration_id TEXT NOT NULL,key_id TEXT NOT NULL,
    state TEXT NOT NULL,manifest TEXT,
    PRIMARY KEY(partition,migration_id),CHECK(state IN ('draft','staged','published','uploaded','verified')))''',
  '''CREATE TABLE crypto_archive_secrets (
    partition TEXT NOT NULL,migration_id TEXT NOT NULL,key_id TEXT NOT NULL,
    key_bytes BLOB,context TEXT,envelopes TEXT,state TEXT NOT NULL,
    PRIMARY KEY(partition,key_id),CHECK(state IN ('draft','wrapped')))''',
  '''CREATE TABLE crypto_archive_segments (
    partition TEXT NOT NULL,migration_id TEXT NOT NULL,key_id TEXT NOT NULL,
    id TEXT NOT NULL,segment_index INTEGER NOT NULL,size INTEGER NOT NULL DEFAULT 0,
    sha256 TEXT,state TEXT NOT NULL CHECK(state IN ('writing','complete')),
    PRIMARY KEY(partition,id),UNIQUE(partition,key_id,segment_index))''',
  '''CREATE TABLE crypto_archive_chunks (
    partition TEXT NOT NULL,segment_id TEXT NOT NULL,chunk_offset INTEGER NOT NULL,
    bytes BLOB NOT NULL,PRIMARY KEY(partition,segment_id,chunk_offset),
    FOREIGN KEY(partition,segment_id) REFERENCES crypto_archive_segments(partition,id))''',
  '''CREATE TABLE crypto_restore_fences (
    partition TEXT PRIMARY KEY,minimum_transport INTEGER NOT NULL,backup_id TEXT NOT NULL,
    state TEXT NOT NULL CHECK(state IN ('requires_reconciliation','verified_pending_secure_anchors','verified')),
    CHECK(minimum_transport>=2))''',
  '''CREATE TABLE crypto_restore_evidence (
    partition TEXT NOT NULL,backup_id TEXT NOT NULL,evidence TEXT NOT NULL,
    PRIMARY KEY(partition,backup_id))''',
  '''CREATE TABLE crypto_scope_state (
    partition TEXT NOT NULL,scope_id TEXT NOT NULL,domain TEXT NOT NULL,
    state TEXT NOT NULL DEFAULT 'legacy',epoch INTEGER NOT NULL DEFAULT 0,
    access_revision INTEGER NOT NULL DEFAULT 0,transport_cursor INTEGER NOT NULL DEFAULT 0,
    projection_cursor INTEGER NOT NULL DEFAULT 0,scope_sequence INTEGER NOT NULL DEFAULT 0,
    complete INTEGER NOT NULL DEFAULT 0,floor INTEGER NOT NULL DEFAULT 0,
    manifest TEXT,scan_generation INTEGER NOT NULL DEFAULT 0,PRIMARY KEY(partition,scope_id,domain),
    CHECK(domain IN ('content','finance')),CHECK(epoch>=0),CHECK(floor>=0),
    CHECK(transport_cursor>=0),CHECK(projection_cursor>=0))''',
  '''CREATE TABLE crypto_outbox (
    sequence INTEGER PRIMARY KEY AUTOINCREMENT,partition TEXT NOT NULL,
    request_id TEXT NOT NULL,operation TEXT NOT NULL,signed_body TEXT NOT NULL,
    request_hash TEXT NOT NULL,state TEXT NOT NULL DEFAULT 'pending',response TEXT,
    UNIQUE(partition,request_id),CHECK(state IN ('pending','applied','rejected','blocked')))''',
  'CREATE INDEX crypto_outbox_delivery ON crypto_outbox(partition,state,sequence)',
  '''CREATE TABLE crypto_outbox_attempts (
    sequence INTEGER PRIMARY KEY AUTOINCREMENT,partition TEXT NOT NULL,request_id TEXT NOT NULL,
    event TEXT NOT NULL,details TEXT NOT NULL)''',
  '''CREATE TABLE crypto_command_keys (
    partition TEXT NOT NULL,action_key TEXT NOT NULL,request_id TEXT NOT NULL,payload_hash TEXT NOT NULL,
    PRIMARY KEY(partition,action_key),UNIQUE(partition,request_id))''',
  '''CREATE TABLE crypto_outbox_records (
    partition TEXT NOT NULL,scope_id TEXT NOT NULL,domain TEXT NOT NULL,record_id TEXT NOT NULL,
    expected_revision INTEGER NOT NULL,request_id TEXT NOT NULL,
    PRIMARY KEY(partition,scope_id,domain,record_id,expected_revision),
    FOREIGN KEY(partition,request_id) REFERENCES crypto_outbox(partition,request_id))''',
  '''CREATE TABLE crypto_outbox_reconciliations (
    partition TEXT NOT NULL,old_request_id TEXT NOT NULL,new_request_id TEXT NOT NULL,
    reason TEXT NOT NULL CHECK(reason='definitive_rejection'),
    PRIMARY KEY(partition,old_request_id),UNIQUE(partition,new_request_id))''',
  '''CREATE TABLE crypto_received_candidates (
    partition TEXT NOT NULL,scope_id TEXT NOT NULL,domain TEXT NOT NULL,
    record_id TEXT NOT NULL,revision INTEGER NOT NULL,candidate_hash TEXT NOT NULL,
    sequence INTEGER NOT NULL,wire TEXT NOT NULL,verdict TEXT NOT NULL,error TEXT,
    batch_key TEXT,last_attempt INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY(partition,scope_id,domain,record_id,revision,candidate_hash))''',
  'CREATE INDEX crypto_candidate_pending ON crypto_received_candidates(partition,scope_id,domain,verdict,batch_key,last_attempt)',
  '''CREATE TABLE crypto_received (
    partition TEXT NOT NULL,scope_id TEXT NOT NULL,domain TEXT NOT NULL,
    record_id TEXT NOT NULL,revision INTEGER NOT NULL,sequence INTEGER NOT NULL,
    wire TEXT NOT NULL,verdict TEXT NOT NULL,error TEXT,superseded_by_revision INTEGER,history_basis TEXT,batch_key TEXT,last_attempt INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY(partition,scope_id,domain,record_id,revision),
    CHECK(revision>0),CHECK(sequence>0),
    CHECK(verdict IN ('received','verified','quarantined','superseded')))''',
  'CREATE INDEX crypto_received_projection ON crypto_received(partition,scope_id,domain,verdict,sequence)',
  '''CREATE TABLE crypto_migrations (
    partition TEXT NOT NULL,id TEXT NOT NULL,state TEXT NOT NULL,journal TEXT NOT NULL,
    PRIMARY KEY(partition,id))''',
  '''CREATE TABLE crypto_migration_staged_records (
    partition TEXT NOT NULL,migration_id TEXT NOT NULL,scope_id TEXT NOT NULL,domain TEXT NOT NULL,
    record_id TEXT NOT NULL,record_proof_hash TEXT NOT NULL,record_proof TEXT NOT NULL,
    batch_commitment TEXT NOT NULL,source_binding TEXT NOT NULL,
    PRIMARY KEY(partition,migration_id,scope_id,domain,record_id))''',
  '''CREATE TABLE crypto_legacy_receipts (
    partition TEXT NOT NULL,scope_id TEXT NOT NULL,domain TEXT NOT NULL,
    legacy_id TEXT NOT NULL,legacy_hash TEXT NOT NULL,outcome TEXT NOT NULL,
    replacement_id TEXT,response TEXT NOT NULL,
    PRIMARY KEY(partition,scope_id,domain,legacy_id),
    UNIQUE(partition,replacement_id))''',
];
