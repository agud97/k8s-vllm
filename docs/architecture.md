# Architecture

## Current Lab Topology

```mermaid
flowchart TB
  internet[Internet / Operator]

  subgraph cluster[Non-managed Kubernetes Cluster]
    subgraph cp[Control Plane Nodes]
      cp1[cp-1]
      cp2[cp-2]
      cp3[cp-3]
    end

    subgraph infra[infra-1]
      argocd[ArgoCD]
      istio[Istio IngressGateway]
      litellm[LiteLLM]
      openwebui[Open WebUI]
      sealed[Sealed Secrets]
      vm[VictoriaMetrics]
    end

    subgraph sxm[sxmgpu\n8x H200]
      qwen122[qwen35-122b\nTP=2\nvLLM runtime]
      minimax[minimax-m25\nTP=4\nvLLM runtime]
      coder[qwen3-coder\nTP=2\nvLLM runtime]
    end

    knative[Knative Serving]
    kserve[KServe]
    cilium[Cilium CNI]
    openebs[OpenEBS LocalPV]
  end

  subgraph external[External Systems]
    github[GitHub Repo\nagud97/k8s-vllm]
    s3[S3 Bucket\nmodel artifacts]
    hf[Hugging Face\nsource models]
  end

  internet -->|NodePort 32081| openwebui
  internet -->|NodePort 32080| istio
  istio --> litellm
  openwebui -->|OpenAI-compatible API| litellm
  litellm -->|public fallback /v1| qwen122
  litellm -->|public fallback /v1| minimax
  litellm -->|public fallback /v1| coder

  argocd --> github
  argocd --> istio
  argocd --> knative
  argocd --> kserve
  argocd --> litellm
  argocd --> openwebui
  argocd --> vm
  argocd --> openebs
  argocd --> sealed

  hf -->|bootstrap/model-sync.sh| s3
  s3 -->|model pull| qwen122
  s3 -->|model pull| minimax
  s3 -->|model pull| coder

  cilium --- cp1
  cilium --- cp2
  cilium --- cp3
  cilium --- infra
  cilium --- sxm
  openebs --- vm
```

## Request Paths

- Public inference: `Internet -> NodePort 32080 -> Istio -> LiteLLM -> model-specific KServe/vLLM predictor`
- Public UI: `Internet -> NodePort 32081 -> Open WebUI -> LiteLLM -> predictor`
- GitOps control: `ArgoCD -> GitHub repository -> platform/apps reconciliation`
- Model supply: `Hugging Face -> S3 sync -> KServe storage initializer -> GPU nodes`

## Node Roles

- `cp-1`, `cp-2`, `cp-3`: Kubernetes control plane and `etcd`
- `infra-1`: ingress, GitOps, API gateway, UI, metrics
- `sxmgpu`: `qwen35-122b`, `minimax-m25`, `qwen3-coder`

## Serving Layout

- `LiteLLM` is the only public inference entrypoint.
- `Open WebUI` uses internal `LiteLLM`, not direct model backends.
- Each model is exposed through one OpenAI-compatible vLLM endpoint and one GitOps-managed public fallback `NodePort` on `sxmgpu`.
- Current serving is non-distributed but multi-GPU within a single node: `TP=2` for `qwen35-122b`, `TP=4` for `minimax-m25`, and `TP=2` for `qwen3-coder`.
