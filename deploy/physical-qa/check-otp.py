"""Exercise one synthetic QA OTP entirely in memory; never print code/tokens."""
import hashlib, hmac, json, urllib.error, urllib.request
from pathlib import Path

root=Path('/opt/abashyaka/secrets/physical-qa')
def env(name):
    return dict(line.split('=',1) for line in (root/name).read_text().splitlines() if '=' in line)
scope_env, runner = env('scope.env'), env('runner.env')
def post(url, data, headers=None):
    req=urllib.request.Request(url,json.dumps(data).encode(),{'Content-Type':'application/json',**(headers or {})})
    try:
        with urllib.request.urlopen(req,timeout=10) as res: return res.status,json.loads(res.read())
    except urllib.error.HTTPError as exc:
        exc.read()
        return exc.code, {}
phone='+919990000172'
status, result=post('http://127.0.0.1:18083/api/v1/auth/otp/request',{'phone_e164':phone})
assert status == 202 and 'otp_code' not in json.dumps(result), f'QA challenge failed: HTTP {status}'
challenge=result['data']
scope={'challenge_id':challenge['challenge_id'],'phone_e164':phone,'purpose':'login',
       'run_id':scope_env['QA_OTP_RUN_ID'],'expires_at':challenge['expires_at']}
message='\0'.join([runner['QA_OTP_RUNNER_ID'],scope['run_id'],scope['challenge_id'],phone,'login',scope['expires_at']])
capability=hmac.new(runner['QA_OTP_RUNNER_SECRET'].encode(),message.encode(),hashlib.sha256).hexdigest()
headers={'Authorization':'Bearer '+capability,'X-QA-Runner-ID':runner['QA_OTP_RUNNER_ID']}
status, code=post('http://127.0.0.1:18085/v1/read',scope,headers)
assert status==200 and len(code['code'])==6, f'Private read failed: HTTP {status}'
status,_=post('http://127.0.0.1:18085/v1/read',scope,headers)
assert status==404, f'Private reader replay was not rejected: HTTP {status}'
body={'phone_e164':phone,'otp_code':code['code'],'challenge_id':scope['challenge_id']}
status,_=post('http://127.0.0.1:18083/api/v1/auth/otp/verify',body)
assert status==200, f'QA OTP verification failed: HTTP {status}'
status,_=post('http://127.0.0.1:18083/api/v1/auth/otp/verify',body)
assert status==401, f'QA OTP replay was not rejected: HTTP {status}'
status,_=post('http://127.0.0.1:18085/v1/read',scope,{'X-QA-Runner-ID':runner['QA_OTP_RUNNER_ID']})
assert status==401, f'Unauthenticated private reader was not rejected: HTTP {status}'
print('PASS: synthetic challenge, private single-use reader, normal verification, OTP replay rejection, unauthorized reader rejection; no code or token printed')
