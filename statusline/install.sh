#!/usr/bin/env bash
# statusline installer — links the script into ~/.claude and points settings.json at it.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SETTINGS="$CLAUDE_DIR/settings.json"

mkdir -p "$CLAUDE_DIR"

echo "Installing statusline into $CLAUDE_DIR ..."
rm -f "$CLAUDE_DIR/statusline.py"
ln -s "$DIR/statusline.py" "$CLAUDE_DIR/statusline.py"
echo "  linked statusline.py"

[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
cp -p "$SETTINGS" "$SETTINGS.bak-$(date +%Y%m%d-%H%M%S)"

python3 - "$SETTINGS" "$CLAUDE_DIR/statusline.py" <<'PY'
import json, sys
settings, script = sys.argv[1], sys.argv[2]
with open(settings) as f:
    data = json.load(f)
before = data.get("statusLine")
data["statusLine"] = {"type": "command", "command": "python3 %s" % script, "timeout": 10}
with open(settings, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
print("  statusLine %s" % ("already pointed here" if before == data["statusLine"] else "wired up"))
PY

echo
echo "Done. Restart Claude Code (or start a new session) to see it."
echo "Preview it now without restarting:  $DIR/demo.sh"
