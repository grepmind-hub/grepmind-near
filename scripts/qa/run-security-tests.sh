#!/usr/bin/env bash
set -euo pipefail
run_file="$(ls -t /home/grepmind/.cache/grepmind/qa-otp-runs/*.env | head -1)"
set -a
source "$run_file"
set +a
cd /mnt/d/grepmind-near
node scripts/qa/negative-security-tests.mjs
