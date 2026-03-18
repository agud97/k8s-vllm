# Sealed Secrets Runbook

## Purpose

This lab uses Sealed Secrets for GitOps-compatible secret delivery.

## Controller Installation

- The controller is installed by `bootstrap/sealed-secrets-bootstrap.sh`.
- The version is pinned in [`docs/dependency-matrix.yaml`](/root/codex/k8s-cloud/docs/dependency-matrix.yaml).

## Key Preservation

The Sealed Secrets controller private key must not be stored in Git.

Recommended lab workflow:

1. Export the controller secret after bootstrap:
   - `kubectl -n kube-system get secret -l sealedsecrets.bitnami.com/sealed-secrets-key=active -o yaml > local/sealed-secrets-key.backup.yaml`
2. Keep that backup outside Git.
3. On cluster rebuild, restore it before applying sealed secrets:
   - `kubectl apply -f local/sealed-secrets-key.backup.yaml`

## Validation

- Controller pod is running in `kube-system`
- Existing sealed secrets decrypt after key restore
- No plaintext application secrets are committed to Git
