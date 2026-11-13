#!/usr/bin/env bash
set -euo pipefail

# Read-only diagnosis for the isolated AUTH-OTP-02 QA reader. This never
# requests, reads, or prints an OTP or any runner credential.
api_container="grepmind_4c_qa_api"
inbox_container="grepmind_4c_qa_otp_inbox"
runner_env="/home/grepmind/.cache/grepmind/qa-otp-runs/auth-otp-8491aa850ef5d0303e4dd51186a06168.env"

container_state() {
  docker inspect --format '{{.State.Status}}' "$1" 2>/dev/null || printf 'missing'
}

container_env() {
  docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$1" 2>/dev/null || true
}

env_value() {
  local data="$1" key="$2" line
  while IFS= read -r line; do
    case "$line" in
      "$key="*) printf '%s' "${line#*=}"; return 0 ;;
    esac
  done <<< "$data"
  return 0
}

api_state="$(container_state "$api_container")"
inbox_state="$(container_state "$inbox_container")"
api_env="$(container_env "$api_container")"
inbox_env="$(container_env "$inbox_container")"
reader_health="$(curl --max-time 3 --silent --output /dev/null --write-out '%{http_code}' http://127.0.0.1:18085/healthz || true)"

printf 'api_container_state=%s\n' "$api_state"
printf 'inbox_container_state=%s\n' "$inbox_state"
printf 'reader_health_http=%s\n' "${reader_health:-unreachable}"

if [[ ! -r "$runner_env" ]]; then
  echo 'runner_config_present=no'
  echo 'scope_checks=not_run'
  exit 0
fi

echo 'runner_config_present=yes'
set -a
# shellcheck disable=SC1090
. "$runner_env"
set +a

api_run="$(env_value "$api_env" QA_OTP_RUN_ID)"
inbox_run="$(env_value "$inbox_env" QA_OTP_RUN_ID)"
reader_id="$(env_value "$inbox_env" QA_OTP_RUNNER_ID)"
reader_secret="$(env_value "$inbox_env" QA_OTP_RUNNER_SECRET)"
api_allowlist="$(env_value "$api_env" QA_OTP_ALLOWLIST)"
api_environment="$(env_value "$api_env" APP_ENV)"
api_provider="$(env_value "$api_env" OTP_PROVIDER)"
api_delivery_enabled="$(env_value "$api_env" QA_OTP_DELIVERY_ENABLED)"
inbox_environment="$(env_value "$inbox_env" APP_ENV)"
inbox_reader_enabled="$(env_value "$inbox_env" QA_OTP_READER_ENABLED)"

if [[ -n "$api_run" && "$api_run" == "$inbox_run" && "$api_run" == "${QA_OTP_RUN_ID:-}" ]]; then
  echo 'run_id_match=yes'
else
  echo 'run_id_match=no'
fi
if [[ -n "$reader_id" && "$reader_id" == "${QA_OTP_RUNNER_ID:-}" ]]; then
  echo 'runner_id_match=yes'
else
  echo 'runner_id_match=no'
fi
if [[ -n "$reader_secret" && "$reader_secret" == "${QA_OTP_RUNNER_SECRET:-}" ]]; then
  echo 'runner_secret_match=yes'
else
  echo 'runner_secret_match=no'
fi
case ",$api_allowlist," in
  *,+919990000174,*) echo 'admin_allowlisted=yes' ;;
  *) echo 'admin_allowlisted=no' ;;
esac
printf 'api_environment=%s\n' "${api_environment:-missing}"
printf 'otp_provider=%s\n' "${api_provider:-missing}"
printf 'api_delivery_enabled=%s\n' "${api_delivery_enabled:-missing}"
printf 'inbox_environment=%s\n' "${inbox_environment:-missing}"
printf 'inbox_reader_enabled=%s\n' "${inbox_reader_enabled:-missing}"
