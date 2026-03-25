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

- default model alias: `qwen35-9b`
- prompt: `Напиши одно короткое предложение о Kubernetes.`

Example request:

```bash
curl -H "Authorization: Bearer $LITELLM_API_KEY" \
  -H "Content-Type: application/json" \
  -X POST "$LITELLM_BASE_URL/v1/chat/completions" \
  -d '{
    "model": "qwen35-9b",
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

## Grafana

- URL: `http://<infra-1-public-ip>:32082`
- Admin credentials are stored in the `monitoring/vmstack-grafana` secret

## Runbooks

- [`docs/architecture.md`](docs/architecture.md)
- [`docs/runbooks/sealed-secrets.md`](docs/runbooks/sealed-secrets.md)
- [`docs/runbooks/storage.md`](docs/runbooks/storage.md)
- [`docs/runbooks/ingress.md`](docs/runbooks/ingress.md)
- [`docs/runbooks/model-artifacts.md`](docs/runbooks/model-artifacts.md)
- [`RUNBOOK.md`](RUNBOOK.md)
- [`HANDOFF.md`](HANDOFF.md)
- [`Release.md`](Release.md)
