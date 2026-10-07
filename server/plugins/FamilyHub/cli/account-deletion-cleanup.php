<?php
if (PHP_SAPI!=='cli') { http_response_code(404);exit; }
require dirname(__DIR__,3).'/app/common.php';
if (session_status()===PHP_SESSION_ACTIVE) { session_abort(); }
try {
    if (!\Kanboard\Plugin\FamilyHub\Model\NativeAccountDeletionService::available()) { exit(0); }
    $rows=$container['db']->getConnection()->query('SELECT operation_id FROM familyhub_deletion_receipts WHERE complete=0 AND cancelled=0 ORDER BY deleted_at LIMIT 50')->fetchAll(\PDO::FETCH_COLUMN);
    $service=new \Kanboard\Plugin\FamilyHub\Model\NativeAccountDeletionService($container);$complete=0;$pending=0;
    foreach ($rows as $id) { $result=$service->finishFiles($id);$result['deleted'] ? $complete++ : $pending++; }
    echo json_encode(['complete'=>$complete,'pending'=>$pending],JSON_THROW_ON_ERROR).PHP_EOL;
} catch (\Throwable $error) { fwrite(STDERR,"Deletion cleanup failed; check server configuration and storage permissions privately.\n");exit(1); }
