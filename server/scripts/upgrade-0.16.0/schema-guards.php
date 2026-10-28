<?php
/** Independent schema19→23 oracle; historical values projected onto original columns. */
if(PHP_SAPI!=='cli'){http_response_code(404);exit;}
function oracle():array{
 if(hash('sha256',bytes(WORK.'/schema-oracle.json'))!==SCHEMA_ORACLE_SHA)stop('schema_oracle_pin');
 $m=readJson(WORK.'/schema-oracle.json');if(count($m['newTables'])!==127)stop('new_table_count');return $m;
}
function oldSchemaGuard(PDO $p,array $d):void{
 foreach(array_keys(oracle()['newTables'])as$t)if(isset($d[$t]))stop('crypto_table_already_exists');
 foreach(['familyhub_scopes'=>'documents_sequence','familyhub_inbox_state'=>'configuration_revision']as$t=>$c)if(in_array($c,$d[$t]['columns'],true))stop('schema22_column_already_exists');
 foreach(oracle()['changedHistorical']as$t=>$v)if($d[$t]['columns']!==$v['before']['columns']||$d[$t]['types']!==$v['before']['types'])stop('original_schema19_columns');
}
function schemaPreserved(PDO $p,array $old):void{
 $d=defs($p);$o=oracle();$all=array_merge(array_keys($old),array_keys($o['newTables']));sort($all,SORT_STRING);$actual=array_keys($d);sort($actual,SORT_STRING);if($actual!==$all)stop('unexpected_new_or_removed_tables');
 foreach($o['newTables']as$t=>$pin){$pin=['columns'=>$pin['columns'],'types'=>$pin['types'],'order'=>$pin['order'],'createSha256'=>$pin['createSha256']];if($d[$t]!==$pin||(int)$p->query('SELECT COUNT(*) FROM '.id($t))->fetchColumn()!==0)stop('new_empty_crypto_table_definition_guard');}
 $projected=[];
 foreach($old as$t=>$before){
  $expected=['columns'=>$before['columns'],'types'=>$before['types'],'order'=>$before['order'],'createSha256'=>$before['createSha256']];
  if(isset($o['changedHistorical'][$t])){
   $change=$o['changedHistorical'][$t];$actualCreate=rows($p,'SHOW CREATE TABLE '.id($t))[0]['Create Table'];
   $beforeLines=explode("\n",$change['before']['create']);$afterLines=explode("\n",$change['after']['create']);$added=array_values(array_diff($afterLines,$beforeLines));
   foreach($added as$line){if(substr_count($actualCreate,$line."\n")!==1)stop('exact_added_schema22_definition_required');$actualCreate=str_replace($line."\n",'',$actualCreate);}
   if(hash('sha256',$actualCreate)!==$before['createSha256'])stop('historical_definition_changed_beyond_schema22');
   if($d[$t]['columns']!==$change['after']['columns']||$d[$t]['types']!==$change['after']['types']||$d[$t]['order']!==$before['order'])stop('schema22_column_type_order');
   $column=['familyhub_scopes'=>'documents_sequence','familyhub_inbox_state'=>'configuration_revision'][$t]??null;
   if($column!==null&&(int)$p->query('SELECT COUNT(*) FROM '.id($t).' WHERE '.id($column).'<>0 OR '.id($column).' IS NULL')->fetchColumn()!==0)stop('schema22_added_counter_not_zero');
  }elseif($d[$t]!==$expected)stop('historical_definition_changed');
  $projected[$t]=$expected;
 }
 $now=snapshot($p,$projected);unset($now['plugin_schema_versions']);$expected=$old;unset($expected['plugin_schema_versions']);if($now!==$expected)stop('historical_row_values_changed');
}
