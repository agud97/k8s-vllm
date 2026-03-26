#!/usr/bin/env bash
set -euo pipefail

need_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    printf 'missing required command: %s\n' "$cmd" >&2
    exit 1
  fi
}

check_s3_config() {
  [[ -f local/s3.env ]] || { printf 'missing required file: local/s3.env\n' >&2; exit 1; }
  grep -q '^S3_BUCKET=' local/s3.env || { printf 'S3_BUCKET missing in local/s3.env\n' >&2; exit 1; }
  grep -q '^S3_PREFIX=' local/s3.env || { printf 'S3_PREFIX missing in local/s3.env\n' >&2; exit 1; }
  printf 's3 config validation passed\n'
}

check_litellm_manifests() {
  grep -q ':32090/v1' gitops/apps/litellm/configmap.yaml || { printf 'qwen-122b upstream api_base missing\n' >&2; exit 1; }
  grep -q 'qwen-122b' gitops/apps/litellm/configmap.yaml || { printf 'qwen-122b alias missing\n' >&2; exit 1; }
  grep -q 'model_name: default' gitops/apps/litellm/configmap.yaml || { printf 'default alias missing\n' >&2; exit 1; }
  printf 'litellm manifest validation passed\n'
}

check_runtime_manifests() {
  grep -q 'Qwen/Qwen3.5-122B-A10B-FP8' docs/runbooks/model-artifacts.md || { printf 'Qwen3.5-122B-A10B-FP8 source missing\n' >&2; exit 1; }
  grep -q 'MiniMaxAI/MiniMax-M2.5' docs/runbooks/model-artifacts.md || { printf 'MiniMax-M2.5 source missing\n' >&2; exit 1; }
  grep -q 'Qwen/Qwen3-Coder-Next' docs/runbooks/model-artifacts.md || { printf 'Qwen3-Coder-Next source missing\n' >&2; exit 1; }
  grep -q 'hostIPC: true' gitops/platform/kserve/cluster-serving-runtime.yaml || { printf 'shared runtime hostIPC missing\n' >&2; exit 1; }
  grep -q 'sizeLimit: 32Gi' gitops/platform/kserve/cluster-serving-runtime.yaml || { printf 'shared runtime /dev/shm sizing missing\n' >&2; exit 1; }
  grep -q 'qwen35-122b-model-cache' gitops/apps/llm-serving/model-cache-pvc.yaml || { printf 'Qwen 122B cache pvc missing\n' >&2; exit 1; }
  grep -q 'minimax-m25-model-cache' gitops/apps/llm-serving/model-cache-pvc.yaml || { printf 'MiniMax cache pvc missing\n' >&2; exit 1; }
  grep -q 'qwen3-coder-model-cache' gitops/apps/llm-serving/model-cache-pvc.yaml || { printf 'Qwen coder cache pvc missing\n' >&2; exit 1; }
  grep -q 'runtime: vllm-openai-runtime' gitops/apps/llm-serving/inference-service-qwen35-122b.yaml || { printf 'Qwen 122B InferenceService runtime missing\n' >&2; exit 1; }
  grep -q 'runtime: vllm-openai-runtime' gitops/apps/llm-serving/inference-service-minimax-m25.yaml || { printf 'MiniMax InferenceService runtime missing\n' >&2; exit 1; }
  grep -q 'runtime: vllm-openai-runtime' gitops/apps/llm-serving/inference-service-qwen3-coder.yaml || { printf 'Qwen coder InferenceService runtime missing\n' >&2; exit 1; }
  grep -q 'mountPath: /mnt/models' gitops/apps/llm-serving/inference-service-qwen35-122b.yaml || { printf 'Qwen 122B local model mount missing\n' >&2; exit 1; }
  printf 'runtime manifest validation passed\n'
}

check_cluster_runtime() {
  need_cmd kubectl
  kubectl -n llm get inferenceservice qwen35-122b >/tmp/inferenceservice-qwen35-122b.txt
  kubectl -n llm get inferenceservice minimax-m25 >/tmp/inferenceservice-minimax-m25.txt
  kubectl -n llm get inferenceservice qwen3-coder >/tmp/inferenceservice-qwen3-coder.txt
  kubectl -n llm get deploy litellm >/tmp/litellm_deploy.txt
  kubectl -n llm get svc litellm >/tmp/litellm_svc.txt
  printf 'cluster serving validation passed\n'
}

mode="${1:-static}"
case "$mode" in
  static)
    check_s3_config
    check_litellm_manifests
    check_runtime_manifests
    ;;
  runtime)
    check_cluster_runtime
    ;;
  all)
    check_s3_config
    check_litellm_manifests
    check_runtime_manifests
    check_cluster_runtime
    ;;
  *)
    printf 'unknown validation mode: %s\n' "$mode" >&2
    exit 1
    ;;
esac
