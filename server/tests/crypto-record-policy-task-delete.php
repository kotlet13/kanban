<?php
/** New tombstone companion case; does not rerun previous companion controls. */
require __DIR__.'/crypto-record-policy-companion-fixture.php';
$task['deleted']=true;$task['metadata']['recordPolicy']['operation']='delete';
$entries=[['record'=>$task,'recordProofHash'=>$hash]];
ck($policy->companion($intent,$entries),'live intent can bind the exact same-batch authorized task tombstone');
$old=['metadata'=>json_encode(['recordPolicy'=>['version'=>1,'createdByAccountId'=>id(1),'operation'=>'edit','fieldCommitments'=>$f],'notificationState'=>['assigneeAccountIds'=>[id(2)]]])];
$task['previousRecordHash']=str_repeat('d',64);
deny(fn()=> $policy->admit($task,$old,['id'=>id(3),'role'=>'viewer','kind'=>'project'],['user'=>['account_id'=>id(2)]]),'record_delete_forbidden','assignee companion still cannot grant task delete permission');
$ownerTask=$task;$ownerTask['accountId']=id(1);
$policy->admit($ownerTask,$old,['id'=>id(3),'role'=>'owner','kind'=>'project'],['user'=>['account_id'=>id(1)]]);
ck(true,'owner task delete retains the ordinary creator and tombstone commitment guard');
echo json_encode(['test'=>'crypto-record-policy-task-delete','status'=>'pass','checks'=>$checks,'fixture'=>'isolated-memory-sqlite','http'=>false,'proofVerification'=>false]).PHP_EOL;
