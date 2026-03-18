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
    cat <<'EOF'
[phase] bootstrap
[next] implement host preparation and Kubespray automation in phase-2
[status] repository entrypoint is ready; cluster bootstrap logic not implemented yet
EOF
    ;;
  deploy)
    require_file "local/hosts.yml"
    require_file "local/s3.env"
    cat <<'EOF'
[phase] deploy
[next] implement ArgoCD, platform, and serving manifests in later phases
[status] deployment entrypoint is ready; GitOps deployment logic not implemented yet
EOF
    ;;
  validate)
    cat <<'EOF'
[phase] validate
[next] implement static and cluster validation scripts in later phases
[status] validation entrypoint is ready; validation suite not implemented yet
EOF
    ;;
  smoke-test)
    require_file "local/s3.env"
    cat <<'EOF'
[phase] smoke-test
[next] implement LiteLLM smoke-test automation in phase-5
[status] smoke-test entrypoint is ready; smoke test not implemented yet
EOF
    ;;
  *)
    printf 'unknown command: %s\n\n' "$cmd" >&2
    exec "$0" help
    ;;
esac
