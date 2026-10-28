<?php
require __DIR__.'/InventoryFiles.php';
$root=sys_get_temp_dir().'/fresh-reset-files-'.bin2hex(random_bytes(6));mkdir($root,0700);mkdir($root.'/familyhub',0700);mkdir($root.'/familyhub/attachments',0700);mkdir($root.'/familyhub/ideas',0700);mkdir($root.'/familyhub/crypto',0700);file_put_contents($root.'/familyhub/attachments/probe',"binary\0payload");file_put_contents($root.'/familyhub/crypto/migration.lock','preserve');mkdir($root.'/private-backups',0700);file_put_contents($root.'/private-backups/proof','preserve');$total=0;
function verify($ok,$label){global $total;if(!$ok)throw new RuntimeException('FAIL:'.$label);$total++;echo 'PASS: '.$label."\n";}
function rejects($fn,$code,$label){try{$fn();}catch(RuntimeException $e){verify($e->getMessage()===$code,$label);return;}throw new RuntimeException('FAIL:'.$label);}
try{
 $a=FamilyHubFreshResetFiles::inspect($root);verify($a['files']===1&&$a['bytes']===14,'exact binary inventory and empty directories');
 verify(!isset($a['entries']['crypto'])&&!isset($a['entries']['private-backups']),'lock and backup namespaces excluded');
 rejects(fn()=>FamilyHubFreshResetFiles::inspect($root,0),'unsupported_or_excess_files','file count bounded');
 rejects(fn()=>FamilyHubFreshResetFiles::inspect($root,100,1),'excess_business_bytes','byte count bounded');
 symlink($root.'/private-backups/proof',$root.'/familyhub/ideas/unsafe');rejects(fn()=>FamilyHubFreshResetFiles::inspect($root),'symlink_business_entry','business symlink refused');unlink($root.'/familyhub/ideas/unsafe');
 mkdir($root.'/familyhub/unknown');rejects(fn()=>FamilyHubFreshResetFiles::inspect($root),'unclassified_familyhub_path','unknown namespace refuses reset inventory');rmdir($root.'/familyhub/unknown');
 verify(FamilyHubFreshResetFiles::inspect($root)===$a,'inventory makes no changes');
 verify(file_get_contents($root.'/familyhub/crypto/migration.lock')==='preserve'&&file_get_contents($root.'/private-backups/proof')==='preserve','lock and private backup retained');
 echo json_encode(['assertions'=>$total,'status'=>'PASS'])."\n";
}finally{
 // Only this synthetic tmp root, never caller-controlled paths.
 foreach(['familyhub/attachments/probe','familyhub/crypto/migration.lock','private-backups/proof'] as $name)unlink($root.'/'.$name);
 foreach(['familyhub/attachments','familyhub/ideas','familyhub/crypto','familyhub','private-backups'] as $name)rmdir($root.'/'.$name);rmdir($root);
}
