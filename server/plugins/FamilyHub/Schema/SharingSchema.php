<?php
namespace Kanboard\Plugin\FamilyHub\Schema;

/** Additive migration; historic memberships retain their issued policy. */
class SharingSchema
{
    public static function create(\PDO $pdo, $mysql)
    {
        $present = $mysql ? $pdo->query("SELECT column_name FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name='familyhub_scopes'")->fetchAll(\PDO::FETCH_COLUMN) : array_column($pdo->query('PRAGMA table_info(familyhub_scopes)')->fetchAll(\PDO::FETCH_ASSOC), 'name');
        if (!in_array('parent_scope_id', $present, true)) { $pdo->exec('ALTER TABLE familyhub_scopes ADD COLUMN parent_scope_id VARCHAR(36) DEFAULT NULL'); }
        $indexed=$mysql ? (int)$pdo->query("SELECT COUNT(*) FROM information_schema.statistics WHERE table_schema=DATABASE() AND table_name='familyhub_scopes' AND index_name='familyhub_scope_parent'")->fetchColumn()>0 : (int)$pdo->query("SELECT COUNT(*) FROM sqlite_master WHERE type='index' AND name='familyhub_scope_parent'")->fetchColumn()>0;
        if (!$indexed) { $pdo->exec('CREATE INDEX familyhub_scope_parent ON familyhub_scopes(parent_scope_id)'); }
        $pdo->exec('UPDATE familyhub_scopes SET parent_scope_id=organization_id WHERE parent_scope_id IS NULL AND organization_id IS NOT NULL');
        $inviteColumns=$mysql ? $pdo->query("SELECT column_name FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name='familyhub_invitations'")->fetchAll(\PDO::FETCH_COLUMN) : array_column($pdo->query('PRAGMA table_info(familyhub_invitations)')->fetchAll(\PDO::FETCH_ASSOC),'name');
        foreach (['invitation_contract'=>'INTEGER NOT NULL DEFAULT 1','access_scope'=>'VARCHAR(20) DEFAULT NULL'] as $column=>$definition) { if (!in_array($column,$inviteColumns,true)) { $pdo->exec('ALTER TABLE familyhub_invitations ADD COLUMN '.$column.' '.$definition); } }
        $pdo->exec('CREATE TABLE IF NOT EXISTS familyhub_record_relocations (scope_id VARCHAR(36) NOT NULL,record_id VARCHAR(36) NOT NULL,finance INTEGER NOT NULL,target_scope_id VARCHAR(36) NOT NULL,PRIMARY KEY(scope_id,record_id,finance))');
    }
}
