<?php
namespace Kanboard\Plugin\FamilyHub\Schema;

/** Additive, repeatable migration. Parent links grant no inherited access. */
class OrganizationSchema
{
    public static function create(\PDO $pdo, $mysql)
    {
        $tables = [
            'familyhub_scopes' => ['organization_id' => 'VARCHAR(36) DEFAULT NULL', 'required_record_contract' => 'INTEGER NOT NULL DEFAULT 1', 'project_root_id'=>'VARCHAR(36) DEFAULT NULL', 'archived'=>'INTEGER NOT NULL DEFAULT 0'],
            'familyhub_finance_policy' => ['required_contract_version' => 'INTEGER NOT NULL DEFAULT 1'],
            'familyhub_finance_records' => ['contract_version' => 'INTEGER NOT NULL DEFAULT 1'],
        ];
        foreach ($tables as $table => $columns) {
            $present = $mysql ? $pdo->query("SELECT column_name FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name='$table'")->fetchAll(\PDO::FETCH_COLUMN) : array_column($pdo->query('PRAGMA table_info('.$table.')')->fetchAll(\PDO::FETCH_ASSOC), 'name');
            foreach ($columns as $name => $definition) {
                if (!in_array($name, $present, true)) { $pdo->exec('ALTER TABLE '.$table.' ADD COLUMN '.$name.' '.$definition); }
            }
        }
        $pdo->exec("UPDATE familyhub_scopes SET project_root_id=id WHERE organization_id IS NOT NULL AND project_root_id IS NULL");
    }
}
