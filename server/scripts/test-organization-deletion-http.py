#!/usr/bin/env python3
"""Policy-v2 website proof; creates fresh synthetic users/scopes only."""
import html, http.cookiejar, json, re, secrets, subprocess, urllib.parse, urllib.request, urllib.error
SERVER='http://127.0.0.1:18380'
CONTAINER='kanban-familyhub-dev-kanboard-1'
checks=0
def check(value,label):
    global checks
    if not value: raise RuntimeError('FAIL: '+label)
    checks+=1;print('PASS: '+label)
def user():
    code='require "/var/www/app/app/common.php";if(!defined("FAMILYHUB_DEVELOPMENT_MODE")||FAMILYHUB_DEVELOPMENT_MODE!==true)exit(2);session_abort();$name="webpolicy2_".bin2hex(random_bytes(8));$pw=bin2hex(random_bytes(16));$id=$container["userModel"]->create(["username"=>$name,"password"=>$pw,"role"=>"app-user"]);echo json_encode(["username"=>$name,"password"=>$pw]);'
    return json.loads(subprocess.check_output(['docker','exec',CONTAINER,'php','-r',code],text=True))
def api(op,params,token=None):
    url=SERVER+'/index.php?controller=NativeApiController&action=handle&plugin=FamilyHub'
    req=urllib.request.Request(url,json.dumps({'v':1,'op':op,'params':params}).encode(),{'Content-Type':'application/json',**({'Authorization':'Bearer '+token} if token else {})})
    try:
        with urllib.request.urlopen(req,timeout=15) as response:return response.status,json.load(response)
    except urllib.error.HTTPError as error:return error.code,json.load(error)
def good(op,params,token=None):
    status,body=api(op,params,token)
    if status!=200:raise RuntimeError('Native fixture setup failed: '+body['error']['code'])
    return body['data']
def uuid():
    import uuid as library
    return str(library.uuid4())
founder=user();successor=user()
f=good('auth.login',{**founder,'deviceName':'Synthetic website founder'})
s=good('auth.login',{**successor,'deviceName':'Synthetic website successor'})
org=uuid();child=uuid()
good('scopes.create',{'id':org,'kind':'organization','name':'Synthetic website organization','requestId':uuid()},f['token'])
good('scopes.create',{'id':child,'kind':'project','name':'Synthetic website project','organizationId':org,'requestId':uuid()},f['token'])
invite=good('invitations.create',{'scopeId':child,'recipientUsername':successor['username'],'role':'member','requestId':uuid()},f['token'])
good('invitations.accept',{'token':invite['token']},s['token'])
client=urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))
def web(action,params=None):
    url=SERVER+'/index.php?'+urllib.parse.urlencode({'controller':'AccountDeletionController','action':action,'plugin':'FamilyHub'})
    try:
        with client.open(urllib.request.Request(url,None if params is None else urllib.parse.urlencode(params,doseq=True).encode()),timeout=15)as response:return response.status,response.read().decode()
    except urllib.error.HTTPError as error:return error.code,error.read().decode()
def fields(body):return {name:html.unescape(value)for name,value in re.findall(r'<input[^>]*name="([^"]+)"[^>]*value="([^"]*)"',body)}
_,body=web('index');csrf=fields(body)['csrf_token']
status,body=web('preview',{**founder,'csrf_token':csrf})
check(status==200 and 'Review impact' in body,'policy2 website shows organization/root preview')
check('detachOrganization' in body and 'independent space' in body,'website presents explicit organization detachment consequence')
check('phase identifiers' in body and 'anonymized project' in body,'website presents explicit root retention consequence')
inputs=fields(body);confirm={key:inputs[key]for key in ['csrf_token','token','operationId','receiptToken','previewHash']}
confirm.update({'password':founder['password'],'confirmation':'DELETE',f'owners[{org}]':'deleteOwnedScope',f'owners[{child}]':s['user']['accountId']})
# No structural checkbox is automatically selected.
check('checked' not in re.sub(r'checked state','',body),'structural choices have no automatic consent')
status,_=web('confirm',confirm);check(status==409,'website rejects missing explicit structural choices')
# The failed validation changes no data, so the same review stays valid.
confirm['structures[]']=[html.unescape(value)for value in re.findall(r'name="structures\[\]" value="([^"]+)"',body)]
status,result=web('confirm',confirm)
check(status==200 and 'Account deleted.' in result,'website policy2 confirms typed actions and deletes synthetic account')
retained=good('scopes.list',{'includeOrganizations':True},s['token'])['scopes']
check(any(scope['id']==child and scope['organizationId'] is None and scope['role']=='owner'for scope in retained),'website keeps successor project standalone with its ownership')
root=good('sync3.pull',{'scopeId':child,'cursor':0},s['token'])['records'][0]
check(not root['deleted'] and root['payload']['title']=='Shared project','website preserves an anonymized usable root record')
print(f'SUCCESS {checks} policy2 website HTTP checks')
