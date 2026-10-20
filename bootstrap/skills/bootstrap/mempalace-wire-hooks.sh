#!/usr/bin/env bash
# Wire MemPalace into settings.json: capture on Stop/SessionEnd/PreCompact, wake-up on
# SessionStart, recall on every prompt. All of them route through mempalace-hook.sh so
# memory is filed and read under the repo's wing. Replaces older mempalace hook entries.
set -uo pipefail
# mempalace_hooks.py needs 3.11+: older releases file every session under one `sessions` wing.
if command -v mempalace >/dev/null 2>&1; then
  v="$(mempalace --version 2>/dev/null | awk '{print $NF}')"
  if [ "$(printf '%s\n3.11.0\n' "$v" | sort -V | head -n 1)" != 3.11.0 ]; then
    { uv tool upgrade mempalace || pipx upgrade mempalace; } >/dev/null 2>&1 \
      || echo "  ✗ mempalace $v is older than 3.11 and could not be upgraded; run 'uv tool upgrade mempalace'"
  fi
fi
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
sj="$CLAUDE_DIR/settings.json"
mkdir -p "$CLAUDE_DIR"; [ -f "$sj" ] || echo '{}' > "$sj"
cp -p "$sj" "$sj.bak-$(date +%Y%m%d-%H%M%S)"
CLAUDE_SETTINGS="$sj" python3 - <<'PY' || { echo "  ✗ could not wire mempalace hooks: $sj unchanged"; exit 1; }
import json, os, collections
p = os.environ['CLAUDE_SETTINGS']
d = json.load(open(p), object_pairs_hook=collections.OrderedDict)
hooks = d.setdefault('hooks', collections.OrderedDict())
hook = 'bash "$HOME/.claude/skills/bootstrap/mempalace-hook.sh"'
wanted = {
    'SessionStart': ('bash "$HOME/.claude/skills/bootstrap/mempalace-session-start.sh"', 30),
    'Stop': (f'{hook} hook stop', 30),
    'SessionEnd': (f'{hook} hook session-end', 30),
    'PreCompact': (f'{hook} hook precompact', 30),
    'UserPromptSubmit': (f'{hook} recall', 10),
}
for event, (cmd, timeout) in wanted.items():
    groups = []
    for g in hooks.get(event, []):
        kept = [h for h in g.get('hooks', []) if 'mempalace' not in str(h.get('command', ''))]
        if kept or not g.get('hooks'):
            g['hooks'] = kept
            groups.append(g)
    groups.append(collections.OrderedDict([("hooks", [collections.OrderedDict(
        [("type", "command"), ("command", cmd), ("timeout", timeout)])])]))
    hooks[event] = groups
with open(p, 'w') as f:
    json.dump(d, f, indent=2, ensure_ascii=False)
    f.write('\n')
PY
echo "  ✓ mempalace hooks wired (SessionStart wake-up, Stop/SessionEnd/PreCompact capture, UserPromptSubmit recall)"
