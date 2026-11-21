"""Remove the retired web service from the active Compose file, with backup."""
import pathlib
import subprocess

root = pathlib.Path('/opt/abashyaka/releases/8d5eb0f-d03/deploy/abashyaka')
path = root / 'compose.yaml'
backup = pathlib.Path('/opt/abashyaka/secrets/backups/compose-before-merchant-removal.yaml')
if backup.exists():
    raise SystemExit('Backup already exists; refusing to overwrite')
original = path.read_bytes()
text = original.decode('utf-8')
start = text.find('\n  merchant:\n')
end = text.find('\n  nginx:\n', start)
if start < 0 or end < 0 or text.count('\n  merchant:\n') != 1:
    raise SystemExit('Unexpected Compose structure; no change made')
backup.write_bytes(original)
backup.chmod(0o600)
try:
    path.write_text(text[:start] + text[end:], encoding='utf-8')
    subprocess.run(['docker', 'compose', '--env-file', '/opt/abashyaka/secrets/deployment.env',
                    '--profile', 'gateway', 'config', '--quiet'], cwd=root, check=True)
except Exception:
    path.write_bytes(original)
    raise
print('Merchant Web service disabled; previous Compose file preserved at', backup)
