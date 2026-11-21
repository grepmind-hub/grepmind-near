"""Initialize only the named disposable, tmpfs-backed physical QA database."""
import json
from pathlib import Path
import subprocess

name = 'abashyaka-physical-qa-postgres-1'
info = json.loads(subprocess.check_output(['docker','inspect',name]))[0]
assert info['Config']['Labels']['com.docker.compose.project'] == 'abashyaka-physical-qa'
assert '/var/lib/postgresql/data' in info['HostConfig']['Tmpfs']
assert not info['Mounts'] and not info['HostConfig']['PortBindings']
def run(args, data=None):
    p=subprocess.run(args,input=data,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    if p.returncode: raise RuntimeError('QA database initialization failed: '+p.stderr.decode()[:800])
    return p.stdout
def sql(data):
    return run(['docker','exec','-i',name,'psql','-X','-qAt','-U','postgres','-d','physical_qa','-v','ON_ERROR_STOP=1'],data)
empty=sql(b"SELECT to_regclass('public.users') IS NULL;").strip()
assert empty == b't', 'QA database is not fresh'
schema=Path('/opt/abashyaka/releases/8d5eb0f-d03/evidence/schema')
toc=(schema/'deployment-restore.toc').read_bytes()
run(['docker','exec','-i',name,'sh','-c','umask 077; cat > /tmp/qa-restore.toc'],toc)
run(['docker','exec','-i',name,'pg_restore','-U','postgres','-d','physical_qa',
     '--schema-only','--single-transaction','--exit-on-error','--no-owner','--no-privileges',
     '--use-list=/tmp/qa-restore.toc'],(schema/'schema.dump').read_bytes())
root=Path('/opt/abashyaka/releases/physical-qa-8d5eb0f')
sql((root/'system-reference.sql').read_bytes())
sql(b"""INSERT INTO platform_delivery_localities(id,district_id,name,slug,delivery_enabled) VALUES
('02200000-0000-4000-8000-000000000101','02200000-0000-4000-8000-000000000001','Kuanpal','kuanpal',true);
""")
sql((root/'phase3e-fixtures.sql').read_bytes())
sql(b"UPDATE businesses SET is_synthetic=true WHERE id='3e000000-0000-4000-8000-000000000101';")
result=sql(b"SELECT count(*) FROM users WHERE phone_e164 IN ('+919990000171','+919990000172','+919990000173','+919990000174');")
assert result.strip()==b'4'
print('QA-only schema and four synthetic identities initialized in tmpfs; no shared database accessed')
