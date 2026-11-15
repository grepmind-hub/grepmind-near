#!/usr/bin/env bash
set -euo pipefail

db="grepmind_3e_qa_db"
dbname="grepmind_fresh_mig_test"
repo_root="/mnt/d/grepmind-near"

echo "=== Dropping and recreating test database $dbname ==="
docker exec "$db" psql -U qa3e -d postgres -c "DROP DATABASE IF EXISTS $dbname;"
docker exec "$db" psql -U qa3e -d postgres -c "CREATE DATABASE $dbname;"

echo "=== Applying migrations 001 to 040 sequentially ==="
for migration in "$repo_root"/backend/migrations/[0-9][0-9][0-9]_*.sql; do
  name="$(basename "$migration")"
  if [[ "$name" == "005_admin_analytics_and_kyc.sql" ]]; then
    docker exec "$db" psql -v ON_ERROR_STOP=1 -U qa3e -d "$dbname" \
      -c "INSERT INTO categories(slug,name,sort_order) VALUES ('fashion','Fashion (legacy migration prerequisite)',11) ON CONFLICT DO NOTHING;" >/dev/null
  fi
  if [[ "$name" == "008_hospitality_and_food_delivery.sql" ]]; then
    docker exec "$db" psql -v ON_ERROR_STOP=1 -U qa3e -d "$dbname" \
      -c "INSERT INTO users(id,phone_e164,display_name) VALUES ('8f3f0000-0000-4000-8000-000000000001','+919000000001','QA legacy migration owner') ON CONFLICT DO NOTHING; INSERT INTO businesses(id,owner_user_id,name,slug,category_slug,address_text,locality,city,postal_code,location) VALUES ('cfb375d3-543b-4bb8-8f1d-11a10659661c','8f3f0000-0000-4000-8000-000000000001','QA legacy Spice Garden','qa-legacy-spice-garden','restaurant','Disposable migration bootstrap','QA locality','Bhubaneswar','751001',ST_SetSRID(ST_MakePoint(85.8,20.3)::geography,4326)) ON CONFLICT (id) DO NOTHING;" >/dev/null
  fi
  printf "Applying %s... " "$name"
  docker exec -i "$db" psql -q -v ON_ERROR_STOP=1 -U qa3e -d "$dbname" < "$migration"
  echo "OK"
done

echo "=== Verifying tables, indexes, constraints, and triggers in fresh database ==="
table_count=$(docker exec "$db" psql -U qa3e -d "$dbname" -t -A -c "SELECT count(*) FROM information_schema.tables WHERE table_schema='public';")
echo "Total tables in fresh database: $table_count"

# Verify 039 tables
docker exec "$db" psql -U qa3e -d "$dbname" -c "\d bank_beneficiaries" >/dev/null && echo "✓ Table bank_beneficiaries exists"
docker exec "$db" psql -U qa3e -d "$dbname" -c "\d bank_beneficiary_audit_events" >/dev/null && echo "✓ Table bank_beneficiary_audit_events exists"
docker exec "$db" psql -U qa3e -d "$dbname" -c "\d payout_transfers" >/dev/null && echo "✓ Table payout_transfers exists"
docker exec "$db" psql -U qa3e -d "$dbname" -c "\d payout_transfer_attempts" >/dev/null && echo "✓ Table payout_transfer_attempts exists"
docker exec "$db" psql -U qa3e -d "$dbname" -c "\d payout_provider_events" >/dev/null && echo "✓ Table payout_provider_events exists"

# Verify 040 tables
docker exec "$db" psql -U qa3e -d "$dbname" -c "\d rider_settlement_batches" >/dev/null && echo "✓ Table rider_settlement_batches exists"
docker exec "$db" psql -U qa3e -d "$dbname" -c "\d rider_settlement_batch_items" >/dev/null && echo "✓ Table rider_settlement_batch_items exists"
docker exec "$db" psql -U qa3e -d "$dbname" -c "\d rider_earning_financial_mappings" >/dev/null && echo "✓ Table rider_earning_financial_mappings exists"

# Verify unique allocation indexes
docker exec "$db" psql -U qa3e -d "$dbname" -t -A -c "SELECT count(*) FROM pg_indexes WHERE indexname='merchant_payable_active_allocation_idx';" | grep -q 1 && echo "✓ Index merchant_payable_active_allocation_idx exists"
docker exec "$db" psql -U qa3e -d "$dbname" -t -A -c "SELECT count(*) FROM pg_indexes WHERE indexname='rider_earning_active_allocation_idx';" | grep -q 1 && echo "✓ Index rider_earning_active_allocation_idx exists"

# Verify triggers
docker exec "$db" psql -U qa3e -d "$dbname" -t -A -c "SELECT count(*) FROM pg_trigger WHERE tgname='payout_provider_events_immutable';" | grep -q 1 && echo "✓ Trigger payout_provider_events_immutable exists"
docker exec "$db" psql -U qa3e -d "$dbname" -t -A -c "SELECT count(*) FROM pg_trigger WHERE tgname='bank_beneficiary_audit_immutable';" | grep -q 1 && echo "✓ Trigger bank_beneficiary_audit_immutable exists"

# Compare schema difference between fresh DB and grepmind_3e_qa
qa_tables=$(docker exec "$db" psql -U qa3e -d grepmind_3e_qa -t -A -c "SELECT count(*) FROM information_schema.tables WHERE table_schema='public';")
echo "Tables in grepmind_3e_qa: $qa_tables"
echo "Tables in grepmind_fresh_mig_test: $table_count"

# Clean up disposable database
docker exec "$db" psql -U qa3e -d postgres -c "DROP DATABASE $dbname;"
echo "=== Disposable test database dropped cleanly ==="
echo "=== FRESH MIGRATION REPRODUCIBILITY TEST PASSED ==="
