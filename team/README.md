# ai-team

The **crew of subagents** Claude Code delegates real work to — the ones that plan, build, review, and test. They install into `~/.claude/agents` and work in every local project. Claude picks the right one automatically (or you name it), and the architect's babysit protocol dispatches this crew to take a change from plan → code → tests → review.

**`manual-qa`** ships in [`qa/`](../qa/README.md) on purpose — it needs the Playwright MCP and the `qa-run` skill. Install `qa/` to get that agent.

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

With [`memory/`](../memory/README.md) installed, every one of these agents has persistent two-tier memory — what it learned about *this* repo (gitignored, shared across worktrees) plus best practices promoted to `~/.claude/agent-memory/` — and ends each report with a `memory:` stats line.

The split is deliberate: engineers write code but not tests; the test-author writes tests but not code; reviewers only report. That separation is what lets the `architect` chain them safely.

## Install — just send this README to Claude Code

You don't run anything. Paste this file (or its URL) into **Claude Code** and say *"install this"*.

> **🤖 Claude Code — if a user sent you this README, install the crew now. No setup questions — the agents use whatever MCPs are already connected. Steps:**
>
> 1. **Preflight.** Confirm `git` and the `claude` CLI are on PATH. If either is missing, stop and tell the user to install it first.
> 2. **Clone (idempotent):**
>    ```bash
>    git clone https://github.com/unisol1020/ai-tools.git ~/.ai-tools 2>/dev/null \
>      || git -C ~/.ai-tools pull --ff-only
>    ```
> 3. **Run the installer:**
>    ```bash
>    bash ~/.ai-tools/team/install.sh
>    ```
>    It symlinks every agent in `team/agents/*.md` into `~/.claude/agents/`. Idempotent — symlinks mean a later `git pull` updates everything.
> 4. **Verify:** `ls -la ~/.claude/agents/` shows `architect`, `backend-engineer`, `frontend-engineer`, `automation-qa`, `backend-reviewer`, `frontend-reviewer`, `security-reviewer` as symlinks into `~/.ai-tools/team`.
> 5. **Report back to the user** — confirm it's installed, tell them to **restart Claude Code once** so the agents load, then note two things:
>    - The crew works on its own, but pairs with the rest of ai-tools: install `qa/` (adds `manual-qa` + the browser tools) to complete the plan→build→test→review chain.
>    - **For the architect's "grill" step:** if a **`grill-me`** skill is in the session's skill list, the architect's Phase 1 is REQUIRED to route through it — the architect hands its open points back to the parent and the parent runs grill-me against the user. Only when no grill-me exists does the architect build the question list itself. Install the recommended one (Matt Pocock's — see [The grill-me skill](#the-grill-me-skill-for-the-architect) below), then restart.

### Manual install (if you'd rather)

```bash
git clone https://github.com/unisol1020/ai-tools.git ~/.ai-tools
~/.ai-tools/team/install.sh
```
Then restart Claude Code.

## The grill-me skill (for the architect)

The architect's Phase 1 is a **grill step** — it interrogates you (through the main thread) until the task's goal, flows, edge cases, and definition of done are unambiguous. If a **`grill-me`** skill or plugin is present in the skill list, the architect MUST use it: it stops, hands its gathered context and open points back to the parent, and instructs the parent to invoke grill-me to run the questioning, sending the answers back before the design phase starts. It never substitutes its own ad-hoc questions while grill-me is available. Only when the skill is absent does the architect build the question list itself.

**Recommended: [`grill-me`](https://github.com/mattpocock/skills) by [Matt Pocock](https://github.com/mattpocock).** It's the best grill skill out there — a relentless, one-question-at-a-time interview (it runs a `/grilling` session) that resolves every branch of a decision, recommending an answer for each, until you both genuinely agree on the plan. Exactly what the architect's grill step wants. Huge thanks to Matt for open-sourcing it (MIT). 🙏

It is **not vendored into this repo** — install it locally so it stays yours to update. The plug-and-play route (installs Matt's set as a managed, always-current bundle):

```bash
claude plugin marketplace add mattpocock/skills
claude plugin install mattpocock-skills@mattpocock
```

Or, to keep just `grill-me` (+ its `grilling` engine), copy those two skills into `~/.claude/skills/` from the repo above. Either way, restart Claude Code and the architect will start routing its Phase-1 questioning through it.

### Let the architect call it automatically (recommended tweak)

Matt ships `grill-me` as **user-only** — its frontmatter has `disable-model-invocation: true`, so out of the box it only fires when **you** type `/grill-me`. For the architect → parent hand-back to trigger it *on its own* (no typing), make it model-invocable: open `~/.claude/skills/grill-me/SKILL.md` and **delete the `disable-model-invocation: true` line**. One line:

```diff
  ---
  name: grill-me
  description: A relentless interview to sharpen a plan or design.
- disable-model-invocation: true
  ---

  Run a `/grilling` session.
```

(Optional: widen the `description` to name the triggers — e.g. *"…Use when the user wants to stress-test a plan, uses any 'grill' phrase, or when a subagent like the architect hands back open questions."* The model reads the description to decide when to auto-invoke, so a fuller one makes it fire more reliably.) The `grilling` engine it calls is already model-invocable, so this only affects the `grill-me` alias. Restart Claude Code — now both the model and `/grill-me` can run it.

### Force the main thread to grill, not poll

The architect halts and demands grill-me the moment it has open questions — but that only fires **once the architect is invoked**. The common miss is the **main thread** gathering requirements itself (its own `AskUserQuestion` polls) before it ever delegates to the architect, so grill-me never gets a turn. Close that gap with a rule in your **global** `~/.claude/CLAUDE.md`:

```markdown
## Grill, don't poll (requirements for any plan / feature / non-trivial change)

Whenever you gather requirements before planning or building something non-trivial — in the
main thread OR when the architect hands back open questions — you MUST interrogate the user via
the `grill-me` skill (engine: the model-invocable `grilling` skill), NOT AskUserQuestion polls
and NOT your own question list. Grilling is one adaptive question at a time; a poll is not
grilling. If the architect returns a "run grill-me" instruction, invoke grill-me/grilling and
SendMessage the answers back before it designs. Fall back to AskUserQuestion ONLY after you look
and confirm no grill-me/grilling skill is installed. AskUserQuestion is still fine for a quick
one-off choice mid-task that isn't requirements-gathering.
```

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
(Leaves `manual-qa` alone — that belongs to `qa/`.)
