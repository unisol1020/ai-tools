#!/usr/bin/env bash
# claude-qa installer — symlinks the global manual-qa agent + qa skills into ~/.claude
# and registers the Playwright MCP (user scope) so QA works in every local project.
# Re-runnable; symlinks mean `git pull` updates everything automatically.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

mkdir -p "$CLAUDE_DIR/agents" "$CLAUDE_DIR/skills"

# rm the target first: ln -sfn nests a link *inside* a pre-existing real directory
link() { rm -rf "$2"; ln -s "$1" "$2"; echo "  linked $(basename "$2")"; }

echo "Installing claude-qa into $CLAUDE_DIR ..."
link "$DIR/agents/manual-qa.md"      "$CLAUDE_DIR/agents/manual-qa.md"
link "$DIR/skills/playwright-qa"     "$CLAUDE_DIR/skills/playwright-qa"
link "$DIR/skills/qa-run"            "$CLAUDE_DIR/skills/qa-run"

echo "Registering Playwright MCP (user scope, headless) ..."
if command -v claude >/dev/null 2>&1; then
  if claude mcp get playwright >/dev/null 2>&1; then
    echo "  playwright MCP already registered — skipping"
  else
    claude mcp add -s user playwright -- npx @playwright/mcp@latest --headless \
      && echo "  added playwright MCP" \
      || echo "  WARN: could not add playwright MCP — add manually: claude mcp add -s user playwright -- npx @playwright/mcp@latest --headless"
  fi
else
  echo "  WARN: 'claude' CLI not found on PATH — add the MCP manually after installing Claude Code."
fi

cat <<'DONE'

Done. Next:
  1. Restart Claude Code (MCP tools surface on restart).
  2. In any project, ask: "QA the login flow" or "verify <X> works in the browser".
     The qa-run skill will, on first run, ask for local-dev login creds (optional) and how to
     verify the DB — via a connected MCP (e.g. Supabase) or psql with a read-only DB URL you
     provide (local/dev). It remembers your choices per project, then runs the manual-qa agent.

Requirements: Node.js (for npx) and Claude Code. cmux (optional, macOS) is only used for
visual/design checks; functional QA needs only the Playwright MCP.
DONE
