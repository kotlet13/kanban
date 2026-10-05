#!/usr/bin/env python3
"""Actual isolated admin-session/CSRF/enrollment race HTTP proof; no external mail."""
import argparse, http.cookiejar, json, pathlib, re, subprocess, tempfile, urllib.error, urllib.parse, urllib.request

parser=argparse.ArgumentParser();parser.add_argument('--fixture',type=pathlib.Path,required=True);args=parser.parse_args()
fixture=json.loads(args.fixture.read_text());server=fixture['server'];container=fixture['container'];checks=0
assert fixture['synthetic'] and server=='http://127.0.0.1:18384' and container.startswith('kanban-familyhub-account-smoke-')
def check(ok,message):
 global checks
 if not ok:raise RuntimeError('FAIL: '+message)
 checks+=1;print('PASS: '+message,flush=True)
def opener():return urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))
def request(client,controller,action,params=None,plugin=None):
 url=server+'/index.php?'+urllib.parse.urlencode(dict(controller=controller,action=action,**({'plugin':plugin}if plugin else {})))
 req=urllib.request.Request(url,None if params is None else urllib.parse.urlencode(params).encode())
 try:
  with client.open(req,timeout=15)as response:return response.status,response.read().decode()
 except urllib.error.HTTPError as error:return error.code,error.read().decode()
def csrf(html):return re.search(r'name="csrf_token" value="([^"]+)"',html).group(1)
def login(client,username,password):
 _,html=request(client,'AuthController','login')
 status,_=request(client,'AuthController','check',dict(username=username,password=password,csrf_token=csrf(html)))
 assert status==200

def php(code):return subprocess.check_output(['docker','exec',container,'php','-r',code],text=True)
def count():return int(php('require "/var/www/app/app/common.php";session_abort();echo $container["db"]->getConnection()->query("SELECT COUNT(*) FROM familyhub_enrollment")->fetchColumn();'))
admin=opener();login(admin,'admin','admin');before=count()
status,html=request(admin,'EnrollmentController','index',plugin='FamilyHub');check(status==200 and count()==before and not re.search('fhe1_[a-f0-9]{64}',html),'admin GET displays setup but never creates/exposes code')
status,_=request(admin,'EnrollmentController','issue',plugin='FamilyHub');check(status==403 and count()==before,'issuance rejects GET even for admin')
status,_=request(admin,'EnrollmentController','issue',{},'FamilyHub');check(status==403 and count()==before,'issuance rejects missing CSRF')
nonadmin=opener();login(nonadmin,fixture['nonadmin']['username'],fixture['nonadmin']['password']);status,_=request(nonadmin,'EnrollmentController','index',plugin='FamilyHub');check(status==403,'non-admin cannot view bootstrap admin page')
status,_=request(nonadmin,'EnrollmentController','issue',dict(csrf_token=csrf(html)),'FamilyHub');check(status==403 and count()==before,'non-admin POST cannot issue code using another CSRF')
status,html=request(admin,'EnrollmentController','index',plugin='FamilyHub');token=csrf(html);issuance=re.search(r'name="issuanceId" value="([^"]+)"',html).group(1)
status,result=request(admin,'EnrollmentController','issue',dict(csrf_token=token,issuanceId=issuance),'FamilyHub');match=re.search('fhe1_[a-f0-9]{64}',result);check(status==200 and bool(match) and count()==before+1,'admin POST plus CSRF explicitly issues short-lived code')
code=match.group(0);status,_=request(admin,'EnrollmentController','issue',dict(csrf_token=token,issuanceId=issuance),'FamilyHub');check(status==409 and count()==before+1,'POST refresh cannot reuse durable issuance ID to issue another code')
status,html=request(admin,'EnrollmentController','index',plugin='FamilyHub');check(code not in html and count()==before+1,'normal page refresh does not replay issued secret')
# Genuine multi-process enrollment, same code, distinct new usernames.
processes=[];paths=[]
try:
 for suffix in ['one','two']:
  req=dict(operation='auth.enroll',params=dict(code=code,username=fixture['owner']['username']+'_'+suffix,password=fixture['owner']['password'],displayName='Synthetic',deviceName='Race'),ip='synthetic-enrollment-'+suffix)
  with tempfile.NamedTemporaryFile(mode='w',prefix='familyhub-enroll-',delete=False)as out:json.dump(req,out);path=pathlib.Path(out.name)
  remote='/tmp/'+path.name;paths.append((path,remote));subprocess.run(['docker','cp',str(path),container+':'+remote],check=True,stdout=subprocess.DEVNULL)
  proc=subprocess.Popen(['docker','exec','-i',container,'php','/familyhub-tests/account-race-child.php',remote],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
  assert proc.stdout.readline().strip()=='ready';processes.append(proc)
 for proc in processes:proc.stdin.write('go\n');proc.stdin.flush()
 outputs=[json.loads(proc.stdout.readline())for proc in processes]
 for proc in processes:proc.stdin.close();proc.wait(timeout=15)
 check(sum(x['ok']for x in outputs)==1 and sum(x.get('error')=='enrollment_closed'for x in outputs)==1,'two concurrent code uses create exactly one first account')
 check(int(php('require "/var/www/app/app/common.php";session_abort();echo $container["db"]->getConnection()->query("SELECT COUNT(*) FROM familyhub_accounts")->fetchColumn();'))==1,'enrollment transaction commits exactly one durable account')
finally:
 for path,remote in paths:path.unlink(missing_ok=True);subprocess.run(['docker','exec',container,'rm','-f',remote],check=True)
status,html=request(admin,'EnrollmentController','index',plugin='FamilyHub');check('Issue new code'not in html,'admin issuance permanently closes after first account')
# Production HTTP deny independent of role: disable only test development exception.
php('$p="/var/www/app/config.php";$s=file_get_contents($p);file_put_contents($p,str_replace("define(\'FAMILYHUB_DEVELOPMENT_ENVIRONMENT\', true);","define(\'FAMILYHUB_DEVELOPMENT_ENVIRONMENT\', false);",$s));')
subprocess.run(['docker','restart',container],check=True,stdout=subprocess.DEVNULL)
import time
for _ in range(30):
 try:
  with urllib.request.urlopen(server+'/healthcheck.php',timeout=2) as response:
   if response.status==200:break
 except (urllib.error.URLError, OSError):pass
 time.sleep(.2)
admin=opener();login(admin,'admin','admin');status,_=request(admin,'EnrollmentController','index',plugin='FamilyHub');check(status==403,'production transport rule denies HTTP admin bootstrap page')
print(f'SUCCESS {checks} admin/enrollment HTTP checks')
