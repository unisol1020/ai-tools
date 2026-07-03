#!/usr/bin/env bash
# claude-team installer — symlinks the crew of planner / engineer / reviewer / tester
# agents into ~/.claude/agents so they're available in every local project.
# Re-runnable; symlinks mean `git pull` updates everything automatically.
#
# manual-qa lives here too, but only functions with qa/'s Playwright MCP + qa-run skill.
# NOT installed here (infra, lives with its tool on purpose):
#   • devops  → in loop/  (install loop/)
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

mkdir -p "$CLAUDE_DIR/agents"

# rm the target first: ln -sfn nests a link *inside* a pre-existing real directory
link() { rm -rf "$2"; ln -s "$1" "$2"; echo "  linked $(basename "$2")"; }

echo "Installing claude-team into $CLAUDE_DIR ..."
for a in "$DIR"/agents/*.md; do
  link "$a" "$CLAUDE_DIR/agents/$(basename "$a")"
done

cat <<'DONE'

Done. Next:
  1. Restart Claude Code once so the agents load.
  2. Use them — Claude picks the right one automatically, or name one:
       "plan this feature"                 → architect  (plans; never implements)
       "add the endpoint / build the page" → backend-engineer / frontend-engineer
       "write tests for this"              → automation-qa
       "QA this in the browser"            → manual-qa   (needs qa/'s Playwright MCP + qa-run skill)
       reviews run after changes           → backend-reviewer / frontend-reviewer / security-reviewer

Optional but recommended for the architect's Phase 1 "grill" (interrogation) step:
  a **grill-me** skill in your skill list. If present, the architect invokes it to run the
  questioning; if absent, it builds the question list itself — so this is a nice-to-have, not
  a requirement. Install one by dropping a grill-me skill into ~/.claude/skills, then restart.

Pairs with the rest of claude-tools: the loop/ engine and the architect's babysit protocol
dispatch exactly these agents (plan → implement → test → review). manual-qa needs qa/ for
its browser (Playwright MCP + qa-run skill) — install qa/ to use it.

Requirements: Claude Code. Individual agents use whatever MCPs are connected (Supabase,
Playwright, trackers, Figma, …) — none are required to install.
DONE
