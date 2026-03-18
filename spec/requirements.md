# Requirements Analysis

## Context Summary

Feature request describes a non-managed Kubernetes cluster in a public cloud with at least two GPU nodes based on NVIDIA A5000, deployment of a Qwen 3.5 model through KServe + vLLM, and GitOps-based in-cluster management through ArgoCD. The request also mentions available S3 storage, absence of network block storage, possible use of OpenEBS on local disks, and an expectation that the agent performs the server and Kubernetes setup work.

Important constraint: the source text mixes stakeholder requirements with architecture recommendations generated during a discussion. Recommendations must not be treated as approved requirements unless explicitly confirmed.

## Confirmed Requirements

1. Infrastructure in the cloud will be created manually by the stakeholder in the cloud provider UI.

2. The agent will not receive access to the cloud account/API, but will receive SSH access to the created servers.

3. Fixed cluster topology:
   - 3 control-plane nodes
   - 2 GPU worker nodes with NVIDIA A5000
   - 1 infra node

4. All nodes will have public IP addresses and will be reachable from the internet.

5. Kubernetes must be deployed as a non-managed cluster using Kubespray.

6. The cluster network stack must use Cilium as CNI.

7. The serving/platform stack must use Istio as service mesh.

8. ArgoCD may be bootstrapped once outside GitOps, then switched to self-management and used as the main GitOps control plane.

9. Model storage approach:
   - model weights are obtained from an external source, with Hugging Face assumed as the default upstream source
   - model artifacts may then be uploaded to the available S3 storage
   - OpenEBS LocalPV may be used for internal cluster stateful workloads

10. Target model is fixed as Qwen3.5-27B in Q4 quantized form.

11. Phase 1 serving must use a single-replica, non-distributed `KServe InferenceService` deployment.

12. The architecture should preserve a future path toward true multi-node inference across two GPU nodes.

13. Secret management for the current lab environment must use Sealed Secrets.

14. ArgoCD UI must not be published publicly; access is through port-forward only.

15. The inference endpoint must be exposed to the internet and protected with token-based authorization.

16. Minimum acceptance criteria:
   - the cluster can be brought up from scratch through prepared automation and operator actions
   - ArgoCD successfully syncs platform components
   - the target model is deployed through KServe
   - the public inference endpoint is reachable with token-based authorization
   - a test inference request returns a valid response

17. Environment type is a lab environment, not a production-like platform.

18. Backups are out of scope.

19. The final deliverable must include:
   - a Git repository containing the deployment automation and GitOps manifests
   - an operator instruction describing how to bring the environment up
   - an execution flow that is as close as possible to "one command" after the VMs are manually created and SSH access is provided

20. External access to model inference must go through LiteLLM deployed in the same Kubernetes cluster.

20a. For phase 1, LiteLLM must call a single internal OpenAI-compatible upstream endpoint provided by the vLLM-based serving stack.

21. VictoriaMetrics Kubernetes stack must be deployed in the same cluster for metrics collection, storage, and visualization.

22. Observability scope is limited to metrics collection, storage, and dashboards only.

23. Logs, tracing, and alerting are out of scope unless needed as an implementation detail.

24. For a future production-oriented version of the platform, Vault should be used instead of Sealed Secrets, but that is out of scope for the current lab implementation.

25. Sealed Secrets key material must be preserved and reused across lab cluster rebuilds so existing encrypted secrets remain valid.

26. Initial public access to the inference endpoint must be provided without TLS through `NodePort` on `infra-1`, using the public IP of `infra-1` and token-based authentication through LiteLLM.

27. There is no hard budget limit; infrastructure sizing should be based on stable cluster operation and successful model serving.

28. The model source must use the Hugging Face repository `Qwen/Qwen3.5-27B-GPTQ-Int4`, pinned in the repository and operator documentation.

29. The current repository is the main deployment and GitOps repository for this project.

30. VictoriaMetrics retention must be set to 7 days for the lab environment.

31. Pinned component versions in the repository plus a reproducible initial bootstrap are sufficient; a full upgrade workflow is out of scope.

32. Final inference validation is a simple smoke test through LiteLLM with a short prompt, `HTTP 200`, a non-empty generated text field, and no infrastructure or runtime error in the response.

33. LiteLLM authentication must use LiteLLM native API keys, without an external auth proxy and without Istio AuthorizationPolicy as the primary auth mechanism.

34. Required VictoriaMetrics scrape targets and dashboard coverage must include:
   - kube-state-metrics
   - node-exporter
   - Kubernetes control plane metrics
   - cAdvisor and kubelet metrics
   - Cilium
   - Istio
   - ArgoCD
   - LiteLLM
   - KServe and vLLM

35. VictoriaMetrics persistent storage size must be 100Gi on the infra node.

36. The smoke test prompt may be a short neutral request such as: "Напиши одно короткое предложение о Kubernetes."

37. Final documentation must include:
   - a README with step-by-step deployment instructions
   - verification commands
   - a sample LiteLLM smoke-test request
   - a sample successful response
   - screenshots are not required

38. Recommended VM sizing is elevated to an explicit requirement for the lab environment:
   - each control-plane node must have 4 vCPU, 16 GB RAM, and 100 GB SSD
   - the infra node must have 8 vCPU, 32 GB RAM, and 200 GB SSD
   - each GPU worker node must have 1x NVIDIA A5000 GPU, 16 vCPU, 64 GB RAM, and 500 GB SSD

39. Components that are only conditionally required by the selected KServe, Knative, or Istio versions, including `cert-manager`, are not mandatory business requirements unless the chosen implementation actually depends on them.

40. Lab performance requirements for acceptance are:
   - the model serving workload must become ready within 30 minutes after deployment starts
   - the documented LiteLLM smoke test must return a successful response within 60 seconds
   - the acceptance concurrency target is 1 client request at a time
   - the acceptance prompt-size scope is limited to the documented smoke-test prompt

41. Storage ownership for the lab environment is:
   - model artifacts: S3
   - VictoriaMetrics data: OpenEBS LocalPV
   - Sealed Secrets key reuse material: preserved outside Git and restored during cluster rebuild
   - ArgoCD state: ephemeral; no PVC-backed ArgoCD features are in scope for the current lab implementation
   - temporary model cache or download workspace: ephemeral unless explicitly configured otherwise

42. GPU resource discovery for the lab environment must use host-installed NVIDIA drivers, NVIDIA container runtime support, and the NVIDIA Device Plugin. NVIDIA GPU Operator is out of scope.

43. The phase-1 LiteLLM upstream contract is:
   - LiteLLM calls one internal HTTP service
   - that service exposes an OpenAI-compatible `/v1/chat/completions` API
   - LiteLLM uses one pinned model alias for the deployed Qwen model
   - the smoke test uses only that pinned model alias

44. The repository must contain a pinned dependency matrix that declares the selected versions of core platform components and any conditionally enabled dependencies for the chosen version set.

## Implementation Risks

1. Cloud provider and region are still unspecified.
Why this is a risk: provisioning of servers is out of scope for the agent, but provider capabilities still affect ingress design, firewall assumptions, S3 endpoint specifics, and operational guidance.

2. The selected KServe, Knative, and vLLM versions may still impose runtime-specific constraints.
Why this is a risk: the phase-1 topology is fixed, but version compatibility can still affect operational behavior and dependency selection.

3. The selected model artifact and vLLM version may still have runtime-specific compatibility constraints.
Why this is a risk: even with a pinned Hugging Face source, practical startup behavior can still depend on the exact vLLM and serving-stack versions.

4. LiteLLM API key configuration and secret-delivery flow still need correct implementation.
Why this is a risk: the authentication mechanism has been selected, but a misconfigured secret flow would still break public inference access.

5. Non-functional requirements are only partially defined.
Why this is a risk: the environment type is now defined as lab, but only the minimum acceptance-level performance targets are fixed.

## Missing Information

No unresolved missing information remains. The remaining implementation risks are technical validation items, not requirement gaps.

## Implicit Assumptions

1. The cloud provider offers VM-based GPU instances with NVIDIA A5000 and supports the needed quotas.

2. The user can provision all 6 required VMs manually.

3. The nodes can communicate reliably enough over public IP networking for Kubernetes control-plane and workload traffic, or equivalent firewall rules will be configured to allow it.

4. Ubuntu 24.04 and containerd are acceptable standards for all nodes.

5. Kubespray is acceptable as the cluster bootstrap mechanism.

6. A one-time non-GitOps bootstrap for ArgoCD is allowed.

7. OpenEBS LocalPV is acceptable despite node-local failure semantics.

8. S3 storage is sufficiently compatible with the access pattern required by KServe/model download jobs.

9. The selected Qwen 3.5 variant can be served by vLLM in an acceptable first-stage configuration on the available hardware.

10. Multi-node or multi-GPU serving across two GPU nodes is deferred, not mandatory for phase 1.

11. Internet egress from the cluster is available for package installation, image pulls, and possibly model downloads.

12. The agent is allowed to install drivers, NVIDIA runtime components, and cluster add-ons on remote hosts.

13. LiteLLM can act as the only public-facing inference entry point while the underlying model-serving components remain internal to the cluster.

14. VictoriaMetrics k8s stack is acceptable instead of Prometheus/Grafana-based monitoring suggestions in the original discussion.

15. Sealed Secrets is acceptable as the cluster secret management mechanism for this lab environment.

16. The inference endpoint will be exposed through `NodePort` on `infra-1`, without a custom domain.

17. LiteLLM native authentication is acceptable as the token-based protection mechanism.

18. Observability requirements are intentionally limited to metrics and dashboards.

19. Vault remains the expected secret-management direction for a future production-grade version, but not for this lab scope.

20. Initial HTTP-only exposure without TLS is acceptable for the lab environment.

21. The current cloud environment permits external access to a `NodePort`-based ingress path on `infra-1`.

22. `Qwen/Qwen3.5-27B-GPTQ-Int4` is assumed to be the target artifact for vLLM-based deployment.

## Edge Cases

1. Only one GPU node is available initially or one GPU node fails after deployment.
Impact: model scheduling and tensor-parallel serving may become impossible.

2. A5000 quota exists but instances are not available in the chosen zone.
Impact: automation may fail after partial provisioning.

3. OpenEBS LocalPV places state on a node that later becomes unavailable.
Impact: ArgoCD, Prometheus, or any stateful component may require manual recovery.

4. KServe and vLLM do not support the selected model format/version combination.
Impact: the chosen model may need repackaging or a different runtime path.

5. Multi-node inference support is more complex than assumed.
Impact: a design using Ray/LeaderWorkerSet may be required instead of a simple InferenceService.

6. S3 credentials or endpoint configuration differ from AWS defaults.
Impact: storage initializer or model pull jobs may fail without custom secret/configuration.

7. External access to the selected `NodePort` on `infra-1` is blocked by firewall or provider networking policy.
Impact: the public inference endpoint will not be reachable even if the cluster is otherwise healthy.

8. Cluster bootstrap partially succeeds and reruns are needed.
Impact: automation must be idempotent and safe to reapply.

9. The model fits into VRAM for startup but runtime KV-cache requirements exceed capacity under target context/concurrency.
Impact: service instability or OOM during inference.

10. GPU operator/device plugin/drivers are version-incompatible with the chosen kernel or Kubernetes version.
Impact: nodes may join cluster but not expose `nvidia.com/gpu`.

11. Private registry or package mirror access is restricted.
Impact: dependency installation and image pulls may fail in otherwise correct manifests.

12. Security constraints require private-only endpoints.
Impact: ArgoCD and inference ingress design changes significantly.

13. LiteLLM and KServe API/protocol expectations do not match out of the box.
Impact: an adapter pattern, OpenAI-compatible routing assumptions, or custom LiteLLM configuration may be required.

14. VictoriaMetrics storage on LocalPV is undersized for default scrape volume.
Impact: observability stack may become unstable or exhaust disk unless retention and resource limits are tuned for lab use.

## Clarifying Questions

No remaining clarifying questions at the requirements level.

## Recommended First Question

No further stakeholder clarification is required before starting implementation.
