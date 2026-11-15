#!/usr/bin/env bash
set -euo pipefail
umask 077

# Rebuilds only the known disposable Phase 4C API and adds an isolated OTP
# helper. The existing tmpfs QA database and business/finance records remain.
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly api=grepmind_4c_qa_api
readonly db=grepmind_3e_qa_db
readonly network=grepmind_3e_qa_net
readonly inbox=grepmind_4c_qa_otp_inbox
readonly image=grepmind-near:auth-otp-e2e-r2
readonly inbox_image=grepmind-near:qa-otp-inbox
readonly allowlist='+919990000171,+919990000172,+919990000173,+919990000174,+919990000175,+919990000176,+919990000177,+919990000181,+919990000182,+919990000183'
readonly previous_allowlist='+919990000171,+919990000172,+919990000173,+919990000174,+919990000175,+919990000176,+919990000177'

for name in "$api" "$db"; do
  docker inspect "$name" >/dev/null 2>&1 || { echo "Required isolated QA container is missing: $name" >&2; exit 2; }
  [[ "$(docker inspect -f '{{.State.Running}}' "$name")" == true ]] || { echo "Required QA container is not running: $name" >&2; exit 2; }
done
[[ "$(docker inspect -f '{{.HostConfig.NetworkMode}}' "$api")" == "$network" ]] || { echo "QA API is not on the expected isolated network." >&2; exit 2; }
[[ "$(docker inspect -f '{{.HostConfig.NetworkMode}}' "$db")" == "$network" ]] || { echo "QA database is not on the expected isolated network." >&2; exit 2; }
[[ "$(docker inspect -f '{{json .Mounts}}' "$db")" == '[]' ]] || { echo "Refusing a QA database with persistent mounts." >&2; exit 2; }
[[ "$(docker inspect -f '{{json .HostConfig.Tmpfs}}' "$db")" == *"/var/lib/postgresql/data"* ]] || { echo "Refusing a database not backed by tmpfs." >&2; exit 2; }
[[ "$(docker inspect -f '{{json .Mounts}}' "$api")" == '[]' ]] || { echo "Refusing an API container with mounted host data." >&2; exit 2; }
[[ "$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$api" | grep -Fx 'APP_ENV=qa' || true)" == 'APP_ENV=qa' ]] || { echo "Refusing an API not explicitly configured for QA." >&2; exit 2; }
[[ "$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$api" | grep -Fx "DB_HOST=$db" || true)" == "DB_HOST=$db" ]] || { echo "QA API database target does not match the isolated database." >&2; exit 2; }
if docker network inspect "$network" -f '{{range $id, $container := .Containers}}{{println $container.Name}}{{end}}' | grep -Eq '^(grepmind_postgres|aayara-postgres)$'; then
  echo "Shared PostgreSQL is attached to the QA network; refusing to continue." >&2; exit 2
fi
existing_inbox=false
old_inbox="${inbox}_previous_$(openssl rand -hex 4)"
inbox_rotated=false
new_inbox_started=false
if docker inspect "$inbox" >/dev/null 2>&1; then
  [[ "$(docker inspect -f '{{.Config.Image}}' "$inbox")" == "$inbox_image" ]] || { echo "Existing inbox image is not the reviewed QA reader image." >&2; exit 2; }
  [[ "$(docker inspect -f '{{.HostConfig.NetworkMode}}' "$inbox")" == "$network" ]] || { echo "Existing inbox is outside the isolated QA network." >&2; exit 2; }
  [[ "$(docker inspect -f '{{json .Mounts}}' "$inbox")" == '[]' ]] || { echo "Existing inbox has a persistent mount; refusing to rotate it." >&2; exit 2; }
  [[ "$(docker inspect -f '{{json .HostConfig.Tmpfs}}' "$inbox")" == *"/run/qa-otp"* ]] || { echo "Existing inbox is not using private tmpfs storage." >&2; exit 2; }
  [[ "$(docker inspect -f '{{json .HostConfig.Tmpfs}}' "$inbox")" == *"uid=0,gid=0"* ]] || { echo "Existing inbox tmpfs is not root-owned." >&2; exit 2; }
  old_inbox_env="$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$inbox")"
  grep -Fxq 'APP_ENV=qa' <<< "$old_inbox_env" || { echo "Existing inbox is not explicitly in QA mode." >&2; exit 2; }
  grep -Fxq 'QA_OTP_READER_ENABLED=true' <<< "$old_inbox_env" || { echo "Existing inbox reader is not explicitly enabled." >&2; exit 2; }
  api_run="$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$api" | sed -n 's/^QA_OTP_RUN_ID=//p')"
  inbox_run="$(sed -n 's/^QA_OTP_RUN_ID=//p' <<< "$old_inbox_env")"
  [[ -n "$api_run" && "$api_run" == "$inbox_run" ]] || { echo "Existing API and inbox run IDs do not match." >&2; exit 2; }
  curl --silent --fail http://127.0.0.1:18085/healthz >/dev/null || { echo "Existing inbox health check failed; refusing to rotate an unhealthy reader." >&2; exit 2; }
  existing_inbox=true
fi
published_readers="$(docker ps --filter publish=18085 --format '{{.Names}}')"
if [[ -n "$published_readers" && ( "$existing_inbox" != true || "$published_readers" != "$inbox" ) ]]; then
  echo "Reader loopback port 18085 is occupied by an unexpected container." >&2; exit 2
fi

# Migration 036 must already be present. This script never alters the database.
schema_ok="$(docker exec "$db" psql -v ON_ERROR_STOP=1 -U qa3e -d grepmind_3e_qa -Atc \
  "SELECT (SELECT count(*)=2 FROM information_schema.columns WHERE table_schema='public' AND table_name='otp_codes' AND column_name IN ('purpose','invalidated_at')) AND to_regclass('public.financial_access_grant_requests') IS NOT NULL")"
[[ "$schema_ok" == t ]] || { echo "Disposable database must have migration 036 auth columns and Phase 4D migration 037; refusing to migrate here." >&2; exit 2; }

cache_dir="${HOME}/.cache/grepmind/qa-otp-runs"
install -d -m 0700 "$cache_dir"
run_id="auth-otp-$(openssl rand -hex 16)"
runner_id="qa-runner-$(openssl rand -hex 8)"
runner_secret="$(openssl rand -hex 32)"
writer_secret="$(openssl rand -hex 32)"
runner_env="$cache_dir/${run_id}.env"
api_env="$(mktemp)"
inbox_env="$(mktemp)"
old_env="$(mktemp)"
api_removed=false
cleanup_temp() { rm -f "$api_env" "$inbox_env" "$old_env" "${old_env}.image"; }
rollback_api() {
  status=$?
  if [[ $status -ne 0 && "$new_inbox_started" == true ]]; then
    docker rm -f "$inbox" >/dev/null 2>&1 || true
    new_inbox_started=false
  fi
  if [[ $status -ne 0 && "$inbox_rotated" == true ]]; then
    docker rename "$old_inbox" "$inbox" >/dev/null 2>&1 || true
    docker start "$inbox" >/dev/null 2>&1 || true
    inbox_rotated=false
  fi
  if [[ "$api_removed" == true && $status -ne 0 ]]; then
    docker rm -f "$api" >/dev/null 2>&1 || true
    docker run -d --name "$api" --network "$network" --network-alias api --restart unless-stopped \
      --tmpfs /run/qa-otp:rw,noexec,nosuid,nodev,size=1m,mode=0700,uid=100,gid=100 \
      -p 127.0.0.1:18083:8080 --env-file "$old_env" "$(cat "${old_env}.image")" >/dev/null 2>&1 || true
  fi
  cleanup_temp
  exit "$status"
}
trap rollback_api EXIT

docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$api" > "$old_env"
old_image="$(docker inspect -f '{{.Config.Image}}' "$api")"
printf '%s\n' "$old_image" > "${old_env}.image"
allowlist_env="$(grep -E '^QA_OTP_ALLOWLIST=' "$old_env" | head -n 1 | cut -d= -f2- || true)"
if [[ -n "$allowlist_env" && "$allowlist_env" != "$allowlist" && "$allowlist_env" != "$previous_allowlist" ]]; then
  echo "Existing QA OTP allowlist differs from the reviewed synthetic identities; refusing to change it." >&2; exit 2
fi
if grep -q '+910000000000' <<< "$allowlist"; then echo "Root superadmin must not be allowlisted." >&2; exit 2; fi
docker exec "$db" psql -v ON_ERROR_STOP=1 -U qa3e -d grepmind_3e_qa -Atc \
  "SELECT count(DISTINCT phone_e164) FROM users WHERE phone_e164 = ANY (ARRAY['+919990000171','+919990000172','+919990000173','+919990000174','+919990000175','+919990000176','+919990000177','+919990000181','+919990000182','+919990000183'])" | grep -qx 10 || {
  echo "Expected synthetic QA identities are not all present; refusing to proceed." >&2; exit 2;
}

grep -Ev '^(OTP_PROVIDER|QA_OTP_.*|PAYMENT_SANDBOX_QA_USER_IDS)=' "$old_env" > "$api_env"
cat >> "$api_env" <<EOF
OTP_PROVIDER=qa_http
QA_OTP_DELIVERY_ENABLED=true
QA_OTP_DELIVERY_URL=http://$inbox:8090
QA_OTP_WRITER_TOKEN=$writer_secret
QA_OTP_RUN_ID=$run_id
QA_OTP_ALLOWLIST=$allowlist
PAYMENT_SANDBOX_QA_USER_IDS=3e000000-0000-4000-8000-000000000001,4e300000-0000-4000-8000-000000000001
EOF
cat > "$runner_env" <<EOF
QA_OTP_READER_URL=http://127.0.0.1:18085
QA_OTP_RUN_ID=$run_id
QA_OTP_RUNNER_ID=$runner_id
QA_OTP_RUNNER_SECRET=$runner_secret
QA_API_BASE=http://127.0.0.1:18083/api/v1
EOF
cat > "$inbox_env" <<EOF
APP_ENV=qa
QA_OTP_READER_ENABLED=true
QA_OTP_INBOX_DIR=/run/qa-otp
QA_OTP_RUN_ID=$run_id
QA_OTP_RUNNER_ID=$runner_id
QA_OTP_RUNNER_SECRET=$runner_secret
QA_OTP_WRITER_SECRET=$writer_secret
QA_OTP_ALLOWLIST=$allowlist
EOF
chmod 0600 "$api_env" "$inbox_env" "$old_env" "${old_env}.image" "$runner_env"

docker build --target qa-otp-inbox -t "$inbox_image" "$root/backend" >/dev/null
if [[ "$existing_inbox" == true ]]; then
  # Retain the previous QA reader under a temporary name for rollback. Stop it
  # only after the replacement image and private credentials are prepared.
  docker stop "$inbox" >/dev/null
  docker rename "$inbox" "$old_inbox"
  inbox_rotated=true
fi
docker run -d --name "$inbox" --network "$network" --restart unless-stopped \
  --tmpfs /run/qa-otp:rw,noexec,nosuid,nodev,size=1m,mode=0700,uid=0,gid=0 \
  -p 127.0.0.1:18085:8090 \
  --env-file "$inbox_env" "$inbox_image" >/dev/null
new_inbox_started=true
for _ in $(seq 1 30); do
  if curl --silent --fail http://127.0.0.1:18085/healthz >/dev/null; then break; fi
  sleep 1
done
curl --silent --fail http://127.0.0.1:18085/healthz >/dev/null || { echo "QA OTP inbox failed health check." >&2; exit 1; }

docker build --target api -t "$image" "$root/backend" >/dev/null
docker rm -f "$api" >/dev/null
api_removed=true
docker run -d --name "$api" --network "$network" --network-alias api --restart unless-stopped \
  -p 127.0.0.1:18083:8080 --env-file "$api_env" "$image" >/dev/null
for _ in $(seq 1 60); do
  if curl --silent --fail http://127.0.0.1:18083/healthz >/dev/null; then break; fi
  sleep 1
done
curl --silent --fail http://127.0.0.1:18083/healthz >/dev/null || { echo "Rebuilt QA API failed health check; rollback will restore prior API image." >&2; exit 1; }
api_removed=false
rm -f "$old_env" "${old_env}.image"
if [[ "$inbox_rotated" == true ]]; then
  docker rm -f "$old_inbox" >/dev/null 2>&1 || true
  inbox_rotated=false
fi
new_inbox_started=false
echo "Isolated QA API and root-owned OTP reader are ready; migration 036 and existing QA DB records were preserved."
echo "Private runner environment: $runner_env (mode 0600). Source it only in the trusted QA runner shell."
echo "OTP values and credentials were not printed."
