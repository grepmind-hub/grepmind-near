#!/usr/bin/env bash
set -euo pipefail

run_file="$(ls -t /home/grepmind/.cache/grepmind/qa-otp-runs/*.env | head -1)"
set -a
source "$run_file"
set +a

cd /mnt/d/grepmind-near
echo "Running Phase 4E.4 Gate G4-B Acceptance Suite with run file: $run_file..."
node scripts/qa/phase4e4-g4b-validation.mjs
