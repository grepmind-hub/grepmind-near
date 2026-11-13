#!/usr/bin/env bash
set -euo pipefail
set +x

# Recreate only the disposable Phase 4D QA API. The PostgreSQL/PostGIS,
# Merchant/Admin portal, MinIO, and shared Compose services are not touched.
readonly api=grepmind_4c_qa_api
readonly db=grepmind_3e_qa_db
readonly dbname=grepmind_3e_qa
readonly network=grepmind_3e_qa_net
readonly image=grepmind-near:phase4c-qa

[[ "$(docker inspect -f '{{.Name}}' "$db" 2>/dev/null || true)" == "/$db" ]] || {
  echo "Expected isolated tmpfs QA database is not running." >&2; exit 2;
}
[[ "$(docker inspect -f '{{json .Mounts}}' "$db")" == "[]" ]] || {
  echo "Refusing a QA database with persistent mounts." >&2; exit 2;
}
[[ "$(docker inspect -f '{{json .HostConfig.Tmpfs}}' "$db")" == *"/var/lib/postgresql/data"* ]] || {
  echo "Refusing a database that is not tmpfs-backed." >&2; exit 2;
}
docker network inspect "$network" >/dev/null
docker exec "$db" psql -U qa3e -d "$dbname" -Atc \
  "SELECT 1 WHERE to_regclass('public.merchant_payable_snapshots') IS NOT NULL AND to_regclass('public.cod_obligations') IS NOT NULL" | grep -qx 1 || {
  echo "The disposable database must have migrations through 035." >&2; exit 2;
}

docker rm -f "$api" >/dev/null 2>&1 || true
jwt_secret="$(openssl rand -hex 48)"
qa_otp_run_id="phase4d-e2er-$(openssl rand -hex 12)"
payment_webhook_secret="$(openssl rand -hex 48)"
docker run -d --name "$api" --network "$network" --network-alias api \
  --tmpfs /run/qa-otp:rw,noexec,nosuid,nodev,size=1m,mode=0700,uid=100,gid=100 \
  -p 127.0.0.1:18083:8080 \
  -e APP_ENV=qa -e APP_PORT=8080 -e LOG_LEVEL=info -e OTP_PROVIDER=qa_file \
  -e QA_OTP_DELIVERY_ENABLED=true -e QA_OTP_INBOX_DIR=/run/qa-otp \
  -e QA_OTP_RUN_ID="$qa_otp_run_id" \
  -e QA_OTP_ALLOWLIST=+919990000171,+919990000172,+919990000173,+919990000174,+919990000175,+919990000176 \
  -e PAYMENT_SANDBOX_ENABLED=true \
  -e PAYMENT_SANDBOX_WEBHOOK_SECRET="$payment_webhook_secret" \
  -e PAYMENT_SANDBOX_WEBHOOK_KEY_ID=phase4d-e2er \
  -e PAYMENT_SANDBOX_QA_USER_IDS=3e000000-0000-4000-8000-000000000001 \
  -e SANDBOX_COD_ENABLED=true -e RIDER_DISPATCH_ENABLED=true \
  -e DB_HOST="$db" -e DB_PORT=5432 -e DB_USER=qa3e \
  -e DB_PASSWORD=qa3e_only_local -e DB_NAME="$dbname" -e DB_SSLMODE=disable \
  -e JWT_SECRET="$jwt_secret" "$image" >/dev/null
unset jwt_secret payment_webhook_secret

for _ in $(seq 1 60); do
  if curl --silent --fail http://127.0.0.1:18083/healthz >/dev/null; then
    echo "Disposable QA API is healthy at http://127.0.0.1:18083 (OTP inbox remains private)."
    echo "QA OTP run ID: $qa_otp_run_id"
    exit 0
  fi
  sleep 1
done
echo "Disposable QA API did not become healthy." >&2
docker logs --tail 80 "$api" >&2 || true
exit 1
