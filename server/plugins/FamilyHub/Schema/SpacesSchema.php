<?php
namespace Kanboard\Plugin\FamilyHub\Schema;

/** No historic permission widening: policy 2 requires explicit publication or preview. */
class SpacesSchema
{
    public static function create(\PDO $pdo, $mysql)
    {
        $present = $mysql ? $pdo->query("SELECT column_name FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name='familyhub_scopes'")->fetchAll(\PDO::FETCH_COLUMN) : array_column($pdo->query('PRAGMA table_info(familyhub_scopes)')->fetchAll(\PDO::FETCH_ASSOC), 'name');
        foreach (['access_policy_version'=>'INTEGER NOT NULL DEFAULT 1','access_revision'=>'BIGINT NOT NULL DEFAULT 0','address'=>'VARCHAR(2000) DEFAULT NULL','metadata_revision'=>'BIGINT NOT NULL DEFAULT 0'] as $name=>$definition) {
            if (!in_array($name,$present,true)) { $pdo->exec('ALTER TABLE familyhub_scopes ADD COLUMN '.$name.' '.$definition); }
        }
        $pdo->exec('CREATE TABLE IF NOT EXISTS familyhub_scope_revocations (scope_id VARCHAR(36) NOT NULL, account_id VARCHAR(36) NOT NULL, PRIMARY KEY(scope_id,account_id))');
        $pdo->exec('CREATE TABLE IF NOT EXISTS familyhub_organization_leaders (scope_id VARCHAR(36) NOT NULL, account_id VARCHAR(36) NOT NULL, PRIMARY KEY(scope_id,account_id))');
    }
}
