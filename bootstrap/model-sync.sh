#!/usr/bin/env bash
set -euo pipefail

need_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    printf 'missing required command: %s\n' "$cmd" >&2
    exit 1
  fi
}

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
S3_ENV_FILE="${ROOT_DIR}/local/s3.env"
WORKDIR="${ROOT_DIR}/bootstrap/cache/model-sync"
MODEL_REPOS=(
  "Qwen/Qwen3.5-122B-A10B-FP8"
  "MiniMaxAI/MiniMax-M2.5"
  "Qwen/Qwen3-Coder-Next"
)

[[ -f "$S3_ENV_FILE" ]] || { printf 'missing required file: %s\n' "$S3_ENV_FILE" >&2; exit 1; }

need_cmd python3
need_cmd aws

# shellcheck disable=SC1090
source "$S3_ENV_FILE"

: "${S3_ENDPOINT:?missing S3_ENDPOINT in local/s3.env}"
: "${S3_BUCKET:?missing S3_BUCKET in local/s3.env}"
: "${S3_ACCESS_KEY_ID:?missing S3_ACCESS_KEY_ID in local/s3.env}"
: "${S3_SECRET_ACCESS_KEY:?missing S3_SECRET_ACCESS_KEY in local/s3.env}"
: "${S3_PREFIX:?missing S3_PREFIX in local/s3.env}"

export AWS_ACCESS_KEY_ID="${S3_ACCESS_KEY_ID}"
export AWS_SECRET_ACCESS_KEY="${S3_SECRET_ACCESS_KEY}"
export AWS_DEFAULT_REGION="${S3_REGION:-us-east-1}"
export AWS_EC2_METADATA_DISABLED=true

mkdir -p "$WORKDIR"

printf '[phase] model-sync\n'
printf '[destination] s3://%s/%s/\n' "$S3_BUCKET" "$S3_PREFIX"

python3 -m venv "${WORKDIR}/venv"
# shellcheck disable=SC1091
source "${WORKDIR}/venv/bin/activate"
python3 -m pip install --quiet --upgrade pip huggingface_hub
for repo in "${MODEL_REPOS[@]}"; do
  safe_repo="${repo//\//__}"
  target_dir="${WORKDIR}/${safe_repo}"
  printf '[source] %s\n' "$repo"
  python3 - <<'PY' "$repo" "$target_dir"
import sys
from huggingface_hub import snapshot_download

repo_id = sys.argv[1]
target_dir = sys.argv[2]
snapshot_download(
    repo_id=repo_id,
    local_dir=target_dir,
    local_dir_use_symlinks=False,
    resume_download=True,
)
PY
  aws --no-verify-ssl --endpoint-url "${S3_ENDPOINT}" s3 sync \
    "${target_dir}/" \
    "s3://${S3_BUCKET}/${S3_PREFIX}/${safe_repo}/" \
    --delete
done

printf '[status] model artifacts synchronized successfully\n'
