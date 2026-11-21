"""Run once on the authorized Ubuntu host; never print credential values."""
import json
import os
from pathlib import Path
import secrets
import subprocess

root = Path('/opt/abashyaka/secrets')
assert root.is_dir() and root.stat().st_uid == os.getuid()
assert root.stat().st_mode & 0o777 == 0o700
images = {}
for key, tag in {
    'POSTGRES_IMAGE': 'postgis/postgis:16-3.7',
    'MINIO_IMAGE': 'elestio/minio:latest',
    'NGINX_IMAGE': 'nginx:stable-alpine',
    'CLOUDFLARED_IMAGE': 'cloudflare/cloudflared:latest',
}.items():
    info = json.loads(subprocess.check_output(['docker', 'image', 'inspect', tag]))[0]
    assert info['Architecture'] == 'amd64' and info['Os'] == 'linux'
    images[key] = info['RepoDigests'][0]

values = dict(images)
values['MINIO_ROOT_USER'] = 'abashyaka-storage-admin'
for key in ['POSTGRES_ADMIN_PASSWORD', 'DB_APP_PASSWORD', 'MINIO_ROOT_PASSWORD',
            'S3_APP_ACCESS_KEY', 'S3_APP_SECRET_KEY', 'JWT_SECRET']:
    values[key] = secrets.token_hex(32)
values['TUNNEL_TOKEN_FILE'] = '/opt/abashyaka/secrets/tunnel-token'
fd = os.open(root / 'deployment.env', os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
with os.fdopen(fd, 'w') as stream:
    stream.write(''.join(f'{key}={value}\n' for key, value in values.items()))
print(json.dumps({'configuration': 'created mode 0600', 'images': images}))
