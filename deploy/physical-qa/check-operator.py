"""Test the operator helper without emitting the retrieved QA OTP."""
import json, re, subprocess, urllib.request
phone='+919990000171'
def post(path, payload):
    req=urllib.request.Request('http://127.0.0.1:18083'+path,json.dumps(payload).encode(),{'Content-Type':'application/json'})
    with urllib.request.urlopen(req,timeout=10) as response: return response.status,json.load(response)
status,result=post('/api/v1/auth/otp/request',{'phone_e164':phone})
assert status==202
p=subprocess.run(['python3','operator-read-code.py'],input=phone+'\n',text=True,capture_output=True)
assert p.returncode==0, 'Operator helper failed; inspect its error without sharing a code'
match=re.search(r'Fresh, single-use synthetic QA code:\s*(\d{6})',p.stdout)
assert match, 'Operator helper did not return a valid code'
status,_=post('/api/v1/auth/otp/verify',{'phone_e164':phone,'otp_code':match.group(1),
                                        'challenge_id':result['data']['challenge_id']})
assert status==200
print('PASS: trusted operator helper retrieved one scoped synthetic code and normal verification accepted it; no code or token printed')
