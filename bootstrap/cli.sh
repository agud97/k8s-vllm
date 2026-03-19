#!/usr/bin/env bash
set -euo pipefail

cmd="${1:-help}"

require_file() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    printf 'missing required file: %s\n' "$path" >&2
    exit 1
  fi
}

print_common_prereqs() {
  cat <<'EOF'
Required local inputs:
  - local/hosts.yml
  - local/s3.env
  - local/llm.env

Reference files:
  - docs/dependency-matrix.yaml
  - spec/plan.yaml
EOF
}

case "$cmd" in
  help)
    cat <<'EOF'
Available commands:
  make bootstrap    Prepare for host provisioning and cluster bootstrap
  make deploy       Apply GitOps-managed platform and application components
  make validate     Run repository and cluster validation workflows
  make smoke-test   Run the documented LiteLLM smoke test
EOF
    printf '\n'
    print_common_prereqs
    ;;
  bootstrap)
    require_file "local/hosts.yml"
    require_file "local/s3.env"
    require_file "local/llm.env"
    cat <<'EOF'
[phase] bootstrap
[steps]
  1. ./bootstrap/render-inventory.sh
  2. ./bootstrap/host-prep.sh
  3. ./bootstrap/cluster-bootstrap.sh
  4. ./bootstrap/gpu-prep.sh
[status] bootstrap entrypoint prerequisites satisfied
EOF
    ;;
  deploy)
    require_file "local/hosts.yml"
    require_file "local/s3.env"
    require_file "local/llm.env"
    cat <<'EOF'
[phase] deploy
[steps]
  1. ./bootstrap/argocd-bootstrap.sh
  2. ./bootstrap/sealed-secrets-bootstrap.sh
  3. ./bootstrap/app-secrets.sh
  4. ./bootstrap/model-sync.sh
[status] deploy entrypoint prerequisites satisfied
EOF
    ;;
  validate)
    cat <<'EOF'
[phase] validate
[steps]
  1. make validate-static
  2. ./tests/validate-cluster.sh all
  3. ./tests/validate-platform.sh all
  4. ./tests/validate-serving.sh runtime
[status] validation entrypoint prerequisites satisfied
EOF
    ;;
  smoke-test)
    require_file "local/llm.env"
    cat <<'EOF'
[phase] smoke-test
[status] smoke test is implemented in ./tests/smoke-test.sh
EOF
    ;;
  *)
    printf 'unknown command: %s\n\n' "$cmd" >&2
    exec "$0" help
    ;;
esac
