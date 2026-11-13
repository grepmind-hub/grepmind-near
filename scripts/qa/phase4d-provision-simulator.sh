#!/usr/bin/env bash
set -euo pipefail
set +x

# One-time synthetic Admin bootstrap for the specifically authorized isolated
# Phase 4D QA settlement simulator. This creates no financial permission grant.
readonly db=grepmind_3e_qa_db
readonly dbname=grepmind_3e_qa
readonly network=grepmind_3e_qa_net
readonly phone='+919990000177'

[[ "$(docker inspect -f '{{.Name}}' "$db" 2>/dev/null || true)" == "/$db" ]] || { echo "Expected isolated QA database container is missing." >&2; exit 2; }
[[ "$(docker inspect -f '{{json .Mounts}}' "$db")" == '[]' ]] || { echo "Refusing a database with persistent mounts." >&2; exit 2; }
[[ "$(docker inspect -f '{{json .HostConfig.Tmpfs}}' "$db")" == *"/var/lib/postgresql/data"* ]] || { echo "Refusing a database that is not tmpfs-backed." >&2; exit 2; }
[[ "$(docker inspect -f '{{range $k,$v := .NetworkSettings.Networks}}{{println $k}}{{end}}' "$db" | tr -d '\r')" == "$network" ]] || { echo "Refusing a database outside the dedicated QA network." >&2; exit 2; }
if docker network inspect "$network" -f '{{range $id,$c := .Containers}}{{println $c.Name}}{{end}}' | grep -Eq '^(grepmind_postgres|aayara-postgres)$'; then
  echo "Shared PostgreSQL is attached to the QA network; refusing to proceed." >&2; exit 2
fi

docker exec -i "$db" psql -v ON_ERROR_STOP=1 -U qa3e -d "$dbname" <<'SQL'
BEGIN;
DO $$
DECLARE existing_id UUID; existing_status TEXT; has_admin BOOLEAN;
BEGIN
  SELECT id,status INTO existing_id,existing_status FROM users WHERE phone_e164='+919990000177' FOR UPDATE;
  IF existing_id IS NOT NULL THEN
    SELECT EXISTS(SELECT 1 FROM user_roles WHERE user_id=existing_id AND role='admin') INTO has_admin;
    IF existing_status<>'active' OR NOT has_admin THEN
      RAISE EXCEPTION 'synthetic simulator identity exists in an unexpected state; refusing to modify it';
    END IF;
    RAISE NOTICE 'authorized synthetic QA simulator already exists; no identity changes made';
  ELSE
    INSERT INTO users(phone_e164,display_name,status) VALUES('+919990000177','Phase 4D QA Settlement Simulator','active') RETURNING id INTO existing_id;
    INSERT INTO user_roles(user_id,role) VALUES(existing_id,'admin');
    INSERT INTO audit_logs(actor_user_id,action,target_type,target_id,reason)
    VALUES(NULL,'qa_fixture_admin_provisioned','user',existing_id,'User-authorized isolated QA simulator fixture; no finance grants issued');
  END IF;
END $$;
COMMIT;
SELECT id::text AS simulator_user_id, phone_e164, status
FROM users WHERE phone_e164='+919990000177' AND status='active'
  AND EXISTS (SELECT 1 FROM user_roles WHERE user_id=users.id AND role='admin');
SELECT count(*) AS active_financial_grants
FROM financial_access_grants g JOIN users u ON u.id=g.user_id
WHERE u.phone_e164='+919990000177' AND g.revoked_at IS NULL;
SQL

echo "Synthetic QA Admin identity provisioned or verified. No financial grants were created."
