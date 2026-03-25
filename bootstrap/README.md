# Bootstrap

One-time and rerunnable orchestration entrypoints for preparing hosts, bootstrapping the cluster, and driving validation workflows.

Operator note:

- the live `sxmgpu` onboarding exposed several replacement-specific recovery steps that are documented in [`docs/runbooks/gpu-node-replacement.md`](../docs/runbooks/gpu-node-replacement.md); use that runbook for future GPU node additions or replacements
- NVSwitch-based GPU hosts need extra post-driver validation; `gpu-prep` now installs `nvidia-fabricmanager`, verifies `nvidia-smi -q` fabric status, and only treats GPU prep as complete after fabric activation succeeds
- cluster DNS domain must be treated as inventory-owned configuration rather than assumed as `cluster.local`; GitOps manifests that build in-cluster FQDNs, especially VictoriaMetrics and Grafana datasources, must match [`inventory/group_vars/k8s_cluster.yml`](../inventory/group_vars/k8s_cluster.yml)
