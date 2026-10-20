#!/usr/bin/env bash
# Migrate claude-mem -> MemPalace, and wire MemPalace's automatic capture hooks.
#   --remove-claude-mem   disable the claude-mem plugin + stop its worker (DB is KEPT)
#   --purge-claude-mem    additionally delete ~/.claude-mem (IRREVERSIBLE)
#   --with-cloud          also install the third-party MemPalace Cloud plugin (see README)
#   --skip-mine           export + hooks only, don't ingest
#   --fresh               rebuild the palace from scratch (needed if an earlier run
#                         mined everything into one flat wing)
set -uo pipefail

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REMOVE=0; PURGE=0; WITH_CLOUD=0; SKIP_MINE=0; FRESH=0
for a in "$@"; do case "$a" in
  --remove-claude-mem) REMOVE=1 ;;
  --purge-claude-mem)  REMOVE=1; PURGE=1 ;;
  --with-cloud)        WITH_CLOUD=1 ;;
  --skip-mine)         SKIP_MINE=1 ;;
  --fresh)             FRESH=1 ;;
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
# Hooks save and recall under the repo's wing, so each project is mined into its
# repo wing. An earlier version mined everything into one flat wing that no repo
# reads; detect that and rebuild rather than stacking per-wing copies on top of it.
if [ "$SKIP_MINE" = 0 ] && mempalace status 2>/dev/null | grep -q "WING: claude_mem_export"; then
  if [ "$FRESH" = 1 ]; then
    PALACE_DIR="${MEMPALACE_PALACE:-$HOME/.mempalace/palace}"
    mv "$PALACE_DIR" "$PALACE_DIR.flat-backup-$(ts)" 2>/dev/null \
      && note "✓ old flat palace moved aside; rebuilding per-project"
  else
    note "⚠ this palace has a flat 'claude_mem_export' wing from an earlier migration."
    note "⚠ nothing in it is recalled for any repo until it is rebuilt."
    note "⚠ re-run with --fresh to rebuild per-project (the export is reused; only mining repeats)."
    SKIP_MINE=1
  fi
fi

PALACE_DB="${MEMPALACE_PALACE:-$HOME/.mempalace/palace}/chroma.sqlite3"
if [ "$SKIP_MINE" = 0 ] && [ -f "$PALACE_DB" ] && have sqlite3 \
   && [ "$(sqlite3 -readonly "$PALACE_DB" "SELECT count(*) FROM embedding_metadata WHERE key='source_file' AND string_value LIKE '$EXPORT_DIR/%'" 2>/dev/null)" -gt 0 ] 2>/dev/null; then
  note "⚠ the palace already holds a claude-mem import; mining again would duplicate it."
  note "⚠ to re-import cleanly: bash \"$SELF_DIR/mempalace-hook.sh\" reorg --reimport-claude-mem"
  SKIP_MINE=1
fi

if [ "$SKIP_MINE" = 0 ] && [ -d "$EXPORT_DIR/projects" ]; then
  note "→ dry run…"
  TOTAL_SKIP=0
  for d in "$EXPORT_DIR"/projects/*/; do
    [ -d "$d" ] || continue
    DRY="$(mempalace mine "$d" --wing "$(bash "$SELF_DIR/mempalace-hook.sh" wing-name "$(basename "$d")" || basename "$d")" --dry-run 2>&1)"
    if echo "$DRY" | grep -q "chunk cap"; then
      TOTAL_SKIP=1
      note "⚠ $(basename "$d"): $(echo "$DRY" | grep 'chunk cap' | tr -d '\n')"
    fi
  done
  [ "$TOTAL_SKIP" = 1 ] && note "⚠ files above were SKIPPED SILENTLY — those memories will NOT import"

  note "→ mining (local embeddings, no API key; CPU-heavy, can take a while)…"
  for d in "$EXPORT_DIR"/projects/*/; do
    [ -d "$d" ] || continue
    W="$(bash "$SELF_DIR/mempalace-hook.sh" wing-name "$(basename "$d")")" || W="$(basename "$d")"
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

have python3 && bash "$SELF_DIR/mempalace-wire-hooks.sh"

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
  # The worker re-parents to init and keeps a chroma/onnxruntime child tree
  # alive, so a single pkill leaves an orphan burning memory. Sweep twice.
  for _ in 1 2 3; do
    pgrep -f 'claude-mem' >/dev/null 2>&1 || break
    pkill -f 'thedotmack/claude-mem' 2>/dev/null
    pkill -f 'claude-mem.*worker-service' 2>/dev/null
    pkill -f 'chroma-mcp.*\.claude-mem' 2>/dev/null
    sleep 2
  done
  if pgrep -f 'claude-mem' >/dev/null 2>&1; then
    note "⚠ some claude-mem processes survived: $(pgrep -f 'claude-mem' | tr '\n' ' ')"
  else
    note "✓ claude-mem stopped (worker + chroma children)"
  fi
  if [ "$PURGE" = 1 ]; then
    rm -rf "$HOME/.claude-mem" && note "✓ ~/.claude-mem deleted (export kept at $EXPORT_DIR)"
  else
    note "· ~/.claude-mem KEPT as a backup — delete it yourself once you trust recall"
  fi
fi

echo
echo "Done. Restart Claude Code so the hooks and MCP load."
echo "Verify with:  mempalace status  &&  mempalace search \"something you worked on\""
