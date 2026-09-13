#!/usr/bin/env bash
# Migrate claude-mem -> MemPalace, and wire MemPalace's automatic capture hooks.
#   --remove-claude-mem   disable the claude-mem plugin + stop its worker (DB is KEPT)
#   --purge-claude-mem    additionally delete ~/.claude-mem (IRREVERSIBLE)
#   --with-cloud          also install the third-party MemPalace Cloud plugin (see README)
#   --skip-mine           export + hooks only, don't ingest
set -uo pipefail

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REMOVE=0; PURGE=0; WITH_CLOUD=0; SKIP_MINE=0
for a in "$@"; do case "$a" in
  --remove-claude-mem) REMOVE=1 ;;
  --purge-claude-mem)  REMOVE=1; PURGE=1 ;;
  --with-cloud)        WITH_CLOUD=1 ;;
  --skip-mine)         SKIP_MINE=1 ;;
esac; done

note() { printf '  %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }
ts()   { date +%Y%m%d-%H%M%S; }
export PATH="$HOME/.local/bin:$PATH"

echo "== MemPalace migration =="

# 1. mempalace present? ---------------------------------------------------------
if ! have mempalace; then
  if   have uv;   then uv tool install mempalace >/dev/null 2>&1
  elif have pipx; then pipx install mempalace >/dev/null 2>&1
  elif have brew; then brew install uv >/dev/null 2>&1 && uv tool install mempalace >/dev/null 2>&1
  fi
fi
have mempalace || { note "✗ mempalace not installed and could not be installed — need uv or pipx (Python 3.10+)"; exit 1; }
note "✓ mempalace $(mempalace --version 2>/dev/null | head -1)"

# 2. export claude-mem ----------------------------------------------------------
EXPORT_DIR="$HOME/claude-mem-export"
if [ -f "$HOME/.claude-mem/claude-mem.db" ]; then
  if have node && have sqlite3; then
    note "→ exporting claude-mem (read-only, no LLM calls)…"
    node "$SELF_DIR/mempalace-export.mjs" 2>&1 | sed 's/^/    /'
  else note "✗ need node + sqlite3 to export claude-mem — skipping export"; fi
else note "· no claude-mem database found — nothing to export"; fi

# 3. ingest — one wing per root project -----------------------------------------
# Mining everything into a single wing makes `mempalace wake-up` return whichever
# project it likes regardless of your cwd, so session-start injects the wrong
# repo's memory. One wing per root project keeps recall scoped.
if [ "$SKIP_MINE" = 0 ] && [ -d "$EXPORT_DIR/projects" ]; then
  note "→ dry run…"
  TOTAL_SKIP=0
  for d in "$EXPORT_DIR"/projects/*/; do
    [ -d "$d" ] || continue
    DRY="$(mempalace mine "$d" --wing "$(basename "$d")" --dry-run 2>&1)"
    if echo "$DRY" | grep -q "chunk cap"; then
      TOTAL_SKIP=1
      note "⚠ $(basename "$d"): $(echo "$DRY" | grep 'chunk cap' | tr -d '\n')"
    fi
  done
  [ "$TOTAL_SKIP" = 1 ] && note "⚠ files above were SKIPPED SILENTLY — those memories will NOT import"

  note "→ mining (local embeddings, no API key; CPU-heavy, can take a while)…"
  for d in "$EXPORT_DIR"/projects/*/; do
    [ -d "$d" ] || continue
    W="$(basename "$d")"
    printf '    %-40s' "$W"
    mempalace mine "$d" --wing "$W" 2>&1 | grep -oE "Drawers filed: [0-9]+" | tail -1
  done
  mempalace status 2>&1 | grep -i drawers | sed 's/^/    /'
fi

# 4. MCP + automatic capture hooks ----------------------------------------------
if have claude; then
  claude mcp list 2>/dev/null | grep -q '^mempalace' \
    || claude mcp add --scope user mempalace -- mempalace-mcp >/dev/null 2>&1
  note "✓ mempalace MCP registered (user scope)"
fi

if have python3; then
  cp -p "$CLAUDE_DIR/settings.json" "$CLAUDE_DIR/settings.json.bak-$(ts)" 2>/dev/null
  CLAUDE_DIR="$CLAUDE_DIR" python3 - <<'PY'
import json, os, collections
p = os.path.join(os.environ['CLAUDE_DIR'], 'settings.json')
d = json.load(open(p), object_pairs_hook=collections.OrderedDict) if os.path.exists(p) else collections.OrderedDict()
hooks = d.setdefault('hooks', collections.OrderedDict())
added = []
for event, name in (('SessionStart','session-start'),('Stop','stop'),
                    ('SessionEnd','session-end'),('PreCompact','precompact')):
    groups = hooks.setdefault(event, [])
    if any('mempalace' in str(h.get('command','')) for g in groups for h in g.get('hooks',[])):
        continue
    if event == 'SessionStart':
        cmd = 'bash "$HOME/.claude/skills/bootstrap/mempalace-session-start.sh"'
    else:
        cmd = ('[ -x "$HOME/.local/bin/mempalace" ] && "$HOME/.local/bin/mempalace" '
               f'hook run --hook {name} --harness claude-code || printf \'{{}}\\n\'')
    groups.append(collections.OrderedDict([("hooks", [
        collections.OrderedDict([("type","command"),("command",cmd)])])]))
    added.append(event)
json.dump(d, open(p,'w'), indent=2)
print("  ✓ capture hooks:", ", ".join(added) if added else "already present")
PY
fi

[ -f "$SELF_DIR/mempalace-rules.sh" ] && bash "$SELF_DIR/mempalace-rules.sh"

# 5. optional third-party cloud plugin ------------------------------------------
if [ "$WITH_CLOUD" = 1 ] && have claude; then
  claude plugin marketplace add cschnatz/mempalace-cloud-plugin >/dev/null 2>&1
  claude plugin install mempalace-cloud@mempalace-cloud >/dev/null 2>&1 \
    && note "✓ MemPalace Cloud plugin installed — NOTE: it auto-saves to api.mempalace.cloud, NOT your local palace"
fi

# 6. retire claude-mem ----------------------------------------------------------
if [ "$REMOVE" = 1 ]; then
  if have python3 && [ -f "$CLAUDE_DIR/settings.json" ]; then
    CLAUDE_DIR="$CLAUDE_DIR" python3 - <<'PY'
import json, os, collections
p = os.path.join(os.environ['CLAUDE_DIR'], 'settings.json')
d = json.load(open(p), object_pairs_hook=collections.OrderedDict)
if d.get('enabledPlugins', {}).pop('claude-mem@thedotmack', None) is not None:
    json.dump(d, open(p,'w'), indent=2); print("  ✓ claude-mem plugin disabled")
else:
    print("  · claude-mem plugin was not enabled")
PY
  fi
  pkill -f 'claude-mem' 2>/dev/null && note "✓ claude-mem worker stopped"
  if [ "$PURGE" = 1 ]; then
    rm -rf "$HOME/.claude-mem" && note "✓ ~/.claude-mem deleted (export kept at $EXPORT_DIR)"
  else
    note "· ~/.claude-mem KEPT as a backup — delete it yourself once you trust recall"
  fi
fi

echo
echo "Done. Restart Claude Code so the hooks and MCP load."
echo "Verify with:  mempalace status  &&  mempalace search \"something you worked on\""
