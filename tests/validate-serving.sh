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
  grep -q '/v1/chat/completions' gitops/apps/litellm/configmap.yaml || { printf 'LiteLLM upstream path missing /v1/chat/completions contract\n' >&2; exit 1; }
  grep -q 'qwen35-27b-gptq-int4' gitops/apps/litellm/configmap.yaml || { printf 'pinned model alias missing\n' >&2; exit 1; }
  printf 'litellm manifest validation passed\n'
}

check_runtime_manifests() {
  grep -q 'Qwen/Qwen3.5-27B-GPTQ-Int4' docs/runbooks/model-artifacts.md || { printf 'pinned Hugging Face source missing\n' >&2; exit 1; }
  grep -q 'runtime: vllm-runtime' gitops/apps/llm-serving/inference-service.yaml || { printf 'InferenceService runtime missing\n' >&2; exit 1; }
  printf 'runtime manifest validation passed\n'
}

check_cluster_runtime() {
  need_cmd kubectl
  kubectl -n llm get inferenceservice qwen35-27b-gptq-int4 >/tmp/inferenceservice.txt
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
