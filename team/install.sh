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

# The dispatch block in the user's global CLAUDE.md is what makes "test this" reach manual-qa
# without naming it; agent descriptions alone are only a hint. Markers keep it replaceable.
md="$CLAUDE_DIR/CLAUDE.md"; start='<!-- ai-tools:dispatch:start -->'; end='<!-- ai-tools:dispatch:end -->'
if [ -f "$md" ] && grep -qF "$start" "$md"; then
  cp -p "$md" "$md.bak-$(date +%Y%m%d-%H%M%S)"
  awk -v s="$start" -v e="$end" -v f="$DIR/dispatch.md" '
    index($0,s)==1 { while ((getline l < f) > 0) print l; skip=1; next }
    index($0,e)==1 { skip=0; next }
    !skip' "$md" > "$md.tmp" && mv "$md.tmp" "$md"
  echo "  refreshed the agent-dispatch block in $md"
else
  if [ -s "$md" ]; then
    [ -n "$(tail -c1 "$md")" ] && echo >> "$md"
    echo >> "$md"
  fi
  cat "$DIR/dispatch.md" >> "$md"
  echo "  appended the agent-dispatch block to $md"
fi

cat <<'DONE'

Done. Next:
  1. Restart Claude Code once so the agents load.
  2. Just say what you need — the dispatch block now in ~/.claude/CLAUDE.md routes plain
     requests to the right agent without naming it:
       "plan this / how should we build it"     → architect  (plans; never implements)
       "fix this in the api / add an endpoint"  → backend-engineer
       "looks bad on the frontend / fix the form" → frontend-engineer
       "write tests / cover this"               → automation-qa
       "test this / check it works"             → qa-run skill → manual-qa (install qa/)
       after code changes, before merge         → backend-reviewer / frontend-reviewer / security-reviewer

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
