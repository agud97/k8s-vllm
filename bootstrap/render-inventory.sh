#!/usr/bin/env bash
set -euo pipefail

src="${1:-local/hosts.yml}"
dst="${2:-inventory/generated/hosts.yml}"

if [[ ! -f "$src" ]]; then
  printf 'missing source inventory: %s\n' "$src" >&2
  exit 1
fi

mkdir -p "$(dirname "$dst")"
cp "$src" "$dst"

printf 'rendered inventory: %s -> %s\n' "$src" "$dst"
