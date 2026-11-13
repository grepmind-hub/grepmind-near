#!/usr/bin/env bash
set -euo pipefail

# Removes only the explicitly named Phase 3E disposable containers/network and
# the QA-only image. No named or persistent volume is used.
readonly containers=("grepmind_3e_qa_api" "grepmind_3e_qa_minio" "grepmind_3e_qa_db")
readonly network="grepmind_3e_qa_net"
readonly image="grepmind-near:phase3e-qa"

for name in "${containers[@]}"; do
  if docker ps -a --format '{{.Names}}' | grep -Fxq "$name"; then
    docker rm -f "$name"
  fi
done
if docker network ls --format '{{.Name}}' | grep -Fxq "$network"; then
  docker network rm "$network"
fi
if docker image inspect "$image" >/dev/null 2>&1; then
  docker image rm "$image"
fi

echo "Phase 3E disposable DB/API/MinIO/network/image cleanup finished."
