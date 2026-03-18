#!/usr/bin/env bash
set -euo pipefail

need_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    printf 'missing required command: %s\n' "$cmd" >&2
    exit 1
  fi
}

check_argocd() {
  need_cmd kubectl
  kubectl -n argocd get deploy argocd-server >/tmp/argocd_server.txt
  awk 'NR==2 { if ($2 != $4) { print "argocd-server not ready" > "/dev/stderr"; exit 1 } }' /tmp/argocd_server.txt
  kubectl -n argocd get applications.argoproj.io >/tmp/argocd_apps.txt
  printf 'argocd validation passed\n'
}

check_sealed_secrets() {
  need_cmd kubectl
  kubectl -n kube-system get deploy -l app.kubernetes.io/name=sealed-secrets >/tmp/sealed_secrets.txt
  awk 'NR==2 { if ($2 != $4) { print "sealed-secrets controller not ready" > "/dev/stderr"; exit 1 } }' /tmp/sealed_secrets.txt
  printf 'sealed-secrets validation passed\n'
}

check_openebs() {
  need_cmd kubectl
  kubectl get storageclass openebs-hostpath >/tmp/openebs_sc.txt
  grep -q 'openebs-hostpath' /tmp/openebs_sc.txt || { printf 'openebs-hostpath storageclass missing\n' >&2; exit 1; }
  printf 'openebs validation passed\n'
}

check_istio() {
  need_cmd kubectl
  kubectl -n istio-system get deploy >/tmp/istio_deploys.txt
  grep -q 'istiod' /tmp/istio_deploys.txt || { printf 'istiod deployment missing\n' >&2; exit 1; }
  kubectl -n istio-ingress get svc istio-ingressgateway-nodeport >/tmp/istio_ingress_svc.txt
  grep -q '32080' /tmp/istio_ingress_svc.txt || { printf 'expected NodePort 32080 missing\n' >&2; exit 1; }
  printf 'istio validation passed\n'
}

mode="${1:-all}"
case "$mode" in
  argocd)
    check_argocd
    ;;
  sealed-secrets)
    check_sealed_secrets
    ;;
  openebs)
    check_openebs
    ;;
  istio)
    check_istio
    ;;
  all)
    check_argocd
    check_sealed_secrets
    check_openebs
    check_istio
    ;;
  *)
    printf 'unknown validation mode: %s\n' "$mode" >&2
    exit 1
    ;;
esac
