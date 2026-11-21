"""Create isolated, one-run QA credentials without printing them."""
import os
from pathlib import Path
import secrets
import socket
import subprocess

root = Path('/opt/abashyaka/secrets/physical-qa')
assert not root.exists(), 'QA secrets directory already exists; inspect before proceeding'
for port in (18083, 18085):
    with socket.socket() as probe:
        probe.bind(('127.0.0.1', port))
names = subprocess.check_output(['docker','ps','-a','--format','{{.Names}}']).decode()
assert 'abashyaka-physical-qa-' not in names, 'Existing QA resources need review'
root.mkdir(mode=0o700)
random_hex = lambda: secrets.token_hex(32)
run_id = 'physical-qa-' + secrets.token_hex(16)
runner_id = 'physical-operator-' + secrets.token_hex(8)
writer_secret, runner_secret = random_hex(), random_hex()
assert writer_secret != runner_secret
files = {
  'compose.env': {
    'QA_POSTGRES_IMAGE':'postgis/postgis@sha256:598aed6d6c562b21e071701e6f8ac3092eece7ae332418347025f9e38bcb351f',
    'QA_MINIO_IMAGE':'elestio/minio@sha256:25348a257f1ece1b192f25f6cd9854618fa86422ac87b494b5d4e629c556d4bd',
    'QA_DB_PASSWORD':random_hex(), 'QA_MINIO_PASSWORD':random_hex(), 'QA_JWT_SECRET':random_hex()},
  'scope.env': {'QA_OTP_RUN_ID':run_id,'QA_OTP_ALLOWLIST':'+919990000171,+919990000172,+919990000173,+919990000174'},
  'writer.env': {'QA_OTP_WRITER_SECRET':writer_secret,'QA_OTP_WRITER_TOKEN':writer_secret},
  'runner.env': {'QA_OTP_RUNNER_ID':runner_id,'QA_OTP_RUNNER_SECRET':runner_secret},
}
for name, values in files.items():
    fd = os.open(root / name, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd,'w') as stream:
        stream.write(''.join(f'{key}={value}\n' for key,value in values.items()))
print('Isolated QA secrets generated in distinct mode-0600 files; reader and writer credentials separated')
