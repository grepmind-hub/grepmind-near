"""Verify deployment boundaries without printing any environment values."""
import json,subprocess
def inspect(name): return json.loads(subprocess.check_output(['docker','inspect',name]))[0]
def env(info): return dict(v.split('=',1) for v in info['Config']['Env'] if '=' in v)
qa=inspect('abashyaka-physical-qa-api-1')
inbox=inspect('abashyaka-physical-qa-otp-inbox-1')
db=inspect('abashyaka-physical-qa-postgres-1')
prod=inspect('abashyaka-api')
qe,pe=env(qa),env(prod)
assert qe['APP_ENV']=='qa' and qe['OTP_PROVIDER']=='qa_http' and qe['QA_OTP_DELIVERY_ENABLED']=='true'
assert pe['APP_ENV']=='production' and pe['QA_OTP_DELIVERY_ENABLED']=='false'
assert qe['DB_HOST']=='postgres' and pe['DB_HOST']=='postgres'
assert qe['DB_USER']=='physical_qa_api'
qa_networks=set(qa['NetworkSettings']['Networks']); prod_networks=set(prod['NetworkSettings']['Networks'])
assert qa_networks.isdisjoint(prod_networks), 'QA and production API share a network'
assert set(db['NetworkSettings']['Networks'])=={'abashyaka-physical-qa_qa'}
assert '/var/lib/postgresql/data' in db['HostConfig']['Tmpfs'] and not db['Mounts']
assert '/run/qa-otp' in inbox['HostConfig']['Tmpfs'] and not inbox['Mounts']
assert 'QA_OTP_RUNNER_SECRET' not in qe
assert '+910000000000' not in qe['QA_OTP_ALLOWLIST']
for flag in ['RIDER_DISPATCH_ENABLED','RIDER_EARNINGS_ALLOW_SYNTHETIC','RIDER_EARNINGS_POSTING_ENABLED','SANDBOX_COD_ENABLED','PAYMENT_SANDBOX_ENABLED']:
    assert qe[flag]=='false', flag
for info in [qa,inbox]:
    for port in (info['HostConfig']['PortBindings'] or {}).values():
        assert all(binding['HostIp']=='127.0.0.1' for binding in port)
assert not db['HostConfig']['PortBindings']
assert prod['State']['Running']
print('PASS: separate networks and tmpfs QA database/inbox, loopback-only QA ports, distinct runner access, QA allowlist and disabled money/dispatch; production API remains production mode')
