<?php
/** Test-only loopback router. Does not load config or retained databases. */
namespace Kanboard\Core { class Base {protected $container;function __construct($c){$this->container=$c;}function __get($k){return $this->container[$k];}} }
namespace Kanboard\Controller { class BaseController {public $container,$response,$configModel;function __construct($c){$this->container=$c;$this->response=$c['response'];$this->configModel=$c['configModel'];}} }
namespace {
    define('FAMILYHUB_ENABLE_NATIVE_API',true);
    define('FAMILYHUB_ACCOUNT_MAIL_KEY_BASE64',base64_encode(str_repeat('S',32)));
    define('FAMILYHUB_SMTP_HOST','smtp.synthetic.invalid');define('FAMILYHUB_SMTP_FROM','sender@synthetic.invalid');
    spl_autoload_register(function($class){$prefix='Kanboard\\Plugin\\FamilyHub\\';if(str_starts_with($class,$prefix))require __DIR__.'/../plugins/FamilyHub/'.str_replace('\\','/',substr($class,strlen($prefix))).'.php';});
    $pdo=new \PDO('sqlite:/tmp/email-links-http.sqlite');$pdo->setAttribute(\PDO::ATTR_ERRMODE,\PDO::ERRMODE_EXCEPTION);
    $db=new class($pdo){function __construct(private $pdo){}function getConnection(){return $this->pdo;}};
    $config=new class {function get($k){return 'https://synthetic.invalid/jivie';}};
    $response=new class {function withHeader($k,$v){header($k.': '.$v);return $this;}function withBody($v){$this->body=$v;return $this;}function withStatusCode($s){http_response_code($s);return $this;}function send(){echo $this->body;}function json($v,$s=200){http_response_code($s);header('Content-Type: application/json');echo json_encode($v);}};
    // Simulated trusted HTTPS frontend; transport under test is local HTTP only.
    $_SERVER['HTTPS']='on';
    $controller=new \Kanboard\Plugin\FamilyHub\Controller\EmailVerificationController(['db'=>$db,'configModel'=>$config,'response'=>$response]);
    if (($_GET['action']??'')==='confirm')$controller->confirm();else $controller->show();
}
