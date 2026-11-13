#!/usr/bin/env bash
set -euo pipefail

# Starts only the disposable Phase 3E API and MinIO on the isolated QA network.
# The database must first be created with phase3e-start-isolated.sh; it uses
# tmpfs and is validated again here before any service is attached.
readonly root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly db="grepmind_3e_qa_db"
readonly api="grepmind_3e_qa_api"
readonly minio="grepmind_3e_qa_minio"
readonly network="grepmind_3e_qa_net"
readonly image="grepmind-near:phase3e-qa"

for name in "$api" "$minio"; do
  if docker ps -a --format '{{.Names}}' | grep -Fxq "$name"; then
    echo "Refusing to reuse existing service container: $name" >&2
    exit 2
  fi
done
docker network inspect "$network" >/dev/null
[[ "$(docker inspect -f '{{.Name}}' "$db" 2>/dev/null || true)" == "/$db" ]] || {
  echo "Refusing: the disposable Phase 3E database is not present." >&2; exit 2;
}
[[ "$(docker inspect -f '{{json .Mounts}}' "$db")" == "[]" ]] || {
  echo "Refusing: Phase 3E database has persistent mounts." >&2; exit 2;
}
[[ "$(docker inspect -f '{{json .HostConfig.Tmpfs}}' "$db")" == *"/var/lib/postgresql/data"* ]] || {
  echo "Refusing: Phase 3E database is not backed by tmpfs." >&2; exit 2;
}
docker exec "$db" psql -U qa3e -d grepmind_3e_qa -Atc \
  "SELECT 1 WHERE to_regclass('public.delivery_execution_events') IS NOT NULL" | grep -qx 1

readonly minio_user="grepmindqa"
minio_password="$(openssl rand -hex 24)"
jwt_secret="$(openssl rand -hex 48)"

docker run -d --name "$minio" --network "$network" \
  --tmpfs /data:rw,size=256m \
  -p 127.0.0.1:19000:9000 -p 127.0.0.1:19001:9001 \
  -e MINIO_ROOT_USER="$minio_user" -e MINIO_ROOT_PASSWORD="$minio_password" \
  elestio/minio:latest server /data --console-address :9001 >/dev/null

docker build --target api -t "$image" "$root/backend"
docker run -d --name "$api" --network "$network" -p 18083:8080 \
  -e APP_ENV=local -e APP_PORT=8080 -e OTP_PROVIDER=stub \
  -e DB_HOST="$db" -e DB_PORT=5432 -e DB_USER=qa3e \
  -e DB_PASSWORD=qa3e_only_local -e DB_NAME=grepmind_3e_qa -e DB_SSLMODE=disable \
  -e JWT_SECRET="$jwt_secret" -e RIDER_DISPATCH_ENABLED=true \
  -e S3_ENDPOINT="http://$minio:9000" -e S3_ACCESS_KEY="$minio_user" \
  -e S3_SECRET_KEY="$minio_password" -e S3_BUCKET=grepmind-near \
  -e S3_PRIVATE_BUCKET=grepmind-near-private -e S3_USE_SSL=false \
  "$image" >/dev/null

for _ in $(seq 1 90); do
  if curl --silent --fail http://127.0.0.1:18083/healthz >/dev/null; then
    echo "Phase 3E isolated API is healthy on port 18083."
    exit 0
  fi
  state="$(docker inspect -f '{{.State.Status}}' "$api")"
  if [[ "$state" == "exited" || "$state" == "dead" ]]; then
    echo "Phase 3E API exited during startup (container state: $state)." >&2
    exit 1
  fi
  sleep 1
done
echo "Timed out waiting for the isolated Phase 3E API." >&2
exit 1
