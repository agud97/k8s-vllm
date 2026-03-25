#!/usr/bin/env bash
set -euo pipefail

need_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    printf 'missing required command: %s\n' "$cmd" >&2
    exit 1
  fi
}

check_hosts() {
  [[ -f local/hosts.yml ]] || { printf 'missing required file: local/hosts.yml\n' >&2; exit 1; }
  need_cmd python3
  python3 - <<'PY'
import sys, yaml
with open("local/hosts.yml", "r", encoding="utf-8") as f:
    data = yaml.safe_load(f)
hosts = data.get("all", {}).get("hosts", {})
required = ["cp-1", "cp-2", "cp-3", "infra-1"]
missing = [name for name in required if name not in hosts]
if missing:
    print("missing required hosts: " + ", ".join(missing), file=sys.stderr)
    sys.exit(1)
gpu_hosts = list(data.get("all", {}).get("children", {}).get("gpu", {}).get("hosts", {}).keys())
if not gpu_hosts:
    print("missing required gpu hosts group entries", file=sys.stderr)
    sys.exit(1)
required.extend(gpu_hosts)
for name in required:
    if not hosts[name].get("ansible_host"):
      print(f"host {name} is missing ansible_host", file=sys.stderr)
      sys.exit(1)
print("host inventory validation passed")
PY
}

check_cluster() {
  need_cmd kubectl
  need_cmd python3
  local expected_nodes
  expected_nodes="$(python3 - <<'PY'
import yaml
with open("local/hosts.yml", "r", encoding="utf-8") as f:
    data = yaml.safe_load(f)
print(len(data.get("all", {}).get("hosts", {})))
PY
)"
  kubectl get nodes --no-headers >/tmp/k8s_nodes.txt
  local node_count
  node_count="$(wc -l </tmp/k8s_nodes.txt | tr -d ' ')"
  [[ "$node_count" = "$expected_nodes" ]] || { printf 'expected %s nodes, got %s\n' "$expected_nodes" "$node_count" >&2; exit 1; }
  awk '$2 != "Ready" { print "node not ready: "$1" status="$2 > "/dev/stderr"; exit 1 }' /tmp/k8s_nodes.txt
  printf 'cluster node readiness validation passed\n'
}

check_cilium() {
  need_cmd kubectl
  kubectl -n kube-system get ds cilium >/tmp/cilium_ds.txt
  awk 'NR==2 { if ($2 != $4) { print "cilium not fully ready" > "/dev/stderr"; exit 1 } }' /tmp/cilium_ds.txt
  printf 'cilium validation passed\n'
}

check_gpu() {
  need_cmd kubectl
  need_cmd python3
  local expected_gpu_nodes
  expected_gpu_nodes="$(python3 - <<'PY'
import yaml
with open("local/hosts.yml", "r", encoding="utf-8") as f:
    data = yaml.safe_load(f)
print(len(data.get("all", {}).get("children", {}).get("gpu", {}).get("hosts", {})))
PY
)"
  local gpu_nodes
  gpu_nodes="$(kubectl get nodes -l node-role.kubernetes.io/gpu= -o name | wc -l | tr -d ' ')"
  [[ "$gpu_nodes" = "$expected_gpu_nodes" ]] || { printf 'expected %s gpu nodes, got %s\n' "$expected_gpu_nodes" "$gpu_nodes" >&2; exit 1; }
  kubectl get nodes -o json >/tmp/k8s_nodes.json
  EXPECTED_GPU_NODES="$expected_gpu_nodes" python3 - <<'PY'
import json, sys
import os
with open("/tmp/k8s_nodes.json", "r", encoding="utf-8") as f:
    data = json.load(f)
gpu_nodes = []
for item in data["items"]:
    labels = item.get("metadata", {}).get("labels", {})
    if "node-role.kubernetes.io/gpu" in labels:
        cap = item.get("status", {}).get("capacity", {})
        if "nvidia.com/gpu" not in cap:
            print(f"gpu capacity missing on {item['metadata']['name']}", file=sys.stderr)
            sys.exit(1)
        gpu_nodes.append(item["metadata"]["name"])
expected = int(os.environ["EXPECTED_GPU_NODES"])
if len(gpu_nodes) != expected:
    print(f"expected {expected} gpu nodes with nvidia.com/gpu, got {len(gpu_nodes)}", file=sys.stderr)
    sys.exit(1)
print("gpu validation passed")
PY
}

mode="${1:-all}"
case "$mode" in
  hosts)
    check_hosts
    ;;
  cluster)
    check_cluster
    ;;
  cilium)
    check_cilium
    ;;
  gpu)
    check_gpu
    ;;
  all)
    check_hosts
    check_cluster
    check_cilium
    check_gpu
    ;;
  *)
    printf 'unknown validation mode: %s\n' "$mode" >&2
    exit 1
    ;;
esac
