#!/usr/bin/env bash
set -euo pipefail
run_file="/home/grepmind/.cache/grepmind/qa-otp-runs/auth-otp-d605b7e73d3d388bb25d87eb282b9d5b.env"
if [[ -f "$run_file" ]]; then
  set -a
  source "$run_file"
  set +a
fi
cd /mnt/d/grepmind-near
node scripts/qa/create-grocery-order.mjs "${1:-cash_on_delivery}"
