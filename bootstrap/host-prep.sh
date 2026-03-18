#!/usr/bin/env bash
set -euo pipefail

need_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    printf 'missing required command: %s\n' "$cmd" >&2
    exit 1
  fi
}

inventory_path="${1:-inventory/generated/hosts.yml}"
playbook_path="bootstrap/playbooks/host-prep.yml"

[[ -f "local/hosts.yml" ]] || { printf 'missing required file: local/hosts.yml\n' >&2; exit 1; }
[[ -f "$playbook_path" ]] || { printf 'missing required file: %s\n' "$playbook_path" >&2; exit 1; }

need_cmd ansible-playbook
need_cmd sshpass

./bootstrap/render-inventory.sh "local/hosts.yml" "$inventory_path" >/dev/null

printf '[phase] host-prep\n'
printf '[inventory] %s\n' "$inventory_path"
printf '[playbook] %s\n' "$playbook_path"

ANSIBLE_HOST_KEY_CHECKING=False \
ansible-playbook -i "$inventory_path" "$playbook_path"
