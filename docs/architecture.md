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

    subgraph gpu1[gpu-1]
      gptoss[gpt-oss-20b\nKServe InferenceService\nvLLM runtime]
    end

    subgraph gpu2[gpu-2]
      qwen[qwen35-9b\nKServe InferenceService\nvLLM runtime]
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
  litellm -->|/v1/chat/completions| gptoss
  litellm -->|/v1/chat/completions| qwen

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
  s3 -->|model pull| gptoss
  s3 -->|model pull| qwen

  cilium --- cp1
  cilium --- cp2
  cilium --- cp3
  cilium --- infra
  cilium --- gpu1
  cilium --- gpu2
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
- `gpu-1`: `gpt-oss-20b`
- `gpu-2`: `qwen35-9b`

## Serving Layout

- `LiteLLM` is the only public inference entrypoint.
- `Open WebUI` uses internal `LiteLLM`, not direct model backends.
- Each model is exposed internally through one OpenAI-compatible vLLM endpoint.
- Phase-1 serving is non-distributed: one model per GPU node.
