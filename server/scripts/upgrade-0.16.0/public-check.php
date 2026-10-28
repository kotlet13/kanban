<?php
/** Anonymous read-only capability gate before delivery workers resume. */
if(PHP_SAPI!=='cli'){http_response_code(404);exit;}
ini_set('display_errors','0');ini_set('log_errors','0');error_reporting(0);umask(0077);
require __DIR__.'/deployment.php';
try{
 $h=curl_init(PUBLIC_URL.'/index.php?controller=NativeApiController&action=handle&plugin=FamilyHub');curl_setopt_array($h,[CURLOPT_RETURNTRANSFER=>true,CURLOPT_FOLLOWLOCATION=>false,CURLOPT_CONNECTTIMEOUT=>10,CURLOPT_TIMEOUT=>30,CURLOPT_SSL_VERIFYPEER=>true,CURLOPT_SSL_VERIFYHOST=>2,CURLOPT_POST=>true,CURLOPT_HTTPHEADER=>['Content-Type: application/json'],CURLOPT_POSTFIELDS=>'{"v":1,"op":"capabilities","params":{}}']);$b=curl_exec($h);$status=curl_getinfo($h,CURLINFO_HTTP_CODE);curl_close($h);
 if(!is_string($b)||strlen($b)>1048576||$status!==200)throw new RuntimeException('capabilities_https200');$wire=json_decode($b,true,64,JSON_THROW_ON_ERROR);$d=$wire['data']??[];
 if(($wire['v']??null)!==1||isset($wire['error'])||($d['api']??null)!=='familyhub_native'||($d['serverId']??null)!==SERVER_ID||($d['enabled']??null)!==true||($d['cryptoTransportVersions']??null)!==[1,2]||($d['cryptoCutoverSupported']??null)!==true||($d['cryptoCutoverVersion']??null)!==3||!in_array(4,$d['invitationContractVersions']??[],true)||($d['invitationPreauthorizationVersions']??null)!==[1]||($d['recordPolicyVersions']??null)!==[1]||($d['recordPolicyRestores']??null)!==true||($d['accountChanges']??null)!==true||($d['features']['invitationDecline']??null)!==true||($d['features']['recipientSearch']??null)!==true)throw new RuntimeException('capabilities_crypto23_contract');
 $out=WORK.'/public-capabilities.json';if(file_exists($out)||is_link($out))throw new RuntimeException('fresh_public_capability_evidence');if(file_put_contents($out,$b,LOCK_EX)!==strlen($b)||!chmod($out,0600))throw new RuntimeException('private_evidence_write');
 echo "HTTPS200 same identity, encrypted transports1/2, cutover3, invitation4+decline, recipient search and account changes verified. No account/business mutation requested.\n";
}catch(Throwable$e){fwrite(STDERR,"Public capability gate stopped; keep delivery crons paused and inspect secret-free evidence.\n");exit(1);}
