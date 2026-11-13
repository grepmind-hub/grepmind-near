#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
container_name="grepmind_3f_qa_$$"
database_name="grepmind_3f_${$}_qa"
created=false
keep_database="${PHASE3F_KEEP_QA_DB:-false}"

cleanup() {
  if [[ "$created" == true ]]; then
    if [[ "$keep_database" == true ]]; then
      printf 'Retained disposable Phase 3F database for live acceptance: container=%s database=%s\n' "$container_name" "$database_name"
    else
      docker rm -f "$container_name" >/dev/null 2>&1 || true
      printf 'Removed disposable Phase 3F database container.\n'
    fi
  fi
}
trap cleanup EXIT INT TERM

if docker inspect "$container_name" >/dev/null 2>&1; then
  printf 'Refusing to reuse existing container %s.\n' "$container_name" >&2
  exit 2
fi

docker run -d \
  --name "$container_name" \
  --tmpfs /var/lib/postgresql/data:rw,size=2g \
  -e POSTGRES_USER=qa3f \
  -e POSTGRES_PASSWORD=qa3f_disposable_only \
  -e "POSTGRES_DB=$database_name" \
  -p 0.0.0.0::5432 \
  postgis/postgis:16-3.4 >/dev/null
created=true

ready=false
for _ in $(seq 1 90); do
  ready_count=$(docker logs "$container_name" 2>&1 | grep -c 'database system is ready to accept connections' || true)
  if [[ "$ready_count" -ge 2 ]] && docker exec "$container_name" pg_isready -U qa3f -d "$database_name" >/dev/null 2>&1; then
    ready=true
    break
  fi
  sleep 1
done
if [[ "$ready" != true ]]; then
  docker logs "$container_name" | tail -60 >&2
  exit 1
fi

# Historical migration 005 inserts a fashion business before the taxonomy has
# that category. Seed only this prerequisite in the disposable QA database;
# do not edit or reorder historical migrations.
for migration in "$repo_root"/backend/migrations/[0-9][0-9][0-9]_*.sql; do
  if [[ "$(basename "$migration")" == "005_admin_analytics_and_kyc.sql" ]]; then
    docker exec "$container_name" psql -v ON_ERROR_STOP=1 -U qa3f -d "$database_name" \
      -c "INSERT INTO categories(slug,name,sort_order) VALUES (\$q\$fashion\$q\$,\$q\$Fashion (legacy migration prerequisite)\$q\$,11) ON CONFLICT DO NOTHING" >/dev/null
  fi
  if [[ "$(basename "$migration")" == "008_hospitality_and_food_delivery.sql" ]]; then
    # Migration 008 also seeds a legacy Spice Garden menu referencing a
    # business ID that is absent from migration 001–007 in a fresh database.
    docker exec "$container_name" psql -v ON_ERROR_STOP=1 -U qa3f -d "$database_name" \
      -c "INSERT INTO users(id,phone_e164,display_name) VALUES (\$q\$8f3f0000-0000-4000-8000-000000000001\$q\$,\$q\$+919000000001\$q\$,\$q\$QA legacy migration owner\$q\$) ON CONFLICT DO NOTHING; INSERT INTO businesses(id,owner_user_id,name,slug,category_slug,address_text,locality,city,postal_code,location) VALUES (\$q\$cfb375d3-543b-4bb8-8f1d-11a10659661c\$q\$,\$q\$8f3f0000-0000-4000-8000-000000000001\$q\$,\$q\$QA legacy Spice Garden\$q\$,\$q\$qa-legacy-spice-garden\$q\$,\$q\$restaurant\$q\$,\$q\$Disposable migration bootstrap\$q\$,\$q\$QA locality\$q\$,\$q\$Bhubaneswar\$q\$,\$q\$751001\$q\$,ST_SetSRID(ST_MakePoint(85.8,20.3)::geography,4326)) ON CONFLICT (id) DO NOTHING" >/dev/null
  fi
  printf 'Applying %s\n' "$(basename "$migration")"
  docker exec -i "$container_name" psql -q -v ON_ERROR_STOP=1 -U qa3f -d "$database_name" \
    < "$migration"
done

tables=$(docker exec "$container_name" psql -U qa3f -d "$database_name" -Atc \
  "SELECT count(*) FROM information_schema.tables WHERE table_schema=\$q\$public\$q\$ AND table_name IN (\$q\$delivery_jobs\$q\$,\$q\$rider_earning_entries\$q\$,\$q\$rider_earning_audit_events\$q\$)")
if [[ "$tables" != "3" ]]; then
  printf 'Expected delivery and earnings tables after migration 028; found %s.\n' "$tables" >&2
  exit 1
fi

port=$(docker port "$container_name" 5432/tcp | sed 's/.*://')
printf 'Running PostgreSQL-backed Phase 3F acceptance against isolated PostGIS (port %s).\n' "$port"
cd "$repo_root/backend"
TEST_DATABASE_DSN="host=127.0.0.1 port=$port user=qa3f password=qa3f_disposable_only dbname=$database_name sslmode=disable" \
  go test -count=1 ./internal/deliverydispatch -run TestChhatiaDeliveryTimelineAndLocalityIsolation -v

