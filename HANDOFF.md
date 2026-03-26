# Handoff

## Purpose

This file is the shortest path for a new agent or operator to continue work from the current repository state and reproduce the platform on new servers.

## Source Of Truth

Use these files first:

- [`AGENTS.md`](AGENTS.md)
- [`README.md`](README.md)
- [`spec/plan.yaml`](spec/plan.yaml)
- [`spec/requirements.md`](spec/requirements.md)
- [`docs/dependency-matrix.yaml`](docs/dependency-matrix.yaml)

## Current Intended Platform Shape

- `3` control-plane nodes
- `1` infra node
- current live topology: `1` GPU worker node named `sxmgpu` with `8x NVIDIA H200`
- original plan topology: `2` GPU worker nodes; this is now an approved live deviation recorded in [`spec/status.md`](spec/status.md)
- `Kubernetes + Cilium + Istio + ArgoCD + Sealed Secrets + OpenEBS + KServe + vLLM + LiteLLM + Open WebUI + VictoriaMetrics`

Phase-1 serving layout:

- current repo target -> both phase-1 models pinned to `sxmgpu`
- public inference entrypoint -> `LiteLLM`
- public UI -> `Open WebUI`

Primary operational recovery doc for this topology change:

- [`docs/runbooks/gpu-node-replacement.md`](docs/runbooks/gpu-node-replacement.md)

## Required Local Files

These files must exist and are intentionally not committed:

- [`local/hosts.yml`](local/hosts.yml)
- [`local/s3.env`](local/s3.env)
- [`local/llm.env`](local/llm.env)

What they contain:

- `local/hosts.yml`: host IPs, SSH access, inventory grouping, and control-plane `access_ip` values when workers join over public IPs
- `local/s3.env`: bucket, endpoint, credentials, prefix
- `local/llm.env`: `LiteLLM` master key and `Open WebUI` admin bootstrap credentials

## Bootstrap Order

Run in this order:

```bash
make validate-static
./bootstrap/render-inventory.sh
./bootstrap/host-prep.sh
./bootstrap/cluster-bootstrap.sh
./bootstrap/gpu-prep.sh
./bootstrap/argocd-bootstrap.sh
./bootstrap/sealed-secrets-bootstrap.sh
./bootstrap/app-secrets.sh
./bootstrap/model-sync.sh
```

Then verify GitOps reconciliation:

```bash
kubectl --kubeconfig local/runtime/admin.conf get applications -n argocd
kubectl --kubeconfig local/runtime/admin.conf get pods -n llm -o wide
kubectl --kubeconfig local/runtime/admin.conf get inferenceservice -n llm -o wide
```

## Expected Public Endpoints

- `LiteLLM`: `http://<infra-public-ip>:32080`
- `Open WebUI`: `http://<infra-public-ip>:32081`
- `Grafana`: `http://<infra-public-ip>:32082`

## Default Runtime Validation

```bash
./tests/validate-cluster.sh all
./tests/validate-platform.sh all
./tests/validate-serving.sh runtime
./tests/validate-observability.sh runtime
```

Smoke test:

```bash
export LITELLM_BASE_URL="http://<infra-public-ip>:32080"
export LITELLM_API_KEY="<litellm-master-key>"
make smoke-test
```

Default smoke-test model alias:

- `default`

Alternative alias available through `LiteLLM`:

- `qwen-122b`
- `minimax-m25`
- `qwen-coder`

## Known Operational Notes

- `llm` namespace creation must remain ordered before `LiteLLM` and `Open WebUI` application sync. This is enforced through `ArgoCD` sync waves and `CreateNamespace=true`.
- if a worker can reach the control plane only through public IPs, `local/hosts.yml` must set `access_ip` for `cp-1`, `cp-2`, and `cp-3`; otherwise Kubespray renders worker-side `nginx-proxy` upstreams to unreachable private IPs
- public `access_ip` values solve worker join only; they do not guarantee healthy `Cilium` east-west traffic if the replacement GPU node cannot route to cluster-node private `InternalIP` addresses
- when that private-network reachability is absent, keep the GitOps fallback topology in place:
  - `LiteLLM` upstreams use public predictor NodePorts on `sxmgpu`
  - `dcgm-exporter` is scraped through the public `VMStaticScrape` target
- replacement GPU nodes may join successfully but remain broken until `cilium-operator` is running on live nodes and the `CiliumNode` object has a populated `spec.ipam.podCIDRs`
- after NVIDIA toolkit configuration, `containerd` must expose `default_runtime_name = "nvidia"` for GPU-device-plugin pods to see NVML correctly
- NVSwitch hosts such as `8x H200` systems also need `nvidia-fabricmanager`; `gpu-prep` must finish with `nvidia-smi -q` showing `Fabric -> State: Completed` and `Status: Success`
- `VictoriaMetrics` and Grafana datasource FQDNs must use the actual cluster DNS domain from [`inventory/group_vars/k8s_cluster.yml`](inventory/group_vars/k8s_cluster.yml); this cluster uses `k8s-vllm-lab`, not `cluster.local`
- S3 model sync is only complete after the real `model.safetensors-*` shard objects exist; Hugging Face `.metadata` side files alone are not enough for `vLLM`
- `bootstrap/app-secrets.sh` is required for reproducible creation of:
  - `llm-s3-credentials`
  - `litellm-auth`
  - `openwebui-admin`
- `ClusterServingRuntime vllm-openai-runtime` must not hard-code `--served-model-name`; each `InferenceService` passes its own model name.
- `Open WebUI` is configured to use internal `LiteLLM` and does not expose secrets via Git.
- `LiteLLM` now exposes three S3-backed public-fallback upstreams on `sxmgpu`:
  - `qwen-122b` via `32090`
  - `minimax-m25` via `32091`
  - `qwen-coder` via `32092`
  - alias `default` maps to `qwen-122b`
- if `Open WebUI` only shows `qwen-122b`, first check `LiteLLM /v1/models`:
  - live `ConfigMap/litellm-config` may already contain all three models while the
    `LiteLLM` pod is still running an older deployment revision
  - a `rollout restart deployment/litellm -n llm` restores the full model list immediately
- `LiteLLM` observability has one specific gotcha that already happened live:
  - `LiteLLM` metrics are exposed at `/metrics/`, not `/metrics`
  - `VMServiceScrape/litellm-metrics` must therefore use `path: /metrics/`
  - `Service/litellm` must carry label `app.kubernetes.io/name=litellm`, otherwise the `VMServiceScrape` selector resolves to `0` Services and Grafana shows `No data`
  - the GitOps fixes were shipped in:
    - `86c65e1` `Fix LiteLLM metrics scrape path`
    - `860e67a` `Label LiteLLM service for scraping`
- model artifacts currently originate from S3, but the active migration path is to keep `S3` as source-of-truth and move runtime pods onto per-model `OpenEBS LocalPV` caches on `sxmgpu`; this avoids full re-downloads on every predictor rollout once the initial cache is populated
- the already-downloaded pod-local model data on `sxmgpu` can be reused for that migration from:
  - `/var/lib/kubelet/pods/66f05e8e-ce6b-405e-8490-e17ddb5a8a69/volumes/kubernetes.io~empty-dir/kserve-provision-location` for `qwen35-122b`
  - `/var/lib/kubelet/pods/1844558b-1da2-4225-aaec-e96f1ec21a86/volumes/kubernetes.io~empty-dir/kserve-provision-location` for `minimax-m25`
  - `/var/lib/kubelet/pods/c9fc43c8-893b-4419-97ce-57d343bec7d5/volumes/kubernetes.io~empty-dir/kserve-provision-location` for `qwen3-coder`

## Fast Recovery Checks

If `LiteLLM` or `Open WebUI` disappear, check:

```bash
kubectl --kubeconfig local/runtime/admin.conf get ns llm
kubectl --kubeconfig local/runtime/admin.conf get applications -n argocd | egrep 'app-litellm|app-openwebui|app-llm-serving'
kubectl --kubeconfig local/runtime/admin.conf get secrets -n llm
```

If needed, recreate runtime secrets:

```bash
./bootstrap/app-secrets.sh
```

## Current Repository Baseline

- three-model serving layout is reflected in implementation, with `2+4+2` GPU allocation on the replacement GPU node `sxmgpu`
- current `main` branch is the deployment source for `ArgoCD`
- use [`Release.md`](Release.md) for the platform change history

## Current Live Serving Status

- `qwen35-122b` is now `READY=True` in the live cluster
- predictor pod `qwen35-122b-predictor-6c9df5b447-2pt49` is `1/1 Running` on `sxmgpu`
- the direct model endpoint is confirmed working:
  - `GET /v1/models` returns model id `qwen-122b`
  - direct `POST /v1/chat/completions` against the predictor returns a valid JSON response
- the successful live startup path used the conservative runtime profile now committed in [`gitops/apps/llm-serving/inference-service-qwen35-122b.yaml`](gitops/apps/llm-serving/inference-service-qwen35-122b.yaml):
  - `--max-model-len=16384`
  - `--gpu-memory-utilization=0.85`
  - `--max-num-seqs=16`
  - `--enforce-eager`
- `qwen35-122b` now runs from a persistent `OpenEBS LocalPV` cache instead of
  `storage-initializer` + pod-local `EmptyDir`
- `qwen3-coder` now also runs from the same `OpenEBS LocalPV` cache pattern via
  `qwen3-coder-model-cache`
- the live `qwen3-coder` failure that was mitigated during that migration was a
  `vLLM` startup crash after model load with `custom_all_reduce.cuh:455 invalid argument`
- `minimax-m25` is the next model being migrated to `OpenEBS LocalPV` cache via
  `minimax-m25-model-cache`
- the public `LiteLLM` path is also confirmed working:
  - correct public entrypoint is `http://89.111.168.161:32080`
  - `POST /v1/chat/completions` through `LiteLLM` returned `HTTP 200`
  - `LiteLLM` routed `qwen-122b` to `http://89.108.125.7:32090/v1`
