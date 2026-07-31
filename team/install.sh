#!/usr/bin/env bash
# ai-team installer — symlinks the crew of planner / engineer / reviewer / tester
# agents into ~/.claude/agents so they're available in every local project.
# Re-runnable; symlinks mean `git pull` updates everything automatically.
#
# NOT installed here (they live with their own tools, on purpose):
#   • manual-qa  → in qa/    (install qa/)
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

mkdir -p "$CLAUDE_DIR/agents"

# rm the target first: ln -sfn nests a link *inside* a pre-existing real directory
link() { rm -rf "$2"; ln -s "$1" "$2"; echo "  linked $(basename "$2")"; }

echo "Installing ai-team into $CLAUDE_DIR ..."
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
       reviews run after changes           → backend-reviewer / frontend-reviewer / security-reviewer

Recommended for the architect's Phase 1 "grill" (interrogation) step — the **grill-me** skill
by Matt Pocock. It's the best grill skill out there: a relentless, one-question-at-a-time
interview that pins a plan down before any code is written. Thank you, Matt! 🙏 (MIT)
  https://github.com/mattpocock/skills
It's NOT bundled here — install it locally once, then restart:
  claude plugin marketplace add mattpocock/skills
  claude plugin install mattpocock-skills@mattpocock
If present, the architect routes its Phase-1 questioning through it; if absent, it builds the
question list itself. grill-me runs a /grilling session, so both skills come with it.

Pairs with the rest of ai-tools: the architect's babysit protocol
dispatches exactly these agents (plan → implement → test → review), and qa/ adds manual-qa.

Requirements: Claude Code. Individual agents use whatever MCPs are connected (Supabase,
Playwright, trackers, Figma, …) — none are required to install.
DONE
