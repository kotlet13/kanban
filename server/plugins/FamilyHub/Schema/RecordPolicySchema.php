<?php
namespace Kanboard\Plugin\FamilyHub\Schema;

/** Signed owner baseline sidecars leave all historical ciphertext/proofs intact. */
class RecordPolicySchema
{
    public static function create(\PDO $pdo,$mysql)
    {
        $text=$mysql?'MEDIUMTEXT':'TEXT';$suffix=$mysql?' ENGINE=InnoDB CHARSET=utf8mb4':'';
        $pdo->exec('CREATE TABLE IF NOT EXISTS familyhub_crypto_record_policy_baselines_v1(scope_id VARCHAR(36) NOT NULL,baseline_id VARCHAR(36) NOT NULL,membership_head_hash VARCHAR(64) NOT NULL,access_revision BIGINT NOT NULL,content_sequence BIGINT NOT NULL,finance_sequence BIGINT NOT NULL,account_id VARCHAR(36) NOT NULL,device_id VARCHAR(36) NOT NULL,prepare_authorization '.$text.' NOT NULL,activation_authorization '.$text.' DEFAULT NULL,baseline_count BIGINT DEFAULT NULL,baseline_root VARCHAR(64) DEFAULT NULL,PRIMARY KEY(scope_id,baseline_id))'.$suffix);
        $pdo->exec('CREATE TABLE IF NOT EXISTS familyhub_crypto_record_policy_entries_v1(scope_id VARCHAR(36) NOT NULL,baseline_id VARCHAR(36) NOT NULL,id VARCHAR(36) NOT NULL,record_proof_hash VARCHAR(64) NOT NULL,entry '.$text.' NOT NULL,stage_authorization '.$text.' NOT NULL,PRIMARY KEY(scope_id,baseline_id,id))'.$suffix);
        $pdo->exec('CREATE TABLE IF NOT EXISTS familyhub_crypto_record_policy_state_v1(scope_id VARCHAR(36) PRIMARY KEY,baseline_id VARCHAR(36) NOT NULL,policy_version INTEGER NOT NULL)'.$suffix);
    }
}
