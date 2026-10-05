#!/usr/bin/env bash
# ai-team installer — symlinks the crew of planner / engineer / reviewer / tester
# agents into ~/.claude/agents so they're available in every local project.
# Re-runnable; symlinks mean `git pull` updates everything automatically.
#
# Flags:
#   --uninstall   remove the agent links, the crew-cost links and the dispatch block
#
# NOT installed here (they live with their own tools, on purpose):
#   • manual-qa  → in qa/    (install qa/)
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
md="$CLAUDE_DIR/CLAUDE.md"; start='<!-- ai-tools:dispatch:start -->'; end='<!-- ai-tools:dispatch:end -->'

BINDIR=""
for d in "$HOME/.local/bin" "$HOME/bin"; do
  [ -d "$d" ] && { BINDIR="$d"; break; }
done
[ -n "$BINDIR" ] || BINDIR="$HOME/.local/bin"

uninstall() {
  echo "Uninstalling ai-team from $CLAUDE_DIR ..."
  for a in "$DIR"/agents/*.md; do
    p="$CLAUDE_DIR/agents/$(basename "$a")"
    [ -L "$p" ] && { rm -f "$p"; echo "  removed $p"; }
  done
  for p in "$CLAUDE_DIR/bin/crew-cost" "$BINDIR/crew-cost"; do
    [ -L "$p" ] && { rm -f "$p"; echo "  removed $p"; }
  done
  if [ -f "$md" ] && grep -qF "$start" "$md"; then
    cp -p "$md" "$md.bak-$(date +%Y%m%d-%H%M%S)"
    awk -v s="$start" -v e="$end" 'index($0,s)==1 { skip=1; next } index($0,e)==1 { skip=0; next } !skip' "$md" > "$md.tmp" && mv "$md.tmp" "$md"
    echo "  removed the agent-dispatch block from $md (backup alongside)"
  fi
  echo "Done. manual-qa belongs to qa/ and was left alone."
}

[ "${1:-}" = "--uninstall" ] && { uninstall; exit 0; }

mkdir -p "$CLAUDE_DIR/agents" "$CLAUDE_DIR/bin"

# rm the target first: ln -sfn nests a link *inside* a pre-existing real directory
link() { rm -rf "$2"; ln -s "$1" "$2"; echo "  linked $(basename "$2")"; }

echo "Installing ai-team into $CLAUDE_DIR ..."
for a in "$DIR"/agents/*.md; do
  link "$a" "$CLAUDE_DIR/agents/$(basename "$a")"
done

chmod +x "$DIR/bin/crew-cost"
link "$DIR/bin/crew-cost" "$CLAUDE_DIR/bin/crew-cost"

mkdir -p "$BINDIR"
ln -sfn "$DIR/bin/crew-cost" "$BINDIR/crew-cost"
echo "  put crew-cost in $BINDIR"
case ":$PATH:" in
  *":$BINDIR:"*) ;;
  *) echo "  NOTE: $BINDIR is not on your PATH. Add this to your shell rc:"
     echo "        export PATH=\"$BINDIR:\$PATH\""
     echo "        (until then, use the full path: $BINDIR/crew-cost)" ;;
esac

# The dispatch block in the user's global CLAUDE.md is what makes "test this" reach manual-qa
# without naming it; agent descriptions alone are only a hint. Markers keep it replaceable.
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

# The agents reach for these before they read anything. Missing ones aren't fatal —
# the agent just falls back to reading files, which is slower and costs more tokens.
# Report only; installing is the bootstrap installer's job.
have() { command -v "$1" >/dev/null 2>&1; }
echo
echo "Toolchain the crew uses to avoid reading files:"
MISSING=0
check() { if have "$1" || { [ "$1" = ast-grep ] && have sg; }; then echo "  ✓ $1 — $2"; else echo "  ✗ $1 — $2"; MISSING=1; fi; }
check rg        "ripgrep; the Grep tool IS ripgrep — one search instead of one Read"
check ast-grep  "structural search for symbols, routes and call sites"
check codegraph "symbols + callers + call paths in one call"
check graphify  "relations that cross files and apps"
check mempalace "cross-session memory, so nothing is re-derived next session"
if [ "$MISSING" = 1 ]; then
  echo "  → install every missing one in a single idempotent pass:"
  echo "      bash $(cd "$DIR/.." && pwd)/bootstrap/skills/bootstrap/setup-env.sh"
  echo "    (that script installs only what's absent, and is safe to re-run)"
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
  3. After a session, run `crew-cost` in the repo to see what each agent type cost in tokens
     (counts, no prices; `crew-cost <transcript.jsonl>` for another session, --json for machines).

Recommended for the architect's Phase 1 "grill" step — **grill-with-ui** by Jason Ku (MIT):
the grill as question cards on a local browser page, answered in any order and sent in rounds.
  git clone https://github.com/jasonku09/grill-with-ui ~/Developer/grill-with-ui
  ln -s ~/Developer/grill-with-ui ~/.claude/skills/grill-with-ui
Terminal fallback for sessions with no browser — **grill-me** by Matt Pocock (MIT):
  claude plugin marketplace add mattpocock/skills
  claude plugin install mattpocock-skills@mattpocock
Neither is bundled here. If either is present the architect routes its Phase-1 questioning
through it; if neither is, it builds the question list itself. Restart after installing.

Pairs with the rest of ai-tools: the architect's babysit protocol
dispatches exactly these agents (plan → implement → test → review), and qa/ adds manual-qa.

Requirements: Claude Code. Every agent uses whatever MCPs are connected (tracker, Slack,
Notion, Wispr Flow, Figma, Sentry, a database, Playwright) and discovers them at run time —
none are required to install. The CLI toolchain listed above isn't required either, but the
agents are written to reach for it before reading files, so installing it is the cheapest
thing you can do for token cost.
DONE
