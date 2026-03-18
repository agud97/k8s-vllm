#!/usr/bin/env bash
set -euo pipefail

need_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    printf 'missing required command: %s\n' "$cmd" >&2
    exit 1
  fi
}

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MATRIX_FILE="${ROOT_DIR}/docs/dependency-matrix.yaml"

need_cmd kubectl

[[ -f "$MATRIX_FILE" ]] || { printf 'missing required file: %s\n' "$MATRIX_FILE" >&2; exit 1; }

SEALED_SECRETS_VERSION="$(awk '/^    sealed_secrets:/{flag=1;next} flag && /version:/{gsub(/"/,"",$2); print $2; exit}' "$MATRIX_FILE")"
[[ -n "$SEALED_SECRETS_VERSION" ]] || { printf 'failed to determine Sealed Secrets version from %s\n' "$MATRIX_FILE" >&2; exit 1; }

install_url="https://github.com/bitnami-labs/sealed-secrets/releases/download/${SEALED_SECRETS_VERSION}/controller.yaml"

printf '[phase] sealed-secrets-bootstrap\n'
printf '[sealed-secrets-version] %s\n' "$SEALED_SECRETS_VERSION"
printf '[install-manifest] %s\n' "$install_url"

kubectl apply -f "$install_url"
kubectl apply -k "${ROOT_DIR}/gitops/infra/sealed-secrets"
