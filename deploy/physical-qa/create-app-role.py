"""Create a restricted role only in the dedicated tmpfs QA database."""
import json,os,secrets,subprocess
from pathlib import Path
name='abashyaka-physical-qa-postgres-1'
info=json.loads(subprocess.check_output(['docker','inspect',name]))[0]
assert info['Config']['Labels']['com.docker.compose.project']=='abashyaka-physical-qa'
assert '/var/lib/postgresql/data' in info['HostConfig']['Tmpfs'] and not info['Mounts']
path=Path('/opt/abashyaka/secrets/physical-qa/compose.env')
assert 'QA_DB_APP_PASSWORD=' not in path.read_text(), 'QA application credential already exists'
password=secrets.token_hex(32)
with path.open('a') as stream: stream.write('QA_DB_APP_PASSWORD='+password+'\n')
statement=f"""CREATE ROLE physical_qa_api LOGIN PASSWORD '{password}' NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
GRANT CONNECT ON DATABASE physical_qa TO physical_qa_api;
GRANT USAGE ON SCHEMA public TO physical_qa_api;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO physical_qa_api;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO physical_qa_api;"""
p=subprocess.run(['docker','exec','-i',name,'psql','-X','-q','-U','postgres','-d','physical_qa','-v','ON_ERROR_STOP=1'],
                 input=statement.encode(),stdout=subprocess.PIPE,stderr=subprocess.PIPE)
if p.returncode: raise RuntimeError('QA app role creation failed; inspect locally with secret redaction')
print('Restricted QA application role created with separate credential')
