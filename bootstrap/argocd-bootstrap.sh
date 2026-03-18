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
BOOTSTRAP_DIR="${ROOT_DIR}/gitops/argocd/bootstrap"

need_cmd kubectl
need_cmd git

[[ -f "$MATRIX_FILE" ]] || { printf 'missing required file: %s\n' "$MATRIX_FILE" >&2; exit 1; }
[[ -d "$BOOTSTRAP_DIR" ]] || { printf 'missing required directory: %s\n' "$BOOTSTRAP_DIR" >&2; exit 1; }

ARGOCD_VERSION="$(awk '/^    argocd:/{flag=1;next} flag && /version:/{gsub(/"/,"",$2); print $2; exit}' "$MATRIX_FILE")"
[[ -n "$ARGOCD_VERSION" ]] || { printf 'failed to determine ArgoCD version from %s\n' "$MATRIX_FILE" >&2; exit 1; }

REPO_URL="${ARGOCD_REPO_URL:-$(git config --get remote.origin.url || true)}"
[[ -n "$REPO_URL" ]] || { printf 'missing ArgoCD repository URL; set ARGOCD_REPO_URL or git remote origin\n' >&2; exit 1; }

install_url="https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

printf '[phase] argocd-bootstrap\n'
printf '[argocd-version] %s\n' "$ARGOCD_VERSION"
printf '[repo-url] %s\n' "$REPO_URL"
printf '[install-manifest] %s\n' "$install_url"

tmp_root_app="$(mktemp)"
sed "s|https://github.com/agud97/k8s-vllm.git|${REPO_URL}|g" "${BOOTSTRAP_DIR}/root-application.yaml" > "${tmp_root_app}"

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply --server-side --force-conflicts -n argocd -f "$install_url"
kubectl apply -f "${BOOTSTRAP_DIR}/namespace.yaml"
kubectl apply -f "${BOOTSTRAP_DIR}/project.yaml"
kubectl apply -f "${tmp_root_app}"

rm -f "${tmp_root_app}"
