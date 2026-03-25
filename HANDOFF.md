# Handoff

## Purpose

This file is the shortest path for a new agent or operator to continue work from the current repository state and reproduce the platform on new servers.

## Source Of Truth

Use these files first:

- [`AGENTS.md`](/root/codex/k8s-cloud/AGENTS.md)
- [`README.md`](/root/codex/k8s-cloud/README.md)
- [`spec/plan.yaml`](/root/codex/k8s-cloud/spec/plan.yaml)
- [`spec/requirements.md`](/root/codex/k8s-cloud/spec/requirements.md)
- [`docs/dependency-matrix.yaml`](/root/codex/k8s-cloud/docs/dependency-matrix.yaml)

## Current Intended Platform Shape

- `3` control-plane nodes
- `1` infra node
- current live topology: `1` GPU worker node named `sxmgpu` with `8x NVIDIA H200`
- original plan topology: `2` GPU worker nodes; this is now an approved live deviation recorded in [`spec/status.md`](/root/codex/k8s-cloud/spec/status.md)
- `Kubernetes + Cilium + Istio + ArgoCD + Sealed Secrets + OpenEBS + KServe + vLLM + LiteLLM + Open WebUI + VictoriaMetrics`

Phase-1 serving layout:

- current repo target -> both phase-1 models pinned to `sxmgpu`
- public inference entrypoint -> `LiteLLM`
- public UI -> `Open WebUI`

Primary operational recovery doc for this topology change:

- [`docs/runbooks/gpu-node-replacement.md`](/root/codex/k8s-cloud/docs/runbooks/gpu-node-replacement.md)

## Required Local Files

These files must exist and are intentionally not committed:

- [`local/hosts.yml`](/root/codex/k8s-cloud/local/hosts.yml)
- [`local/s3.env`](/root/codex/k8s-cloud/local/s3.env)
- [`local/llm.env`](/root/codex/k8s-cloud/local/llm.env)

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

- `qwen35-9b`

Alternative alias available through `LiteLLM`:

- `gpt-oss-20b`

## Known Operational Notes

- `llm` namespace creation must remain ordered before `LiteLLM` and `Open WebUI` application sync. This is enforced through `ArgoCD` sync waves and `CreateNamespace=true`.
- if a worker can reach the control plane only through public IPs, `local/hosts.yml` must set `access_ip` for `cp-1`, `cp-2`, and `cp-3`; otherwise Kubespray renders worker-side `nginx-proxy` upstreams to unreachable private IPs
- replacement GPU nodes may join successfully but remain broken until `cilium-operator` is running on live nodes and the `CiliumNode` object has a populated `spec.ipam.podCIDRs`
- after NVIDIA toolkit configuration, `containerd` must expose `default_runtime_name = "nvidia"` for GPU-device-plugin pods to see NVML correctly
- `bootstrap/app-secrets.sh` is required for reproducible creation of:
  - `llm-s3-credentials`
  - `litellm-auth`
  - `openwebui-admin`
- `ClusterServingRuntime vllm-openai-runtime` must not hard-code `--served-model-name`; each `InferenceService` passes its own model name.
- `Open WebUI` is configured to use internal `LiteLLM` and does not expose secrets via Git.

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

- dual-model serving layout is reflected in implementation, but the current live cluster uses one replacement GPU node `sxmgpu`
- current `main` branch is the deployment source for `ArgoCD`
- use [`Release.md`](/root/codex/k8s-cloud/Release.md) for the platform change history
