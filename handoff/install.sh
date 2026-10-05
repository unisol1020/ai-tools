#!/usr/bin/env bash
# handoff installer — links the /handoff skill and its two hooks into ~/.claude, wires
# SessionStart / UserPromptSubmit / PostToolUse into settings.json, and gitignores
# .claude/handoffs/ globally. Idempotent; backs up settings before editing.
#
# Flags:
#   --uninstall   remove the links and the three hook entries; keeps every handoff document
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SETTINGS="$CLAUDE_DIR/settings.json"
EXCLUDE_LINE=".claude/handoffs/"
ts() { date +%Y%m%d-%H%M%S; }

hook_present() {
  jq -e --arg ev "$1" --arg sub "$2" '[.hooks[$ev][]?.hooks[]?.command // ""] | any(contains($sub))' "$SETTINGS" >/dev/null 2>&1
}

uninstall() {
  echo "Uninstalling handoff from $CLAUDE_DIR ..."
  for p in "$CLAUDE_DIR/skills/handoff" "$CLAUDE_DIR/hooks/context-nudge.sh" "$CLAUDE_DIR/hooks/handoff-load.sh"; do
    [ -L "$p" ] && { rm -f "$p"; echo "  removed $p"; }
  done
  if [ -f "$SETTINGS" ] && command -v jq >/dev/null 2>&1; then
    cp -p "$SETTINGS" "$SETTINGS.bak-$(ts)"
    jq '
      def ours: contains("context-nudge.sh") or contains("handoff-load.sh");
      def strip: map(.hooks = ((.hooks // []) | map(select((.command // "") | ours | not))))
                 | map(select(.hooks != []));
      .hooks |= (if . == null then . else
        reduce ("SessionStart", "UserPromptSubmit", "PostToolUse") as $ev (.;
          if has($ev) then (.[$ev] |= strip) | (if .[$ev] == [] then del(.[$ev]) else . end)
          else . end)
      end)
    ' "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
    echo "  removed the handoff hook entries from settings.json (backup alongside)"
  fi
  cat <<KEPT

Done. Kept on purpose:
  <repo>/.claude/handoffs/    every handoff document, in every repo
  $EXCLUDE_LINE line in your global git excludes file
  the statusline snippet, if you pasted it into ~/.claude/statusline.sh
KEPT
}

[ "${1:-}" = "--uninstall" ] && { uninstall; exit 0; }

for t in git jq; do
  command -v "$t" >/dev/null 2>&1 || { echo "ERROR: $t is required (brew install $t / apt install $t)"; exit 1; }
done
command -v python3 >/dev/null 2>&1 || echo "  NOTE: python3 not found — the 50% nudge stays silent until it is on PATH."

mkdir -p "$CLAUDE_DIR/skills" "$CLAUDE_DIR/hooks"
link() { rm -rf "$2"; ln -s "$1" "$2"; echo "  linked $(basename "$2")"; }

echo "Installing handoff into $CLAUDE_DIR ..."
chmod +x "$DIR/hooks/context-nudge.sh" "$DIR/hooks/handoff-load.sh"
link "$DIR/skills/handoff"           "$CLAUDE_DIR/skills/handoff"
link "$DIR/hooks/context-nudge.sh"   "$CLAUDE_DIR/hooks/context-nudge.sh"
link "$DIR/hooks/handoff-load.sh"    "$CLAUDE_DIR/hooks/handoff-load.sh"

echo "Wiring the hooks into settings.json ..."
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
cp -p "$SETTINGS" "$SETTINGS.bak-$(ts)"
# The hook string stays "$HOME"-relative so settings.json is portable; a non-default config dir gets its literal path.
if [ "$CLAUDE_DIR" = "$HOME/.claude" ]; then hooks='"$HOME/.claude/hooks'; else hooks="\"$CLAUDE_DIR/hooks"; fi
add_hook() {  # event  script  matcher
  if hook_present "$1" "$2"; then
    echo "  $1 hook already present — skipping"
    return
  fi
  jq --arg ev "$1" --arg cmd "$hooks/$2\"" --arg m "$3" '
    .hooks = (.hooks // {}) | .hooks[$ev] = (.hooks[$ev] // []) |
    .hooks[$ev] += [(if $m == "" then {} else {matcher: $m} end)
                    + {hooks: [{type: "command", command: $cmd, timeout: 5}]}]
  ' "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
  echo "  added $1 hook${3:+ (matcher $3)}"
}
add_hook SessionStart     handoff-load.sh  "startup|clear|compact"
add_hook UserPromptSubmit context-nudge.sh ""
add_hook PostToolUse      context-nudge.sh "Bash|Edit|Write|Agent"

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

cat <<DONE

Optional — feed the nudge Claude Code's own context number instead of its transcript estimate.
This installer never edits your statusline; paste this into $CLAUDE_DIR/statusline.sh yourself,
right after the block that finalises \`pct\` (the \`fi\` before \`if [ -n "\$pct" ]\`):

DONE
sed 's/^/    /' "$DIR/statusline/snippet.sh"
cat <<'DONE'

Done. Next:
  1. Restart Claude Code once so the skill and the hooks load.
  2. Near 50% context (the nudge tells you) or before a break, run  /handoff
     then start a fresh `claude` in the same directory and run  /handoff resume
  3. Verify offline:  sh ~/.ai-tools/handoff/tests/run.sh
DONE
