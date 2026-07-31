#!/usr/bin/env bash
# ai-morning installer — symlinks the `morning` and `review-prs` skills into
# ~/.claude/skills so the morning briefing + PR review work in every project.
# Re-runnable; the symlinks mean `git pull` updates them automatically.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

mkdir -p "$CLAUDE_DIR/skills"

# rm the target first: ln -sfn nests a link *inside* a pre-existing real directory
link() { rm -rf "$2"; ln -s "$1" "$2"; echo "  linked $(basename "$2")"; }

echo "Installing ai-morning into $CLAUDE_DIR ..."
link "$DIR/skills/morning"    "$CLAUDE_DIR/skills/morning"
link "$DIR/skills/review-prs" "$CLAUDE_DIR/skills/review-prs"

echo
echo "Checking dependencies ..."
if command -v gh >/dev/null 2>&1; then
  gh auth status >/dev/null 2>&1 && echo "  ✓ gh CLI authenticated" \
    || echo "  ⚠ gh CLI found but not authenticated — run 'gh auth login'"
else
  echo "  ✗ gh CLI not found — install it ('brew install gh') and 'gh auth login'. Required for PR review."
fi

if command -v claude >/dev/null 2>&1; then
  mcps="$(claude mcp list 2>/dev/null || true)"
  echo "$mcps" | grep -iq 'linear'          && echo "  ✓ Linear MCP detected"          || true
  echo "$mcps" | grep -iqE 'jira|atlassian' && echo "  ✓ Atlassian/Jira MCP detected"   || true
  echo "$mcps" | grep -iq 'slack'           && echo "  ✓ Slack MCP detected"            || true
  echo "$mcps" | grep -iqE 'linear|jira|atlassian' \
    || echo "  ⚠ No tracker MCP (Linear/Jira) — the 'my tickets' section will be skipped until you connect one."
  echo "$mcps" | grep -iq 'slack' \
    || echo "  ⚠ No Slack MCP — the Slack section will be skipped until you connect one."
else
  echo "  WARN: 'claude' CLI not on PATH — connect Linear/Jira + Slack MCPs to get the full briefing."
fi

cat <<'DONE'

Done. Next:
  1. Restart Claude Code (so the skills and any MCP tools load).
  2. Connect a Linear or Atlassian (Jira) MCP and a Slack MCP for the full morning briefing.
  3. Use them in any project — no command needed:
       "do my morning routine"        or  /morning
       "review all PRs"               "review this PR: <url>"   or  /review-prs

First /morning asks once for the repos to scan + Slack channels, then remembers them
in ~/.claude/morning.local.json. PR comments are always shown for your OK before
anything is posted to a colleague's PR.
DONE
