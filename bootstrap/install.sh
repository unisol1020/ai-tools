#!/usr/bin/env bash
# bootstrap installer — installs the /bootstrap skill + the session-start nudge hook
# into ~/.claude and wires the SessionStart hooks (bootstrap nudge + CodeGraph auto-sync)
# into settings.json. Idempotent; backs up settings before editing.
#
# Flags:
#   --with-deps   also run setup-env.sh now (jq, ripgrep, ast-grep, CodeGraph + MCP,
#                 graphify + skill, MemPalace + MCP + hooks, ponytail)
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
WITH_DEPS=0; for a in "$@"; do [ "$a" = "--with-deps" ] && WITH_DEPS=1; done
ts() { date +%Y%m%d-%H%M%S; }

mkdir -p "$CLAUDE_DIR/skills" "$CLAUDE_DIR/hooks"
link() { rm -rf "$2"; ln -s "$1" "$2"; echo "  linked $(basename "$2")"; }

echo "Installing bootstrap into $CLAUDE_DIR ..."

# 1. The /bootstrap skill (carries setup-env.sh alongside SKILL.md)
chmod +x "$DIR/skills/bootstrap/setup-env.sh"
link "$DIR/skills/bootstrap" "$CLAUDE_DIR/skills/bootstrap"

# 2. The session-start nudge hook
[ -e "$CLAUDE_DIR/hooks/bootstrap-check.sh" ] && [ ! -L "$CLAUDE_DIR/hooks/bootstrap-check.sh" ] \
  && cp -p "$CLAUDE_DIR/hooks/bootstrap-check.sh" "$CLAUDE_DIR/hooks/bootstrap-check.sh.bak-$(ts)" \
  && echo "  backed up existing bootstrap-check.sh"
chmod +x "$DIR/hooks/bootstrap-check.sh"
link "$DIR/hooks/bootstrap-check.sh" "$CLAUDE_DIR/hooks/bootstrap-check.sh"

# 3. Wire SessionStart hooks into settings.json (idempotent)
if command -v jq >/dev/null 2>&1; then
  sj="$CLAUDE_DIR/settings.json"; [ -f "$sj" ] || echo '{}' > "$sj"
  cp -p "$sj" "$sj.bak-$(ts)"
  nudge='bash "$HOME/.claude/hooks/bootstrap-check.sh"'
  sync='d="${CLAUDE_PROJECT_DIR:-$PWD}"; cg="$(command -v codegraph)"; [ -n "$cg" ] && [ -d "$d/.codegraph" ] && (cd "$d" && nohup "$cg" sync >/dev/null 2>&1 &); true'
  jq --arg nudge "$nudge" --arg sync "$sync" '
    .hooks = (.hooks // {}) | .hooks.SessionStart = (.hooks.SessionStart // []) |
    ([ .hooks.SessionStart[]?.hooks[]?.command ]) as $c |
    (if ($c | any(contains("bootstrap-check.sh"))) then .
       else .hooks.SessionStart += [{hooks:[{type:"command", command:$nudge, timeout:10}]}] end) |
    ([ .hooks.SessionStart[]?.hooks[]?.command ]) as $c2 |
    (if ($c2 | any((contains("codegraph") and contains("sync")) or (contains("graphs") and contains("ensure")))) then .
       else .hooks.SessionStart += [{hooks:[{type:"command", command:$sync}]}] end)
  ' "$sj" > "$sj.tmp" && mv "$sj.tmp" "$sj"
  echo "  wired SessionStart hooks (bootstrap nudge + codegraph auto-sync) into settings.json"
else
  echo "  WARN: jq not found — add the SessionStart hook manually (see README)."
fi

# 4. Optionally install the extensions now
if [ "$WITH_DEPS" = 1 ]; then
  echo; bash "$DIR/skills/bootstrap/setup-env.sh"
fi

cat <<'DONE'

Done. Next:
  1. Restart Claude Code once (so the skill + any newly-wired hooks load).
  2. Open any repo and run  /bootstrap  — it installs every tool the agents expect
     if missing (jq, ripgrep, ast-grep, CodeGraph + MCP, graphify + skill,
     MemPalace + MCP + capture hooks, ponytail), builds the CodeGraph index,
     offers to run /graphify, and records the repo as done.
  Or set up the toolchain right now without opening a repo:
     bash ~/.claude/skills/bootstrap/setup-env.sh
DONE
