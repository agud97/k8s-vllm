#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    printf 'missing required command: %s\n' "$cmd" >&2
    exit 1
  fi
}

require_file() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    printf 'missing required file: %s\n' "$path" >&2
    exit 1
  fi
}

cleanup() {
  if [[ -n "${PORT_FORWARD_PID:-}" ]]; then
    kill "${PORT_FORWARD_PID}" >/dev/null 2>&1 || true
    wait "${PORT_FORWARD_PID}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

require_cmd curl
require_cmd jq
require_cmd kubectl
require_file "local/llm.env"
require_file "local/runtime/admin.conf"

# shellcheck disable=SC1091
source "local/llm.env"

: "${LITELLM_MASTER_KEY:?missing LITELLM_MASTER_KEY}"

LITELLM_UI_ADMIN_NAME="${LITELLM_UI_ADMIN_NAME:-${OPENWEBUI_ADMIN_NAME:-Admin}}"
LITELLM_UI_ADMIN_EMAIL="${LITELLM_UI_ADMIN_EMAIL:-${OPENWEBUI_ADMIN_EMAIL:-}}"
LITELLM_UI_ADMIN_PASSWORD="${LITELLM_UI_ADMIN_PASSWORD:-${OPENWEBUI_ADMIN_PASSWORD:-}}"
LITELLM_UI_ADMIN_ROLE="${LITELLM_UI_ADMIN_ROLE:-proxy_admin}"

: "${LITELLM_UI_ADMIN_EMAIL:?missing LITELLM_UI_ADMIN_EMAIL}"
: "${LITELLM_UI_ADMIN_PASSWORD:?missing LITELLM_UI_ADMIN_PASSWORD}"

kubectl --kubeconfig local/runtime/admin.conf -n llm rollout status statefulset/litellm-postgres --timeout=10m >/dev/null
kubectl --kubeconfig local/runtime/admin.conf -n llm rollout status deployment/litellm --timeout=10m >/dev/null

kubectl --kubeconfig local/runtime/admin.conf -n llm port-forward svc/litellm 4000:4000 >/tmp/litellm-ui-user-port-forward.log 2>&1 &
PORT_FORWARD_PID=$!
sleep 5

create_payload="$(jq -n \
  --arg user_id "${LITELLM_UI_ADMIN_EMAIL}" \
  --arg user_email "${LITELLM_UI_ADMIN_EMAIL}" \
  --arg user_alias "${LITELLM_UI_ADMIN_NAME}" \
  --arg user_role "${LITELLM_UI_ADMIN_ROLE}" \
  '{user_id: $user_id, user_email: $user_email, user_alias: $user_alias, user_role: $user_role, auto_create_key: false}')"

if ! curl -fsS \
  -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
  -G \
  --data-urlencode "user_id=${LITELLM_UI_ADMIN_EMAIL}" \
  http://127.0.0.1:4000/user/info >/dev/null 2>&1; then
  curl -fsS \
    -X POST \
    -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
    -H "Content-Type: application/json" \
    -d "${create_payload}" \
    http://127.0.0.1:4000/user/new >/dev/null
fi

update_payload="$(jq -n \
  --arg user_email "${LITELLM_UI_ADMIN_EMAIL}" \
  --arg password "${LITELLM_UI_ADMIN_PASSWORD}" \
  --arg user_alias "${LITELLM_UI_ADMIN_NAME}" \
  --arg user_role "${LITELLM_UI_ADMIN_ROLE}" \
  '{user_email: $user_email, password: $password, user_alias: $user_alias, user_role: $user_role}')"

curl -fsS \
  -X POST \
  -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
  -H "Content-Type: application/json" \
  -d "${update_payload}" \
  http://127.0.0.1:4000/user/update >/dev/null

printf 'litellm ui user ensured: %s (%s)\n' "${LITELLM_UI_ADMIN_EMAIL}" "${LITELLM_UI_ADMIN_ROLE}"
