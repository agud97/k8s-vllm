# Runbook

## Goal

Bring up the platform from new servers to the first successful smoke test.

## Preconditions

You already have:

- Ubuntu 24.04 servers for:
  - `3` control-plane nodes
  - `1` infra node
  - `1` or more GPU worker nodes
- public IPs for all nodes
- SSH access to all nodes
- `S3` bucket and credentials
- this repository checked out

Target roles:

- `cp-1`, `cp-2`, `cp-3`
- `infra-1`
- GPU workers grouped under `gpu` in [`local/hosts.yml`](local/hosts.yml)

Important inventory note:

- if worker nodes can reach the control plane only through public IPs, set `access_ip` for `cp-1`, `cp-2`, and `cp-3` to those public IPs in [`local/hosts.yml`](local/hosts.yml)

## 1. Fill Local Files

Fill:

- [`local/hosts.yml`](local/hosts.yml)
- [`local/s3.env`](local/s3.env)
- [`local/llm.env`](local/llm.env)

Required values:

- `local/hosts.yml`: IPs, `root`, SSH passwords, node grouping
- `local/s3.env`: endpoint, bucket, access key, secret key, prefix
- `local/llm.env`: `LITELLM_MASTER_KEY`, `OPENWEBUI_ADMIN_*`

## 2. Validate Repository

```bash
make validate-static
```

Expected result:

- static validation passes

## 3. Render Inventory

```bash
./bootstrap/render-inventory.sh
```

Expected result:

- generated inventory appears under `inventory/generated/`

## 4. Prepare Hosts

```bash
./bootstrap/host-prep.sh
```

Expected result:

- host preparation completes without fatal errors

## 5. Bootstrap Kubernetes

```bash
./bootstrap/cluster-bootstrap.sh
```

Expected result:

- cluster comes up
- `local/runtime/admin.conf` exists

Operational note:

- `local/runtime/admin.conf` may still point to `127.0.0.1:6443`
- if that happens, use SSH to `cp-1` or create a local tunnel instead of assuming the file is directly usable from the operator machine

Verify:

```bash
kubectl --kubeconfig local/runtime/admin.conf get nodes -o wide
```

You should see:

- `3` control-plane nodes
- `1` infra node
- the GPU nodes currently declared in [`local/hosts.yml`](local/hosts.yml)
- all live nodes `Ready`

## 6. Prepare GPU Nodes

```bash
./bootstrap/gpu-prep.sh
```

Verify:

```bash
kubectl --kubeconfig local/runtime/admin.conf get nodes
kubectl --kubeconfig local/runtime/admin.conf describe node gpu-1 | grep -A3 Capacity
kubectl --kubeconfig local/runtime/admin.conf describe node gpu-2 | grep -A3 Capacity
```

Expected result:

- `nvidia.com/gpu` is visible on every host in the `gpu` group

Critical validation:

```bash
kubectl --kubeconfig local/runtime/admin.conf get node -l node-role.kubernetes.io/gpu= \
  -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.allocatable.nvidia\.com/gpu}{"\n"}{end}'
```

## 7. Bootstrap ArgoCD

```bash
./bootstrap/argocd-bootstrap.sh
```

Verify:

```bash
kubectl --kubeconfig local/runtime/admin.conf get pods -n argocd
kubectl --kubeconfig local/runtime/admin.conf get applications -n argocd
```

Expected result:

- ArgoCD pods are running
- applications exist

## 8. Bootstrap Sealed Secrets

```bash
./bootstrap/sealed-secrets-bootstrap.sh
```

Verify:

```bash
kubectl --kubeconfig local/runtime/admin.conf get pods -n kube-system | grep -i sealed || true
kubectl --kubeconfig local/runtime/admin.conf get pods -A | grep -i sealed
```

Expected result:

- Sealed Secrets controller is running

## 9. Apply Runtime Application Secrets

```bash
./bootstrap/app-secrets.sh
```

Verify:

```bash
kubectl --kubeconfig local/runtime/admin.conf get ns llm
kubectl --kubeconfig local/runtime/admin.conf get secrets -n llm
```

Expected result:

- namespace `llm` exists
- secrets exist:
  - `llm-s3-credentials`
  - `litellm-auth`
  - `openwebui-admin`

## 10. Sync Models To S3

```bash
./bootstrap/model-sync.sh
```

Expected result:

- model sync completes for:
  - `openai/gpt-oss-20b`
  - `Qwen/Qwen3.5-9B`

## 11. Wait For GitOps Reconciliation

Check:

```bash
kubectl --kubeconfig local/runtime/admin.conf get applications -n argocd
kubectl --kubeconfig local/runtime/admin.conf get pods -n llm -o wide
kubectl --kubeconfig local/runtime/admin.conf get inferenceservice -n llm -o wide
```

Expected target state:

- `app-litellm` -> `Synced/Healthy`
- `app-openwebui` -> `Synced/Healthy`
- `app-llm-serving` -> `Synced/Healthy` or temporarily `Progressing` during model load
- `litellm` pod -> `Running`
- `openwebui` pod -> `Running`
- predictors scheduled only on currently active GPU nodes

If GPU nodes were replaced after initial bootstrap:

- verify the live `InferenceService` or predictor pod `nodeSelector` values no longer reference retired hostnames

## 12. Validate Cluster And Platform

```bash
./tests/validate-cluster.sh all
./tests/validate-platform.sh all
./tests/validate-serving.sh runtime
./tests/validate-observability.sh runtime
```

Expected result:

- all validation commands pass

## 13. Smoke Test LiteLLM

Set environment:

```bash
export LITELLM_BASE_URL="http://<infra-public-ip>:32080"
export LITELLM_API_KEY="<value-from-local-llm-env>"
```

Run:

```bash
make smoke-test
```

Expected result:

- `HTTP 200`
- non-empty generated text
- no runtime error in response

Default smoke-test model:

- `qwen35-9b`

## 14. Open Open WebUI

URL:

```text
http://<infra-public-ip>:32081
```

Credentials come from:

- [`local/llm.env`](local/llm.env)

Expected result:

- login works
- Open WebUI uses internal `LiteLLM`

## 15. Open Grafana

URL:

```text
http://<infra-public-ip>:32082
```

Credentials come from:

- `monitoring/vmstack-grafana` secret

Expected result:

- Grafana opens in the browser
- GPU, LiteLLM, and LLM platform dashboards are visible

## Failure Checklist

## GPU Node Replacement

For future replacement or onboarding of GPU nodes, use:

- [`docs/runbooks/gpu-node-replacement.md`](docs/runbooks/gpu-node-replacement.md)

That runbook captures the live `sxmgpu` onboarding, including:

- public-IP-only worker join
- worker `nginx-proxy` fixes
- `cilium-operator` relocation
- `CiliumNode` IPAM recovery
- NVIDIA runtime fixes for `containerd`
- safe deletion of dead GPU node objects

If `llm` apps disappear:

```bash
kubectl --kubeconfig local/runtime/admin.conf get ns llm
kubectl --kubeconfig local/runtime/admin.conf get applications -n argocd | egrep 'app-litellm|app-openwebui|app-llm-serving'
./bootstrap/app-secrets.sh
```

If predictors are stuck:

```bash
kubectl --kubeconfig local/runtime/admin.conf get pods -n llm -o wide
kubectl --kubeconfig local/runtime/admin.conf describe pod -n llm <predictor-pod>
kubectl --kubeconfig local/runtime/admin.conf logs -n llm <predictor-pod> -c kserve-container --tail=200
```

If ArgoCD is unhealthy:

```bash
kubectl --kubeconfig local/runtime/admin.conf get applications -n argocd
kubectl --kubeconfig local/runtime/admin.conf describe app app-llm-serving -n argocd
```
