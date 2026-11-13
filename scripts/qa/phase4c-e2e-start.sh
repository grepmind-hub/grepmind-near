#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly api=grepmind_4c_qa_api
readonly otp=grepmind_4c_qa_otp_inbox
readonly minio=grepmind_4c_qa_minio
readonly admin=grepmind_4c_qa_admin
readonly merchant=grepmind_4c_qa_merchant
readonly network=grepmind_3e_qa_net
readonly db=grepmind_3e_qa_db
readonly dbname=grepmind_3e_qa
readonly qa_image=grepmind-near:phase4c-qa

for name in "$api" "$otp" "$minio" "$admin" "$merchant"; do
  if docker ps -a --format '{{.Names}}' | grep -Fxq "$name"; then
    echo "Refusing to reuse existing QA container: $name" >&2
    exit 2
  fi
done
docker network inspect "$network" >/dev/null
[[ "$(docker inspect -f '{{.Name}}' "$db" 2>/dev/null || true)" == "/$db" ]] || {
  echo "Start the disposable migration stack first with phase3e-start-isolated.sh." >&2; exit 2;
}
[[ "$(docker inspect -f '{{json .Mounts}}' "$db")" == "[]" ]] || {
  echo "Refusing database with persistent mounts." >&2; exit 2;
}
[[ "$(docker inspect -f '{{json .HostConfig.Tmpfs}}' "$db")" == *"/var/lib/postgresql/data"* ]] || {
  echo "Refusing database not backed by tmpfs." >&2; exit 2;
}
docker exec "$db" psql -U qa3e -d "$dbname" -Atc \
  "SELECT 1 WHERE to_regclass('public.cod_obligations') IS NOT NULL AND to_regclass('public.cod_collections') IS NOT NULL" | grep -qx 1 || {
  echo "Disposable database is missing Phase 4C migration 034." >&2; exit 2;
}

docker exec -i "$db" psql -v ON_ERROR_STOP=1 -U qa3e -d "$dbname" < "$root/scripts/qa/phase3e-fixtures.sql"
docker exec -i "$db" psql -v ON_ERROR_STOP=1 -U qa3e -d "$dbname" < "$root/scripts/qa/phase4c-e2e-finance-fixture.sql"

minio_user=qa4cminio
minio_password="$(openssl rand -hex 24)"
jwt_secret="$(openssl rand -hex 48)"
qa_otp_run_id="phase4c-$(openssl rand -hex 12)"
qa_otp_writer_token="$(openssl rand -hex 32)"
qa_otp_runner_id="codex-runner-$(openssl rand -hex 8)"
qa_otp_runner_secret="$(openssl rand -hex 32)"
qa_otp_env="${QA_OTP_RUN_ENV_FILE:-${TMPDIR:-/tmp}/grepmind-phase4c-qa-otp.env}"
umask 077
cat > "$qa_otp_env" <<EOF
QA_OTP_READER_URL=http://127.0.0.1:18085
QA_OTP_RUN_ID=$qa_otp_run_id
QA_OTP_RUNNER_ID=$qa_otp_runner_id
QA_OTP_RUNNER_SECRET=$qa_otp_runner_secret
EOF
chmod 0600 "$qa_otp_env"
docker run -d --name "$minio" --network "$network" \
  --tmpfs /data:rw,size=256m -e MINIO_ROOT_USER="$minio_user" \
  -e MINIO_ROOT_PASSWORD="$minio_password" \
  elestio/minio:latest server /data --console-address :9001 >/dev/null

docker build --target api -t "$qa_image" "$root/backend"
docker build --target qa-otp-inbox -t grepmind-near:qa-otp-inbox "$root/backend"
docker run -d --name "$otp" --network "$network" \
  --tmpfs /run/qa-otp:rw,noexec,nosuid,nodev,size=1m,mode=0700,uid=0,gid=0 \
  -p 127.0.0.1:18085:8090 \
  -e APP_ENV=qa -e QA_OTP_READER_ENABLED=true \
  -e QA_OTP_INBOX_DIR=/run/qa-otp -e QA_OTP_RUN_ID="$qa_otp_run_id" \
  -e QA_OTP_RUNNER_ID="$qa_otp_runner_id" -e QA_OTP_RUNNER_SECRET="$qa_otp_runner_secret" \
  -e QA_OTP_WRITER_SECRET="$qa_otp_writer_token" \
  -e QA_OTP_ALLOWLIST=+919990000171,+919990000172,+919990000173,+919990000174,+919990000175,+919990000176 \
  grepmind-near:qa-otp-inbox >/dev/null
docker run -d --name "$api" --network "$network" --network-alias api \
  -p 127.0.0.1:18083:8080 \
  -e APP_ENV=qa -e APP_PORT=8080 -e OTP_PROVIDER=qa_http \
  -e QA_OTP_DELIVERY_ENABLED=true \
  -e QA_OTP_DELIVERY_URL="http://$otp:8090" \
  -e QA_OTP_WRITER_TOKEN="$qa_otp_writer_token" \
  -e QA_OTP_RUN_ID="$qa_otp_run_id" \
  -e QA_OTP_ALLOWLIST=+919990000171,+919990000172,+919990000173,+919990000174,+919990000175,+919990000176 \
  -e SANDBOX_COD_ENABLED=true -e RIDER_DISPATCH_ENABLED=true \
  -e DB_HOST="$db" -e DB_PORT=5432 -e DB_USER=qa3e \
  -e DB_PASSWORD=qa3e_only_local -e DB_NAME="$dbname" -e DB_SSLMODE=disable \
  -e JWT_SECRET="$jwt_secret" \
  -e S3_ENDPOINT="http://$minio:9000" -e S3_ACCESS_KEY="$minio_user" \
  -e S3_SECRET_KEY="$minio_password" -e S3_BUCKET=grepmind-near \
  -e S3_PRIVATE_BUCKET=grepmind-near-private -e S3_USE_SSL=false \
  "$qa_image" >/dev/null

docker build -t grepmind-near:phase4c-qa-merchant \
  --build-arg API_PROXY_TARGET=http://api:8080/api/v1 "$root/apps/merchant-web"
docker run -d --name "$merchant" --network "$network" \
  -p 127.0.0.1:3301:3001 grepmind-near:phase4c-qa-merchant >/dev/null

docker build -t grepmind-near:phase4c-qa-admin "$root/apps/admin-web"
docker run -d --name "$admin" --network "$network" \
  -e API_PROXY_TARGET=http://api:8080/api/v1 \
  -p 127.0.0.1:3302:3000 grepmind-near:phase4c-qa-admin >/dev/null

for url in http://127.0.0.1:18083/healthz http://127.0.0.1:18085/healthz http://127.0.0.1:3301 http://127.0.0.1:3302/admin/login; do
  ready=false
  for _ in $(seq 1 90); do
    if curl --silent --fail "$url" >/dev/null; then ready=true; break; fi
    sleep 1
  done
  [[ "$ready" == true ]] || { echo "QA service failed health check: $url" >&2; exit 1; }
done
echo "Phase 4C isolated API, Merchant, Admin and PostGIS services are ready."
echo "API: http://127.0.0.1:18083 | Merchant: http://127.0.0.1:3301 | Admin: http://127.0.0.1:3302/admin/login"
echo "OTP inbox runs as a separate root-owned private tmpfs service; reader configuration is stored in a mode-0600 file."
echo "QA runner env file: $qa_otp_env"
