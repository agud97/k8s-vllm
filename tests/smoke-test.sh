#!/usr/bin/env bash
set -euo pipefail

prompt='Напиши одно короткое предложение о Kubernetes.'
model="${SMOKE_MODEL_ALIAS:-qwen35-9b}"

: "${LITELLM_BASE_URL:?set LITELLM_BASE_URL, for example http://<infra-1-public-ip>:32080}"
: "${LITELLM_API_KEY:?set LITELLM_API_KEY}"

need_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    printf 'missing required command: %s\n' "$cmd" >&2
    exit 1
  fi
}

need_cmd curl
need_cmd python3

tmp_response="$(mktemp)"
trap 'rm -f "$tmp_response"' EXIT

curl --silent --show-error --fail \
  --max-time 60 \
  -H "Authorization: Bearer ${LITELLM_API_KEY}" \
  -H "Content-Type: application/json" \
  -o "$tmp_response" \
  -X POST "${LITELLM_BASE_URL}/v1/chat/completions" \
  -d "{
    \"model\": \"${model}\",
    \"messages\": [{\"role\": \"user\", \"content\": \"${prompt}\"}],
    \"max_tokens\": 64
  }"

python3 - <<'PY' "$tmp_response"
import json, sys
path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)

choices = data.get("choices") or []
if not choices:
    print("smoke test failed: choices missing", file=sys.stderr)
    sys.exit(1)

message = choices[0].get("message", {})
content = message.get("content", "")
if not content or not str(content).strip():
    print("smoke test failed: empty generated text", file=sys.stderr)
    sys.exit(1)

if data.get("error"):
    print("smoke test failed: runtime error present in response", file=sys.stderr)
    sys.exit(1)

print("smoke test passed")
print(content.strip())
PY
