<?php
namespace Kanboard\Plugin\FamilyHub\Schema;

/** Additive tables: no changes to accounts, sessions, identities or ledgers. */
class ModerationSchema
{
    public static function create(\PDO $pdo, $mysql)
    {
        $text=$mysql?'MEDIUMTEXT':'TEXT';
        $pdo->exec('CREATE TABLE IF NOT EXISTS familyhub_policy_acceptances (account_id VARCHAR(36) NOT NULL,policy_version INTEGER NOT NULL,accepted_at INTEGER NOT NULL,PRIMARY KEY(account_id,policy_version))');
        $pdo->exec('CREATE TABLE IF NOT EXISTS familyhub_moderation_reports (id VARCHAR(36) PRIMARY KEY,reporter_account_id VARCHAR(36) NOT NULL,request_id VARCHAR(36) NOT NULL,request_hash VARCHAR(64) NOT NULL,scope_id VARCHAR(36) NOT NULL,target_type VARCHAR(16) NOT NULL,target_id VARCHAR(36) NOT NULL,target_revision INTEGER NOT NULL,preview_hash VARCHAR(64) NOT NULL,reason VARCHAR(20) NOT NULL,details TEXT DEFAULT NULL,snapshot '.$text.' DEFAULT NULL,created_at INTEGER NOT NULL,status VARCHAR(16) NOT NULL,review_revision INTEGER NOT NULL DEFAULT 0,resolved_at INTEGER DEFAULT NULL,redacted_at INTEGER DEFAULT NULL,UNIQUE(reporter_account_id,request_id))');
        $pdo->exec('CREATE TABLE IF NOT EXISTS familyhub_moderation_audit (id VARCHAR(36) PRIMARY KEY,report_id VARCHAR(36) NOT NULL,admin_id INTEGER NOT NULL,action VARCHAR(32) NOT NULL,note TEXT NOT NULL,created_at INTEGER NOT NULL,review_revision INTEGER NOT NULL,UNIQUE(report_id,review_revision))');
        $pdo->exec('CREATE TABLE IF NOT EXISTS familyhub_moderation_blocks (scope_id VARCHAR(36) NOT NULL,account_id VARCHAR(36) NOT NULL,created_at INTEGER NOT NULL,PRIMARY KEY(scope_id,account_id))');
    }
}
