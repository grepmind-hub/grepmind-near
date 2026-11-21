"""Provision private buckets and an API-only MinIO account via private stdin."""
import json
from pathlib import Path
import subprocess

env = dict(line.split('=', 1) for line in Path('/opt/abashyaka/secrets/deployment.env').read_text().splitlines() if '=' in line)
policy = {'Version':'2012-10-17','Statement':[
    {'Effect':'Allow','Action':['s3:GetBucketLocation','s3:ListBucket','s3:ListBucketMultipartUploads'],
     'Resource':['arn:aws:s3:::abashyaka-public','arn:aws:s3:::abashyaka-private']},
    {'Effect':'Allow','Action':['s3:GetObject','s3:PutObject','s3:DeleteObject','s3:AbortMultipartUpload','s3:ListMultipartUploadParts'],
     'Resource':['arn:aws:s3:::abashyaka-public/*','arn:aws:s3:::abashyaka-private/*']} ]}
key, secret = env['S3_APP_ACCESS_KEY'], env['S3_APP_SECRET_KEY']
assert all(c in '0123456789abcdef' for c in key + secret)
script = """set -eu
umask 077
export MC_CONFIG_DIR=$(mktemp -d)
trap 'rm -rf "$MC_CONFIG_DIR"' EXIT
export MC_HOST_bootstrap="http://$MINIO_ROOT_USER:$MINIO_ROOT_PASSWORD@127.0.0.1:9000"
mc mb --ignore-existing bootstrap/abashyaka-public >/dev/null
mc mb --ignore-existing bootstrap/abashyaka-private >/dev/null
cat > "$MC_CONFIG_DIR/api-policy.json" <<'POLICY'
""" + json.dumps(policy) + "\nPOLICY\n" + f"""
mc admin policy create bootstrap abashyaka-api-storage "$MC_CONFIG_DIR/api-policy.json" >/dev/null
mc admin user add bootstrap '{key}' '{secret}' >/dev/null
mc admin policy attach bootstrap abashyaka-api-storage --user '{key}' >/dev/null
export MC_HOST_verify='http://{key}:{secret}@127.0.0.1:9000'
mc stat verify/abashyaka-public >/dev/null
mc stat verify/abashyaka-private >/dev/null
mc anonymous get bootstrap/abashyaka-public
mc anonymous get bootstrap/abashyaka-private
"""
result = subprocess.run(['docker','exec','-i','abashyaka-minio','/bin/sh','-s'],
                        input=script.encode(), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
if result.returncode:
    raise RuntimeError('Private MinIO provisioning/check failed; inspect locally with credential redaction')
print(result.stdout.decode())
print('Two private buckets ready; restricted API account can access both; no root credentials in API')
