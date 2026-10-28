<?php
/** One fresh disposable DB per invocation. No application config/bootstrap. */
require '/var/www/app/vendor/autoload.php';
spl_autoload_register(function($c){$prefix='Kanboard\\Plugin\\FamilyHub\\';if(str_starts_with($c,$prefix))require '/source/server/plugins/FamilyHub/'.str_replace('\\','/',substr($c,strlen($prefix))).'.php';});
require __DIR__.'/ResetDatabase.php';
$mysql=getenv('FRESH_RESET_MYSQL')==='1';define('DB_DRIVER',$mysql?'mysql':'sqlite');
$p=new PDO($mysql?'mysql:host=127.0.0.1;dbname=fresh_reset_synthetic;charset=utf8mb4':'sqlite::memory:',$mysql?'root':null,null,[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION]);
require '/var/www/app/app/Schema/'.($mysql?'Mysql':'Sqlite').'.php';
for($v=1;$v<=\Schema\VERSION;$v++){ $f='Schema\\version_'.$v;if(function_exists($f))$f($p); }
require '/source/server/plugins/FamilyHub/Schema/'.($mysql?'Mysql':'Sqlite').'.php';
for($v=1;$v<=23;$v++)('Kanboard\\Plugin\\FamilyHub\\Schema\\version_'.$v)($p);
// Independent expected complete schema captured BEFORE synthetic user/business inserts.
$r=new FamilyHubFreshReset($p);$defs=$r->definitions();$users=[];
for($n=0;$n<3;$n++){$id=$n+2;$name='fresh_synthetic_'.$n;$aid=sprintf('%08d-1111-4111-a111-111111111111',$id);$p->prepare("INSERT INTO users(id,username,password,role) VALUES(?,?,?,'app-user')")->execute([$id,$name,password_hash('fixture-only',PASSWORD_BCRYPT)]);$p->prepare('INSERT INTO familyhub_accounts VALUES(?,?)')->execute([$id,$aid]);$users[]=['id'=>$id,'username'=>$name,'role'=>'app-user'];}
$aid='00000002-1111-4111-a111-111111111111';$sid='77777777-1111-4111-a111-111111111111';
$p->exec("INSERT INTO familyhub_scopes(id,kind,name,owner_id,created_at) VALUES('$sid','household','synthetic',2,1)");
$p->exec("INSERT INTO familyhub_members(scope_id,user_id,account_id,role) VALUES('$sid',2,'$aid','owner')");
$p->exec("INSERT INTO familyhub_records(scope_id,id,type,revision,sequence,updated_at,payload) VALUES('$sid','88888888-1111-4111-a111-111111111111','task',1,1,'synthetic','{}')");
$p->exec("INSERT INTO familyhub_devices(id,user_id,account_id,name,token_hash,credentials_hash,created_at,expires_at) VALUES('99999999-1111-4111-a111-111111111111',2,'$aid','fixture','oldtoken','oldcredential',1,9999999999)");
$p->exec("INSERT INTO familyhub_crypto_migrations_v2(id,component_id,component_hash,scope_ids,participants_hash,state,challenge,created_at,updated_at) VALUES('migration','component','hash','[]','hash','staged','challenge',1,1)");
$p->exec("INSERT INTO familyhub_crypto_blob_chunks_v2(scope_id,blob_id,chunk_offset,data) VALUES('$sid','blob',0,'c3ludGhldGlj')");
function check($ok,$label){if(!$ok)throw new RuntimeException('FAIL:'.$label);echo 'PASS: '.$label."\n";}
function denied($fn,$prefix,$label){try{$fn();}catch(RuntimeException $e){check(str_starts_with($e->getMessage(),$prefix),$label);return;}throw new RuntimeException('FAIL:'.$label);}
$plan=$r->plan($defs,$users,3);check(count($plan['deleteOrder'])>150,'complete real schema23 plan');
check(count($plan['users'])===3&&$plan['counts']['familyhub_devices']===1,'exact account/session inventory');
denied(fn()=>$r->plan($defs,$users,2),'wrong_user_count','wrong target count rejected');
$bad=$users;$bad[0]['username']='wrong';denied(fn()=>$r->plan($defs,$bad,3),'users_mismatch','identity mismatch rejected');
$p->exec("INSERT INTO user_has_metadata(user_id,name,value) VALUES(2,'synthetic','keep')");
denied(fn()=>$r->plan($defs,$users,3),'core_user_reference','core user metadata reference stops before reset');
$p->exec('DELETE FROM user_has_metadata WHERE user_id=2');
$p->exec('CREATE TABLE familyhub_unknown_reset_fixture(id INTEGER)');denied(fn()=>$r->plan($defs,$users,3),'schema_mismatch','unreviewed table rejected');$p->exec('DROP TABLE familyhub_unknown_reset_fixture');
$maintenance=['http503'=>true,'allWorkersPaused'=>true,'restoreVerified'=>true,'filesQuarantined'=>true,'drainedSeconds'=>65];
$short=$maintenance;$short['drainedSeconds']=64;denied(fn()=>$r->apply($plan,$short),'drain_required','insufficient drain rejected');
$unpaused=$maintenance;$unpaused['allWorkersPaused']=false;denied(fn()=>$r->apply($plan,$unpaused),'maintenance_required','workers must be paused');
$p->exec('UPDATE familyhub_native_lock SET counter=1');denied(fn()=>$r->apply($plan,$maintenance),'stale_plan','changed data makes approved plan stale');$p->exec('UPDATE familyhub_native_lock SET counter=0');
$admin=$p->query('SELECT * FROM users WHERE id=1')->fetch(PDO::FETCH_ASSOC);$config=$p->query('SELECT * FROM settings')->fetchAll(PDO::FETCH_ASSOC);$result=$r->apply($plan,$maintenance);
check($result['newServerId']!==$plan['oldServerId'],'new server incarnation');
check($p->query('SELECT COUNT(*) FROM familyhub_devices')->fetchColumn()===0,'old bearer sessions absent');
check($p->query('SELECT COUNT(*) FROM familyhub_accounts')->fetchColumn()===0,'fresh first-account enrollment available');
check($p->query('SELECT COUNT(*) FROM familyhub_crypto_migrations_v2')->fetchColumn()===0&&$p->query('SELECT COUNT(*) FROM familyhub_crypto_blob_chunks_v2')->fetchColumn()===0,'staged migration and blob chunks removed');
check($p->query('SELECT * FROM users WHERE id=1')->fetch(PDO::FETCH_ASSOC)===$admin&&$p->query('SELECT * FROM settings')->fetchAll(PDO::FETCH_ASSOC)===$config,'admin and hosting settings exact');
check($r->definitions()===$defs,'all schema definitions unchanged');
denied(fn()=>$r->apply($plan,$maintenance),'users_mismatch','old approved plan cannot replay');
echo json_encode(['driver'=>$mysql?'MariaDB':'SQLite','status'=>'PASS','assertions'=>16,'result'=>$result],JSON_PRETTY_PRINT)."\n";
