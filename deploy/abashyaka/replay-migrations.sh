#!/usr/bin/env bash
set -euo pipefail
umask 077

if [[ $# -ne 2 || ! $1 =~ @sha256:[[:xdigit:]]{64}$ ]]; then
  printf 'Usage: bash %s POSTGIS_IMAGE@sha256:DIGEST NEW_ARTIFACT_DIRECTORY\n' "$0" >&2
  exit 2
fi

image=$1
output=$2
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
migrations=("$repo"/backend/migrations/[0-9][0-9][0-9]_*.sql)

if [[ ${#migrations[@]} -ne 43 ]]; then
  printf 'Expected 43 numbered migrations.\n' >&2
  exit 1
fi
for index in "${!migrations[@]}"; do
  printf -v expected '%03d_' "$((index + 1))"
  if [[ ${migrations[index]##*/} != "$expected"* ]]; then
    printf 'Missing or duplicate migration prefix %s\n' "$expected" >&2
    exit 1
  fi
done

mkdir -- "$output"
replay=
cleanup() {
  if [[ -n $replay ]]; then
    docker rm -fv "$replay" >/dev/null
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

replay=$(docker run -d --network none --label abashyaka.role=migration-replay \
  -e POSTGRES_DB=abashyaka_replay -e POSTGRES_HOST_AUTH_METHOD=trust "$image")
# TCP distinguishes the final server from the PostgreSQL initialization process.
for ((attempt=0; attempt<60; attempt++)); do
  if docker exec "$replay" pg_isready -q -h 127.0.0.1 -U postgres -d abashyaka_replay; then
    break
  fi
  sleep 2
done
docker exec "$replay" pg_isready -h 127.0.0.1 -U postgres -d abashyaka_replay

run_sql() {
  docker exec -i "$replay" psql -X -U postgres -d abashyaka_replay -v ON_ERROR_STOP=1 "$@"
}

for migration in "${migrations[@]}"; do
  name=${migration##*/}
  case "$name" in
    005_*) run_sql -q -c "INSERT INTO categories(slug,name,sort_order) VALUES ('fashion','Fashion',11) ON CONFLICT DO NOTHING;" ;;
    008_*) run_sql -q <<'SQL'
INSERT INTO users(id, phone_e164, display_name)
VALUES ('8f3f0000-0000-4000-8000-000000000001', '+919000000001', 'Disposable replay owner')
ON CONFLICT DO NOTHING;
INSERT INTO businesses(id, owner_user_id, name, slug, category_slug, address_text, locality, city, postal_code, location)
VALUES ('cfb375d3-543b-4bb8-8f1d-11a10659661c', '8f3f0000-0000-4000-8000-000000000001',
        'Disposable replay prerequisite', 'disposable-replay-prerequisite', 'restaurant',
        'Disposable replay prerequisite', 'Replay', 'Bhubaneswar', '751001',
        ST_SetSRID(ST_MakePoint(85.8,20.3)::geography,4326))
ON CONFLICT (id) DO NOTHING;
SQL
      ;;
  esac
  run_sql -q < "$migration"
  printf 'Applied %s\n' "$name"
done

schema_check=$(run_sql -At <<'SQL'
SELECT to_regclass('public.admin_mpin_devices') IS NOT NULL
   AND (SELECT count(*) FROM information_schema.columns
        WHERE table_schema = 'public'
          AND ((table_name = 'businesses' AND column_name = 'is_synthetic')
           OR (table_name = 'products' AND column_name IN ('grocery_category','barcode','unit_label','mrp')))) = 5;
SQL
)
[[ $schema_check == t ]]

docker exec "$replay" pg_dump -U postgres -d abashyaka_replay --schema-only --format=custom \
  --no-owner --no-privileges > "$output/schema.dump.partial"
docker exec -i "$replay" pg_restore --list < "$output/schema.dump.partial" > "$output/schema.toc"
if grep -Eq ' (TABLE DATA|MATERIALIZED VIEW DATA|SEQUENCE SET|BLOB DATA) ' "$output/schema.toc"; then
  printf 'Unexpected data in schema-only export.\n' >&2
  exit 1
fi
(
  cd "$repo/backend/migrations"
  sha256sum -- [0-9][0-9][0-9]_*.sql
) > "$output/migrations.sha256"
mv -- "$output/schema.dump.partial" "$output/schema.dump"
(cd "$output" && sha256sum schema.dump > schema.sha256)
printf 'Schema-only replay archive verified: %s/schema.dump\n' "$output"
