#!/usr/bin/env bash
# config installer — merges the shared preferences preset into ~/.claude/settings.json.
# Only the keys in settings.preset.json are touched; hooks, model and statusLine are left alone.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SETTINGS="$CLAUDE_DIR/settings.json"

mkdir -p "$CLAUDE_DIR"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
cp -p "$SETTINGS" "$SETTINGS.bak-$(date +%Y%m%d-%H%M%S)"

python3 - "$SETTINGS" "$DIR/settings.preset.json" "${1:-}" <<'PY'
import json, sys
settings, preset_path, force = sys.argv[1], sys.argv[2], sys.argv[3] == "--force"
with open(settings) as f:
    data = json.load(f)
with open(preset_path) as f:
    preset = json.load(f)

def merge(dst, src, path=""):
    for k, v in src.items():
        here = "%s.%s" % (path, k) if path else k
        if isinstance(v, dict) and isinstance(dst.get(k), dict):
            merge(dst[k], v, here)
        elif isinstance(v, list) and isinstance(dst.get(k), list):
            added = [x for x in v if x not in dst[k]]
            if added:
                dst[k] += added
                print("  + %s (%d new)" % (here, len(added)))
        elif k not in dst:
            dst[k] = v
            print("  + %s = %s" % (here, json.dumps(v)))
        elif dst[k] != v:
            if force:
                print("  ~ %s: %s -> %s" % (here, json.dumps(dst[k]), json.dumps(v)))
                dst[k] = v
            else:
                print("  = %s kept as %s (preset wanted %s)"
                      % (here, json.dumps(dst[k]), json.dumps(v)))

merge(data, preset)
with open(settings, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY

echo
echo "Done. Restart Claude Code once so plugins and permissions take effect."
echo "Re-run with --force to let the preset overwrite values you have already set."
