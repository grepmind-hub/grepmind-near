"""Apply a reversible Nginx guard to the exposed pre-login registration route."""
import pathlib
import subprocess

path = pathlib.Path('/opt/abashyaka/releases/8d5eb0f-d03/deploy/abashyaka/nginx.conf')
backup = pathlib.Path('/opt/abashyaka/secrets/backups/nginx-before-prelogin-guard-recheck.conf')
original = path.read_bytes()
if backup.exists():
    raise SystemExit('Backup already exists; refusing to overwrite')
backup.write_bytes(original)
backup.chmod(0o600)
text = original.decode('utf-8')
for host in ('api.abashyaka.com', 'admin.abashyaka.com'):
    marker = f'    server_name {host};\n'
    if text.count(marker) != 1:
        raise SystemExit(f'Unexpected Nginx configuration for {host}; no change made')
    text = text.replace(marker, marker + '    location = /api/v1/devices/register-prelogin { return 403; }\n')
try:
    # Write in place: an atomic rename would leave the Docker bind mount on the old inode.
    path.write_text(text, encoding='utf-8')
    subprocess.run(['docker', 'exec', 'abashyaka-nginx', 'nginx', '-t'], check=True)
    subprocess.run(['docker', 'exec', 'abashyaka-nginx', 'nginx', '-s', 'reload'], check=True)
except Exception:
    path.write_bytes(original)
    subprocess.run(['docker', 'exec', 'abashyaka-nginx', 'nginx', '-s', 'reload'], check=False)
    raise
print('Nginx guard applied; original configuration preserved at', backup)
