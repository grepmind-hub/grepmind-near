#!/usr/bin/env bash
set -euo pipefail
set +x
api=http://127.0.0.1:18083/api/v1
auth(){
  local phone="$1" req status otp reply token
  req=$(curl -fsS -w '\n%{http_code}' "$api/auth/otp/request" -H 'Content-Type: application/json' -d "{\"phone_e164\":\"$phone\"}")
  status=${req##*$'\n'}; req=${req%$'\n'*}
  [[ "$status" == 202 ]] || { printf 'otp_request_failed phone_suffix=%s status=%s\n' "${phone: -3}" "$status" >&2; return 1; }
  otp=$(bash scripts/qa/phase4c-read-otp.sh grepmind_4c_qa_api "$phone")
  reply=$(printf '{"phone_e164":"%s","otp_code":"%s"}' "$phone" "$otp" | curl -fsS "$api/auth/otp/verify" -H 'Content-Type: application/json' --data-binary @-)
  unset otp req
  token=$(jq -r '.data.access_token // empty' <<<"$reply"); unset reply
  [[ -n "$token" ]] || return 1
  printf '%s' "$token"
}
admin=$(auth +919990000175)
rider=$(auth +919990000173)
jobs=(59694156-626c-4dcc-a298-5932db060816 9fda3373-38fd-4b53-a963-91761fc58210)
for job in "${jobs[@]}"; do
  result=$(curl -sS -w '\n%{http_code}' -X POST "$api/admin/delivery-jobs/$job/retry" -H "Authorization: Bearer $admin" -H 'Content-Type: application/json' -d '{"reason":"Phase 4D disposable QA dispatch retry"}')
  status=${result##*$'\n'}; body=${result%$'\n'*}
  printf 'retry job_suffix=%s status=%s error=%s\n' "${job: -6}" "$status" "$(jq -r '.error.code // "none"' <<<"$body" 2>/dev/null || echo invalid_response)"
done
curl -fsS -X PUT "$api/rider/availability" -H "Authorization: Bearer $rider" -H 'Content-Type: application/json' -d '{"online":true}' >/dev/null
offers=$(curl -fsS "$api/rider/offers" -H "Authorization: Bearer $rider")
jq -r '.data[]? | [.id,.job_id,.reference_code] | @tsv' <<<"$offers"
unset admin rider offers
