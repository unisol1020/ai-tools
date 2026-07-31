#!/usr/bin/env bash
# ai-tickets installer — symlinks the global `ticket` skill into ~/.claude/skills
# so human-readable Linear/Jira ticket creation works in every project.
# Re-runnable; the symlink means `git pull` updates it automatically.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

mkdir -p "$CLAUDE_DIR/skills"

# rm the target first: ln -sfn nests a link *inside* a pre-existing real directory
link() { rm -rf "$2"; ln -s "$1" "$2"; echo "  linked $(basename "$2")"; }

echo "Installing ai-tickets into $CLAUDE_DIR ..."
link "$DIR/skills/ticket" "$CLAUDE_DIR/skills/ticket"

echo
echo "Checking for a connected tracker MCP ..."
if command -v claude >/dev/null 2>&1; then
  mcps="$(claude mcp list 2>/dev/null || true)"
  echo "$mcps" | grep -iq 'linear'              && echo "  ✓ Linear MCP detected"   || true
  echo "$mcps" | grep -iqE 'jira|atlassian'     && echo "  ✓ Atlassian/Jira MCP detected" || true
  if ! echo "$mcps" | grep -iqE 'linear|jira|atlassian'; then
    echo "  ⚠ No Linear or Atlassian (Jira) MCP found."
    echo "    Connect one before creating tickets:"
    echo "      • Linear / Jira via the claude.ai integrations panel, or"
    echo "      • your own MCP:  claude mcp add -s user <name> -- <command>"
  fi
else
  echo "  WARN: 'claude' CLI not on PATH — install Claude Code, then connect a Linear or Atlassian MCP."
fi

cat <<'DONE'

Done. Next:
  1. Restart Claude Code (so the skill and any tracker MCP tools load).
  2. Connect a Linear or Atlassian (Jira) MCP if you haven't.
  3. In any project, just ask — no command needed:
       "create a ticket for this bug"   "file a Linear issue for the discount bug"
       "open a Jira ticket: add CSV export to reports"   or  /ticket
     First run in a project, it asks once which tracker + team/project to use,
     then remembers it in .claude/tickets.local.json.

It writes short, human-readable tickets (reproduction + verification + where the
problem is), pulls any Figma/design/screenshot links from the chat into the ticket,
and posts recent test results as a comment.
DONE
