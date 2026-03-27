#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

require_file() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    printf 'missing required file: %s\n' "$path" >&2
    exit 1
  fi
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    printf 'missing required command: %s\n' "$cmd" >&2
    exit 1
  fi
}

require_cmd kubectl
require_file "local/s3.env"
require_file "local/llm.env"

# shellcheck disable=SC1091
source "local/s3.env"
# shellcheck disable=SC1091
source "local/llm.env"

: "${S3_ACCESS_KEY_ID:?missing S3_ACCESS_KEY_ID}"
: "${S3_SECRET_ACCESS_KEY:?missing S3_SECRET_ACCESS_KEY}"
: "${LITELLM_MASTER_KEY:?missing LITELLM_MASTER_KEY}"
: "${LITELLM_POSTGRES_PASSWORD:?missing LITELLM_POSTGRES_PASSWORD}"
: "${OPENWEBUI_ADMIN_NAME:?missing OPENWEBUI_ADMIN_NAME}"
: "${OPENWEBUI_ADMIN_EMAIL:?missing OPENWEBUI_ADMIN_EMAIL}"
: "${OPENWEBUI_ADMIN_PASSWORD:?missing OPENWEBUI_ADMIN_PASSWORD}"

LITELLM_UI_ADMIN_NAME="${LITELLM_UI_ADMIN_NAME:-${OPENWEBUI_ADMIN_NAME}}"
LITELLM_UI_ADMIN_EMAIL="${LITELLM_UI_ADMIN_EMAIL:-${OPENWEBUI_ADMIN_EMAIL}}"
LITELLM_UI_ADMIN_PASSWORD="${LITELLM_UI_ADMIN_PASSWORD:-${OPENWEBUI_ADMIN_PASSWORD}}"
LITELLM_UI_ADMIN_ROLE="${LITELLM_UI_ADMIN_ROLE:-proxy_admin}"
LITELLM_POSTGRES_USER="litellm"
LITELLM_POSTGRES_DB="litellm"
LITELLM_DATABASE_URL="postgresql://${LITELLM_POSTGRES_USER}:${LITELLM_POSTGRES_PASSWORD}@litellm-postgres.llm.svc:5432/${LITELLM_POSTGRES_DB}"

kubectl --kubeconfig local/runtime/admin.conf create namespace llm --dry-run=client -o yaml | kubectl --kubeconfig local/runtime/admin.conf apply -f -

kubectl --kubeconfig local/runtime/admin.conf -n llm create secret generic llm-s3-credentials \
  --from-literal=AWS_ACCESS_KEY_ID="${S3_ACCESS_KEY_ID}" \
  --from-literal=AWS_SECRET_ACCESS_KEY="${S3_SECRET_ACCESS_KEY}" \
  --dry-run=client -o yaml | kubectl --kubeconfig local/runtime/admin.conf apply -f -

kubectl --kubeconfig local/runtime/admin.conf -n llm annotate secret llm-s3-credentials \
  serving.kserve.io/s3-endpoint="${S3_ENDPOINT#https://}" \
  serving.kserve.io/s3-usehttps="1" \
  serving.kserve.io/s3-region="${S3_REGION:-us-east-1}" \
  serving.kserve.io/s3-verifyssl="0" \
  serving.kserve.io/s3-useanoncredential="false" \
  --overwrite >/dev/null

kubectl --kubeconfig local/runtime/admin.conf -n llm create secret generic litellm-auth \
  --from-literal=master-key="${LITELLM_MASTER_KEY}" \
  --dry-run=client -o yaml | kubectl --kubeconfig local/runtime/admin.conf apply -f -

kubectl --kubeconfig local/runtime/admin.conf -n llm create secret generic litellm-postgres-auth \
  --from-literal=postgres-user="${LITELLM_POSTGRES_USER}" \
  --from-literal=postgres-password="${LITELLM_POSTGRES_PASSWORD}" \
  --from-literal=postgres-db="${LITELLM_POSTGRES_DB}" \
  --from-literal=database-url="${LITELLM_DATABASE_URL}" \
  --dry-run=client -o yaml | kubectl --kubeconfig local/runtime/admin.conf apply -f -

kubectl --kubeconfig local/runtime/admin.conf -n llm create secret generic openwebui-admin \
  --from-literal=admin-name="${OPENWEBUI_ADMIN_NAME}" \
  --from-literal=admin-email="${OPENWEBUI_ADMIN_EMAIL}" \
  --from-literal=admin-password="${OPENWEBUI_ADMIN_PASSWORD}" \
  --dry-run=client -o yaml | kubectl --kubeconfig local/runtime/admin.conf apply -f -

printf 'llm application secrets applied\n'
