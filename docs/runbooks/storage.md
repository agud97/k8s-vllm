# Storage Runbook

## Lab Storage Matrix

- Model artifacts: S3
- VictoriaMetrics data: OpenEBS LocalPV
- Sealed Secrets key reuse material: backed up outside Git
- ArgoCD state: ephemeral in current lab scope
- Temporary model cache: ephemeral unless explicitly configured otherwise

## OpenEBS LocalPV

- Intended for local persistent volumes in the lab cluster
- Node-local by design; data is not replicated
- Use for VictoriaMetrics and other explicitly stateful lab components that tolerate node locality

## Storage Class

- Name: `openebs-hostpath`
- Binding mode: `WaitForFirstConsumer`
- Base path: `/var/openebs/local`
