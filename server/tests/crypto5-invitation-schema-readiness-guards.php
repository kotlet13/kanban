<?php
/** NEW readiness/cache checks only; no previous invitation scenario is rerun. */
namespace Kanboard\Core { class Base {} }
namespace {
    spl_autoload_register(function($class){$prefix='Kanboard\\Plugin\\FamilyHub\\';if(str_starts_with($class,$prefix))require_once __DIR__.'/../plugins/FamilyHub/'.str_replace('\\','/',substr($class,strlen($prefix))).'.php';});
    use Kanboard\Plugin\FamilyHub\Model\NativeCryptoInvitationPreauthorizationV5 as Prepared;
    use Kanboard\Plugin\FamilyHub\Schema\PreauthorizedInvitationSchema;
    class CountingPDO extends \PDO {
        public $queries=0;
        public function query(string $query,?int $fetchMode=null,mixed ...$fetchModeArgs):\PDOStatement|false {
            $this->queries++;
            return $fetchMode===null?parent::query($query):parent::query($query,$fetchMode,...$fetchModeArgs);
        }
    }
    $pdo=new CountingPDO('sqlite::memory:');$pdo->setAttribute(\PDO::ATTR_ERRMODE,\PDO::ERRMODE_EXCEPTION);$checks=0;
    function ck($ok,$label){global $checks;if(!$ok)throw new \RuntimeException('FAIL: '.$label);$checks++;echo 'PASS: '.$label.PHP_EOL;}
    ck(!Prepared::ready($pdo),'schema20 connection does not advertise uninstalled preauthorization tables');
    PreauthorizedInvitationSchema::create($pdo,false);
    ck(Prepared::ready($pdo),'negative readiness never hides tables installed later on the same PDO');
    $baseline=$pdo->queries;for($i=0;$i<100;$i++)if(!Prepared::ready($pdo))throw new \RuntimeException('lost readiness');
    ck($pdo->queries===$baseline,'positive readiness performs no repeated catalog queries per member');
    $other=new CountingPDO('sqlite::memory:');$other->setAttribute(\PDO::ATTR_ERRMODE,\PDO::ERRMODE_EXCEPTION);
    ck(!Prepared::ready($other),'positive readiness is isolated to the exact PDO connection');
    echo json_encode(['status'=>'pass','checks'=>$checks,'fixture'=>'new in-memory SQLite readiness only','performanceClaim'=>'query count only; no speed benchmark or cached authorization']).PHP_EOL;
}
