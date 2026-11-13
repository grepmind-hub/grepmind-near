#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
container_name="grepmind_4e2_qa_$$"
database_name="grepmind_4e2_${$}_qa"
created=false
cleanup() {
  if [[ "$created" == true ]]; then
    docker rm -f "$container_name" >/dev/null 2>&1 || true
    printf 'Removed disposable tmpfs Phase 4E.2 PostGIS container %s.\n' "$container_name"
  fi
}
trap cleanup EXIT INT TERM

if docker inspect "$container_name" >/dev/null 2>&1; then
  printf 'Refusing to reuse existing container %s.\n' "$container_name" >&2
  exit 2
fi

docker run -d --name "$container_name" \
  --tmpfs /var/lib/postgresql/data:rw,size=2g \
  -e POSTGRES_USER=qa4e2 -e POSTGRES_PASSWORD=qa4e2_disposable_only \
  -e "POSTGRES_DB=$database_name" -p 127.0.0.1::5432 postgis/postgis:16-3.4 >/dev/null
created=true

ready=false
for _ in $(seq 1 90); do
  ready_count="$(docker logs "$container_name" 2>&1 | grep -c 'database system is ready to accept connections' || true)"
  if [[ "$ready_count" -ge 2 ]] && docker exec "$container_name" pg_isready -U qa4e2 -d "$database_name" >/dev/null 2>&1; then ready=true; break; fi
  sleep 1
done
if [[ "$ready" != true ]]; then docker logs "$container_name" | tail -60 >&2; exit 1; fi

for migration in "$repo_root"/backend/migrations/[0-9][0-9][0-9]_*.sql; do
  name="$(basename "$migration")"
  [[ $((10#${name%%_*})) -le 37 ]] || continue
  if [[ "$name" == "005_admin_analytics_and_kyc.sql" ]]; then
    docker exec "$container_name" psql -v ON_ERROR_STOP=1 -U qa4e2 -d "$database_name" \
      -c "INSERT INTO categories(slug,name,sort_order) VALUES ('fashion','Fashion (legacy migration prerequisite)',11) ON CONFLICT DO NOTHING" >/dev/null
  fi
  if [[ "$name" == "008_hospitality_and_food_delivery.sql" ]]; then
    docker exec "$container_name" psql -v ON_ERROR_STOP=1 -U qa4e2 -d "$database_name" \
      -c "INSERT INTO users(id,phone_e164,display_name) VALUES ('8f3f0000-0000-4000-8000-000000000001','+919000000001','QA legacy migration owner') ON CONFLICT DO NOTHING; INSERT INTO businesses(id,owner_user_id,name,slug,category_slug,address_text,locality,city,postal_code,location) VALUES ('cfb375d3-543b-4bb8-8f1d-11a10659661c','8f3f0000-0000-4000-8000-000000000001','QA legacy Spice Garden','qa-legacy-spice-garden','restaurant','Disposable migration bootstrap','QA locality','Bhubaneswar','751001',ST_SetSRID(ST_MakePoint(85.8,20.3)::geography,4326)) ON CONFLICT (id) DO NOTHING" >/dev/null
  fi
  printf 'Applying %s to disposable database\n' "$name"
  docker exec -i "$container_name" psql -q -v ON_ERROR_STOP=1 -U qa4e2 -d "$database_name" < "$migration"
done

port="$(docker port "$container_name" 5432/tcp | sed 's/.*://')"
db_name="$(docker exec "$container_name" psql -U qa4e2 -d "$database_name" -Atc 'SELECT current_database()')"
[[ "$db_name" == *_qa ]] || { printf 'Database name is not isolated QA: %s\n' "$db_name" >&2; exit 1; }

cd "$repo_root/backend"
unset TEST_DATABASE_DSN TEST_DATABASE_URL GREPMIND_TEST_DATABASE_URL
printf 'Running full Go suite without database DSNs.\n'
go test -p 1 -count=1 ./...

export TEST_DATABASE_DSN="host=127.0.0.1 port=$port user=qa4e2 password=qa4e2_disposable_only dbname=$database_name sslmode=disable"
printf 'Running focused payment-state transition tests against %s.\n' "$database_name"
go test -count=1 ./internal/platformfulfillment -run '^TestUnverifiedUPIIsBlockedFromMerchantFulfillmentPostGIS$'
go test -count=1 ./internal/deliverydispatch -run '^TestUPIDispatchWaitsForVerifiedPaymentPostGIS$'

printf 'Migration/schema check: '
docker exec "$container_name" psql -U qa4e2 -d "$database_name" -Atc "SELECT count(*) FROM information_schema.tables WHERE table_schema='public' AND table_name IN ('payment_intents','payment_attempts','cod_obligations','delivery_jobs','financial_feature_config')"
