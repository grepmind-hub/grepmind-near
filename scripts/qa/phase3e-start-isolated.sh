#!/usr/bin/env bash
set -euo pipefail

# Disposable Phase 3E PostGIS fixture. The database uses tmpfs only and does
# not connect to or alter the shared Grepmind development database.
readonly name="grepmind_3e_qa_db"
readonly network="grepmind_3e_qa_net"
readonly migrations_source="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../backend/migrations" && pwd)"
readonly qa_fixture="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/phase3e-qa-fashion-prerequisite.sql"

for resource in "$name" "$network"; do
  if docker ps -a --format '{{.Names}}' | grep -Fxq "$resource" ||
     docker network ls --format '{{.Name}}' | grep -Fxq "$resource"; then
    echo "Refusing to reuse existing QA resource: $resource" >&2
    exit 2
  fi
done

docker network create "$network" >/dev/null
docker run -d \
  --name "$name" \
  --network "$network" \
  --tmpfs /var/lib/postgresql/data:rw,size=1g \
  -e POSTGRES_DB=grepmind_3e_qa \
  -e POSTGRES_USER=qa3e \
  -e POSTGRES_PASSWORD=qa3e_only_local \
  -p 127.0.0.1:55432:5432 \
  postgis/postgis:16-3.4 >/dev/null

for _ in $(seq 1 90); do
  logs="$(docker logs "$name" 2>&1)"
  ready_starts="$(grep -c 'database system is ready to accept connections' <<<"$logs" || true)"
  if grep -q 'PostgreSQL init process complete; ready for start up.' <<<"$logs" &&
     (( ready_starts >= 2 )) &&
     docker exec "$name" psql -U qa3e -d grepmind_3e_qa -Atc 'SELECT 1' >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

docker exec "$name" pg_isready -U qa3e -d grepmind_3e_qa
docker exec "$name" mkdir -p /tmp/qa-migrations
for migration in "$migrations_source"/[0-9][0-9][0-9]_*.sql; do
  docker cp "$migration" "$name:/tmp/qa-migrations/"
done
docker cp "$qa_fixture" "$name:/tmp/qa-migrations/004a_qa_fashion_category.sql"

for migration in "$migrations_source"/[0-9][0-9][0-9]_*.sql; do
  filename="$(basename "$migration")"
  if [[ "$filename" == "005_admin_analytics_and_kyc.sql" ]]; then
    docker exec "$name" psql -U qa3e -d grepmind_3e_qa -v ON_ERROR_STOP=1 \
      -f /tmp/qa-migrations/004a_qa_fashion_category.sql
  fi
  echo "Applying isolated migration $filename"
  docker exec "$name" psql -U qa3e -d grepmind_3e_qa -v ON_ERROR_STOP=1 \
    -f "/tmp/qa-migrations/$filename"
done

docker exec "$name" psql -U qa3e -d grepmind_3e_qa -v ON_ERROR_STOP=1 \
  -c "SELECT count(*) AS applied_public_tables FROM information_schema.tables WHERE table_schema='public'"
