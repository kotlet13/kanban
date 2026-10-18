<?php
require '/var/www/app/app/common.php';
if (!defined('FAMILYHUB_DEVELOPMENT_MODE') || FAMILYHUB_DEVELOPMENT_MODE !== true) { throw new RuntimeException('Synthetic only'); }
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoRecordAddressV2 as Address;
use Kanboard\Plugin\FamilyHub\Model\NativeError;
$vectors=json_decode(file_get_contents(__DIR__.'/fixtures/e2ee-record-address-v2.json'),true,32,JSON_THROW_ON_ERROR);
$checks=0;
foreach($vectors as $vector){
    $context=$vector['context'];
    if(Address::sourceKind($vector['type'])!==$context['sourceKind'] || Address::domain($vector['type'])!==$context['domain'] || Address::derive($context['serverId'],$context['scopeId'],$context['domain'],$context['sourceKind'],$context['canonicalId'])!==$vector['wireId']){throw new RuntimeException('Address golden mismatch: '.$vector['type']);}
    $record=$context+['type'=>$vector['type'],'id'=>$vector['wireId'],'metadata'=>['identity'=>['sourceKind'=>$context['sourceKind'],'canonicalId'=>$context['canonicalId']]]];
    Address::verify($record);$checks++;
    $record['domain']=$context['domain']==='finance'?'content':'finance';
    try{Address::verify($record);throw new RuntimeException('Wrong domain accepted');}catch(NativeError $error){if($error->errorCode!=='crypto_record_identity_binding')throw $error;}$checks++;
}
foreach(['33333333-3333-8333-8333-333333333333','33333333-3333-0333-8333-333333333333','33333333-3333-4333-7333-333333333333'] as $invalid){try{Address::canonicalId($invalid);throw new RuntimeException('Invalid canonical namespace accepted');}catch(NativeError $e){if($e->errorCode!=='validation_error')throw $e;}$checks++;}
echo 'Crypto2 address vectors: '.$checks.' checks PASS'.PHP_EOL;
