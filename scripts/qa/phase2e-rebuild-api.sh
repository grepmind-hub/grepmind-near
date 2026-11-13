#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../../backend"
container=grepmind-phase2e-api-qa
image=grepmind-phase2e-api-qa:latest
network=grepmind-phase2e-qa-net
env_file="$(mktemp /tmp/phase2e-api-env.XXXXXX)"
old_image="$(docker inspect --format '{{.Image}}' "$container")"
trap 'rm -f "$env_file"' EXIT
chmod 600 "$env_file"
docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$container" > "$env_file"

docker build --target api -f Dockerfile -t "$image" .
docker stop "$container" >/dev/null
docker rm "$container" >/dev/null

if ! docker run -d --name "$container" --network "$network" -p 8083:8080 --env-file "$env_file" "$image" >/dev/null; then
  docker run -d --name "$container" --network "$network" -p 8083:8080 --env-file "$env_file" "$old_image" >/dev/null || true
  echo 'The new QA API container failed to start; the previous image was restored.' >&2
  exit 1
fi

for attempt in $(seq 1 20); do
  if curl -fsS http://127.0.0.1:8083/healthz; then
    exit 0
  fi
  sleep 1
done
echo 'The rebuilt QA API did not become healthy.' >&2
exit 1
