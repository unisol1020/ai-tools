# claude-team

The **crew of subagents** Claude Code delegates real work to — the ones that plan, build, review, and test. They install into `~/.claude/agents` and work in every local project. Claude picks the right one automatically (or you name it), and the `loop` engine + the architect's babysit protocol dispatch exactly this crew to take a change from plan → code → tests → review.

Two members of the crew live with their own tools on purpose and are **not** installed here:
- **`manual-qa`** ships in [`qa/`](../qa/README.md) — it needs the Playwright MCP and the `qa-run` skill.
- **`devops`** ships in [`loop/`](../loop/README.md) — it stands up the loop's per-task Docker stacks.

Install those tools to get those agents.

## The crew

| Agent | Role | Writes |
|-------|------|--------|
| `architect` | The single **planning** authority. Gathers all context (CLAUDE.md hierarchy, tickets, Figma, DB, running app via MCPs), grills you until the task is understood, and emits self-contained plan files + a parallel-execution graph + a per-phase babysit protocol. Plans; never implements. | plan files only |
| `backend-engineer` | Implements **server-side** work — endpoints, services, DB queries/migrations, jobs, webhooks, server config. | production code |
| `frontend-engineer` | Implements **UI** work in any frontend app (React/Next, Vue, Svelte, Expo, …) — pages, forms, components, wiring to endpoints. | production code |
| `automation-qa` | The **test author**. After a feature/bugfix (or a manual-QA handoff), checks coverage then writes the missing unit + integration tests. | test files only |
| `backend-reviewer` | Reviews backend/API/DB changes — cited, prioritized findings. | report only |
| `frontend-reviewer` | Reviews frontend/UI changes — cited, prioritized findings. | report only |
| `security-reviewer` | Security review of a diff before merge (authn/z, input, data, secrets, uploads, redirects, webhooks, …). | report only |

The split is deliberate: engineers write code but not tests; the test-author writes tests but not code; reviewers only report. That separation is what lets the `loop` and `architect` chain them safely.

## Install — just send this README to Claude Code

You don't run anything. Paste this file (or its URL) into **Claude Code** and say *"install this"*.

> **🤖 Claude Code — if a user sent you this README, install the crew now. No setup questions — the agents use whatever MCPs are already connected. Steps:**
>
> 1. **Preflight.** Confirm `git` and the `claude` CLI are on PATH. If either is missing, stop and tell the user to install it first.
> 2. **Clone (idempotent):**
>    ```bash
>    git clone https://github.com/unisol1020/claude-tools.git ~/.claude-tools 2>/dev/null \
>      || git -C ~/.claude-tools pull --ff-only
>    ```
> 3. **Run the installer:**
>    ```bash
>    bash ~/.claude-tools/team/install.sh
>    ```
>    It symlinks every agent in `team/agents/*.md` into `~/.claude/agents/`. Idempotent — symlinks mean a later `git pull` updates everything.
> 4. **Verify:** `ls -la ~/.claude/agents/` shows `architect`, `backend-engineer`, `frontend-engineer`, `automation-qa`, `backend-reviewer`, `frontend-reviewer`, `security-reviewer` as symlinks into `~/.claude-tools/team`.
> 5. **Report back to the user** — confirm it's installed, tell them to **restart Claude Code once** so the agents load, then note two things:
>    - The crew works on its own, but pairs with the rest of claude-tools: install `qa/` (adds `manual-qa` + the browser tools) and `loop/` (adds `devops` + the autonomous engine) to complete the plan→build→test→review→PR chain.
>    - **For the architect's "grill" step:** if a **`grill-me`** skill is in the session's skill list, the architect's Phase 1 is REQUIRED to route through it — the architect hands its open points back to the parent and the parent runs grill-me against the user. Only when no grill-me exists does the architect build the question list itself. To enable it, drop a grill-me skill into `~/.claude/skills/` and restart.

### Manual install (if you'd rather)

```bash
git clone https://github.com/unisol1020/claude-tools.git ~/.claude-tools
~/.claude-tools/team/install.sh
```
Then restart Claude Code.

## The grill-me skill (for the architect)

The architect's Phase 1 is a **grill step** — it interrogates you (through the main thread) until the task's goal, flows, edge cases, and definition of done are unambiguous. If a **`grill-me`** skill or plugin is present in the skill list, the architect MUST use it: it stops, hands its gathered context and open points back to the parent, and instructs the parent to invoke grill-me to run the questioning, sending the answers back before the design phase starts. It never substitutes its own ad-hoc questions while grill-me is available. Only when the skill is absent does the architect build the question list itself. To enable it, put a `grill-me` skill under `~/.claude/skills/` (or install it as a plugin) and restart Claude Code.

## Requirements

- [Claude Code](https://claude.com/claude-code) and `git`.
- No MCP is required to install. Individual agents use whatever's connected — Supabase/Postgres (engineers, for real data shapes), Playwright (frontend-engineer, to drive the UI), trackers/Figma/Slack (architect, for context). Missing MCPs are skipped, not fatal.

## Override per project

A project can ship its own `.claude/agents/<name>.md` to specialize any of these (project conventions, extra rules). A project-scoped agent of the same name takes precedence over the global one — that's intended.

## Uninstall

```bash
for a in architect backend-engineer frontend-engineer automation-qa backend-reviewer frontend-reviewer security-reviewer; do
  rm -f ~/.claude/agents/$a.md
done
```
(Leaves `manual-qa` and `devops` alone — those belong to `qa/` and `loop/`.)
