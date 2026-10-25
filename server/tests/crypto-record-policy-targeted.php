<?php
/** New exact selector + hidden-cursor controls after the privacy correction. */
require __DIR__.'/crypto-record-policy-evidence-fixture.php';
$direct=$service->read('crypto2.scope.recordPolicy.baseline',['scopeId'=>id(3),'recordId'=>id(10)],$actor);
ck(count($direct['records'])===1&&$direct['records'][0]['entry']['id']===id(10)&&!$direct['hasMore'],'record selector returns only one exact baseline entry');
$hidden=$service->read('crypto2.scope.recordPolicy.baseline',['scopeId'=>id(3),'recordId'=>id(8)],$actor);
ck($hidden['records']===[]&&!$hidden['hasMore']&&$hidden['nextAfterId']===null&&!str_contains(json_encode($hidden),id(8)),'targeting denied finance reveals neither entry nor existence cursor');
$page=$service->read('crypto2.scope.recordPolicy.baseline',['scopeId'=>id(3),'limit'=>1],$actor);
ck(count($page['records'])===1&&$page['records'][0]['entry']['id']===id(10)&&$page['nextAfterId']===id(10)&&!$page['hasMore']&&!str_contains(json_encode($page),id(8)),'ordinary pagination filters hidden IDs before selecting its continuation');
$missing=$service->read('crypto2.scope.recordPolicy.baseline',['scopeId'=>id(3),'recordId'=>id(99)],$actor);
ck($missing['records']===[]&&!$missing['hasMore']&&$missing['nextAfterId']===null,'unknown exact selector has the same empty finite envelope');
deny(fn()=> $service->read('crypto2.scope.recordPolicy.baseline',['scopeId'=>id(3),'recordId'=>id(10),'afterId'=>id(8)],$actor),'invalid_cursor','exact lookup rejects an ambiguous pagination selector');
sql("INSERT INTO familyhub_finance_grants VALUES(?,?,'read')",[id(3),id(2)]);
$allowed=$service->read('crypto2.scope.recordPolicy.baseline',['scopeId'=>id(3),'recordId'=>id(8)],$actor);
ck(count($allowed['records'])===1&&$allowed['records'][0]['entry']['domain']==='finance'&&!$allowed['hasMore'],'authorized finance exact lookup retains its original domain guard');
echo json_encode(['test'=>'crypto-record-policy-targeted','status'=>'pass','checks'=>$checks,'fixture'=>'isolated-memory-sqlite','http'=>false,'proofVerification'=>false]).PHP_EOL;
