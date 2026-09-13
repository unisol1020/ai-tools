#!/usr/bin/env bash
# memory installer — puts `agent-memory` on PATH, links the memory-curator agent and the
# /evolve skill, wires the SessionStart / SubagentStart / SubagentStop hooks into
# settings.json, and gitignores the project tier globally. Idempotent; backs up settings
# before editing.
#
# Flags:
#   --uninstall   remove the links and the three hook entries; keeps every memory file
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SETTINGS="$CLAUDE_DIR/settings.json"
GLOBAL="$CLAUDE_DIR/agent-memory"
EXCLUDE_LINE=".claude/agent-memory-local/"
ts() { date +%Y%m%d-%H%M%S; }

BINDIR=""
for d in "$HOME/.local/bin" "$HOME/bin"; do
  [ -d "$d" ] && { BINDIR="$d"; break; }
done
[ -n "$BINDIR" ] || BINDIR="$HOME/.local/bin"

hook_present() {
  jq -e --arg ev "$1" '[.hooks[$ev][]?.hooks[]?.command // ""] | any(contains("agent-memory"))' "$SETTINGS" >/dev/null 2>&1
}

uninstall() {
  echo "Uninstalling memory from $CLAUDE_DIR ..."
  for p in "$CLAUDE_DIR/bin/agent-memory" "$BINDIR/agent-memory" \
           "$CLAUDE_DIR/agents/memory-curator.md" "$CLAUDE_DIR/skills/evolve"; do
    [ -L "$p" ] && { rm -f "$p"; echo "  removed $p"; }
  done
  if [ -f "$SETTINGS" ] && command -v jq >/dev/null 2>&1; then
    cp -p "$SETTINGS" "$SETTINGS.bak-$(ts)"
    jq '
      def strip: map(.hooks = ((.hooks // []) | map(select((.command // "") | contains("agent-memory") | not))))
                 | map(select(.hooks != []));
      .hooks |= (if . == null then . else
        reduce ("SessionStart", "SubagentStart", "SubagentStop") as $ev (.;
          if has($ev) then (.[$ev] |= strip) | (if .[$ev] == [] then del(.[$ev]) else . end)
          else . end)
      end)
    ' "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
    echo "  removed the agent-memory hook entries from settings.json (backup alongside)"
  fi
  cat <<KEPT

Done. Kept on purpose (delete them yourself if you want the memories gone):
  $GLOBAL/                       the GLOBAL tier, registry, vetoes, proposals
  <repo>/.claude/agent-memory-local/    the PROJECT tier in every repo
  $EXCLUDE_LINE line in your global git excludes file
KEPT
}

[ "${1:-}" = "--uninstall" ] && { uninstall; exit 0; }

for t in git jq; do
  command -v "$t" >/dev/null 2>&1 || { echo "ERROR: $t is required (brew install $t / apt install $t)"; exit 1; }
done
command -v claude >/dev/null 2>&1 || echo "  NOTE: claude CLI not found on PATH — the hooks need Claude Code >= 2.1.33."

mkdir -p "$CLAUDE_DIR/bin" "$CLAUDE_DIR/agents" "$CLAUDE_DIR/skills"
link() { rm -rf "$2"; ln -s "$1" "$2"; echo "  linked $(basename "$2")"; }

echo "Installing memory into $CLAUDE_DIR ..."
chmod +x "$DIR/bin/agent-memory"
link "$DIR/bin/agent-memory"             "$CLAUDE_DIR/bin/agent-memory"
link "$DIR/agents/memory-curator.md"     "$CLAUDE_DIR/agents/memory-curator.md"
link "$DIR/skills/evolve"                "$CLAUDE_DIR/skills/evolve"

mkdir -p "$BINDIR"
ln -sfn "$DIR/bin/agent-memory" "$BINDIR/agent-memory"
echo "  put agent-memory in $BINDIR"
case ":$PATH:" in
  *":$BINDIR:"*) ;;
  *) echo "  NOTE: $BINDIR is not on your PATH. Add this to your shell rc:"
     echo "        export PATH=\"$BINDIR:\$PATH\""
     echo "        (until then, use the full path: $BINDIR/agent-memory status)" ;;
esac

echo "Wiring the hooks into settings.json ..."
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
cp -p "$SETTINGS" "$SETTINGS.bak-$(ts)"
# The hook string stays "$HOME"-relative so settings.json is portable; a non-default config dir gets its literal path.
if [ "$CLAUDE_DIR" = "$HOME/.claude" ]; then bin='"$HOME/.claude/bin/agent-memory"'; else bin="\"$CLAUDE_DIR/bin/agent-memory\""; fi
for ev in SessionStart SubagentStart SubagentStop; do
  if hook_present "$ev"; then
    echo "  $ev hook already present — skipping"
    continue
  fi
  sub="$(echo "$ev" | sed 's/\([a-z]\)\([A-Z]\)/\1-\2/g' | tr '[:upper:]' '[:lower:]')"
  jq --arg ev "$ev" --arg cmd "$bin $sub" '
    .hooks = (.hooks // {}) | .hooks[$ev] = (.hooks[$ev] // []) |
    .hooks[$ev] += [{hooks: [{type: "command", command: $cmd, timeout: 10}]}]
  ' "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
  echo "  added $ev hook"
done

mkdir -p "$GLOBAL/_skills"
for f in .registry .vetoed promotions.log proposals.md; do
  [ -f "$GLOBAL/$f" ] || : > "$GLOBAL/$f"
done
echo "  global tier ready at $GLOBAL"

excl="$(git config --global --path core.excludesFile 2>/dev/null || true)"
if [ -z "$excl" ]; then
  git config --global core.excludesFile '~/.gitignore_global'
  excl="$HOME/.gitignore_global"
  echo "  set git core.excludesFile to ~/.gitignore_global"
fi
mkdir -p "$(dirname "$excl")"
[ -f "$excl" ] || : > "$excl"
if grep -qxF "$EXCLUDE_LINE" "$excl"; then
  echo "  $EXCLUDE_LINE already in $excl"
else
  [ -s "$excl" ] && [ -n "$(tail -c1 "$excl")" ] && echo >> "$excl"
  echo "$EXCLUDE_LINE" >> "$excl"
  echo "  added $EXCLUDE_LINE to $excl"
fi

cat <<'DONE'

Done. Next:
  1. Restart Claude Code once so the hooks, the memory-curator agent and /evolve load.
  2. Use any agent from team/ or qa/ in a repo — it now ends its report with
       memory: recalled N used M saved K repeats R
     and its lessons land in <repo>/.claude/agent-memory-local/<agent>/.
  3. Check on it:  agent-memory status     (this repo)
                   agent-memory selfcheck  (offline test suite, seconds)
                   /evolve                 (run the curator now)
DONE
