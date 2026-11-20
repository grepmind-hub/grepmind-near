#!/usr/bin/env bash
set -euo pipefail

migrations_dir="/mnt/d/grepmind-near/backend/migrations"
db="grepmind_3e_qa_db"
dbname="grepmind_3e_qa"
user="qa3e"

for m in "$migrations_dir"/[0-9][0-9][0-9]_*.sql; do
  fname="$(basename "$m")"
  if [[ "$fname" == "005_admin_analytics_and_kyc.sql" ]]; then
    echo "Applying fashion prerequisite..."
    docker exec -i "$db" psql -U "$user" -d "$dbname" -v ON_ERROR_STOP=1 < /mnt/d/grepmind-near/scripts/qa/phase3e-qa-fashion-prerequisite.sql
  fi
  echo "Applying $fname..."
  docker exec -i "$db" psql -U "$user" -d "$dbname" -v ON_ERROR_STOP=1 < "$m"
done

echo "Applying phase3e-fixtures..."
docker exec -i "$db" psql -U "$user" -d "$dbname" -v ON_ERROR_STOP=1 < /mnt/d/grepmind-near/scripts/qa/phase3e-fixtures.sql

echo "Applying phase4c-e2e-finance-fixture..."
docker exec -i "$db" psql -U "$user" -d "$dbname" -v ON_ERROR_STOP=1 < /mnt/d/grepmind-near/scripts/qa/phase4c-e2e-finance-fixture.sql

echo "Done!"
