"""Trusted operator terminal only: prints one synthetic QA OTP once."""
import hashlib, hmac, json, re, subprocess, urllib.request
from pathlib import Path

root=Path('/opt/abashyaka/secrets/physical-qa')
def env(name):
    return dict(line.split('=',1) for line in (root/name).read_text().splitlines() if '=' in line)
scope_env, runner=env('scope.env'),env('runner.env')
phone=input('Synthetic QA phone number: ').strip()
if phone not in scope_env['QA_OTP_ALLOWLIST'].split(','):
    raise SystemExit('That phone is not an allowlisted synthetic identity.')
query="""SELECT id::text, to_char(expires_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
FROM otp_codes WHERE phone_e164 = :'phone' AND purpose='login' AND verified_at IS NULL
AND invalidated_at IS NULL AND expires_at > now() ORDER BY created_at DESC LIMIT 1;"""
res=subprocess.run(['docker','exec','-i','abashyaka-physical-qa-postgres-1','psql','-X','-qAt',
                    '-U','postgres','-d','physical_qa','-v','ON_ERROR_STOP=1','-v','phone='+phone],
                   input=query.encode(),stdout=subprocess.PIPE,stderr=subprocess.PIPE,check=True)
parts=res.stdout.decode().strip().split('|')
if len(parts)!=2 or not re.fullmatch(r'[a-f0-9-]{36}',parts[0]):
    raise SystemExit('No active challenge found; ask the tester to request a new code.')
scope={'challenge_id':parts[0],'phone_e164':phone,'purpose':'login',
       'run_id':scope_env['QA_OTP_RUN_ID'],'expires_at':parts[1]}
message='\0'.join([runner['QA_OTP_RUNNER_ID'],scope['run_id'],scope['challenge_id'],phone,'login',scope['expires_at']])
capability=hmac.new(runner['QA_OTP_RUNNER_SECRET'].encode(),message.encode(),hashlib.sha256).hexdigest()
request=urllib.request.Request('http://127.0.0.1:18085/v1/read',json.dumps(scope).encode(),
 {'Content-Type':'application/json','Authorization':'Bearer '+capability,'X-QA-Runner-ID':runner['QA_OTP_RUNNER_ID']})
with urllib.request.urlopen(request,timeout=5) as response: code=json.load(response)['code']
if not re.fullmatch(r'\d{6}',code): raise SystemExit('Invalid QA reader response.')
print('Fresh, single-use synthetic QA code:',code)
