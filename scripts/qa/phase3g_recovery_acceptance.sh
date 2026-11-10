#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
container_name="grepmind_3gb_qa_$$"
database_name="grepmind_3gb_${$}_qa"
created=false

cleanup() {
  if [[ "$created" == true ]]; then
    docker rm -f "$container_name" >/dev/null 2>&1 || true
    printf 'Removed disposable Phase 3G-B PostGIS container.\n'
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
  -e POSTGRES_USER=qa3g \
  -e POSTGRES_PASSWORD=qa3g_disposable_only \
  -e "POSTGRES_DB=$database_name" \
  -p 0.0.0.0::5432 \
  postgis/postgis:16-3.4 >/dev/null
created=true

ready=false
for _ in $(seq 1 90); do
  ready_count=$(docker logs "$container_name" 2>&1 | grep -c 'database system is ready to accept connections' || true)
  if [[ "$ready_count" -ge 2 ]] && docker exec "$container_name" pg_isready -U qa3g -d "$database_name" >/dev/null 2>&1; then
    ready=true
    break
  fi
  sleep 1
done
if [[ "$ready" != true ]]; then
  docker logs "$container_name" | tail -60 >&2
  exit 1
fi

# Historical migration prerequisites for a pristine disposable database only.
for migration in "$repo_root"/backend/migrations/[0-9][0-9][0-9]_*.sql; do
  name="$(basename "$migration")"
  if [[ "$name" == "005_admin_analytics_and_kyc.sql" ]]; then
    docker exec "$container_name" psql -v ON_ERROR_STOP=1 -U qa3g -d "$database_name" \
      -c "INSERT INTO categories(slug,name,sort_order) VALUES ('fashion','Fashion (legacy migration prerequisite)',11) ON CONFLICT DO NOTHING" >/dev/null
  fi
  if [[ "$name" == "008_hospitality_and_food_delivery.sql" ]]; then
    docker exec "$container_name" psql -v ON_ERROR_STOP=1 -U qa3g -d "$database_name" \
      -c "INSERT INTO users(id,phone_e164,display_name) VALUES ('8f3f0000-0000-4000-8000-000000000001','+919000000001','QA legacy migration owner') ON CONFLICT DO NOTHING; INSERT INTO businesses(id,owner_user_id,name,slug,category_slug,address_text,locality,city,postal_code,location) VALUES ('cfb375d3-543b-4bb8-8f1d-11a10659661c','8f3f0000-0000-4000-8000-000000000001','QA legacy Spice Garden','qa-legacy-spice-garden','restaurant','Disposable migration bootstrap','QA locality','Bhubaneswar','751001',ST_SetSRID(ST_MakePoint(85.8,20.3)::geography,4326)) ON CONFLICT (id) DO NOTHING" >/dev/null
  fi
  printf 'Applying %s\n' "$name"
  docker exec -i "$container_name" psql -q -v ON_ERROR_STOP=1 -U qa3g -d "$database_name" < "$migration"
done

schema_check=$(docker exec "$container_name" psql -U qa3g -d "$database_name" -Atc \
  "SELECT count(*) FROM information_schema.tables WHERE table_schema='public' AND table_name IN ('delivery_recovery_cases','delivery_recovery_events','delivery_recovery_idempotency','delivery_return_receipts','delivery_recovery_partner_confirmations')")
if [[ "$schema_check" != "5" ]]; then
  printf 'Migration 029 did not create the complete recovery schema (found %s tables).\n' "$schema_check" >&2
  exit 1
fi

port=$(docker port "$container_name" 5432/tcp | sed 's/.*://')
printf 'Running Phase 3G-B PostgreSQL acceptance against isolated tmpfs PostGIS on port %s.\n' "$port"
cd "$repo_root/backend"
export TEST_DATABASE_DSN="host=127.0.0.1 port=$port user=qa3g password=qa3g_disposable_only dbname=$database_name sslmode=disable"
go test -count=1 ./internal/deliverydispatch -run 'TestDispatchPrepareOfferAcceptAndIsolation|TestChhatiaDeliveryTimelineAndLocalityIsolation' -v
GREPMIND_TEST_DATABASE_URL="postgres://qa3g:qa3g_disposable_only@127.0.0.1:$port/$database_name?sslmode=disable" go test -count=1 ./cmd/api -run TestAdminUserAccessRoleBoundaries -v
