<?php
/** Render-only fixture: no database, request capability or external connection. */
namespace Kanboard\Core { class Base {} }
namespace Kanboard\Controller { class BaseController {public $response,$configModel;public function __construct($c){$this->response=$c['response'];$this->configModel=$c['configModel'];}} }
namespace {
    define('FAMILYHUB_ENABLE_NATIVE_API',true);
    spl_autoload_register(function($c){$p='Kanboard\\Plugin\\FamilyHub\\';if(str_starts_with($c,$p))require __DIR__.'/../plugins/FamilyHub/'.str_replace('\\','/',substr($c,strlen($p))).'.php';});
    $config=new class {function get($k){return 'https://synthetic.invalid/jivie';}};
    $response=new class {public $body;function withHeader($k,$v){return $this;}function withBody($v){$this->body=$v;return $this;}function withStatusCode($s){return $this;}function send(){echo $this->body;}};
    $_SERVER=['REQUEST_METHOD'=>'GET','HTTPS'=>'on'];$_GET=['language'=>$argv[1]??'sl'];
    (new \Kanboard\Plugin\FamilyHub\Controller\EmailVerificationController(['configModel'=>$config,'response'=>$response]))->show();
}
