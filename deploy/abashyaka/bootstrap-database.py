"""Restore the reviewed schema into new empty databases; never print secrets."""
from pathlib import Path
import subprocess

release = Path('/opt/abashyaka/releases/8d5eb0f-d03')
artifact = release / 'evidence/schema/schema.dump'

def run(args, data=None):
    result = subprocess.run(args, input=data, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode:
        # These commands do not contain credentials; SQL input is deliberately omitted.
        raise RuntimeError('Database operation failed: ' + result.stderr.decode()[:1200])
    return result.stdout

def sql(database, statement):
    return run(['docker','exec','-i','abashyaka-postgres','psql','-X','-qAt',
                '-U','postgres','-d',database,'-v','ON_ERROR_STOP=1'], statement.encode())

empty = """SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='public' AND c.relkind IN ('r','p') AND NOT EXISTS
(SELECT 1 FROM pg_depend d WHERE d.classid='pg_class'::regclass AND d.objid=c.oid
AND d.refclassid='pg_extension'::regclass AND d.deptype='e');"""

assert sql('abashyaka', empty).strip() == b'0', 'Deployment database is not empty'
rehearsed = sql('postgres', "SELECT count(*) FROM pg_database WHERE datname='abashyaka_restore_check';").strip() == b'1'
if not rehearsed:
    run(['docker','exec','abashyaka-postgres','createdb','-U','postgres',
         '--template=template0','abashyaka_restore_check'])
for database in ['abashyaka_restore_check', 'abashyaka']:
    if database == 'abashyaka_restore_check' and rehearsed:
        assert sql(database, "SELECT to_regclass('public.admin_mpin_devices') IS NOT NULL;").strip() == b't'
    else:
        restore = ['docker','exec','-i','abashyaka-postgres','pg_restore','-U','postgres','-d',database,
                   '--schema-only','--single-transaction','--exit-on-error','--no-owner','--no-privileges']
        if database == 'abashyaka':
            # PostGIS image initialization already installed its topology schema.
            assert sql(database, "SELECT EXISTS(SELECT 1 FROM pg_extension WHERE extname='postgis_topology');").strip() == b't'
            toc = (release / 'evidence/schema/schema.toc').read_text()
            lines = toc.splitlines(keepends=True)
            excluded = [line for line in lines if ' SCHEMA - topology ' in line]
            assert len(excluded) == 1, 'Review unexpected archive topology schema entries'
            filtered = ''.join(line for line in lines if line not in excluded)
            (release / 'evidence/schema/deployment-restore.toc').write_text(filtered)
            run(['docker','exec','-i','abashyaka-postgres','sh','-c',
                 'umask 077; cat > /tmp/abashyaka-deployment-restore.toc'], filtered.encode())
            restore.extend(['--use-list=/tmp/abashyaka-deployment-restore.toc'])
        run(restore, artifact.read_bytes())
    counts = sql(database, 'SELECT (SELECT count(*) FROM users), (SELECT count(*) FROM businesses), '
                 '(SELECT count(*) FROM products), (SELECT count(*) FROM customer_orders);').strip()
    assert counts == b'0|0|0|0', 'Unexpected application rows'
    print(database + ': schema restored; users/businesses/products/orders = 0/0/0/0')

env = dict(line.split('=', 1) for line in Path('/opt/abashyaka/secrets/deployment.env').read_text().splitlines() if '=' in line)
password = env['DB_APP_PASSWORD']
assert len(password) == 64 and all(c in '0123456789abcdef' for c in password)
statement = f"""CREATE ROLE abashyaka_api LOGIN PASSWORD '{password}' NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
GRANT CONNECT ON DATABASE abashyaka TO abashyaka_api;
GRANT USAGE ON SCHEMA public TO abashyaka_api;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO abashyaka_api;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO abashyaka_api;"""
# Never return SQL/credential text even if role provisioning fails.
try:
    sql('abashyaka', statement)
except RuntimeError:
    raise RuntimeError('Restricted database role provisioning failed; inspect locally without exposing SQL') from None
print('Restricted application database role provisioned')
print(sql('abashyaka', 'SELECT version(); SELECT PostGIS_Full_Version();').decode())
