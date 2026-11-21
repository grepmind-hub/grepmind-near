"""Emit and save a sanitized internal deployment inventory."""
import json
from pathlib import Path
import subprocess

release = Path('/opt/abashyaka/releases/8d5eb0f-d03')
names = subprocess.check_output(['docker','ps','-a','--filter','label=com.docker.compose.project=abashyaka',
                                 '--format','{{.Names}}']).decode().splitlines()
containers = []
for name in names:
    info = json.loads(subprocess.check_output(['docker','inspect',name]))[0]
    containers.append({'name':name, 'state':info['State']['Status'],
                       'health':info['State'].get('Health',{}).get('Status','none') if info['State']['Running'] else 'not running',
                       'image':info['Image'], 'published_ports':info['HostConfig']['PortBindings'],
                       'networks':list(info['NetworkSettings']['Networks'])})
    assert not info['HostConfig']['PortBindings'], 'Unexpected host port publication'
    assert name != 'abashyaka-cloudflared', 'Connector must remain stopped and absent'

statement = """SELECT json_build_object(
 'users',(SELECT count(*) FROM users), 'businesses',(SELECT count(*) FROM businesses),
 'products',(SELECT count(*) FROM products), 'orders',(SELECT count(*) FROM customer_orders),
 'platform_products',(SELECT count(*) FROM platform_catalog_products),
 'categories',(SELECT count(*) FROM categories),
 'platform_categories',(SELECT count(*) FROM platform_catalog_categories),
 'districts',(SELECT count(*) FROM platform_districts),
 'delivery_localities',(SELECT count(*) FROM platform_delivery_localities),
 'financial_journals',(SELECT count(*) FROM financial_journals),
 'financial_postings',(SELECT count(*) FROM financial_postings),
 'cod_collections',(SELECT count(*) FROM cod_collections),
 'payout_transfers',(SELECT count(*) FROM payout_transfers));
SELECT json_build_object('role','abashyaka_api','superuser',rolsuper,'create_db',rolcreatedb,
 'create_role',rolcreaterole,'replication',rolreplication) FROM pg_roles WHERE rolname='abashyaka_api';
"""
result = subprocess.run(['docker','exec','-i','abashyaka-postgres','psql','-X','-qAt','-U','postgres',
                         '-d','abashyaka','-v','ON_ERROR_STOP=1'],input=statement.encode(),
                        stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
database = [json.loads(line) for line in result.stdout.decode().splitlines()]
for key in ['users','businesses','products','orders','platform_products','delivery_localities',
            'financial_journals','financial_postings','cod_collections','payout_transfers']:
    assert database[0][key] == 0, key
assert database[0]['categories'] == 11 and database[0]['districts'] == 2
assert not any(database[1][key] for key in ['superuser','create_db','create_role','replication'])
running = [item['name'] for item in containers if item['state'] == 'running']
assert 'abashyaka-merchant' not in running, 'Merchant web must remain paused'
stats = subprocess.check_output(['docker','stats','--no-stream','--format','{{json .}}',*running]).decode()
record = {'containers':containers, 'database':database,
          'resource_samples':[json.loads(line) for line in stats.splitlines()],
          'host_memory':subprocess.check_output(['free','-h']).decode(),
          'disk':subprocess.check_output(['df','-h','/opt/abashyaka']).decode(),
          'load':Path('/proc/loadavg').read_text().strip(),
          'secret_file_mode':oct(Path('/opt/abashyaka/secrets/deployment.env').stat().st_mode & 0o777)}
(release / 'evidence/internal-inventory.json').write_text(json.dumps(record, indent=2))
print(json.dumps(record, indent=2))
