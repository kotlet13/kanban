#!/usr/bin/env python3
"""Actual no-app deletion/CSRF HTTP proof on an isolated disposable fixture."""
import argparse, html, http.cookiejar, json, pathlib, re, secrets, subprocess, urllib.error, urllib.parse, urllib.request
from html.parser import HTMLParser
parser=argparse.ArgumentParser();parser.add_argument('--fixture',type=pathlib.Path,required=True);args=parser.parse_args()
f=json.loads(args.fixture.read_text());server=f['server'];container=f['container'];checks=0
assert f['synthetic'] and server=='http://127.0.0.1:18384' and container.startswith('kanban-familyhub-account-deletion-')
def check(ok,message):
 global checks
 if not ok:raise RuntimeError('FAIL: '+message)
 checks+=1;print('PASS: '+message,flush=True)
def opener():return urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))
def request(client,action,params=None,controller='AccountDeletionController',plugin='FamilyHub'):
 url=server+'/index.php?'+urllib.parse.urlencode(dict(controller=controller,action=action,**({'plugin':plugin}if plugin else {})))
 try:
  with client.open(urllib.request.Request(url,None if params is None else urllib.parse.urlencode(params,doseq=True).encode()),timeout=15)as r:return r.status,r.read().decode(),dict(r.headers)
 except urllib.error.HTTPError as e:return e.code,e.read().decode(),dict(e.headers)
def fields(body):
 return {n:html.unescape(v)for n,v in re.findall(r'<input[^>]*name="([^"]+)"[^>]*value="([^"]*)"',body)}
def php(code):return subprocess.check_output(['docker','exec',container,'php','-r',code],text=True)
code='require "/var/www/app/app/common.php";session_abort();$name="delweb_".bin2hex(random_bytes(8));$pw=bin2hex(random_bytes(16));$id=$container["userModel"]->create(["username"=>$name,"password"=>$pw,"role"=>"app-user"]);echo json_encode(["id"=>$id,"username"=>$name,"password"=>$pw]);'
user=json.loads(php(code));web=opener();core=opener()
status,body,headers=request(web,'index');check(status==200 and headers.get('Cache-Control')=='no-store' and headers.get('Referrer-Policy')=='no-referrer' and 'name="username"'in body,'public self-service page is usable without app and does not cache')
status,_,_=request(web,'confirm');check(status==403,'confirmation rejects GET')
status,_,_=request(web,'preview',dict(username=user['username'],password=user['password']));check(status==403,'password POST without CSRF cannot create deletion session')
_,body,_=request(core,'login',controller='AuthController',plugin=None);status,_,_=request(core,'check',dict(username=user['username'],password=user['password'],csrf_token=fields(body)['csrf_token']),controller='AuthController',plugin=None);check(status==200,'separate browser has an existing Kanboard web login')
_,body,_=request(web,'index');status,body,headers=request(web,'preview',dict(username=user['username'],password=user['password'],csrf_token=fields(body)['csrf_token']));check(status==200 and 'Review impact'in body and 'name="previewHash"'in body and user['password']not in body,'web login displays review without returning password')
inputs=fields(body);confirm={k:inputs[k]for k in ['csrf_token','token','operationId','receiptToken','previewHash']};confirm.update(password=user['password'],confirmation='DELETE')
bad=dict(confirm,csrf_token='wrong');status,_,_=request(web,'confirm',bad);check(status==403,'confirmation validates CSRF independently')
status,body,_=request(web,'confirm',confirm);check(status==200 and 'Account deleted.'in body,'explicit website confirmation deletes actual account without mobile app')
check(php('require "/var/www/app/app/common.php";session_abort();echo $container["db"]->getConnection()->query("SELECT COUNT(*) FROM users WHERE id='+str(user['id'])+'")->fetchColumn();').strip()=='0','website removed real Kanboard users row')
newfields=fields(body);status,result,_=request(web,'status',{k:newfields[k]for k in ['csrf_token','operationId','receiptToken']});check(status==200 and 'Account deleted.'in result,'public receipt status still works after deletion')
# Simulate lost ACK by resubmitting the original destructive form with current CSRF.
status,result,_=request(web,'confirm',confirm);check(status==200 and 'Account deleted.'in result,'website replay recovers receipt despite revoked bearer')
status,body,_=request(core,'index',controller='DashboardController',plugin=None);check(status==200 and ('name="password"'in body or 'name="username"'in body),'pre-existing Kanboard login is rejected after users deletion')
# Explicit web cancellation seals the operation before a delayed original form.
user2=json.loads(php(code));cancelweb=opener();_,body,_=request(cancelweb,'index');_,body,_=request(cancelweb,'preview',dict(username=user2['username'],password=user2['password'],csrf_token=fields(body)['csrf_token']));inputs=fields(body);original={k:inputs[k]for k in ['csrf_token','token','operationId','receiptToken','previewHash']};original.update(password=user2['password'],confirmation='DELETE');cancel={k:inputs[k]for k in ['csrf_token','token','operationId','receiptToken']};status,body,_=request(cancelweb,'cancelPending',cancel);check(status==200 and 'Deletion request cancelled.'in body,'website explicitly seals pending operation before late original request');status,body,_=request(cancelweb,'confirm',original);check(status==409 and 'deletion_cancelled'in body,'late website confirm cannot delete a cancelled operation');check(php('require "/var/www/app/app/common.php";session_abort();echo $container["db"]->getConnection()->query("SELECT COUNT(*) FROM users WHERE id='+str(user2['id'])+'")->fetchColumn();').strip()=='1','cancel-first website leaves account intact');
# Last admin rule uses only a fresh isolated fixture, never changes core roles.
capurl=server+'/index.php?controller=NativeApiController&action=handle&plugin=FamilyHub'
def api(op,params,token=None):
 req=urllib.request.Request(capurl,json.dumps(dict(v=1,op=op,params=params)).encode(),{'Content-Type':'application/json',**({'Authorization':'Bearer '+token}if token else {})})
 try:
  with urllib.request.urlopen(req,timeout=15)as r:return r.status,json.load(r)
 except urllib.error.HTTPError as e:return e.code,json.load(e)
status,session=api('auth.login',dict(username='admin',password='admin',deviceName='last admin fixture'));status,plan=api('account.deletion.preview',{},session['data']['token']);check(status==200 and any(b['code']=='last_admin'for b in plan['data']['blockers']),'only active Kanboard administrator cannot delete account')
# Require production HTTPS independently, restoring the exact private config even
# when the request/assertion fails. The same fixture is used by Flutter HTTP QA.
import time
def restart_and_wait():
 subprocess.run(['docker','restart',container],check=True,stdout=subprocess.DEVNULL)
 for _ in range(30):
  try:
   with urllib.request.urlopen(server+'/healthcheck.php',timeout=2)as r:
    if r.status==200:return
  except (urllib.error.URLError,OSError):pass
  time.sleep(.2)
 raise RuntimeError('Synthetic fixture did not become healthy after restart')
backup='/tmp/familyhub-deletion-config-'+secrets.token_hex(16)+'.php'
php('$src="/var/www/app/config.php";$dst="'+backup+'";if(!copy($src,$dst)||!chmod($dst,0600)){throw new RuntimeException("Synthetic config backup failed");}')
try:
 php('$p="/var/www/app/config.php";$s=file_get_contents($p);if(file_put_contents($p,str_replace("define(\'FAMILYHUB_DEVELOPMENT_ENVIRONMENT\', true);","define(\'FAMILYHUB_DEVELOPMENT_ENVIRONMENT\', false);",$s))===false){throw new RuntimeException("Synthetic transport switch failed");}')
 restart_and_wait()
 status,_,_=request(opener(),'index');check(status==403,'production account website refuses insecure HTTP')
finally:
 php('$src="'+backup+'";$dst="/var/www/app/config.php";$s=file_get_contents($src);if($s===false||file_put_contents($dst,$s)===false){throw new RuntimeException("Synthetic config restoration failed");}unlink($src);')
 restart_and_wait()
print(f'SUCCESS {checks} real deletion HTTP checks')
