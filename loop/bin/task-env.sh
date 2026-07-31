#!/usr/bin/env bash
# Minimal task-env shim for rivi-loop (statedir/log/progress)
set -euo pipefail
STATE="${TASK_ENV_STATEDIR:-$HOME/.cache/loop-engine}"
cmd="${1:-}"
shift || true
case "$cmd" in
  statedir)
    echo "$STATE"
    ;;
  log)
    id="${1:-}"
    msg="${2:-}"
    [[ -n "$id" ]] || { echo "usage: task-env log <id> <msg>" >&2; exit 2; }
    mkdir -p "$STATE"
    printf '%s\n' "- [$(date '+%Y-%m-%d %H:%M:%S')] $msg" >> "$STATE/${id}.progress.md"
    ;;
  progress)
    id="${1:-}"
    [[ -n "$id" ]] || { echo "usage: task-env progress <id>" >&2; exit 2; }
    f="$STATE/${id}.progress.md"
    if [[ -f "$f" ]]; then cat "$f"; else echo "(no progress for $id)"; fi
    ;;
  *)
    echo "task-env shim: unsupported '$cmd' (statedir|log|progress)" >&2
    exit 1
    ;;
esac
