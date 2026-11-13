#!/usr/bin/env bash
set -euo pipefail

# Read-only reconciliation against the disposable Phase 3E/PostGIS QA container.
container="grepmind_3e_qa_db"
job_id="46c8b827-e149-41db-b41f-c4a72912bc82"
docker exec -i "$container" sh -lc 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -X -A -F "|"' <<SQL
SELECT 'database_clock', now()::text;
SELECT 'offer', sequence::text, right(rider_user_id::text,4), state, offered_at::text, expires_at::text
FROM delivery_offers WHERE job_id='$job_id' ORDER BY sequence;
SELECT 'assignment', right(rider_user_id::text,4), state, assigned_at::text, ended_at::text
FROM delivery_assignments WHERE job_id='$job_id' ORDER BY assigned_at;
SQL
