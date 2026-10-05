<?php
// Concurrent, bounded local synthetic SMTP receiver. Never shipped in plugin.
[$script,$output,$port]=$argv;
if (!str_starts_with($output,'/tmp/familyhub-smtp-') || !ctype_digit($port)) { exit(2); }
function saveCapture($output,$captured){$tmp=$output.'.tmp';file_put_contents($tmp,json_encode($captured));chmod($tmp,0600);rename($tmp,$output);}
$server=stream_socket_server('tcp://127.0.0.1:'.$port,$errno,$error);if(!$server){exit(3);}stream_set_blocking($server,false);
$captured=['messages'=>[],'verbs'=>[]];saveCapture($output,$captured);$clients=[];$buffers=[];$data=[];$recipients=[];echo "ready\n";flush();$duration=isset($argv[3])&&ctype_digit($argv[3])?(int)$argv[3]:60;if($duration<1||$duration>900){exit(2);}$deadline=microtime(true)+$duration;
while(microtime(true)<$deadline){
 $read=array_merge([$server],array_values($clients));$write=null;$except=null;if(!stream_select($read,$write,$except,1)){continue;}
 foreach($read as$socket){
  if($socket===$server){$client=stream_socket_accept($server,0);if($client){stream_set_blocking($client,false);$id=(int)$client;$clients[$id]=$client;$buffers[$id]='';$data[$id]=null;$recipients[$id]=[];fwrite($client,"220 capture.invalid ESMTP\r\n");}continue;}
  $id=(int)$socket;$chunk=fread($socket,8192);if($chunk===''&&feof($socket)){fclose($socket);unset($clients[$id],$buffers[$id],$data[$id],$recipients[$id]);continue;}$buffers[$id].=$chunk;if(strlen($buffers[$id])>65536){exit(4);}
  while(($end=strpos($buffers[$id],"\n"))!==false){$line=substr($buffers[$id],0,$end+1);$buffers[$id]=substr($buffers[$id],$end+1);
   if($data[$id]!==null){if($line===".\r\n"){$captured['messages'][]=['recipients'=>$recipients[$id],'body'=>$data[$id]];$data[$id]=null;saveCapture($output,$captured);fwrite($socket,"250 Accepted\r\n");}else{$data[$id].=$line;if(strlen($data[$id])>65536){exit(4);}}continue;}
   $verb=strtoupper(strtok(trim($line),' '));$captured['verbs'][]=$verb;$mode=is_file($output.'.mode')?trim(file_get_contents($output.'.mode')):'accept';saveCapture($output,$captured);
   if($verb==='EHLO'){fwrite($socket,$mode==='rejectEhlo'?"502 EHLO rejected\r\n":"250-capture.invalid\r\n250 SIZE 65536\r\n");}
   elseif($verb==='HELO'){fwrite($socket,"250 capture.invalid\r\n");}
   elseif($verb==='STARTTLS'){fwrite($socket,"454 TLS unavailable\r\n");}
   elseif($verb==='MAIL'){$recipients[$id]=[];fwrite($socket,"250 OK\r\n");}
   elseif($verb==='RCPT'){preg_match('/<([^>]+)>/',$line,$m);$recipients[$id][]=$m[1]??'';fwrite($socket,$mode==='reject'?"550 Recipient rejected\r\n":"250 OK\r\n");}
   elseif($verb==='DATA'){$data[$id]='';fwrite($socket,"354 Send data\r\n");}
   elseif($verb==='QUIT'){fwrite($socket,"221 Bye\r\n");fclose($socket);unset($clients[$id],$buffers[$id],$data[$id],$recipients[$id]);break;}
   else{fwrite($socket,"250 OK\r\n");}
  }
 }
}
foreach($clients as$client){fclose($client);}fclose($server);
