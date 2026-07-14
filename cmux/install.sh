#!/usr/bin/env bash
# cmux-setup installer — lays down a cmux + Ghostty + Claude Code environment 1:1.
# SAFE: every target file is backed up to a timestamped .bak before being written, and
# Claude Code settings are MERGED (never overwritten). macOS only.
#
# Flags:
#   --with-deps   brew-install missing deps (Cursor, JetBrains Mono Nerd Font, jq)
#   --with-db     brew-install the recommended terminal SQL client (harlequin)
# WARNING: the merged settings include permissions.defaultMode=bypassPermissions
# (auto-approves ALL tool calls). Delete those keys from the snippet to opt out.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WITH_DEPS=0; WITH_DB=0
for a in "$@"; do case "$a" in
  --with-deps) WITH_DEPS=1 ;; --with-db) WITH_DB=1 ;;
  --bypass) echo "note: --bypass is obsolete — bypassPermissions now ships in the settings snippet" ;;
  *) echo "unknown flag: $a" >&2; exit 2 ;;
esac; done

[ "$(uname)" = "Darwin" ] || { echo "macOS only (cmux is macOS-only)." >&2; exit 1; }
ts() { date +%Y%m%d-%H%M%S; }
backup() { [ -e "$1" ] && cp -p "$1" "$1.bak-$(ts)" && echo "  backed up $1 -> $1.bak-$(ts)"; }
render() { sed "s|__HOME__|$HOME|g" "$1"; }

mkdir -p "$HOME/.config/cmux" "$HOME/.config/ghostty" "$HOME/.claude" "$HOME/.local/bin"

echo "Installing cmux + Ghostty + statusline config ..."

# 1. cmux.json (preferredEditor path rendered to your home)
backup "$HOME/.config/cmux/cmux.json"
render "$DIR/config/cmux.json" > "$HOME/.config/cmux/cmux.json"; echo "  wrote ~/.config/cmux/cmux.json"

# 2. editor-open wrapper (routes text/code opens to Cursor at the git repo root)
backup "$HOME/.config/cmux/open-in-micro.sh"
cp "$DIR/config/open-in-micro.sh" "$HOME/.config/cmux/open-in-micro.sh"
chmod +x "$HOME/.config/cmux/open-in-micro.sh"; echo "  wrote ~/.config/cmux/open-in-micro.sh"

# 3. Ghostty terminal rendering (colors / theme / opacity / blur / font)
backup "$HOME/.config/ghostty/config"
cp "$DIR/config/ghostty-config" "$HOME/.config/ghostty/config"; echo "  wrote ~/.config/ghostty/config"

# 4. Claude Code statusline script
backup "$HOME/.claude/statusline.sh"
cp "$DIR/config/statusline.sh" "$HOME/.claude/statusline.sh"
chmod +x "$HOME/.claude/statusline.sh"; echo "  wrote ~/.claude/statusline.sh"

# 5. Merge the visual/functional keys into ~/.claude/settings.json (deep merge, snippet wins)
snip="$(render "$DIR/config/claude-settings.snippet.json" | jq 'del(."//")')"
if command -v jq >/dev/null 2>&1; then
  backup "$HOME/.claude/settings.json"
  if [ -f "$HOME/.claude/settings.json" ]; then
    printf '%s' "$snip" | jq -s '.[0] * .[1]' "$HOME/.claude/settings.json" /dev/stdin > "$HOME/.claude/settings.json.tmp" \
      && mv "$HOME/.claude/settings.json.tmp" "$HOME/.claude/settings.json"
  else
    printf '%s\n' "$snip" > "$HOME/.claude/settings.json"
  fi
  echo "  merged statusLine/theme/tui/effort/model/ultracode/bypassPermissions into ~/.claude/settings.json"
  echo "  ⚠ permissions.defaultMode=bypassPermissions is ON (auto-approves ALL tool calls)"
else
  echo "  WARN: jq not found — skipped settings merge. Set statusLine manually (see README)."
fi

# 6. db-tui launcher on PATH
ln -sf "$DIR/bin/db-tui.sh" "$HOME/.local/bin/db-tui"; echo "  linked ~/.local/bin/db-tui"

# 7. Optional dep installs
brew_has() { command -v brew >/dev/null 2>&1; }
if [ "$WITH_DEPS" = 1 ]; then
  brew_has && { echo "Installing deps via brew ..."
    command -v jq     >/dev/null 2>&1 || brew install jq
    command -v cursor >/dev/null 2>&1 || brew install --cask cursor
    brew list --cask font-jetbrains-mono-nerd-font >/dev/null 2>&1 || { brew tap homebrew/cask-fonts 2>/dev/null; brew install --cask font-jetbrains-mono-nerd-font; }
  } || echo "  WARN: Homebrew not found; install deps manually (see README)."
fi
if [ "$WITH_DB" = 1 ]; then
  brew_has && { command -v harlequin >/dev/null 2>&1 || brew install harlequin; } || echo "  WARN: Homebrew not found; install harlequin manually."
fi

# 9. Reload cmux (covers cmux.json + Ghostty config; no app restart)
command -v cmux >/dev/null 2>&1 && cmux reload-config >/dev/null 2>&1 && echo "  reloaded cmux config"

echo
echo "=== Dependency check ==="
chk() { if command -v "$1" >/dev/null 2>&1; then echo "  ✓ $1"; else echo "  ✗ $1 — $2"; fi; }
chk cmux      "brew install --cask cmux"
chk cursor    "brew install --cask cursor  (the editor the open wrapper drives)"
chk jq        "brew install jq             (statusline + settings merge)"
chk harlequin "brew install harlequin      (terminal SQL client; or use db-tui's other clients)"
brew list --cask font-jetbrains-mono-nerd-font >/dev/null 2>&1 && echo "  ✓ JetBrains Mono Nerd Font" || echo "  ✗ JetBrains Mono Nerd Font — brew install --cask font-jetbrains-mono-nerd-font"

cat <<'DONE'

Done. Notes:
  • Restart Claude Code once so the statusline + merged settings take effect.
  • The [PONYTAIL] badge is a static label the statusline always shows. The ponytail
    plugin (lazy-senior-dev mode) installs separately: /plugin in Claude Code, add
    marketplace DietrichGebert/ponytail, enable it.
  • ⚠ "bypass permissions on" IS enabled (ships in the settings snippet) — every tool
    call is auto-approved. Opt out: delete the permissions key from ~/.claude/settings.json
    or cycle modes with Shift+Tab in Claude Code.
  • Open a DB anywhere:  db-tui 'postgres://user:pass@host/db'   (right-side cmux split)
  • Revert anything from the timestamped .bak files next to each target.
DONE
