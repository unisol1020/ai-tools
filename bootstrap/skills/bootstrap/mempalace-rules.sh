#!/usr/bin/env bash
# Insert (or refresh) the MemPalace recall rules in ~/.claude/CLAUDE.md.
# The hooks make SAVING automatic; this block is what makes the model RECALL —
# without it Claude has the MCP tools but no instruction on when to use them.
set -uo pipefail
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$CLAUDE_DIR/CLAUDE.md"
BLOCK="$SELF_DIR/mempalace-rules.md"
[ -f "$BLOCK" ] || { echo "  ✗ mempalace-rules.md missing"; exit 1; }
mkdir -p "$CLAUDE_DIR"; [ -f "$TARGET" ] || : > "$TARGET"
cp -p "$TARGET" "$TARGET.bak-$(date +%Y%m%d-%H%M%S)" 2>/dev/null
TARGET="$TARGET" BLOCK="$BLOCK" python3 - <<'PY'
import os
t, b = os.environ['TARGET'], os.environ['BLOCK']
s = open(t).read()
block = '<!-- mempalace:start -->\n' + open(b).read().rstrip() + '\n<!-- mempalace:end -->'
S, E = '<!-- mempalace:start -->', '<!-- mempalace:end -->'
if S in s and E in s:
    s = s[:s.index(S)] + block + s[s.index(E)+len(E):]; action = 'refreshed'
else:
    s = (s.rstrip() + '\n\n' + block + '\n') if s.strip() else block + '\n'; action = 'added'
open(t, 'w').write(s)
print(f"  ✓ MemPalace recall rules {action} in {t}")
PY
