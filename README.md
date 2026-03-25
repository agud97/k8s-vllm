# k8s-vllm Lab

Spec-driven lab for a non-managed Kubernetes cluster with:

- Kubespray
- Cilium
- Istio
- ArgoCD
- Sealed Secrets
- OpenEBS LocalPV
- KServe + vLLM
- LiteLLM
- VictoriaMetrics

## Repository Areas

- `bootstrap/` - bootstrap and operator-facing shell entrypoints
- `inventory/` - Git-managed inventory templates and group variables
- `gitops/` - ArgoCD-managed manifests
- `docs/` - dependency matrix and runbooks
- `tests/` - static validation, cluster validation, smoke tests
- `local/` - ignored local-only inputs such as inventory and S3 credentials

## Local Inputs

Fill these files before running bootstrap:

- `local/hosts.yml`
- `local/s3.env`
- `local/llm.env`

They are ignored by Git.

## Dependency Matrix

Pinned versions are declared in:

- [`docs/dependency-matrix.yaml`](docs/dependency-matrix.yaml)

## Bootstrap Flow

1. Validate static repository state:

```bash
make validate-static
```

2. Render inventory from local input:

```bash
./bootstrap/render-inventory.sh
```

3. Prepare hosts:

```bash
./bootstrap/host-prep.sh
```

4. Bootstrap Kubernetes with Kubespray:

```bash
./bootstrap/cluster-bootstrap.sh
```

5. Prepare GPU nodes:

```bash
./bootstrap/gpu-prep.sh
```

6. Bootstrap ArgoCD:

```bash
./bootstrap/argocd-bootstrap.sh
```

7. Bootstrap Sealed Secrets:

```bash
./bootstrap/sealed-secrets-bootstrap.sh
```

8. Apply LLM application secrets:

```bash
./bootstrap/app-secrets.sh
```

9. Sync model artifacts to S3:

```bash
./bootstrap/model-sync.sh
```

10. Let ArgoCD reconcile platform and applications:

```bash
kubectl --kubeconfig local/runtime/admin.conf get applications -n argocd
```

## Critical Bootstrap Lessons

- GPU workers must have L3 reachability to the `InternalIP` addresses of every cluster node. Public `access_ip` values are enough for `kubeadm join`, but they are not enough to guarantee healthy cross-node pod networking with `Cilium`.
- If a replacement GPU node cannot reach control-plane or infra-node private `InternalIP` addresses, treat that as a bootstrap blocker for normal in-cluster east-west traffic. Either place the node onto the same private network or explicitly route serving and observability traffic through GitOps-managed public endpoints.
- The current serving target is three S3-backed models on `sxmgpu`:
  - `Qwen/Qwen3.5-122B-A10B-FP8` exposed as `qwen-122b` and `default`
  - `MiniMaxAI/MiniMax-M2.5` exposed as `minimax-m25`
  - `Qwen/Qwen3-Coder-Next` exposed as `qwen-coder`
- Multi-GPU `vLLM` runtimes on the `8x H200` worker require `hostIPC: true`, a large `/dev/shm`, and successful `nvidia-fabricmanager` initialization before predictor pods can initialize CUDA reliably.
- `dcgm-exporter` on public-only GPU workers must be scraped through the GitOps-managed public endpoint if the observability stack cannot reliably reach the GPU pod CIDR.

## Validation Commands

Static:

```bash
make validate-static
./tests/validate-serving.sh static
./tests/validate-observability.sh static
```

Cluster baseline:

```bash
./tests/validate-cluster.sh all
./tests/validate-platform.sh all
```

Serving and observability runtime:

```bash
./tests/validate-serving.sh runtime
./tests/validate-observability.sh runtime
```

## Smoke Test

Required environment:

- `LITELLM_BASE_URL=http://<infra-1-public-ip>:32080`
- `LITELLM_API_KEY=<valid-api-key>`

Run:

```bash
make smoke-test
```

The scripted request uses:

- default model alias: `default`
- current default route: `qwen-122b`
- prompt: `Напиши одно короткое предложение о Kubernetes.`

Example request:

```bash
curl -H "Authorization: Bearer $LITELLM_API_KEY" \
  -H "Content-Type: application/json" \
  -X POST "$LITELLM_BASE_URL/v1/chat/completions" \
  -d '{
    "model": "default",
    "messages": [{"role": "user", "content": "Напиши одно короткое предложение о Kubernetes."}],
    "max_tokens": 64
  }'
```

Example successful response shape:

```json
{
  "id": "chatcmpl-...",
  "object": "chat.completion",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "Kubernetes automates deployment, scaling, and management of containerized applications."
      }
    }
  ]
}
```

## Open WebUI

- URL: `http://<infra-1-public-ip>:32081`
- Admin credentials are sourced from `local/llm.env` and bootstrapped via `./bootstrap/app-secrets.sh`
- If models do not appear in the selector, inspect [`gitops/apps/litellm/configmap.yaml`](gitops/apps/litellm/configmap.yaml) first; Open WebUI only reflects the aliases currently exported by `LiteLLM`
- If model replies fail after a model switch, inspect the public fallback upstreams in [`gitops/apps/litellm/configmap.yaml`](gitops/apps/litellm/configmap.yaml) and the S3-backed `InferenceService` objects in [`gitops/apps/llm-serving`](gitops/apps/llm-serving)

## Grafana

- URL: `http://<infra-1-public-ip>:32082`
- Admin credentials are stored in the `monitoring/vmstack-grafana` secret
- `VictoriaMetrics` and Grafana datasource FQDNs must follow the real cluster DNS domain from [`inventory/group_vars/k8s_cluster.yml`](inventory/group_vars/k8s_cluster.yml), not a hard-coded `cluster.local`

## Runbooks

- [`docs/architecture.md`](docs/architecture.md)
- [`docs/runbooks/sealed-secrets.md`](docs/runbooks/sealed-secrets.md)
- [`docs/runbooks/storage.md`](docs/runbooks/storage.md)
- [`docs/runbooks/ingress.md`](docs/runbooks/ingress.md)
- [`docs/runbooks/model-artifacts.md`](docs/runbooks/model-artifacts.md)
- [`RUNBOOK.md`](RUNBOOK.md)
- [`HANDOFF.md`](HANDOFF.md)
- [`Release.md`](Release.md)
