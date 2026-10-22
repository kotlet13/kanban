<?php
/** Standalone in-memory read-contract controls; no app bootstrap or retained DB. */
namespace Kanboard\Core {
    // The real model SQL/visibility/validation code below runs unchanged; only
    // framework wiring, authenticated fixture identity, rate and transaction
    // setup are supplied locally. This is not an authentication test.
    class Base {
        protected $container;
        public function __construct($container) { $this->container = $container; }
        public function __get($name) { return $this->container[$name]; }
    }
}
namespace {
    use Kanboard\Plugin\FamilyHub\Model\NativeError;
    use Kanboard\Plugin\FamilyHub\Model\NativeScopeService;
    $model = is_dir(__DIR__.'/../plugins/FamilyHub/Model')
        ? __DIR__.'/../plugins/FamilyHub/Model/' : '/var/www/app/plugins/FamilyHub/Model/';
    foreach (['NativeError', 'NativeDatabase', 'NativeModerationService', 'NativeOrganizationAccess', 'NativeScopeService'] as $file) {
        require $model.$file.'.php';
    }
    class ScopeChangesFixture extends NativeScopeService {
        public function rate(array $buckets) {}
        protected function actor($lock = true) { return $this->container['actor']; }
        protected function transaction(callable $callback, $global = false, $snapshot = false) { return $callback(); }
        protected function scopeWire(array $scope) { throw new \RuntimeException('scopeWire must never run'); }
    }
    $pdo = new \PDO('sqlite::memory:');
    $pdo->setAttribute(\PDO::ATTR_ERRMODE, \PDO::ERRMODE_EXCEPTION);
    $pdo->exec('CREATE TABLE familyhub_instance(id INTEGER PRIMARY KEY,server_id TEXT);
        CREATE TABLE users(id INTEGER PRIMARY KEY,is_active INTEGER,username TEXT,name TEXT);
        CREATE TABLE familyhub_accounts(account_id TEXT PRIMARY KEY,user_id INTEGER);
        CREATE TABLE familyhub_scopes(id TEXT PRIMARY KEY,kind TEXT,name TEXT,owner_id INTEGER,parent_scope_id TEXT,organization_id TEXT,access_policy_version INTEGER,access_revision INTEGER,deleted_at INTEGER,archived INTEGER);
        CREATE TABLE familyhub_members(scope_id TEXT,user_id INTEGER,account_id TEXT,role TEXT,active INTEGER);
        CREATE TABLE familyhub_organization_leaders(scope_id TEXT,account_id TEXT);
        CREATE TABLE familyhub_moderation_blocks(scope_id TEXT,account_id TEXT);
        CREATE TABLE familyhub_scope_revocations(scope_id TEXT,account_id TEXT,PRIMARY KEY(scope_id,account_id));');
    function gid($number) { return sprintf('00000000-0000-4000-a000-%012d', $number); }
    function fixtureSql($sql, $params) { global $pdo; $q=$pdo->prepare($sql);$q->execute($params); }
    $account=gid(1); $other=gid(2); $server=gid(3); $device=gid(4);
    fixtureSql('INSERT INTO familyhub_instance VALUES(1,?)', [$server]);
    fixtureSql('INSERT INTO users VALUES(1,1,?,?)', ['synthetic','Synthetic']);
    fixtureSql('INSERT INTO users VALUES(2,1,?,?)', ['foreign','Foreign']);
    fixtureSql('INSERT INTO familyhub_accounts VALUES(?,1)', [$account]);
    fixtureSql('INSERT INTO familyhub_accounts VALUES(?,2)', [$other]);
    $parent=gid(10); $child=gid(11); $missingNotice=gid(12); $regrant=gid(13);
    $deleted=gid(14); $foreign=gid(15); $missingScope=gid(16); $unknown=gid(17);
    $inheritedParent=gid(18); $inheritedChild=gid(19);
    foreach ([$parent,$child,$missingNotice,$regrant,$deleted,$foreign,$inheritedParent,$inheritedChild] as $id) {
        $isChild=in_array($id,[$child,$inheritedChild],true);
        fixtureSql('INSERT INTO familyhub_scopes VALUES(?,?,?,?,?,NULL,3,2,?,0)', [
            $id,$isChild?'project':'household','PRIVATE_NAME_SENTINEL',2,
            $id===$child?$parent:($id===$inheritedChild?$inheritedParent:null),$id===$deleted?1:null]);
    }
    foreach ([$parent,$child,$regrant,$deleted,$missingScope,$inheritedChild] as $id) {
        fixtureSql('INSERT INTO familyhub_scope_revocations VALUES(?,?)', [$id,$account]);
    }
    fixtureSql('INSERT INTO familyhub_scope_revocations VALUES(?,?)', [$foreign,$other]);
    // A direct regrant and a still-active inherited parent must suppress stale notices.
    fixtureSql("INSERT INTO familyhub_members VALUES(?,1,?,'member',1)", [$regrant,$account]);
    fixtureSql("INSERT INTO familyhub_members VALUES(?,1,?,'member',1)", [$inheritedParent,$account]);
    $db = new class($pdo) {
        private $pdo;
        public function __construct($pdo) { $this->pdo=$pdo; }
        public function getConnection() { return $this->pdo; }
    };
    $service = new ScopeChangesFixture(['db'=>$db,'actor'=>[
        'user'=>['id'=>1,'account_id'=>$account], 'device'=>['id'=>$device]]]);
    $pdo->exec('PRAGMA query_only=ON');
    $changesBefore=(int)$pdo->query('SELECT total_changes()')->fetchColumn();
    $checks=0;
    function ck($ok,$label) { global $checks;if(!$ok){throw new \RuntimeException('FAIL: '.$label);}$checks++;echo 'PASS: '.$label.PHP_EOL; }
    function requestChanges($ids) { global $service;return $service->execute('scopes.list',[
        'includeAccessChanges'=>true,'accessChangesOnly'=>true,'scopeIds'=>$ids]); }
    function denyChanges($params,$label) {
        global $service;
        try {$service->execute('scopes.list',$params);$caught=false;}
        catch (NativeError $error) {$caught=$error->errorCode==='validation_error';}
        ck($caught,$label);
    }
    $ids=[$parent,$child,$missingNotice,$regrant,$deleted,$foreign,$missingScope,$unknown,$inheritedParent,$inheritedChild];
    sort($ids,SORT_STRING); $result=requestChanges($ids);
    $keys=array_keys($result);sort($keys,SORT_STRING);
    ck($keys===['accessChangesVersion','accountId','deletedScopeIds','deviceId','revokedScopeIds','scopeIds','serverId'], 'exact metadata-free response shape');
    ck($result['accessChangesVersion']===1 && $result['serverId']===$server && $result['accountId']===$account && $result['deviceId']===$device, 'version and authenticated identity binding');
    ck($result['scopeIds']===$ids, 'exact sorted requested scope echo');
    ck($result['revokedScopeIds']===[$parent,$child,$deleted], 'explicit parent and inherited-child notices only');
    ck($result['deletedScopeIds']===[$deleted] && !array_diff($result['deletedScopeIds'],$result['revokedScopeIds']), 'explicit deleted notice is a revoked subset');
    ck(!str_contains(json_encode($result),'PRIVATE_NAME_SENTINEL'), 'no scope name or scopeWire disclosure');
    ck(!in_array($regrant,$result['revokedScopeIds'],true) && !in_array($inheritedChild,$result['revokedScopeIds'],true), 'current direct and inherited visibility suppress stale notices');
    ck(!array_intersect([$missingNotice,$missingScope,$unknown,$foreign],$result['revokedScopeIds']), 'absence, unknown scope and another account are not denial evidence');
    ck(requestChanges([$unknown])['revokedScopeIds']===[], 'empty notice result preserves unknown access state');
    $valid=['includeAccessChanges'=>true,'accessChangesOnly'=>true,'scopeIds'=>[$parent]];
    denyChanges(['accessChangesOnly'=>true,'scopeIds'=>[$parent]], 'mode requires explicit access-change request');
    denyChanges(array_replace($valid,['includeAccessChanges'=>false]), 'false access-change request rejected');
    denyChanges(array_replace($valid,['accessChangesOnly'=>false]), 'false early-read mode rejected');
    denyChanges(array_replace($valid,['scopeIds'=>[]]), 'empty requested set rejected');
    denyChanges(array_replace($valid,['scopeIds'=>[$parent,$parent]]), 'duplicate scope IDs rejected');
    denyChanges(array_replace($valid,['scopeIds'=>[$child,$parent]]), 'unsorted scope IDs rejected');
    denyChanges(array_replace($valid,['scopeIds'=>['not-a-uuid']]), 'malformed scope ID rejected');
    denyChanges(array_replace($valid,['scopeIds'=>array_map('gid',range(100,150))]), 'more than fifty scope IDs rejected');
    denyChanges(array_replace($valid,['scopeIds'=>['scope'=>$parent]]), 'non-list requested set rejected');
    denyChanges($valid+['includePersonal'=>true], 'unrelated scope enumeration option rejected');
    ck((int)$pdo->query('SELECT total_changes()')->fetchColumn()===$changesBefore, 'read route performs no SQL mutation');
    echo json_encode(['guard'=>'scope-access-changes-only','checks'=>$checks,'status'=>'pass','fixture'=>'standalone-memory','retainedDatabaseAccess'=>false]).PHP_EOL;
}
