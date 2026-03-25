# Technical Constraints

Relevant specs:
- [requirements.md](/root/codex/k8s-cloud/spec/requirements.md)
- [acceptance_criteria.md](/root/codex/k8s-cloud/spec/acceptance_criteria.md)
- [proposal.md](/root/codex/k8s-cloud/spec/proposal.md)

## 1. Project Structure

### MUST

- The repository MUST remain the single source of truth for deployment automation, GitOps manifests, version pinning, and operator documentation.
- The implementation MUST result in a live deployed lab cluster on the provided virtual machines; repository artifacts alone are not a sufficient completion state.
- The repository MUST separate concerns into top-level areas for bootstrap automation, cluster inventory/configuration, GitOps applications, reusable platform manifests, and operator documentation.
- The GitOps area MUST be organized by platform responsibility, not by ad hoc file accumulation.
- The GitOps area MUST include distinct directories for:
  - ArgoCD bootstrap or self-management manifests
  - cluster infrastructure add-ons
  - platform services
  - application-level serving workloads
- The repository MUST include a root bootstrap entrypoint that is callable as a single documented command or wrapper script.
- The repository MUST include a machine-readable inventory or host-definition area for the 3 control-plane nodes, 2 GPU nodes, and 1 infra node.
- The repository MUST include environment-specific values only for the current lab environment and MUST NOT imply unsupported production environments as ready-to-use.
- The repository MUST store rendered or source manifests in a way that ArgoCD can reconcile directly from Git.
- The repository MUST include a dedicated documentation file for bootstrap, validation, and recovery steps relevant to the lab scope.
- The documentation MUST capture the commands and environment-specific outputs needed to prove that the live deployment was executed successfully.
- The documentation MUST include a reusable runbook for replacing or onboarding GPU worker nodes after the initial cluster bootstrap.

### SHOULD

- The top-level layout SHOULD resemble:
  - `bootstrap/` for one-time orchestration and operator wrappers
  - `inventory/` for host definitions and group variables
  - `gitops/` for ArgoCD-managed manifests
  - `platform/` or `charts/` for reusable packaged manifests or Helm values
  - `docs/` for operator runbooks
  - `tests/` for validation and smoke tests
- GitOps subdirectories SHOULD follow deployment order and responsibility boundaries, for example `argocd`, `infra`, `platform`, `apps`.
- Generated artifacts SHOULD be excluded from source control unless they are intentionally used as the reconciled source of truth.

### MUST NOT

- The repository MUST NOT mix bootstrap scripts, inventory data, and application manifests in a single flat directory.
- The repository MUST NOT depend on manual, undocumented in-cluster edits as part of normal deployment.
- The repository MUST NOT require a second repository for the current lab scope.

## 2. Component Design

### MUST

- Bootstrap automation MUST be designed as idempotent orchestration steps with explicit inputs, observable outputs, and non-zero exit codes on failure.
- The agent MUST execute the bootstrap automation against the provided hosts once prerequisites are available, unless blocked by a real infrastructure or credential failure.
- Inventory and bootstrap logic MUST support worker onboarding in environments where control-plane private IPs are not reachable from replacement workers, using explicit inventory access addresses when required.
- Each major platform capability MUST have a clearly defined ownership boundary:
  - cluster bootstrap
  - ArgoCD bootstrap
  - secrets bootstrap
  - storage
  - networking and ingress
  - model serving
  - observability
  - validation
- Reusable configuration MUST be parameterized through values files, inventory variables, or environment files rather than duplicated manifests.
- ArgoCD applications MUST express dependency order declaratively using supported GitOps mechanisms such as sync waves, app-of-apps ordering, or equivalent reconciliation-safe constructs.
- The public inference entrypoint MUST terminate at LiteLLM and MUST treat KServe or vLLM as internal upstream services.
- LiteLLM MUST integrate with the serving layer through internal OpenAI-compatible upstream endpoints for phase 1.
- The phase-1 LiteLLM upstream contract MUST use internal HTTP endpoints exposing `/v1/chat/completions`, with pinned model aliases for `gpt-oss-20b` and `qwen35-9b`; the default smoke test alias MUST be `qwen35-9b`.
- Secret material consumed by workloads MUST enter the cluster through Sealed Secrets and standard Kubernetes Secrets derived from them.
- The design MUST preserve an upgrade path to future multi-node inference without forcing a distributed serving implementation in phase 1.
- Platform components MUST be deployable independently enough to support failure isolation and targeted reconciliation.
- Validation logic MUST be encapsulated in dedicated scripts or targets rather than buried in README prose only.
- Component delivery is not complete until the corresponding live component is installed and validated in the target cluster.
- Recovery logic for GPU node replacement MUST account for Cilium operator placement, worker-side API reachability, and NVIDIA runtime configuration rather than assuming a pristine first-bootstrap path.

### SHOULD

- Shared logic in scripts SHOULD be organized into reusable shell functions or task helpers rather than repeated command blocks.
- Component boundaries SHOULD align with the acceptance categories: bootstrap, GitOps, secrets, access, serving, storage, observability, documentation validation.
- Application packaging SHOULD prefer Helm values overlays or Kustomize overlays over copy-pasted YAML variants.
- Inventory and host-group metadata SHOULD encode node roles needed for scheduling, taints, labels, and add-on placement.

### MUST NOT

- The design MUST NOT couple LiteLLM directly to public secrets stored outside Sealed Secrets or plaintext files in Git.
- The design MUST NOT expose ArgoCD publicly as part of the intended steady state.
- The design MUST NOT treat production-only concerns such as Vault as active dependencies for the current lab implementation.
- The design MUST NOT hard-code mutable runtime state into static manifests when the value belongs in inventory, values files, or sealed secret inputs.

## 3. Technology Decisions

### MUST

- Kubernetes bootstrap MUST use Kubespray.
- Node operating system assumptions MUST target Ubuntu 24.04 LTS.
- Container runtime assumptions MUST target containerd.
- The cluster network plugin MUST be Cilium.
- The service mesh MUST be Istio.
- GitOps control plane MUST be ArgoCD.
- Secret management for the lab environment MUST use Sealed Secrets.
- Model serving MUST use KServe with vLLM-compatible serving configuration.
- Phase 1 model serving MUST use two single-replica, non-distributed `KServe InferenceService` workloads, one pinned to each GPU node.
- The model sources MUST be pinned to `openai/gpt-oss-20b` and `Qwen/Qwen3.5-9B`.
- Public inference access MUST go through LiteLLM using LiteLLM native API key authentication.
- Observability MUST use VictoriaMetrics Kubernetes stack with 7-day retention and 100Gi persistent storage.
- Persistent storage for in-cluster stateful workloads MUST use OpenEBS LocalPV where persistence is required in this lab environment.
- Storage ownership MUST follow this lab matrix:
  - model artifacts in S3
  - VictoriaMetrics data on OpenEBS LocalPV
  - Sealed Secrets key reuse material preserved outside Git for rebuild reuse
  - ArgoCD state treated as ephemeral, with no PVC-backed ArgoCD features in current lab scope
  - temporary model cache treated as ephemeral unless explicitly configured otherwise
- Platform versions MUST be pinned explicitly in manifests, values, image tags, or dependency lockfiles.
- The deployment stack MUST expose the initial public inference path through `NodePort` on `infra-1` over HTTP by IP.
- GPU enablement MUST include NVIDIA driver installation, NVIDIA container runtime support, and Kubernetes GPU resource discovery sufficient for `nvidia.com/gpu` scheduling.
- GPU enablement MUST validate the host with `nvidia-smi` after installation and MUST treat driver or library mismatches as a host-level issue requiring remediation before Kubernetes GPU discovery is considered complete.
- GPU resource discovery MUST use the NVIDIA Device Plugin. NVIDIA GPU Operator MUST NOT be used in the active lab deployment path.
- Container runtime configuration for GPU nodes MUST ensure that containerd exposes an NVIDIA runtime that is actually usable by Kubernetes GPU workloads and device-plugin pods.
- Conditionally required dependencies of the selected KServe, Knative, or Istio versions, including `cert-manager`, MUST be included only when the chosen implementation actually requires them.
- The repository MUST declare a pinned dependency matrix covering the selected versions of core platform components and any conditionally enabled dependencies.
- Acceptance-level performance validation MUST use these lab thresholds:
  - serving readiness within 30 minutes from deployment start
  - smoke-test response within 60 seconds
  - concurrency target of 1

### SHOULD

- Helm SHOULD be the default packaging mechanism for third-party platforms that already publish maintained charts.
- Kustomize SHOULD be used for composition, overlays, and ArgoCD application assembly where chart wrapping alone is insufficient.
- The root bootstrap command SHOULD be implemented through `make`, a task runner, or a single entrypoint shell script with subcommands.
- The implementation SHOULD prefer upstream-maintained charts and manifests over custom forks.
- Model download or synchronization SHOULD occur through an explicit job or script that can be rerun safely.
- The implementation SHOULD use Kubernetes labels, taints, and tolerations to separate infra and GPU workloads by node role.
- The implementation SHOULD preserve enough inventory flexibility to accommodate GPU node replacement or temporary topology reduction without breaking validation scripts.

### MUST NOT

- The implementation MUST NOT introduce an external auth proxy as the primary inference authentication path.
- The implementation MUST NOT use Vault in the active lab deployment path.
- The implementation MUST NOT require managed Kubernetes services or cloud-account automation APIs.
- The implementation MUST NOT assume DNS names or public TLS certificates for the initial inference path.
- The implementation MUST NOT depend on centralized logging or distributed tracing as acceptance prerequisites.

## 4. Code Style

### MUST

- All repository paths, file names, manifest names, script names, and variable names MUST be descriptive and role-oriented.
- Shell scripts MUST use strict mode where practical, including `set -euo pipefail` or an equivalent failure-safe pattern.
- Script output MUST be concise, human-readable, and structured enough for operators to identify the current phase and failing step.
- Every non-trivial script entrypoint MUST validate required inputs before making changes.
- YAML manifests MUST remain declarative, minimal, and free of commented-out dead configuration blocks.
- Names for Kubernetes resources MUST be stable and predictable across reruns.
- Image tags, chart versions, and critical component versions MUST be declared in obvious, reviewable locations.
- Documentation commands MUST be copy-pasteable as written, with placeholders clearly marked where operator input is required.

### SHOULD

- Directory and file naming SHOULD use lowercase kebab-case.
- Variable names in scripts and values files SHOULD use consistent uppercase snake_case for environment variables and lower snake_case or lower kebab-case for YAML keys according to tool conventions.
- Comments SHOULD explain intent or non-obvious tradeoffs, not restate syntax.
- Wrapper commands SHOULD expose clear verbs such as `bootstrap`, `deploy`, `validate`, `smoke-test`, and `port-forward`.
- Validation scripts SHOULD print actionable remediation hints on failure.

### MUST NOT

- The codebase MUST NOT contain plaintext secrets, inline private keys, or hard-coded API tokens.
- The codebase MUST NOT rely on floating `latest` image tags for pinned platform components.
- The codebase MUST NOT duplicate large YAML blocks when values-driven reuse or overlays would satisfy the same need.
- The codebase MUST NOT use undocumented magic ordering between scripts or manifests.
- The codebase MUST NOT require operators to edit generated files manually as a normal workflow step.

## 5. Testing Strategy

### MUST

- The repository MUST include automated validation for bootstrap prerequisites, manifest correctness, and post-deployment smoke checks.
- Tests MUST cover at least these categories:
  - static validation of YAML, Helm, or Kustomize inputs
  - bootstrap or orchestration script validation
  - ArgoCD-managed manifest integrity
  - Sealed Secrets workflow validation
  - inference authentication behavior
  - inference smoke test behavior
  - observability stack presence and target coverage
- Static tests MUST run without requiring access to the target cluster.
- Post-deployment validation MUST verify:
  - all six nodes are present and Ready
  - Cilium is active
  - Istio control plane is healthy
  - ArgoCD is healthy
  - Sealed Secrets is healthy
  - GPU resources are discoverable
  - KServe or vLLM serving is healthy
  - LiteLLM is reachable
  - VictoriaMetrics stack is healthy
- Post-deployment validation MUST include a negative test for inference access without a valid API key.
- Post-deployment validation MUST include the documented smoke test prompt through LiteLLM and assert successful HTTP response plus non-empty text output.
- Validation for pinned versions MUST assert that required platform images or chart references are not left floating.
- Validation logic MUST be runnable from the repository with documented commands.
- Final validation MUST be performed against the live target cluster, not only through static repository checks.
- Post-deployment validation MUST be actually executed before completion is claimed.
- The implementation MUST produce or preserve a usable kubeconfig or equivalent cluster access path for post-deployment validation.
- Post-bootstrap documentation MUST describe an alternate SSH- or tunnel-based cluster access path when the generated kubeconfig is localhost-scoped and not directly usable from the operator machine.

### SHOULD

- Static validation SHOULD include tools such as `yamllint`, `helm lint`, `kustomize build`, `kubectl apply --dry-run=client`, or equivalent validators appropriate to the chosen packaging.
- Script validation SHOULD include `shellcheck` or an equivalent shell linter.
- End-to-end validation SHOULD be split into fast checks and cluster-dependent checks.
- Smoke tests SHOULD be implemented as repeatable scripts rather than manually composed curl commands in docs only.
- Tests SHOULD fail fast and report the failing component category clearly.
- Live deployment evidence SHOULD be recorded in the final documentation so that a reviewer can inspect what was actually executed and what endpoint was produced.

### MUST NOT

- The test strategy MUST NOT rely exclusively on manual inspection.
- The test strategy MUST NOT treat a running pod count alone as sufficient evidence of success.
- The test strategy MUST NOT require screenshots to prove correctness.
- The test strategy MUST NOT skip negative-path checks for authentication or failed prerequisite handling.
- The test strategy MUST NOT treat generated manifests, unexecuted scripts, or static validation alone as proof that the environment is deployed.
