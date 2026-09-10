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

for d in "$HOME/bin" "$HOME/.local/bin"; do
  if [ -d "$d" ]; then ln -sfn "$DIR/bin/graphs" "$d/graphs"; echo "  put graphs on PATH via $d"; break; fi
done

echo "Wiring the SessionStart hook ..."
HOOK='d="${CLAUDE_PROJECT_DIR:-$PWD}"; g="$HOME/.claude/bin/graphs"; [ -x "$g" ] && (cd "$d" && nohup "$g" ensure >/dev/null 2>&1 &); true'
python3 - "$SETTINGS" "$HOOK" <<'PY'
import json, os, sys
path, hook = sys.argv[1], sys.argv[2]
d = json.load(open(path)) if os.path.exists(path) else {}
hooks = d.setdefault("hooks", {}).setdefault("SessionStart", [])
flat = [h for e in hooks for h in e.get("hooks", [])]
if any("graphs" in h.get("command", "") and "ensure" in h.get("command", "") for h in flat):
    print("  hook already present — skipping")
else:
    replaced = False
    for h in flat:
        if "codegraph sync" in h.get("command", ""):
            h["command"] = hook; replaced = True
    if not replaced:
        hooks.append({"hooks": [{"type": "command", "command": hook}]})
    json.dump(d, open(path, "w"), indent=2); open(path, "a").write("\n")
    print("  replaced the old codegraph-sync hook" if replaced else "  added SessionStart hook")
PY

echo
if ! command -v codegraph >/dev/null 2>&1; then
  echo "  NOTE: codegraph not found — install it (e.g. volta install @colbymchenry/codegraph)"
  echo "        and run 'codegraph init' once in each repo you want indexed."
fi
command -v graphify >/dev/null 2>&1 || echo "  NOTE: graphify not found — optional; codegraph alone is enough."

echo
echo "Done. Check any repo with:  graphs status"
