#!/usr/bin/env python3
"""Fresh loopback account/private-sync fixture; never touches 18380 or prior volumes."""
import argparse, base64, json, os, pathlib, secrets, subprocess, tempfile, urllib.request, urllib.error, time

repo = pathlib.Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument('--project', default='kanban-familyhub-account-tests')
parser.add_argument('--port', type=int, choices=[18383, 18384], default=18383)
parser.add_argument('--output', type=pathlib.Path, default=repo/'build/qa/personal-sync-recovery/account-http-fixture.json')
args = parser.parse_args()
if not args.project.startswith('kanban-familyhub-account-') or any(c not in 'abcdefghijklmnopqrstuvwxyz0123456789-' for c in args.project):
    raise SystemExit('Use a dedicated synthetic account project name')
args.output = args.output.resolve()
if args.output.exists():
    raise SystemExit('Private fixture already exists; use a new output and fresh project')
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.parent.chmod(0o700)
env = dict(os.environ, FAMILYHUB_ACCOUNT_TEST_PORT=str(args.port))
compose = ['docker', 'compose', '-p', args.project, '-f', str(repo/'server/compose.account-tests.yaml')]
subprocess.run(compose+['up','-d','--wait'], env=env, check=True, stdout=subprocess.DEVNULL)
container = subprocess.check_output(compose+['ps','-q','kanboard'],env=env,text=True).strip()
name = subprocess.check_output(['docker','inspect','--format','{{.Name}}',container],text=True).strip().lstrip('/')
key = base64.b64encode(secrets.token_bytes(32)).decode()
config = (repo/'server/dev-config.php').read_text()+f"\ndefine('FAMILYHUB_ACCOUNT_MAIL_KEY_BASE64', '{key}');\ndefine('FAMILYHUB_SMTP_HOST', '127.0.0.1');\ndefine('FAMILYHUB_SMTP_PORT', 25252);\ndefine('FAMILYHUB_SMTP_ENCRYPTION', 'none');\ndefine('FAMILYHUB_SMTP_ALLOW_LOCAL_PLAINTEXT', true);\ndefine('FAMILYHUB_SMTP_FROM', 'sender@capture.invalid');\n"
with tempfile.TemporaryDirectory(prefix='familyhub-account-config-') as tmp:
    path=pathlib.Path(tmp)/'config.php';path.write_text(config);path.chmod(0o600)
    subprocess.run(['docker','cp',str(path),container+':/var/www/app/config.php'],check=True,stdout=subprocess.DEVNULL)
subprocess.run(['docker','exec',container,'sh','-c','chown nginx:nginx /var/www/app/config.php && chmod 600 /var/www/app/config.php'],check=True)
server=f'http://127.0.0.1:{args.port}'
request=urllib.request.Request(server+'/index.php?controller=NativeApiController&action=handle&plugin=FamilyHub',json.dumps({'v':1,'op':'capabilities','params':{}}).encode(),{'Content-Type':'application/json'})
for _ in range(30):
    try:
        with urllib.request.urlopen(request, timeout=5) as response:
            caps=json.load(response)['data']
        if caps['enabled'] and caps['features']['emailVerification']:break
    except (urllib.error.URLError, KeyError):pass
    time.sleep(.2)
else:raise SystemExit('Local account configuration did not become ready')
if not caps['features']['accountEnrollment']:raise SystemExit('Existing FamilyHub account found: use a fresh dedicated project')
fixture=json.loads(subprocess.check_output(compose+['exec','-T','kanboard','php','/familyhub-tests/account-http-seed.php'],env=env,text=True))
fixture.update(server=server,project=args.project,container=name,capturePath='/tmp/familyhub-smtp-account-http.json',smtpPort=25252)
subprocess.run(['docker','exec','-d',container,'php','/familyhub-tests/smtp-capture.php',fixture['capturePath'],'25252','900'],check=True)
for _ in range(30):
    if subprocess.run(['docker','exec',container,'test','-f',fixture['capturePath']],stdout=subprocess.DEVNULL).returncode==0:break
    time.sleep(.1)
else:raise SystemExit('Synthetic SMTP capture not ready')
with os.fdopen(os.open(args.output,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600),'w') as output:json.dump(fixture,output,indent=2)
print(f'Fresh account fixture ready on {server}; private mode0600 output: {args.output}')
print(f'Stop only this fixture: docker compose -p {args.project} -f server/compose.account-tests.yaml down')
