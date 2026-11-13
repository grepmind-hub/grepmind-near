#!/usr/bin/env bash
set -euo pipefail

readonly containers=(grepmind_4c_qa_admin grepmind_4c_qa_merchant grepmind_4c_qa_api grepmind_4c_qa_otp_inbox grepmind_4c_qa_minio)
readonly db=grepmind_3e_qa_db
readonly network=grepmind_3e_qa_net
readonly images=(grepmind-near:phase4c-qa-admin grepmind-near:phase4c-qa-merchant grepmind-near:phase4c-qa)

for name in "${containers[@]}"; do
  if docker ps -a --format '{{.Names}}' | grep -Fxq "$name"; then
    docker rm -f "$name" >/dev/null
    echo "Removed disposable container $name."
  fi
done

if docker ps -a --format '{{.Names}}' | grep -Fxq "$db"; then
  [[ "$(docker inspect -f '{{json .Mounts}}' "$db")" == "[]" ]] || {
    echo "Refusing to remove database with persistent mounts." >&2; exit 2;
  }
  [[ "$(docker inspect -f '{{json .HostConfig.Tmpfs}}' "$db")" == *"/var/lib/postgresql/data"* ]] || {
    echo "Refusing to remove database not backed by tmpfs." >&2; exit 2;
  }
  docker rm -f "$db" >/dev/null
  echo "Removed disposable tmpfs database $db."
fi
if docker network ls --format '{{.Name}}' | grep -Fxq "$network"; then
  docker network rm "$network" >/dev/null
  echo "Removed isolated QA network $network."
fi
for image in "${images[@]}"; do
  if docker image inspect "$image" >/dev/null 2>&1; then docker image rm "$image" >/dev/null; fi
done
for serial in emulator-5554 emulator-5556; do
  if adb -s "$serial" get-state >/dev/null 2>&1; then
    adb -s "$serial" shell pm clear local.grepmind.grepmind_mobile >/dev/null || true
  fi
done
echo "Phase 4C isolated QA data/inbox/runtime cleanup complete."
