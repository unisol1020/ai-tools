#!/usr/bin/env bash
# parallel-tasks installer — symlinks the task-research + task-parallel + task-runner
# skills and the qa-lock helper into ~/.claude and ~/.local/bin. Re-runnable; symlinks
# mean `git pull` updates everything automatically.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
BIN_DIR="$HOME/.local/bin"

mkdir -p "$CLAUDE_DIR/skills" "$BIN_DIR"

# rm the target first: ln -sfn nests a link *inside* a pre-existing real directory
link() { rm -rf "$2"; ln -s "$1" "$2"; echo "  linked $(basename "$2")"; }

echo "Installing parallel-tasks into $CLAUDE_DIR ..."
link "$DIR/skills/task-research"  "$CLAUDE_DIR/skills/task-research"
link "$DIR/skills/task-parallel"  "$CLAUDE_DIR/skills/task-parallel"
link "$DIR/skills/task-runner"    "$CLAUDE_DIR/skills/task-runner"
chmod +x "$DIR/bin/qa-lock.sh"
link "$DIR/bin/qa-lock.sh"        "$BIN_DIR/qa-lock"

echo "Verifying qa-lock ..."
"$DIR/bin/qa-lock.sh" selfcheck || echo "  ⚠ qa-lock selfcheck failed — check bash version"

echo "Checking dependencies ..."
dep() { command -v "$1" >/dev/null 2>&1 && echo "  ✓ $1" || echo "  ✗ $1 — $2"; }
dep git  "worktrees per task need git"
dep cmux "fan-out surfaces + live status need cmux (brew install --cask cmux; macOS)"
dep gh   "task-runner opens the PR via the GitHub CLI when no GitHub MCP is connected (brew install gh)"
case ":$PATH:" in *":$BIN_DIR:"*) ;; *) echo "  ⚠ $BIN_DIR is not on PATH — add it so 'qa-lock' resolves";; esac

cat <<'DONE'

Done. Next:
  1. Restart Claude Code once so the three skills load.
  2. Reuses the rest of claude-tools — make sure these are installed too:
       • team/     (architect + frontend/backend-engineer + automation-qa) — plan, build, test
       • qa/       (manual-qa + qa-run)                                     — the QA step
       • tickets/  (ticket skill)                                           — find/create the ticket + PR text
     Plus a connected tracker MCP (Linear or Jira). cmux (macOS) for the surfaces.
  3. Use it:
       "run task research routine — all bugs/features about <topic>"   → task-research (discover → triage → fan out)
       "run these tasks in parallel: <linear/jira links>"              → task-parallel (fan out now)
       ...then while they run:  "also run this one: <link>"            → adds a task on the fly

These are the SIMPLE, no-Docker path (plain worktrees, QA against your one real app/Simulator
serialized by qa-lock). For full per-task isolation (own Docker stack + DB) use loop/ instead.
DONE
