#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

check_shell_syntax() {
  local failed=0
  while IFS= read -r -d '' file; do
    if ! bash -n "$file"; then
      printf 'shell syntax check failed: %s\n' "$file" >&2
      failed=1
    fi
  done < <(find "${ROOT_DIR}/bootstrap" "${ROOT_DIR}/tests" -type f \( -name '*.sh' \) -print0)
  [[ "$failed" -eq 0 ]] || exit 1
  printf 'shell syntax validation passed\n'
}

check_pinned_versions() {
  grep -q 'version:' "${ROOT_DIR}/docs/dependency-matrix.yaml" || {
    printf 'dependency matrix does not contain pinned versions\n' >&2
    exit 1
  }
  if grep -R -nE 'image: .*:latest($|[[:space:]])' "${ROOT_DIR}/gitops" "${ROOT_DIR}/platform" 2>/dev/null; then
    printf 'floating latest image tag detected\n' >&2
    exit 1
  fi
  printf 'pinned version validation passed\n'
}

check_required_layout() {
  local required_paths=(
    "${ROOT_DIR}/bootstrap"
    "${ROOT_DIR}/inventory"
    "${ROOT_DIR}/gitops"
    "${ROOT_DIR}/docs"
    "${ROOT_DIR}/tests"
    "${ROOT_DIR}/docs/dependency-matrix.yaml"
    "${ROOT_DIR}/Makefile"
  )
  for path in "${required_paths[@]}"; do
    [[ -e "$path" ]] || {
      printf 'required path missing: %s\n' "$path" >&2
      exit 1
    }
  done
  printf 'repository layout validation passed\n'
}

check_secret_hygiene() {
  if grep -R -n --exclude='validate-static.sh' 'REPLACE_LITELLM_MASTER_KEY' "${ROOT_DIR}" 2>/dev/null; then
    printf 'plaintext LiteLLM secret placeholder still present in repository\n' >&2
    exit 1
  fi
  if grep -R -nE 'ansible_password: [^R]' \
    --exclude-dir='generated' \
    "${ROOT_DIR}/inventory" "${ROOT_DIR}/gitops" "${ROOT_DIR}/docs" 2>/dev/null; then
    printf 'unexpected concrete ansible password found in tracked files\n' >&2
    exit 1
  fi
  printf 'secret hygiene validation passed\n'
}

check_manifest_placeholders() {
  local allowed_patterns='REPLACE_S3_|<infra-1-public-ip>'
  while IFS= read -r -d '' file; do
    if [[ "$file" == *.example ]]; then
      continue
    fi
    if grep -n 'REPLACE_' "$file" >/tmp/static_placeholders.txt 2>/dev/null; then
      if grep -vE "$allowed_patterns" /tmp/static_placeholders.txt >/dev/null 2>&1; then
        printf 'unexpected unresolved placeholder detected in %s\n' "$file" >&2
        cat /tmp/static_placeholders.txt >&2
        exit 1
      fi
    fi
  done < <(find "${ROOT_DIR}/gitops" "${ROOT_DIR}/docs" "${ROOT_DIR}/inventory" -type f -print0)
  printf 'placeholder validation passed\n'
}

check_root_apps() {
  local expected_apps=(
    app-argocd.yaml
    app-infra-sealed-secrets.yaml
    app-infra-openebs.yaml
    app-infra-istio.yaml
    app-infra-nvidia-device-plugin.yaml
    app-platform-knative-serving.yaml
    app-platform-kserve.yaml
    app-platform-victoriametrics.yaml
    app-app-litellm.yaml
    app-app-llm-serving.yaml
  )
  for app in "${expected_apps[@]}"; do
    [[ -f "${ROOT_DIR}/gitops/root/${app}" ]] || {
      printf 'missing root application: %s\n' "$app" >&2
      exit 1
    }
  done
  printf 'root application validation passed\n'
}

check_shell_syntax
check_pinned_versions
check_required_layout
check_secret_hygiene
check_manifest_placeholders
check_root_apps

printf 'static validation suite passed\n'
