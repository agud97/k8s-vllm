#!/usr/bin/env bash
set -euo pipefail

need_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    printf 'missing required command: %s\n' "$cmd" >&2
    exit 1
  fi
}

check_static() {
  grep -q 'storage: 100Gi' gitops/platform/victoriametrics/victoria-metrics-pvc.yaml || { printf 'victoriametrics pvc size mismatch\n' >&2; exit 1; }
  grep -q 'retentionPeriod: "7d"' gitops/platform/victoriametrics/victoria-metrics-config.yaml || { printf 'victoriametrics retention mismatch\n' >&2; exit 1; }
  grep -q 'litellm' gitops/platform/victoriametrics/victoria-metrics-config.yaml || { printf 'litellm scrape target missing\n' >&2; exit 1; }
  grep -q 'kserve' gitops/platform/victoriametrics/victoria-metrics-config.yaml || { printf 'kserve scrape target missing\n' >&2; exit 1; }
  printf 'observability static validation passed\n'
}

check_runtime() {
  need_cmd kubectl
  kubectl -n monitoring get pvc victoriametrics-data >/tmp/vm_pvc.txt
  kubectl -n monitoring get configmap victoriametrics-settings >/tmp/vm_config.txt
  printf 'observability runtime validation passed\n'
}

mode="${1:-static}"
case "$mode" in
  static)
    check_static
    ;;
  runtime)
    check_runtime
    ;;
  all)
    check_static
    check_runtime
    ;;
  *)
    printf 'unknown validation mode: %s\n' "$mode" >&2
    exit 1
    ;;
esac
