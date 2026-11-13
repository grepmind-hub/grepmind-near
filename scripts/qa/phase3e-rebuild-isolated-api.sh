#!/usr/bin/env bash
set -euo pipefail

readonly api_container="grepmind_3e_qa_api"
readonly db_container="grepmind_3e_qa_db"
readonly network="grepmind_3e_qa_net"
readonly image="grepmind-near:phase3e-qa"
readonly root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

[[ "$(docker inspect -f '{{.Name}}' "$db_container" 2>/dev/null || true)" == "/$db_container" ]] || {
  echo "Refusing: the named Phase 3E disposable database is not present." >&2; exit 2;
}
[[ "$(docker inspect -f '{{json .Mounts}}' "$db_container")" == "[]" ]] || {
  echo "Refusing: Phase 3E database has persistent mounts." >&2; exit 2;
}
tmpfs="$(docker inspect -f '{{json .HostConfig.Tmpfs}}' "$db_container")"
[[ "$tmpfs" == *"/var/lib/postgresql/data"* ]] || {
  echo "Refusing: Phase 3E database is not backed by the expected tmpfs." >&2; exit 2;
}
docker network inspect "$network" >/dev/null
[[ "$(docker inspect -f '{{.Name}}' "$api_container" 2>/dev/null || true)" == "/$api_container" ]] || {
  echo "Refusing: the named Phase 3E API container is not present." >&2; exit 2;
}

umask 077
env_file="$(mktemp /tmp/phase3e-api-env.XXXXXX)"
trap 'rm -f "$env_file"' EXIT
docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$api_container" >"$env_file"
grep -qx 'DB_HOST=grepmind_3e_qa_db' "$env_file" || { echo "Refusing: API DB host is not isolated QA." >&2; exit 2; }
grep -qx 'DB_NAME=grepmind_3e_qa' "$env_file" || { echo "Refusing: API database is not isolated QA." >&2; exit 2; }

docker build --target api -t "$image" "$root/backend"
docker rm -f "$api_container" >/dev/null
docker run -d --name "$api_container" --network "$network" --env-file "$env_file" -p 18083:8080 "$image" >/dev/null

for _ in $(seq 1 60); do
  state="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$api_container")"
  [[ "$state" == "healthy" || "$state" == "running" ]] && break
  [[ "$state" == "unhealthy" || "$state" == "exited" ]] && { docker logs "$api_container"; exit 1; }
  sleep 1
done
docker ps --filter "name=^/${api_container}$" --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
