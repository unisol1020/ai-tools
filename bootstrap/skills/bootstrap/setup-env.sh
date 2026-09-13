#!/usr/bin/env bash
# Idempotent environment setup for the ai-tools stack. Installs + configures the
# extensions the projects here expect — ripgrep, CodeGraph (+ its MCP), graphify (+ its
# skill), and the ponytail plugin — but ONLY the ones missing. Safe to re-run.
#
# Runnable two ways:
#   bash ~/.claude/skills/bootstrap/setup-env.sh     # standalone, from a terminal
#   (invoked by the /bootstrap skill)
set -uo pipefail
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
have() { command -v "$1" >/dev/null 2>&1; }
note() { printf '  %s\n' "$*"; }
ts()   { date +%Y%m%d-%H%M%S; }

echo "Setting up the ai-tools stack (installs only what's missing) ..."

# 1. ripgrep ----------------------------------------------------------------
if have rg; then note "✓ ripgrep already installed"
elif have brew; then note "installing ripgrep…"; brew install ripgrep >/dev/null && note "✓ ripgrep"
else note "✗ ripgrep missing — install Homebrew or your distro's ripgrep package"; fi

# 2. CodeGraph CLI + MCP ----------------------------------------------------
if have codegraph; then note "✓ codegraph already installed ($(codegraph --version 2>/dev/null))"
else
  note "installing @colbymchenry/codegraph…"
  if   have volta; then volta install @colbymchenry/codegraph >/dev/null 2>&1
  elif have npm;   then npm  i -g     @colbymchenry/codegraph >/dev/null 2>&1
  else note "✗ codegraph needs node/npm (or volta) — install Node first"; fi
  have codegraph && note "✓ codegraph installed" || note "✗ codegraph install failed — run: npm i -g @colbymchenry/codegraph"
fi
# Wire the CodeGraph MCP into Claude Code (non-interactive, global, auto-allow).
if have codegraph; then
  codegraph install -y >/dev/null 2>&1 && note "✓ codegraph MCP wired into Claude Code" \
    || note "… run 'codegraph install -y' manually to add the MCP"
fi

# 3. graphify (PyPI pkg 'graphifyy', provides the 'graphify' CLI) + its skill --
# safishamsi/graphify is a Python tool needing Python 3.10+. Install with uv/pipx —
# they fetch a compatible Python, isolate the package, and put 'graphify' on PATH.
# Avoid plain 'pip install': it breaks when system Python < 3.10 or the env mismatches.
if have graphify; then note "✓ graphify already installed ($(graphify --version 2>/dev/null))"
else
  note "installing graphifyy (Python)…"
  if   have uv;   then uv tool install graphifyy >/dev/null 2>&1
  elif have pipx; then pipx install graphifyy >/dev/null 2>&1
  elif have brew; then brew install uv >/dev/null 2>&1 && uv tool install graphifyy >/dev/null 2>&1
  else note "✗ graphify needs uv or pipx (Python 3.10+) — 'brew install uv', then re-run"; fi
  have graphify && note "✓ graphify installed" \
    || note "… graphify not on PATH — add ~/.local/bin (try 'uv tool update-shell'), reopen shell, re-run"
fi
# Register the graphify skill into Claude Code (gives the /graphify command).
if [ -f "$CLAUDE_DIR/skills/graphify/SKILL.md" ]; then note "✓ graphify skill already installed"
elif have graphify; then
  graphify install >/dev/null 2>&1 && note "✓ graphify skill installed (/graphify available after restart)" \
    || note "… run 'graphify install' manually"
fi

# 4. plugin: ponytail (merge marketplace + enable into settings.json) ----------
if have jq; then
  mkdir -p "$CLAUDE_DIR"; sj="$CLAUDE_DIR/settings.json"; [ -f "$sj" ] || echo '{}' > "$sj"
  if jq -e '.enabledPlugins["ponytail@ponytail"] == true' "$sj" >/dev/null 2>&1; then
    note "✓ ponytail plugin already enabled"
  else
    cp -p "$sj" "$sj.bak-$(ts)"
    jq '.extraKnownMarketplaces.ponytail.source = {source:"github", repo:"DietrichGebert/ponytail"}
        | .enabledPlugins = (.enabledPlugins // {})
        | .enabledPlugins["ponytail@ponytail"] = true' "$sj" > "$sj.tmp" && mv "$sj.tmp" "$sj" \
      && note "✓ ponytail marketplace + enable written to settings.json (fetched on next Claude Code start)"
  fi
else note "✗ jq needed to enable the ponytail plugin — brew install jq"; fi

# 5. MemPalace: cross-session memory — local embeddings, no API key ------------
if have mempalace; then note "✓ mempalace already installed"
else
  if have uv; then uv tool install mempalace >/dev/null 2>&1
  elif have pipx; then pipx install mempalace >/dev/null 2>&1
  elif have brew; then brew install uv >/dev/null 2>&1 && uv tool install mempalace >/dev/null 2>&1
  else note "✗ mempalace needs uv or pipx (Python 3.10+) — 'brew install uv', then re-run"; fi
  have mempalace && note "✓ mempalace installed" \
    || note "… mempalace not on PATH — add ~/.local/bin (try 'uv tool update-shell'), reopen shell, re-run"
fi
if have mempalace && have claude; then
  if claude mcp list 2>/dev/null | grep -q '^mempalace'; then
    note "✓ mempalace MCP already registered"
  else
    claude mcp add mempalace -- mempalace-mcp >/dev/null 2>&1 \
      && note "✓ mempalace MCP registered (available after restart)" \
      || note "… run 'claude mcp add mempalace -- mempalace-mcp' manually"
  fi
fi

echo "Done. Restart Claude Code once so the ponytail plugin + CodeGraph/MemPalace MCP load."
