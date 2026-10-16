<?php
namespace Kanboard\Plugin\FamilyHub\Schema;

/** Additive schema19; never changes an existing record or preference. */
class DocumentsSchema
{
    public static function create(\PDO $pdo, $mysql)
    {
        $text=$mysql?'MEDIUMTEXT':'TEXT';$engine=$mysql?' ENGINE=InnoDB CHARSET=utf8mb4':'';
        $pdo->exec('CREATE TABLE IF NOT EXISTS familyhub_tables (scope_id VARCHAR(36) NOT NULL,id VARCHAR(36) NOT NULL,title VARCHAR(200) NOT NULL,cells '.$text.' NOT NULL,revision INTEGER NOT NULL,deleted INTEGER NOT NULL DEFAULT 0,updated_at BIGINT NOT NULL,created_by VARCHAR(36) NOT NULL,lease_hash VARCHAR(64) DEFAULT NULL,lease_nonce VARCHAR(64) DEFAULT NULL,lease_account_id VARCHAR(36) DEFAULT NULL,lease_device_id VARCHAR(36) DEFAULT NULL,lease_name VARCHAR(200) DEFAULT NULL,lease_expires BIGINT NOT NULL DEFAULT 0,PRIMARY KEY(scope_id,id))'.$engine);
        $pdo->exec('CREATE TABLE IF NOT EXISTS familyhub_attachments (scope_id VARCHAR(36) NOT NULL,id VARCHAR(36) NOT NULL,target_type VARCHAR(16) NOT NULL,target_id VARCHAR(36) NOT NULL,name VARCHAR(240) NOT NULL,mime VARCHAR(100) NOT NULL,size INTEGER NOT NULL,sha256 VARCHAR(64) NOT NULL,owner_account_id VARCHAR(36) NOT NULL,owner_device_id VARCHAR(36) NOT NULL,received INTEGER NOT NULL DEFAULT 0,complete INTEGER NOT NULL DEFAULT 0,deleted INTEGER NOT NULL DEFAULT 0,created_at BIGINT NOT NULL,updated_at BIGINT NOT NULL,PRIMARY KEY(scope_id,id))'.$engine);
        $pdo->exec('CREATE TABLE IF NOT EXISTS familyhub_attachment_chunks (scope_id VARCHAR(36) NOT NULL,attachment_id VARCHAR(36) NOT NULL,chunk_offset INTEGER NOT NULL,data '.$text.' NOT NULL,PRIMARY KEY(scope_id,attachment_id,chunk_offset))'.$engine);
        $pdo->exec('CREATE TABLE IF NOT EXISTS familyhub_document_requests (scope_id VARCHAR(36) NOT NULL,account_id VARCHAR(36) NOT NULL,device_id VARCHAR(36) NOT NULL,request_id VARCHAR(36) NOT NULL,object_id VARCHAR(36) NOT NULL,request_hash VARCHAR(64) NOT NULL,response '.$text.' NOT NULL,PRIMARY KEY(scope_id,account_id,device_id,request_id))'.$engine);
        $pdo->exec('CREATE TABLE IF NOT EXISTS familyhub_document_cleanup (storage_key VARCHAR(64) PRIMARY KEY,created_at BIGINT NOT NULL)'.$engine);
    }
    public static function ready(\PDO $pdo)
    {
        try {
            foreach (['familyhub_tables'=>'lease_hash,lease_nonce,lease_expires,cells,deleted','familyhub_attachments'=>'owner_device_id,received,deleted','familyhub_attachment_chunks'=>'chunk_offset,data','familyhub_document_requests'=>'request_hash,response','familyhub_document_cleanup'=>'storage_key'] as $table=>$columns) { $s=$pdo->query('SELECT '.$columns.' FROM '.$table.' WHERE 1=0');$s->closeCursor(); }
            return true;
        } catch (\Throwable $e) { return false; }
    }
}
