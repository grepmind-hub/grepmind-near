"""Read/write/delete probes using the existing restricted application account."""
from pathlib import Path
import secrets
import subprocess

env = dict(line.split('=',1) for line in Path('/opt/abashyaka/secrets/deployment.env').read_text().splitlines() if '=' in line)
key, secret = env['S3_APP_ACCESS_KEY'], env['S3_APP_SECRET_KEY']
probe = 'deployment-check/' + secrets.token_hex(16) + '.txt'
script = f"""set -eu
umask 077
export MC_CONFIG_DIR=$(mktemp -d)
export MC_HOST_verify='http://{key}:{secret}@127.0.0.1:9000'
trap 'status=$?; mc rm --force "verify/abashyaka-public/{probe}" "verify/abashyaka-private/{probe}" >/dev/null 2>&1 || :; rm -rf "$MC_CONFIG_DIR"; exit "$status"' EXIT
printf 'abashyaka internal storage connectivity' > "$MC_CONFIG_DIR/probe.txt"
for bucket in abashyaka-public abashyaka-private; do
    mc cp "$MC_CONFIG_DIR/probe.txt" "verify/$bucket/{probe}" >/dev/null
    mc cat "verify/$bucket/{probe}" > "$MC_CONFIG_DIR/readback.txt"
    test "$(cat "$MC_CONFIG_DIR/readback.txt")" = 'abashyaka internal storage connectivity'
    mc rm "verify/$bucket/{probe}" >/dev/null
    printf '%s: write/read/delete passed\n' "$bucket"
done
"""
result = subprocess.run(['docker','exec','-i','abashyaka-minio','/bin/sh','-s'],
                        input=script.encode(), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
print(result.stdout.decode())
if result.returncode:
    message = result.stderr.decode()
    for value in env.values():
        if len(value) >= 16:
            message = message.replace(value, '[redacted]')
    raise RuntimeError('Storage validation failed: ' + message[:1000])
