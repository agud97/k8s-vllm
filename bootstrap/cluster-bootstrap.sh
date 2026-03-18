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
MATRIX_FILE="${ROOT_DIR}/docs/dependency-matrix.yaml"
INVENTORY_FILE="${ROOT_DIR}/inventory/generated/hosts.yml"
KUBESPRAY_CACHE_DIR="${ROOT_DIR}/bootstrap/cache/kubespray"
VENV_DIR="${ROOT_DIR}/.venv"

[[ -f "${ROOT_DIR}/local/hosts.yml" ]] || { printf 'missing required file: local/hosts.yml\n' >&2; exit 1; }
[[ -f "$MATRIX_FILE" ]] || { printf 'missing required file: %s\n' "$MATRIX_FILE" >&2; exit 1; }

need_cmd git
need_cmd python3
need_cmd ansible-playbook

./bootstrap/render-inventory.sh "${ROOT_DIR}/local/hosts.yml" "$INVENTORY_FILE" >/dev/null

KUBESPRAY_VERSION="$(sed -n 's/^    kubespray:$/kubespray/p' "$MATRIX_FILE" >/dev/null 2>&1 || true)"
if [[ -z "${KUBESPRAY_VERSION}" ]]; then
  KUBESPRAY_VERSION="$(awk '/^    kubespray:/{flag=1;next} flag && /version:/{gsub(/"/,"",$2); print $2; exit}' "$MATRIX_FILE")"
fi

if [[ -z "${KUBESPRAY_VERSION}" ]]; then
  printf 'failed to determine Kubespray version from %s\n' "$MATRIX_FILE" >&2
  exit 1
fi

mkdir -p "${ROOT_DIR}/bootstrap/cache"

if [[ ! -d "$KUBESPRAY_CACHE_DIR/.git" ]]; then
  git clone --depth 1 --branch "$KUBESPRAY_VERSION" https://github.com/kubernetes-sigs/kubespray.git "$KUBESPRAY_CACHE_DIR"
else
  git -C "$KUBESPRAY_CACHE_DIR" fetch --tags --depth 1 origin "$KUBESPRAY_VERSION"
  git -C "$KUBESPRAY_CACHE_DIR" checkout "$KUBESPRAY_VERSION"
fi

if [[ -f "${VENV_DIR}/bin/activate" ]]; then
  # Keep Kubespray Python dependencies isolated from the system interpreter.
  # This avoids controller-side package skew during repeated bootstrap runs.
  # shellcheck disable=SC1091
  source "${VENV_DIR}/bin/activate"
fi

python3 -m pip install -r "${KUBESPRAY_CACHE_DIR}/requirements.txt"

printf '[phase] cluster-bootstrap\n'
printf '[inventory] %s\n' "$INVENTORY_FILE"
printf '[kubespray] %s (%s)\n' "$KUBESPRAY_CACHE_DIR" "$KUBESPRAY_VERSION"

pushd "${KUBESPRAY_CACHE_DIR}" >/dev/null
ANSIBLE_HOST_KEY_CHECKING=False \
ANSIBLE_CONFIG="${KUBESPRAY_CACHE_DIR}/ansible.cfg" \
ansible-playbook \
  -i "$INVENTORY_FILE" \
  -e "@${ROOT_DIR}/inventory/group_vars/all.yml" \
  -e "@${ROOT_DIR}/inventory/group_vars/k8s_cluster.yml" \
  -e "@${ROOT_DIR}/inventory/group_vars/k8s_cluster/k8s-cluster.yml" \
  -e "@${ROOT_DIR}/inventory/group_vars/k8s_cluster/addons.yml" \
  "${KUBESPRAY_CACHE_DIR}/cluster.yml"
popd >/dev/null
