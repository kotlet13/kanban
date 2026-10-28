<?php
/** Offline reset primitive. No config loading, web route, credentials or CLI entry point.
 * Caller must enforce real maintenance/worker drain, verified restore and file journal.
 * Deliberately does not remove files, alter DDL, reset auto_increment, or run workers. */
final class FamilyHubFreshReset
{
    private PDO $pdo;
    private bool $mysql;
    public function __construct(PDO $pdo) {
        $this->pdo=$pdo;$this->mysql=$pdo->getAttribute(PDO::ATTR_DRIVER_NAME)==='mysql';
        if(!in_array($pdo->getAttribute(PDO::ATTR_DRIVER_NAME),['sqlite','mysql'],true))throw new RuntimeException('unsupported_driver');
        $pdo->setAttribute(PDO::ATTR_ERRMODE,PDO::ERRMODE_EXCEPTION);
        if(!$this->mysql)$pdo->exec('PRAGMA foreign_keys=ON');
    }
    private function quote(string $name): string {if(!preg_match('/^[a-z][a-z0-9_]*$/D',$name))throw new RuntimeException('unsafe_identifier');return '`'.$name.'`';}
    public function definitions(): array {
        $names=$this->mysql?$this->pdo->query("SELECT TABLE_NAME FROM information_schema.TABLES WHERE TABLE_SCHEMA=DATABASE() AND TABLE_TYPE='BASE TABLE' ORDER BY TABLE_NAME")->fetchAll(PDO::FETCH_COLUMN):$this->pdo->query("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name")->fetchAll(PDO::FETCH_COLUMN);
        $out=[];foreach($names as $name){$q=$this->quote($name);$out[$name]=$this->mysql?preg_replace('/ AUTO_INCREMENT=[0-9]+/', '', $this->pdo->query('SHOW CREATE TABLE '.$q)->fetch(PDO::FETCH_NUM)[1]):$this->pdo->query("SELECT sql FROM sqlite_master WHERE type='table' AND name=".$this->pdo->quote($name))->fetchColumn();}ksort($out);return $out;
    }
    private function rows(string $table): array {$r=$this->pdo->query('SELECT * FROM '.$this->quote($table))->fetchAll(PDO::FETCH_ASSOC);usort($r,fn($a,$b)=>strcmp(serialize($a),serialize($b)));return $r;}
    private function fingerprint(): string {$h=hash_init('sha256');hash_update($h,serialize($this->indexes()));foreach($this->definitions() as $t=>$ddl){hash_update($h,serialize([$t,$ddl,$this->rows($t)]));}return hash_final($h);}
    private function indexes(): array {return $this->mysql?[]:$this->pdo->query("SELECT name,sql FROM sqlite_master WHERE type='index' ORDER BY name")->fetchAll(PDO::FETCH_ASSOC);}
    private function assertNoExtraObjects(): void {
        $sql=$this->mysql?"SELECT (SELECT COUNT(*) FROM information_schema.VIEWS WHERE TABLE_SCHEMA=DATABASE())+(SELECT COUNT(*) FROM information_schema.TRIGGERS WHERE TRIGGER_SCHEMA=DATABASE())+(SELECT COUNT(*) FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA=DATABASE())+(SELECT COUNT(*) FROM information_schema.EVENTS WHERE EVENT_SCHEMA=DATABASE())":"SELECT COUNT(*) FROM sqlite_master WHERE type IN ('view','trigger')";
        if((int)$this->pdo->query($sql)->fetchColumn())throw new RuntimeException('unsupported_database_objects');
        if($this->mysql&&(int)$this->pdo->query("SELECT COUNT(*) FROM information_schema.KEY_COLUMN_USAGE WHERE REFERENCED_TABLE_SCHEMA=DATABASE() AND TABLE_SCHEMA<>DATABASE()")->fetchColumn())throw new RuntimeException('incoming_cross_schema_reference');
    }
    private function refs(string $table): array {
        if(!$this->mysql){$rows=$this->pdo->query('PRAGMA foreign_key_list('.$this->quote($table).')')->fetchAll(PDO::FETCH_ASSOC);return array_map(fn($r)=>[$r['from'],$r['table'],$r['to']],$rows);}
        $s=$this->pdo->prepare('SELECT COLUMN_NAME,REFERENCED_TABLE_NAME,REFERENCED_COLUMN_NAME FROM information_schema.KEY_COLUMN_USAGE WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME=? AND REFERENCED_TABLE_NAME IS NOT NULL');$s->execute([$table]);return $s->fetchAll(PDO::FETCH_NUM);
    }
    private function columns(string $table): array {if(!$this->mysql)return array_column($this->pdo->query('PRAGMA table_info('.$this->quote($table).')')->fetchAll(PDO::FETCH_ASSOC),'name');$s=$this->pdo->prepare('SELECT COLUMN_NAME FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME=?');$s->execute([$table]);return $s->fetchAll(PDO::FETCH_COLUMN);}
    /** expectedDefinitions must be independently approved, not derived from target DB. */
    public function plan(array $expectedDefinitions,array $exactUsers,int $expectedCount): array {
        if(count($exactUsers)!==$expectedCount||!$exactUsers)throw new RuntimeException('wrong_user_count');
        $this->assertNoExtraObjects();$defs=$this->definitions();if(isset($defs['sessions'])&&$this->rows('sessions'))throw new RuntimeException('nonempty_core_sessions');$expected=$expectedDefinitions;ksort($expected);if($defs!==$expected)throw new RuntimeException('schema_mismatch');
        $userIds=array_column($exactUsers,'id');sort($userIds);if(count(array_unique($userIds))!==count($userIds))throw new RuntimeException('duplicate_user');
        $users=[];foreach($this->rows('users') as $u){if(in_array((int)$u['id'],$userIds,true)){if(!empty($u['avatar_path']))throw new RuntimeException('target_core_avatar_requires_review');$users[]=['id'=>(int)$u['id'],'username'=>$u['username'],'role'=>$u['role']];if($u['role']==='app-admin')throw new RuntimeException('target_is_admin');}}
        usort($users,fn($a,$b)=>$a['id']<=>$b['id']);usort($exactUsers,fn($a,$b)=>$a['id']<=>$b['id']);if($users!==$exactUsers)throw new RuntimeException('users_mismatch');
        $admins=array_filter($this->rows('users'),fn($u)=>$u['role']==='app-admin'&&(int)$u['is_active']===1);if(!$admins)throw new RuntimeException('missing_admin');
        $mapped=array_map('intval',array_column($this->rows('familyhub_accounts'),'user_id'));sort($mapped);if($mapped!==$userIds)throw new RuntimeException('account_mapping_mismatch');
        $fh=array_values(array_filter(array_keys($defs),fn($n)=>str_starts_with($n,'familyhub_')));
        foreach(array_keys($defs) as $t){if($t==='users'||in_array($t,$fh,true))continue;
            $cols=[];foreach($this->refs($t) as [$col,$target,$to]){if($target==='users')$cols[]=$col;if(in_array($target,$fh,true))throw new RuntimeException('external_familyhub_reference');}
            foreach($this->columns($t) as $col)if(preg_match('/(^|_)(user|owner|creator|assignee)_id$/D',$col))$cols[]=$col;
            foreach(array_unique($cols) as $col){$s=$this->pdo->prepare('SELECT COUNT(*) FROM '.$this->quote($t).' WHERE '.$this->quote($col).' IN ('.implode(',',array_fill(0,count($userIds),'?')).')');$s->execute($userIds);if((int)$s->fetchColumn())throw new RuntimeException('core_user_reference:'.$t.':'.$col);}
        }
        // Reverse dependency topological order, retaining FK enforcement throughout.
        $pending=array_fill_keys($fh,true);$order=[];
        while($pending){$progress=false;foreach(array_keys($pending) as $candidate){$referenced=false;foreach(array_keys($pending) as $other){if($candidate===$other)continue;foreach($this->refs($other) as [, $target])if($target===$candidate)$referenced=true;}if(!$referenced){$order[]=$candidate;unset($pending[$candidate]);$progress=true;}}if(!$progress)throw new RuntimeException('cyclic_familyhub_schema');}
        $counts=[];foreach($fh as $t)$counts[$t]=count($this->rows($t));
        $sid=$this->pdo->query('SELECT server_id FROM familyhub_instance WHERE id=1')->fetchColumn();if(!is_string($sid)||!preg_match('/^[a-f0-9-]{36}$/D',$sid))throw new RuntimeException('invalid_server_id');
        return ['version'=>1,'beforeHash'=>$this->fingerprint(),'oldServerId'=>$sid,'users'=>$exactUsers,'deleteOrder'=>$order,'counts'=>$counts,'definitions'=>$defs];
    }
    public function apply(array $plan,array $maintenance): array {
        foreach(['http503','allWorkersPaused','restoreVerified','filesQuarantined'] as $k)if(($maintenance[$k]??null)!==true)throw new RuntimeException('maintenance_required:'.$k);
        if(($maintenance['drainedSeconds']??0)<65)throw new RuntimeException('drain_required');
        if($this->pdo->inTransaction())throw new RuntimeException('existing_transaction');
        // Transaction-local replan makes stale/replayed plans fail before any deletion.
        if($this->mysql)$this->pdo->exec('SET TRANSACTION ISOLATION LEVEL SERIALIZABLE');
        $this->pdo->beginTransaction();try{
            $current=$this->plan($plan['definitions'],$plan['users'],count($plan['users']));if($current!==$plan)throw new RuntimeException('stale_plan');
            $retained=[];foreach(array_keys($plan['definitions']) as $t)if(!str_starts_with($t,'familyhub_'))$retained[$t]=$this->rows($t);
            foreach($plan['deleteOrder'] as $t)$this->pdo->exec('DELETE FROM '.$this->quote($t));
            $s=$this->pdo->prepare('DELETE FROM users WHERE id=? AND username=? AND role=?');foreach($plan['users'] as $u){$s->execute([$u['id'],$u['username'],$u['role']]);if($s->rowCount()!==1)throw new RuntimeException('user_delete_mismatch');}
            $hex=bin2hex(random_bytes(16));$sid=substr($hex,0,8).'-'.substr($hex,8,4).'-4'.substr($hex,13,3).'-a'.substr($hex,17,3).'-'.substr($hex,20);
            if($sid===$plan['oldServerId'])throw new RuntimeException('identity_collision');
            $s=$this->pdo->prepare('INSERT INTO familyhub_instance(id,server_id) VALUES(1,?)');$s->execute([$sid]);$this->pdo->exec('INSERT INTO familyhub_native_lock(id,counter) VALUES(1,0)');
            foreach($retained as $t=>$before){if($t==='users')$before=array_values(array_filter($before,fn($r)=>!in_array((int)$r['id'],array_column($plan['users'],'id'),true)));if($this->rows($t)!==$before)throw new RuntimeException('retained_rows_changed:'.$t);}
            foreach($plan['deleteOrder'] as $t){$expected=in_array($t,['familyhub_instance','familyhub_native_lock'],true)?1:0;if(count($this->rows($t))!==$expected)throw new RuntimeException('reset_count_mismatch');}
            if($this->definitions()!==$plan['definitions'])throw new RuntimeException('ddl_changed');
            $this->pdo->commit();return ['version'=>1,'beforeHash'=>$plan['beforeHash'],'afterHash'=>$this->fingerprint(),'newServerId'=>$sid,'deletedUsers'=>count($plan['users']),'familyhubTables'=>count($plan['deleteOrder'])];
        }catch(Throwable $e){if($this->pdo->inTransaction())$this->pdo->rollBack();throw $e;}
    }
}
