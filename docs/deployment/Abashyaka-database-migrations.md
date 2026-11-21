# Abashyaka database migrations

## Executed deployment baseline

Migrations 001–043 passed disposable isolated replay, schema-only restore rehearsal, and restore into the fresh Abashyaka deployment database on 20 November 2026. See [the execution report](INTERNAL_DEPLOYMENT_RESULT_2026-11-20.md) for hashes and counts. The PostGIS 16-3.7 image already supplies `topology`; successful restore used the TOC filtering in `deploy/abashyaka/bootstrap-database.py` to omit only its duplicate schema-creation entry. The unfiltered generic restore example below is insufficient for this image. Do not rerun bootstrap scripts against the deployed schema. Only explicitly listed reference data was inserted; no users, businesses, products, orders or QA rows were imported.

## Migration set

The active deployment checkout is D:\grepmind-near on abashyaka-dev-02 at 8d5eb0f. All 43 numbered migrations are tracked in that commit. The server source archive uses the committed backend and web build contexts, and the deployment overlay carries the deployment scripts and guides.

| Range | Role |
|---|---|
| 001–020 | Core schema, identity, business discovery, commerce, addresses, and order events |
| 021–030 | Platform commerce, rider dispatch and execution, and finance ledger foundation |
| 031–040 | Payment intents, sandbox accounting, OTP challenge scope, finance safeguards and settlements |
| 041 | Admin MPIN device schema and session metadata |
| 042 | Business synthetic marker and limited backfill |
| 043 | Merchant catalog attributes and delivery/payment trigger changes |

The old SQL includes built-in identities, businesses, menu items, and activity. Migration 042 marks only records matching its predicates. It does not sanitize the legacy data set. Leave all numbered SQL unchanged and exclude seed_images.sql from the deployment bootstrap.

## Rehearse 001–043

Run on the Ubuntu Docker host from the transferred release directory. Set POSTGRES_IMAGE explicitly to the same reviewed PostgreSQL 16 + PostGIS digest used by Compose.

~~~bash
: "${POSTGRES_IMAGE:?Set the reviewed PostgreSQL 16 and PostGIS image digest}"
umask 077
mkdir -p "$HOME/abashyaka-migration"
set -o pipefail
replay_dir=$(mktemp -d "$HOME/abashyaka-migration/run.XXXXXX")
bash deploy/abashyaka/replay-migrations.sh "$POSTGRES_IMAGE" "$replay_dir/artifacts" |
  tee "$replay_dir/replay.log"
artifacts="$replay_dir/artifacts"
(cd "$artifacts" && sha256sum -c schema.sha256)
(cd backend/migrations && sha256sum -c "$artifacts/migrations.sha256")
~~~

The script runs the original SQL in order in a temporary container with networking disabled and no host ports or DB volume mounts. It supplies the two historical prerequisites before 005 and 008. Those rows remain in the disposable replay. The script exports a schema-only archive, validates its table of contents, and removes its own container and anonymous volumes. Retain the replay log, schema archive, table of contents, and checksum files together. Repository verification compared the three added files to the source commit. SQL replay and restore have passed for the documented release; retain these instructions for a new empty target only.

## Restore to the fresh deployment database

Run from the same release directory with this shell function, also used in the Ubuntu deployment guide:

~~~bash
dc() { docker compose --env-file /opt/abashyaka/secrets/deployment.env -f deploy/abashyaka/compose.yaml "$@"; }
dc up -d --wait postgres
~~~

Confirm the Docker project is abashyaka and that the database belongs to the new deployment. Run the following check against the actual target. It permits PostGIS extension-owned relations and stops if it finds an application table. Stop on any failed check. Existing deployments require an incremental migration plan and a tested backup.

~~~bash
test "$(dc exec -T postgres psql -X -U postgres -d abashyaka -v ON_ERROR_STOP=1 -Atc "
  SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='public' AND c.relkind IN ('r','p')
  AND NOT EXISTS (
    SELECT 1 FROM pg_depend d
    WHERE d.classid='pg_class'::regclass AND d.objid=c.oid
      AND d.refclassid='pg_extension'::regclass AND d.deptype='e'
  )")" = 0 &&
dc exec -T postgres pg_restore -U postgres -d abashyaka \
  --schema-only --single-transaction --exit-on-error --no-owner --no-privileges \
  < "$artifacts/schema.dump"
~~~

Rehearse restoring the same artifact into a separate empty database first. The live restore must use a new database and must not use --clean. PostgreSQL's single-transaction restore rolls back on failure.

~~~bash
dc exec -T postgres psql -X -U postgres -d abashyaka -v ON_ERROR_STOP=1 <<'SQL'
SELECT current_database(), PostGIS_Full_Version();
SELECT to_regclass('public.admin_mpin_devices') AS migration_041;
SELECT column_name FROM information_schema.columns
WHERE table_schema = 'public'
  AND ((table_name = 'businesses' AND column_name = 'is_synthetic')
   OR (table_name = 'products' AND column_name IN ('unit_label','mrp','barcode','grocery_category')))
ORDER BY column_name;
SELECT (SELECT count(*) FROM users) AS users,
       (SELECT count(*) FROM businesses) AS businesses,
       (SELECT count(*) FROM products) AS products,
       (SELECT count(*) FROM customer_orders) AS orders;
DO $verify$
BEGIN
  IF EXISTS (SELECT 1 FROM users)
    OR EXISTS (SELECT 1 FROM businesses)
    OR EXISTS (SELECT 1 FROM products)
    OR EXISTS (SELECT 1 FROM customer_orders) THEN
    RAISE EXCEPTION 'Fresh schema restore contains unexpected application rows';
  END IF;
END
$verify$;
SQL
~~~

Expect zero rows in the four application tables immediately after restore. Verify migration 041's table, migration 042's column, and all four migration 043 product columns. Validate affected payment and fulfillment triggers with the exact API build in a separate validation database before enabling commerce.

## Runtime database role and reference data

Connect interactively as the bootstrap database administrator. At the psql password prompt enter the same generated value stored as DB_APP_PASSWORD in the protected Compose environment file.

~~~bash
dc exec postgres psql -X -U postgres -d abashyaka -v ON_ERROR_STOP=1
~~~

~~~sql
CREATE ROLE abashyaka_api LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;
\password abashyaka_api
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
GRANT CONNECT ON DATABASE abashyaka TO abashyaka_api;
GRANT USAGE ON SCHEMA public TO abashyaka_api;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO abashyaka_api;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO abashyaka_api;
\q
~~~

Review data separately and apply approved categories, service areas, and role or policy reference records through a versioned, reviewed seed step. Record inserted keys and counts by table. Provision a genuine Admin using the approved account workflow. The schema-only archive contains no legacy Admin identity. Keep checkout, dispatch, payouts, and live SMS disabled until reference data, access controls, and the relevant workflows are verified.

## Subsequent updates and recovery

Retain the release revision, numbered SQL checksums, replay output, and restore verification in the deployment record. Treat 001–043 as the baseline after a successful restore. For later migrations, back up the deployment, test the incremental migration and restore on a separate database, apply only unapplied numbered SQL in order with stop-on-error, and record the exact file checksums. Never restore the baseline archive over deployed data. If an application rollback is needed, check schema compatibility before starting the previous image. Restore a full DB backup to a separate target and validate before any cutover.

[PostgreSQL 16 pg_restore reference](https://www.postgresql.org/docs/16/app-pgrestore.html)
