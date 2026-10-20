#!/usr/bin/env bash
# Runs mempalace_hooks.py under MemPalace's own interpreter; a missing install is a silent no-op.
MP="$(command -v mempalace 2>/dev/null || echo "$HOME/.local/bin/mempalace")"
PY="$(head -n 1 "$MP" 2>/dev/null | sed -n 's/^#! *//p')"
# uv/pip write a /bin/sh trampoline when the venv path has spaces or is too long.
case "$PY" in */sh|*/bash|"") PY="$(sed -n "s/^'''exec' '\{0,1\}\"\{0,1\}\([^\"']*\)[\"']\{0,1\} .*/\1/p" "$MP" 2>/dev/null | head -n 1)" ;; esac
DIR="$(dirname "${BASH_SOURCE[0]}")"
case "${1:-}" in
  reorg) shift; exec "$PY" "$DIR/mempalace-reorg.py" "$@" ;;
  wing|wing-name) exec "$PY" "$DIR/mempalace_hooks.py" "$@" ;;
esac
# A hook must never exit 2: Claude Code would block the prompt or the stop.
case "$PY" in *python*) [ -x "$PY" ] && { "$PY" "$DIR/mempalace_hooks.py" "$@"; exit 0; } ;; esac
cat >/dev/null; printf '{}\n'
