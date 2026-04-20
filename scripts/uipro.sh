#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${CONDA_PREFIX:-}" && -x "${CONDA_PREFIX}/.npm-global/bin/uipro" ]]; then
  exec "${CONDA_PREFIX}/.npm-global/bin/uipro" "$@"
fi

if command -v uipro >/dev/null 2>&1; then
  exec uipro "$@"
fi

if command -v npx >/dev/null 2>&1; then
  exec npx uipro-cli "$@"
fi

echo "uipro not found. Install with: npm install -g uipro-cli" >&2
exit 1
