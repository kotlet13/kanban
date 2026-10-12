<?php
namespace Kanboard\Plugin\FamilyHub\Schema;

/** Additive metadata; immutable image bytes live beneath private DATA_DIR. */
class IdeasSchema
{
    public static function create(\PDO $pdo, $mysql)
    {
        $text=$mysql?'MEDIUMTEXT':'TEXT';
        $pdo->exec('CREATE TABLE IF NOT EXISTS familyhub_idea_assets (scope_id VARCHAR(36) NOT NULL,board_id VARCHAR(36) NOT NULL,sha256 VARCHAR(64) NOT NULL,owner_account_id VARCHAR(36) NOT NULL,mime VARCHAR(16) NOT NULL,size INTEGER NOT NULL,width INTEGER NOT NULL,height INTEGER NOT NULL,received INTEGER NOT NULL DEFAULT 0,complete INTEGER NOT NULL DEFAULT 0,published INTEGER NOT NULL DEFAULT 0,data '.$text.' DEFAULT NULL,created_at INTEGER NOT NULL,updated_at INTEGER NOT NULL,PRIMARY KEY(scope_id,board_id,sha256))');
        $pdo->exec('CREATE TABLE IF NOT EXISTS familyhub_idea_report_assets (report_id VARCHAR(36) NOT NULL,scope_id VARCHAR(36) NOT NULL,board_id VARCHAR(36) NOT NULL,sha256 VARCHAR(64) NOT NULL,PRIMARY KEY(report_id,sha256))');
    }
}
