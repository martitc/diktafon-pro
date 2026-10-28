#!/usr/bin/env bash
set -euo pipefail

GH_BIN="$(command -v gh || true)"
if [ -z "$GH_BIN" ]; then
  GH_BIN="$HOME/.local/bin/gh"
fi
[ -x "$GH_BIN" ] || { echo 'ERROR: gh is not installed or not on PATH' >&2; exit 1; }
"$GH_BIN" api /user --jq '"OK — autenticado como @" + .login'
