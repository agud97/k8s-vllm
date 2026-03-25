# Release History

## Current

- Deployment source: `main`
- Current platform line: dual-model lab serving
- Primary public services:
  - `LiteLLM` on `NodePort 32080`
  - `Open WebUI` on `NodePort 32081`

## Releases

### 2026-03-19

#### `9dcdd64` Align specs with dual-model serving layout

- synchronized `requirements`, `acceptance_criteria`, `constraints`, and `plan`
- replaced old single-model `Qwen3.5-27B` phase-1 assumptions with:
  - `openai/gpt-oss-20b`
  - `Qwen/Qwen3.5-9B`
- updated spec package so future agents following `plan.yaml` reproduce the current architecture instead of the obsolete one

#### `62ab649` Deploy gpt-oss-20b and qwen35-9b models

- replaced the failing `Qwen3.5-27B` phase-1 layout with two pinned models
- added a second `InferenceService`
- pinned serving placement one-to-one to the two GPU nodes
- updated `LiteLLM` to expose two model aliases:
  - `gpt-oss-20b`
  - `qwen35-9b`
- updated model sync and smoke-test defaults

#### `6fa879e` Fix llm app sync ordering and namespace creation

- fixed `ArgoCD` sync order for `llm` applications
- ensured `llm` namespace is created before `LiteLLM` and `Open WebUI`
- added `CreateNamespace=true` to the affected `Application` resources

#### `1e5badb` Add reproducible app secret bootstrap flow

- added `bootstrap/app-secrets.sh`
- made `LiteLLM` and `Open WebUI` secrets reproducible from ignored local files
- added `local/llm.env.example`

#### `b0432af` Bootstrap Open WebUI admin credentials from secret

- removed dependency on first-login manual admin creation
- moved admin bootstrap to Kubernetes secret input

#### `974029b` Add Open WebUI routed through LiteLLM

- deployed `Open WebUI` into the cluster
- connected `Open WebUI` to internal `LiteLLM`
- exposed `Open WebUI` through `NodePort 32081`

#### `63e3d23` Drop CPU offload and tighten text-only context

- removed unstable CPU offload attempt from `vLLM`
- tightened model runtime profile after live runtime failures

#### `e2d33c0` Tune text-only Qwen serving and LiteLLM upstream auth

- fixed `LiteLLM` upstream auth behavior
- tuned text-only serving args for `Qwen`

#### `935648e` Reduce vLLM memory pressure on A5000

- reduced memory pressure in the single-GPU attempt
- adjusted runtime parameters for A5000 constraints

#### `1fffadb` Tune vLLM dtype for GPTQ serving

- switched dtype to a GPTQ-compatible configuration
- addressed runtime failure path caused by incompatible defaults

#### `c4d5d53` Switch serving stack to direct vLLM runtime

- replaced the incompatible `huggingfaceserver` path with direct `vLLM`
- introduced `vllm-openai-runtime`

#### `8fe2071` Point LiteLLM to predictor service

- moved `LiteLLM` upstream to the predictor service path

#### `ede9874` Stabilize serving runtime and storage configuration

- refined serving/storage manifest behavior during the early `KServe` integration

#### `7a65b7d` Fix llm service account and KServe ingress config

- repaired serving account wiring
- fixed KServe ingress-related configuration

#### `bb62bf8` Use minimal GPU runtime for phase-1 inference

- introduced a smaller runtime footprint for initial phase-1 inference attempts

#### `8b19a6f` Schedule all cert-manager components on infra node

- constrained cert-manager placement to `infra-1`

#### `466ab3a` Install cert-manager and KServe standard mode

- enabled the chosen dependency set for the live version combination
- deployed KServe in standard deployment mode

#### `a2d87f7` Use official OpenEBS LocalPV Helm chart

- switched `OpenEBS` to the official Helm packaging

#### `e3f2da9` Fix LiteLLM image tag

- corrected the `LiteLLM` container tag for live deployment

#### `8518d50` Add cluster bootstrap and GitOps deployment assets

- established the first end-to-end bootstrap/GitOps repository skeleton

## Notes

- `spec/proposal.md` remains the original source discussion and may describe superseded choices.
- The operational source of truth for new work is:
  - [`spec/requirements.md`](spec/requirements.md)
  - [`spec/acceptance_criteria.md`](spec/acceptance_criteria.md)
  - [`spec/constraints.md`](spec/constraints.md)
  - [`spec/plan.yaml`](spec/plan.yaml)
  - [`HANDOFF.md`](HANDOFF.md)
