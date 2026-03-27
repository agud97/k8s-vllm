# Acceptance Criteria

## Cluster Bootstrap And Topology

1. WHEN the stakeholder has manually created six reachable Ubuntu 24.04 virtual machines with SSH access and the repository bootstrap instructions are executed, THEN the deployment workflow is started from the current repository, SHALL provision a non-managed Kubernetes cluster with exactly 3 control-plane nodes, 2 GPU worker nodes, and 1 infra node.

2. WHEN the cluster bootstrap completes successfully, THEN the Kubernetes cluster state is inspected, SHALL show all intended nodes in `Ready` state.

2a. WHEN the agent claims phase-1 or final completion, THEN the live target environment is inspected, SHALL contain an actually running Kubernetes cluster on the provided six virtual machines and SHALL not be accepted based on repository artifacts alone.

3. WHEN the infrastructure prerequisites are reviewed before bootstrap, THEN the provisioned virtual machines are inspected, SHALL satisfy the role-specific sizing requirements defined in the requirements document.

4. WHEN the cluster bootstrap completes successfully, THEN the cluster network is inspected, SHALL show Cilium installed and operating as the active CNI.

5. WHEN the cluster bootstrap completes successfully, THEN the service mesh components are inspected, SHALL show Istio installed and its control-plane components healthy.

6. WHEN the bootstrap workflow is re-run against an already configured environment, THEN the same bootstrap command is executed again, SHALL complete without destructive rollback of the intended cluster state and SHALL preserve the managed topology.

7. WHEN one or more required hosts are missing or unreachable before bootstrap, THEN the bootstrap workflow is executed, SHALL fail with an observable error identifying that host reachability or inventory prerequisites are not satisfied.

8. WHEN a previous bootstrap attempt failed partway through, THEN the bootstrap workflow is executed again on the same environment, SHALL resume or reconcile safely without requiring destructive cleanup as a prerequisite.

8a. WHEN a GPU worker is replaced after the initial bootstrap, THEN the documented node-replacement workflow is executed, SHALL add the replacement worker to the live cluster without requiring destruction of the control plane or a full cluster rebuild.

8b. WHEN a replacement GPU worker is declared ready for serving use, THEN live Cilium health and workload reachability are inspected, SHALL demonstrate either healthy cross-node pod networking to the GPU worker or an explicitly documented GitOps-managed public-endpoint fallback for serving and GPU telemetry.

## GitOps And Repository Behavior

9. WHEN the repository is inspected before deployment, THEN the operator reviews the repository contents, SHALL find deployment automation, GitOps manifests, pinned component versions, and operator-facing instructions in the same repository.

10. WHEN ArgoCD bootstrap is executed after cluster creation, THEN ArgoCD is installed once outside GitOps, SHALL become operational and capable of reconciling the repository-managed platform resources.

11. WHEN ArgoCD has been bootstrapped and repository synchronization is enabled, THEN the managed applications are reconciled, SHALL result in ArgoCD self-management and GitOps management of in-cluster platform components.

11a. WHEN final acceptance is evaluated, THEN the live cluster is inspected, SHALL show that ArgoCD is actually installed in the cluster and not merely described in manifests or scripts.

12. WHEN a managed manifest in the repository is changed to a valid desired state, THEN ArgoCD reconciliation occurs, SHALL converge the cluster toward that desired state without requiring manual in-cluster edits.

13. WHEN the repository contains pinned versions for platform components, THEN the operator reviews the manifests and values, SHALL find explicit version pinning for the deployed stack instead of floating latest-version references where pinning is expected.

13a. WHEN the repository is reviewed for implementation metadata, THEN it SHALL contain a pinned dependency matrix declaring the selected platform versions and any conditionally enabled dependencies for the chosen version set.

## Secrets Management

14. WHEN the lab environment is deployed, THEN the cluster secret-management components are inspected, SHALL show Sealed Secrets deployed as the secret-management mechanism for this environment.

15. WHEN a required application secret is stored in Git for deployment, THEN the repository content is reviewed, SHALL contain the secret only in sealed form and not as plaintext Kubernetes Secret data.

16. WHEN the lab cluster is rebuilt and the preserved Sealed Secrets key material is restored, THEN previously committed sealed secrets are applied again, SHALL decrypt successfully into usable Kubernetes Secrets without requiring resealing.

17. WHEN the Sealed Secrets controller or key material is absent during secret reconciliation, THEN sealed secrets are applied, SHALL fail observably rather than producing silent partial secret injection.

## Access And Exposure

18. WHEN the cluster platform is fully reconciled, THEN external exposure is inspected, SHALL show that ArgoCD UI is not publicly exposed and is reachable only through port-forward access.

19. WHEN the inference entrypoint is inspected after deployment, THEN public access configuration is reviewed, SHALL expose inference through LiteLLM on `NodePort` at the public IP of `infra-1`.

20. WHEN the public inference endpoint is called without an API key, THEN a client request is sent to LiteLLM, SHALL be rejected with an authorization failure response.

21. WHEN the public inference endpoint is called with an invalid API key, THEN a client request is sent to LiteLLM, SHALL be rejected with an authorization failure response.

22. WHEN the public inference endpoint is called with a valid LiteLLM API key, THEN a supported inference request is sent, SHALL be accepted and routed through LiteLLM to the underlying model-serving path.

22a. WHEN the active LiteLLM aliases are called through the documented client path, THEN the returned assistant message SHALL follow the intended UX for that model and SHALL not fail with infrastructure or routing errors caused by missing aliases or broken upstream endpoint selection.

23. WHEN the deployed lab environment is inspected for transport settings, THEN the public inference endpoint configuration is reviewed, SHALL permit initial HTTP access without requiring TLS or a custom DNS name.

24. WHEN the active inference integration is inspected, THEN the LiteLLM upstream configuration is reviewed, SHALL reference exactly three OpenAI-compatible upstream endpoints provided by the serving stack.

24a. WHEN the active inference integration is inspected, THEN the LiteLLM upstream configuration is reviewed, SHALL target an HTTP endpoint exposing `/v1/chat/completions`, using the repository-managed public-fallback topology whenever private east-west reachability to `sxmgpu` is unavailable.

24b. WHEN the LiteLLM model configuration is inspected, THEN the configured models are reviewed, SHALL define pinned model aliases for `qwen-122b`, `minimax-m25`, and `qwen-coder`, and the default smoke test SHALL use `default`.

24c. WHEN the LiteLLM admin UI is opened after deployment, THEN the operator logs in with the documented internal `email/password`, SHALL reach the UI successfully and SHALL not receive `Authentication Error, Not connected to DB!`.

24d. WHEN the LiteLLM admin UI auth path is inspected after deployment, THEN the live cluster resources are reviewed, SHALL show a healthy in-cluster database backing LiteLLM internal users.

24e. WHEN the documented LiteLLM UI bootstrap flow is executed, THEN the LiteLLM internal user-management API is inspected, SHALL show that the seeded admin user exists with the configured email and role.

25. WHEN the selected `NodePort` on `infra-1` is blocked by firewall or provider networking, THEN external inference validation is executed, SHALL fail with an observable endpoint reachability error.

## Model Serving

26. WHEN the platform components are reconciled successfully, THEN the model-serving stack is inspected, SHALL show KServe and vLLM components deployed in the cluster.

26a. WHEN final acceptance is evaluated, THEN the live cluster is inspected, SHALL show that KServe, LiteLLM, and VictoriaMetrics are actually installed and reconciled in the cluster rather than only present in the repository.

27. WHEN the deployment configuration is inspected, THEN the model source definition is reviewed, SHALL reference `Qwen/Qwen3.5-122B-A10B-FP8`, `MiniMaxAI/MiniMax-M2.5`, and `Qwen/Qwen3-Coder-Next` as the pinned model sources.

28. WHEN the selected KServe, Knative, or Istio implementation requires additional dependencies such as `cert-manager`, THEN the deployed platform is inspected, SHALL match the conditionally enabled dependencies declared in the repository dependency matrix.

29. WHEN the current lab-serving configuration is applied, THEN the runtime topology is inspected, SHALL use three single-replica, non-distributed `KServe InferenceService` deployments co-located on the active `8x H200` GPU node with the repository-declared `2+4+2` GPU split, without requiring true multi-node inference across multiple GPU nodes.

30. WHEN the target model deployments reach a healthy state, THEN Kubernetes workload resources are inspected, SHALL show the serving workloads scheduled only onto GPU-capable nodes.

31. WHEN the target model deployments reach a healthy state, THEN cluster GPU resources are inspected, SHALL show NVIDIA GPU capacity discoverable by Kubernetes workloads.

31a. WHEN the GPU discovery components are inspected in the lab environment, THEN the platform configuration is reviewed, SHALL use the NVIDIA Device Plugin and SHALL not depend on NVIDIA GPU Operator.

31b. WHEN a replacement GPU worker is onboarded in an environment where control-plane private IPs are not reachable from that worker, THEN the bootstrap and recovery workflow is executed, SHALL provide a documented and working API access path for the replacement worker and SHALL still result in discoverable `nvidia.com/gpu` capacity.

31c. WHEN an NVSwitch-based GPU worker such as an `8x H200` host is onboarded, THEN post-install validation is executed, SHALL confirm successful fabric initialization and SHALL not accept the node as ready for CUDA workloads based on `nvidia-smi -L` alone.

32. WHEN the cluster is asked to serve inference after the model is reported ready, THEN a smoke-test request is sent through LiteLLM, SHALL return `HTTP 200`, a non-empty generated text field, and no infrastructure or runtime error in the response.

33. WHEN the smoke-test request uses a short neutral prompt such as "Напиши одно короткое предложение о Kubernetes.", THEN the request is processed by the deployed model, SHALL return non-empty model-generated text rather than an infrastructure error.

34. WHEN model startup fails because a selected artifact or runtime setting is incompatible with vLLM, THEN the deployment attempt occurs, SHALL fail observably instead of reporting that model as successfully ready.

35. WHEN only one GPU node is available or one GPU node becomes unavailable before a GPU-dependent serving deployment, THEN the serving workloads are reconciled, SHALL not falsely report a healthy ready state if the required GPU scheduling constraints cannot be met.

36. WHEN the phase-1 model deployment is started in an otherwise healthy cluster, THEN readiness is measured from deployment start, SHALL reach the documented ready state within 30 minutes.

37. WHEN the documented LiteLLM smoke test is executed against a ready deployment, THEN response time is measured from request start, SHALL complete successfully within 60 seconds.

38. WHEN acceptance testing is performed for inference behavior, THEN the test workload is applied, SHALL assume a concurrency target of 1 client request at a time.

39. WHEN the S3 credentials or endpoint configuration are invalid, THEN model synchronization or serving initialization is attempted, SHALL fail observably with a storage access error.

40. WHEN model artifacts cannot be downloaded or synchronized from the configured S3 location, THEN the model deployment workflow runs, SHALL fail observably and SHALL not report the serving workload as ready.

41. WHEN GPU resource discovery is missing or `nvidia.com/gpu` is not exposed on the target nodes, THEN the GPU-dependent serving workload is reconciled, SHALL remain unready with an observable scheduling or runtime error.

## Storage Behavior

42. WHEN platform storage configuration is inspected, THEN model artifact storage settings are reviewed, SHALL support the use of external S3-backed model artifacts.

43. WHEN stateful in-cluster components requiring persistent volumes are deployed in the lab environment, THEN their storage classes are inspected, SHALL use OpenEBS LocalPV for persistent storage where configured in this environment.

43a. WHEN LiteLLM admin UI auth persistence is enabled for the lab environment, THEN the backing Postgres workload is inspected, SHALL use OpenEBS LocalPV for its persistent volume.

44. WHEN the VictoriaMetrics stack is deployed, THEN its persistent volume claims are inspected, SHALL request 100Gi of persistent storage.

45. WHEN the Sealed Secrets key management approach is inspected for the lab environment, THEN the bootstrap and recovery documentation are reviewed, SHALL preserve the reusable Sealed Secrets key material outside Git for cluster rebuild.

46. WHEN ArgoCD deployment state is inspected for the lab environment, THEN its configuration is reviewed, SHALL not use PVC-backed persistence and SHALL not include PVC-backed ArgoCD features in current lab scope.

47. WHEN temporary model download or cache storage is inspected, THEN the serving and synchronization configuration are reviewed, SHALL treat that workspace as ephemeral unless explicitly configured otherwise.

48. WHEN the lab environment is inspected for backup behavior, THEN operational documentation and manifests are reviewed, SHALL not require backup workflows as a condition of acceptance.

49. WHEN VictoriaMetrics persistent volume provisioning fails or the requested storage is unavailable, THEN the observability stack is reconciled, SHALL fail observably and SHALL not be reported healthy.

## Observability

50. WHEN the observability stack is reconciled, THEN the cluster monitoring components are inspected, SHALL show VictoriaMetrics Kubernetes stack deployed in the same cluster.

51. WHEN the deployed observability configuration is reviewed, THEN retention settings are inspected, SHALL set VictoriaMetrics retention to 7 days.

52. WHEN the observability stack is healthy, THEN metrics targets are inspected, SHALL collect metrics for kube-state-metrics, node-exporter, Kubernetes control plane, cAdvisor or kubelet, Cilium, Istio, ArgoCD, LiteLLM, and KServe or vLLM.

52a. WHEN GPU observability is reviewed after deployment, THEN the live cluster resources are inspected, SHALL show a GPU metrics exporter running on active GPU worker nodes and exposing scrapeable NVIDIA telemetry to the observability stack.

52b. WHEN the active GPU worker is reachable only through the public-endpoint fallback path, THEN the observability stack is reviewed, SHALL scrape GPU telemetry successfully through the GitOps-managed public target rather than depending on broken cross-node pod-network access.

53. WHEN the operator opens the observability dashboards, THEN dashboard coverage is reviewed, SHALL provide dashboard coverage for these monitored areas: cluster nodes, Kubernetes workloads, Kubernetes control plane, Cilium, Istio, ArgoCD, LiteLLM, and KServe or vLLM.

53a. WHEN the observability dashboards are opened after reconciliation, THEN the Grafana datasources are exercised, SHALL resolve the in-cluster VictoriaMetrics service using the actual cluster DNS domain rather than a hard-coded `cluster.local` assumption.

54. WHEN the observability deliverable is inspected, THEN the deployed scope is reviewed, SHALL include metrics and dashboards and SHALL not require alerting, tracing, or centralized logging for acceptance.

## Documentation And Operator Experience

55. WHEN the final repository is delivered, THEN the README is reviewed, SHALL contain step-by-step deployment instructions for bringing the environment up after the VMs are created and SSH access is available.

56. WHEN the final repository is delivered, THEN the documentation is reviewed, SHALL describe an execution path that is as close as possible to one command for bootstrap after manual VM creation.

57. WHEN the final documentation is reviewed, THEN it SHALL include verification commands for cluster health, ArgoCD status, and inference validation.

57a. WHEN the final documentation is reviewed for recovery coverage, THEN it SHALL include a GPU node replacement runbook covering worker join, Cilium recovery, NVIDIA runtime recovery, and stale-node removal.

57b. WHEN the final documentation is reviewed for repeatability, THEN it SHALL explain the difference between public-IP worker join and private-IP east-west cluster reachability, and SHALL document the active public-fallback serving topology plus the model alias contract exported through LiteLLM.

57c. WHEN the final documentation is reviewed for operator access, THEN it SHALL document the LiteLLM admin UI URL, the DB-backed login flow, required local variables, and the command that seeds or updates the admin user.

58. WHEN the final documentation is reviewed, THEN it SHALL include a sample LiteLLM smoke-test request and a sample successful response.

59. WHEN the final documentation package is reviewed, THEN it SHALL not depend on screenshots as a required acceptance artifact.

60. WHEN the final handoff is reviewed, THEN the deployment evidence is inspected, SHALL include the actual final inference endpoint address and the actual commands used to validate the live cluster.

61. WHEN the final handoff is reviewed, THEN the live environment is validated, SHALL pass cluster health checks, ArgoCD health checks, application reconciliation checks, and the documented smoke test without requiring the reviewer to perform the initial deployment for the agent.
