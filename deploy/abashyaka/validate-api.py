"""Anonymous internal smoke checks only; no token fabrication or identities."""
import json
import subprocess

def request(path, expected):
    result = subprocess.run(['docker','exec','abashyaka-minio','curl','-sS','--max-time','10',
                             '-w','\n%{http_code}','http://api:8080'+path],
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
    body, status = result.stdout.decode().rsplit('\n', 1)
    assert int(status) == expected, f'{path}: unexpected HTTP {status}'
    assert 'otp' not in body.lower() or 'code' not in body.lower(), 'Review unexpected authentication content'
    print(f'{path}: HTTP {status}')
    return json.loads(body)

assert request('/healthz', 200)['status'] == 'ok'
request('/api/v1/categories', 200)
request('/api/v1/catalog/locations', 200)
request('/api/v1/catalog/categories?vertical=food', 400)
request('/api/v1/catalog/products?vertical=food', 400)
request('/api/v1/catalog/categories?vertical=food&city=Cuttack', 200)
request('/api/v1/catalog/products?vertical=food&city=Cuttack', 200)
request('/api/v1/catalog/products?vertical=food&city=Bhubaneswar', 400)
request('/api/v1/merchant/businesses', 401)
request('/api/v1/merchant/businesses/00000000-0000-4000-8000-000000000001/platform-orders', 401)
request('/api/v1/admin/admins', 401)
request('/api/v1/events', 401)

info = json.loads(subprocess.check_output(['docker','inspect','abashyaka-api']))[0]
env = dict(value.split('=', 1) for value in info['Config']['Env'] if '=' in value)
assert env['APP_ENV'] == 'production' and env['SMS_PROVIDER'] == 'stub'
for flag in ['QA_OTP_DELIVERY_ENABLED','PAYMENT_SANDBOX_ENABLED','SANDBOX_COD_ENABLED',
             'RIDER_DISPATCH_ENABLED','RIDER_EARNINGS_ALLOW_SYNTHETIC',
             'RIDER_EARNINGS_POSTING_ENABLED','RIDER_EARNINGS_POLICY_APPROVED']:
    assert env[flag] == 'false', flag
assert not any(key.startswith(('FAST2SMS_', 'QA_OTP_WRITER', 'QA_OTP_ALLOWLIST', 'PAYMENT_SANDBOX_WEBHOOK')) for key in env)
assert env['DB_USER'] == 'abashyaka_api'
assert not info['HostConfig']['PortBindings']
print('API runtime security flags verified; no host port published')

logs = subprocess.check_output(['docker','logs','abashyaka-api'], stderr=subprocess.STDOUT).decode()
for value in [env['JWT_SECRET'], env['DB_PASSWORD'], env['S3_SECRET_KEY']]:
    assert value not in logs, 'Credential detected in API logs; do not print logs'
assert not any(f'"level":"{level}"' in logs for level in ['error','fatal','panic']), 'Startup error found; inspect with redaction'
print('API logs checked: no error/fatal/panic levels or configured secret values')
