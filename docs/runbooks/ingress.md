# Ingress Runbook

## Phase-1 Public Inference Path

- Entry point: `http://<infra-1-public-ip>:32080`
- Exposure model: `NodePort`
- Traffic path: public client -> `infra-1` -> Istio ingress gateway -> internal LiteLLM service

## Scope

- HTTP only
- No custom domain
- No public TLS in the current lab scope
- ArgoCD remains private and accessed only through port-forward
