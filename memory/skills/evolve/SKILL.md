---
name: evolve
description: >-
  Run the agent-memory curator now instead of waiting for the automatic SessionStart
  trigger. Use when the user says "/evolve", "consolidate agent memory", "evolve the
  agents", "promote lessons", or when the hook printed EVOLVE DUE and nothing was spawned.
  Shows agent-memory status, spawns the memory-curator subagent in the background for the
  current repo (--all: every repo in the registry), relays its report, and reminds the user
  that deleting a memory file is the veto. Runs in the MAIN thread; the curator does the work.
---

# evolve — consolidate agent memory on demand

The SessionStart hook spawns the curator on its own when a threshold is crossed. `/evolve` is the manual trigger: same curator, same bounds, no waiting for the threshold.

## Steps

1. **Status.** Resolve the CLI and print the repo's memory state:

   ```bash
   AM="$HOME/.claude/bin/agent-memory"; [ -x "$AM" ] || AM="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/bin/agent-memory"
   cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" && "$AM" status
   ```

   No `agent-memory` binary → say the memory tool is not installed (`bash ~/.ai-tools/memory/install.sh`, then restart Claude Code) and stop. Show the status output as is; it is short.

2. **Scope.** Default is the current repo: `MAIN=$("$AM" root)`. With `--all`, the targets are every existing path in `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/agent-memory/.registry` (skip lines whose path is gone and say which). If `status` says the repo is **locked**, a curator is already running (or died less than 60 minutes ago): report that and do not spawn for that repo; the user can `rmdir <MAIN>/.claude/agent-memory-local/.curator/lock` if they know nothing is running.

3. **Spawn.** For each target, first take its lock: `cd "<MAIN>" && "$AM" lock` (exit 1 = a curator already holds it; report that and skip the repo). Then one Agent tool call: `subagent_type: "memory-curator"`, run in the background, prompt exactly `Consolidate agent memory for <MAIN>`. Nothing else goes in the prompt: the SubagentStart hook briefs the curator with `agent-memory report`, and its stop releases the lock. Do not wait; continue with whatever the user asked. With `--all` the runs may overlap, each repo has its own lock.

4. **Relay.** When a curator finishes, pass its report through unchanged: the counts line, the `Leftover:` line and every path under `Changed:`. Do not summarise the paths away; the user needs them to veto.

5. **Close.** After the report, one reminder:
   - Deleting a file listed under `Changed:` is the veto. For a GLOBAL entry use `agent-memory veto <agent> <slug>` so it is never re-promoted.
   - Suggestions for CLAUDE.md, agent prompts or skills were appended to `~/.claude/agent-memory/proposals.md`; nothing was applied.
   - If `Leftover:` is not `none`, the curator hit its per-run bound; run `/evolve` again to finish.

## Not this skill

- `agent-memory lint --fix` is the zero-token cleanup (indexes, oversized files, decay); use it when no judgement is needed.
- The curator never edits agents, skills, CLAUDE.md or code; if the user wants a proposal applied, that is a normal edit in the main thread.
