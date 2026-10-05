#!/usr/bin/env bash
# worktree-graphs installer — puts `graphs` on PATH, links the skill, and wires the
# SessionStart hook that seeds a worktree's code graphs the first time a session opens there.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SETTINGS="$CLAUDE_DIR/settings.json"

mkdir -p "$CLAUDE_DIR/bin" "$CLAUDE_DIR/skills"

link() { rm -rf "$2"; ln -s "$1" "$2"; echo "  linked $(basename "$2")"; }

echo "Installing worktree-graphs into $CLAUDE_DIR ..."
link "$DIR/bin/graphs"              "$CLAUDE_DIR/bin/graphs"
link "$DIR/skills/worktree-graphs"  "$CLAUDE_DIR/skills/worktree-graphs"

BINDIR=""
for d in "$HOME/.local/bin" "$HOME/bin"; do
  [ -d "$d" ] && { BINDIR="$d"; break; }
done
[ -n "$BINDIR" ] || { BINDIR="$HOME/.local/bin"; mkdir -p "$BINDIR"; }
ln -sfn "$DIR/bin/graphs" "$BINDIR/graphs"
echo "  put graphs in $BINDIR"
case ":$PATH:" in
  *":$BINDIR:"*) ;;
  *) echo "  NOTE: $BINDIR is not on your PATH. Add this to your shell rc:"
     echo "        export PATH=\"$BINDIR:\$PATH\""
     echo "        (until then, use the full path: $BINDIR/graphs status)" ;;
esac

echo "Wiring the SessionStart hook ..."
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required (brew install jq / apt install jq)"; exit 1; }
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
cp -p "$SETTINGS" "$SETTINGS.bak-$(date +%Y%m%d-%H%M%S)"
HOOK='d="${CLAUDE_PROJECT_DIR:-$PWD}"; g="$HOME/.claude/bin/graphs"; [ -x "$g" ] && (cd "$d" && nohup "$g" ensure >/dev/null 2>&1 &); true'
# startup|resume only: /clear and compact reopen the same checkout, so re-running ensure buys nothing.
MATCHER='startup|resume'
DEFS='
  def ours: (.command // "") | (contains("graphs") and contains("ensure"));
  def old:  (.command // "") | (contains("codegraph") and contains("sync"));
  def entries: [.hooks.SessionStart[]?];'
action=$(jq -r --arg m "$MATCHER" "$DEFS"'
  if any(entries[].hooks[]?; ours) then
    (if any(entries[]; any(.hooks[]?; ours) and .matcher == null) then "matcher" else "present" end)
  elif any(entries[].hooks[]?; old) then "replaced" else "added" end' "$SETTINGS")
jq --arg hook "$HOOK" --arg m "$MATCHER" --arg action "$action" "$DEFS"'
  .hooks = (.hooks // {}) | .hooks.SessionStart = (.hooks.SessionStart // []) |
  if $action == "matcher"  then .hooks.SessionStart |= map(if any(.hooks[]?; ours) and .matcher == null then .matcher = $m else . end)
  elif $action == "replaced" then .hooks.SessionStart |= map(if any(.hooks[]?; old) then .matcher = $m | .hooks |= map(if old then .command = $hook else . end) else . end)
  elif $action == "added"    then .hooks.SessionStart += [{matcher: $m, hooks: [{type: "command", command: $hook}]}]
  else . end' "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
case "$action" in
  present)  echo "  hook already present — skipping";;
  matcher)  echo "  hook already present — set matcher to $MATCHER";;
  replaced) echo "  replaced the old codegraph-sync hook";;
  added)    echo "  added SessionStart hook (matcher: $MATCHER)";;
esac

echo
if ! command -v codegraph >/dev/null 2>&1; then
  echo "  NOTE: codegraph not found — install it (e.g. volta install @colbymchenry/codegraph)"
  echo "        and run 'codegraph init' once in each repo you want indexed."
fi
command -v graphify >/dev/null 2>&1 || echo "  NOTE: graphify not found — optional; codegraph alone is enough."

echo
echo "Done. Check any repo with:  graphs status"
