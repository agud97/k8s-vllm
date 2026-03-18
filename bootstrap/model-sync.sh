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
HF_REPO="Qwen/Qwen3.5-27B-GPTQ-Int4"
WORKDIR="${ROOT_DIR}/bootstrap/cache/model-sync"

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
printf '[source] %s\n' "$HF_REPO"
printf '[destination] s3://%s/%s/\n' "$S3_BUCKET" "$S3_PREFIX"

python3 -m venv "${WORKDIR}/venv"
# shellcheck disable=SC1091
source "${WORKDIR}/venv/bin/activate"
python3 -m pip install --quiet --upgrade pip huggingface_hub
python3 - <<'PY'
from huggingface_hub import snapshot_download

snapshot_download(
    repo_id="Qwen/Qwen3.5-27B-GPTQ-Int4",
    local_dir="bootstrap/cache/model-sync/model",
    local_dir_use_symlinks=False,
    resume_download=True,
)
PY

aws --no-verify-ssl --endpoint-url "${S3_ENDPOINT}" s3 sync "${WORKDIR}/model/" "s3://${S3_BUCKET}/${S3_PREFIX}/" --delete

printf '[status] model artifacts synchronized successfully\n'
