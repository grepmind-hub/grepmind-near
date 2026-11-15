#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
db="grepmind_3e_qa_db"
dbname="grepmind_3e_qa"

echo "Checking container $db..."
docker inspect "$db" >/dev/null

echo "Applying migrations 001 to 037 to $db..."
for migration in "$repo_root"/backend/migrations/[0-9][0-9][0-9]_*.sql; do
  name="$(basename "$migration")"
  prefix="${name%%_*}"
  num=$((10#$prefix))
  if [[ $num -gt 37 ]]; then
    continue
  fi
  if [[ "$name" == "005_admin_analytics_and_kyc.sql" ]]; then
    docker exec "$db" psql -v ON_ERROR_STOP=1 -U qa3e -d "$dbname" \
      -c "INSERT INTO categories(slug,name,sort_order) VALUES ('fashion','Fashion (legacy migration prerequisite)',11) ON CONFLICT DO NOTHING" >/dev/null
  fi
  if [[ "$name" == "008_hospitality_and_food_delivery.sql" ]]; then
    docker exec "$db" psql -v ON_ERROR_STOP=1 -U qa3e -d "$dbname" \
      -c "INSERT INTO users(id,phone_e164,display_name) VALUES ('8f3f0000-0000-4000-8000-000000000001','+919000000001','QA legacy migration owner') ON CONFLICT DO NOTHING; INSERT INTO businesses(id,owner_user_id,name,slug,category_slug,address_text,locality,city,postal_code,location) VALUES ('cfb375d3-543b-4bb8-8f1d-11a10659661c','8f3f0000-0000-4000-8000-000000000001','QA legacy Spice Garden','qa-legacy-spice-garden','restaurant','Disposable migration bootstrap','QA locality','Bhubaneswar','751001',ST_SetSRID(ST_MakePoint(85.8,20.3)::geography,4326)) ON CONFLICT (id) DO NOTHING" >/dev/null
  fi
  printf "Applying %s\n" "$name"
  docker exec -i "$db" psql -q -v ON_ERROR_STOP=1 -U qa3e -d "$dbname" < "$migration"
done

echo "Applying QA fixtures..."
docker exec -i "$db" psql -q -v ON_ERROR_STOP=1 -U qa3e -d "$dbname" < "$repo_root/scripts/qa/phase3e-fixtures.sql"
docker exec -i "$db" psql -q -v ON_ERROR_STOP=1 -U qa3e -d "$dbname" < "$repo_root/scripts/qa/phase4c-e2e-finance-fixture.sql"
docker exec -i "$db" psql -q -v ON_ERROR_STOP=1 -U qa3e -d "$dbname" < "$repo_root/scripts/qa/phase4d-e2er-finance-fixtures.sql"

# Provision simulator user +919990000177
docker exec -i "$db" psql -q -v ON_ERROR_STOP=1 -U qa3e -d "$dbname" <<'EOF'
DO $$
DECLARE existing_id UUID;
BEGIN
  SELECT id INTO existing_id FROM users WHERE phone_e164='+919990000177';
  IF existing_id IS NULL THEN
    INSERT INTO users(phone_e164,display_name,status) VALUES('+919990000177','Phase 4D QA Settlement Simulator','active') RETURNING id INTO existing_id;
    INSERT INTO user_roles(user_id,role) VALUES(existing_id,'admin');
  END IF;
END $$;
EOF

echo "Verification:"
docker exec "$db" psql -U qa3e -d "$dbname" -c "SELECT count(*) AS total_tables FROM information_schema.tables WHERE table_schema='public';"
count=$(docker exec "$db" psql -U qa3e -d "$dbname" -Atc \
  "SELECT count(DISTINCT phone_e164) FROM users WHERE phone_e164 = ANY (ARRAY['+919990000171','+919990000172','+919990000173','+919990000174','+919990000175','+919990000176','+919990000177'])")
echo "Synthetic QA users count: $count (expected 7)"
[[ "$count" == "7" ]] || { echo "User count mismatch" >&2; exit 1; }
echo "QA DB initialized successfully!"
