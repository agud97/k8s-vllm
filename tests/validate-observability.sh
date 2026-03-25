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
  grep -q 'chart: victoria-metrics-k8s-stack' gitops/root/app-platform-victoriametrics.yaml || { printf 'victoriametrics chart missing\n' >&2; exit 1; }
  grep -q 'targetRevision: 0.72.5' gitops/root/app-platform-victoriametrics.yaml || { printf 'victoriametrics chart version mismatch\n' >&2; exit 1; }
  grep -q 'storage: 100Gi' gitops/root/app-platform-victoriametrics.yaml || { printf 'victoriametrics pvc size mismatch\n' >&2; exit 1; }
  grep -q 'retentionPeriod: 7d' gitops/root/app-platform-victoriametrics.yaml || { printf 'victoriametrics retention mismatch\n' >&2; exit 1; }
  grep -q 'victoria-metrics-operator:' gitops/root/app-platform-victoriametrics.yaml || { printf 'victoriametrics operator placement missing\n' >&2; exit 1; }
  grep -q 'kube-state-metrics:' gitops/root/app-platform-victoriametrics.yaml || { printf 'kube-state-metrics placement missing\n' >&2; exit 1; }
  grep -q 'releaseName: vmstack' gitops/root/app-platform-victoriametrics.yaml || { printf 'victoriametrics release name not shortened\n' >&2; exit 1; }
  grep -q 'kind: VMServiceScrape' gitops/platform/victoriametrics/vmservicescrape-argocd.yaml || { printf 'argocd scrape missing\n' >&2; exit 1; }
  grep -q 'kind: VMServiceScrape' gitops/platform/victoriametrics/vmservicescrape-kserve-controller.yaml || { printf 'kserve scrape missing\n' >&2; exit 1; }
  grep -q 'chart: dcgm-exporter' gitops/root/app-infra-dcgm-exporter.yaml || { printf 'dcgm exporter chart missing\n' >&2; exit 1; }
  printf 'observability static validation passed\n'
}

check_runtime() {
  need_cmd kubectl
  kubectl -n argocd get application platform-victoriametrics >/tmp/vm_app.txt
  kubectl -n argocd get application infra-dcgm-exporter >/tmp/dcgm_app.txt
  kubectl -n monitoring get pods >/tmp/vm_pods.txt
  kubectl -n monitoring get vmsingle,vmagent,vmservicescrape >/tmp/vm_objects.txt
  kubectl -n monitoring get ds dcgm-exporter >/tmp/dcgm_ds.txt
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
