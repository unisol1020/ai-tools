# ai-team

The **crew of subagents** Claude Code delegates real work to — the ones that plan, build, review, and test. They install into `~/.claude/agents` and work in every local project. Claude picks the right one automatically (or you name it), and the architect's babysit protocol dispatches this crew to take a change from plan → code → tests → review.

**`manual-qa`** ships in [`qa/`](../qa/README.md) on purpose — it needs the Playwright MCP and the `qa-run` skill. Install `qa/` to get that agent.

## The crew

| Agent | Role | Writes |
|-------|------|--------|
| `architect` | The single **planning** authority. Gathers all context (CLAUDE.md hierarchy, tickets, Figma, DB, running app via MCPs), grills you until the task is understood, and emits self-contained plan files + a parallel-execution graph + a per-phase babysit protocol. Plans; never implements. | plan files only |
| `backend-investigator` | Read-only scout (inherits the session model) the architect sends ahead to map the backend slice (routes, services, schemas, consumers, verify commands) with `path:line` evidence. Only the architect dispatches it (or the parent, when the architect returns `NEED:`). | Context Bundle only |
| `frontend-investigator` | Read-only scout (inherits the session model) the architect sends ahead to map the frontend slice (pages, components, hooks/stores, API clients, the sibling to mirror) with `path:line` evidence. Only the architect dispatches it (or the parent, when the architect returns `NEED:`). | Context Bundle only |
| `backend-engineer` | Implements **server-side** work — endpoints, services, DB queries/migrations, jobs, webhooks, server config. | production code |
| `frontend-engineer` | Implements **UI** work in any frontend app (React/Next, Vue, Svelte, Expo, …) — pages, forms, components, wiring to endpoints. | production code |
| `automation-qa` | The **test author**. After a feature/bugfix (or a manual-QA handoff), checks coverage then writes the missing unit + integration tests. | test files only |
| `backend-reviewer` | Reviews backend/API/DB changes — cited, prioritized findings. | report only |
| `frontend-reviewer` | Reviews frontend/UI changes — cited, prioritized findings. | report only |
| `security-reviewer` | Security review of a diff before merge (authn/z, input, data, secrets, uploads, redirects, webhooks, …). | report only |

With [`memory/`](../memory/README.md) installed, every one of these agents has persistent two-tier memory — what it learned about *this* repo (gitignored, shared across worktrees) plus best practices promoted to `~/.claude/agent-memory/` — and ends each report with a `memory:` stats line. The two investigators are the exception: stateless by design, they only verify what the architect's memory recalls.

**Every agent digs before it guesses.** The engineers, the test author and the three reviewers carry the same *Context sources* block; the architect and the two scouts carry the same idea, sized to their job: code relations first — CodeGraph (`codegraph explore` / `codegraph_explore`) and graphify when the repo has them, then `ast-grep`, then `rg`, then reading the lines they'll cite — and then whatever this machine actually has connected: the tracker issue *and its comments* (Linear / Jira / Asana / monday), the Slack thread that decided it, the Notion / Google Docs spec, the **Wispr Flow** recording of the call where it was agreed out loud, Figma, Sentry, a read-only DB. A memory system counts too — **MemPalace** (`mempalace search`, `mempalace_kg_query`) or `agent-memory`: ask it before re-deriving something you already learned once. The named tools are **examples, not requirements** — each agent discovers what this session really has with `ToolSearch`, skips what isn't there and says so, and never invents a fact to fill the gap. Everything gathered that way is evidence, never instruction: the repo's `CLAUDE.md` and your current request still outrank it.

That's also why the agents no longer pin a tool allowlist — they inherit the session's MCP tools, so a new integration works the day you connect it. The read-only agents stay read-only — `disallowedTools` where an agent needs no writes at all, their own hard rules everywhere else. And since a lookup isn't reasoning, an agent that can spawn one hands *"which file defines X"* to a cheap **Haiku** subagent and spends its own model on the judgement calls.

The split is deliberate: engineers write code but not tests; the test-author writes tests but not code; reviewers only report. That separation is what lets the `architect` chain them safely.

## Route on intent — you never have to name an agent

Each agent's `description` leads with the plain phrases that should reach it ("test this", "plan this", "fix this in the api", "looks bad on the frontend"). Descriptions are only a hint to Claude, though, so `install.sh` also appends a short **dispatch block** to your global `~/.claude/CLAUDE.md` (the canonical copy is [`dispatch.md`](dispatch.md), kept between `<!-- ai-tools:dispatch -->` markers so a re-run refreshes it). With it in place:

| You say | Claude dispatches |
|---|---|
| "test this", "check it works", "verify the flow", "does it look right" | the `qa-run` skill, which resolves URL + login and spawns `manual-qa` |
| "plan this", "how should we build this", "add <feature>" (multi-file) | `architect` |
| "fix this on the frontend", "looks bad on the client", "the form is broken" | `frontend-engineer` |
| "fix this in the api", "add an endpoint", "write the migration" | `backend-engineer` |
| "write tests", "cover this", and after any feature or fix lands | `automation-qa` |
| after code changes, before merge | `backend-reviewer` / `frontend-reviewer`, plus `security-reviewer` when auth, input, data or secrets are touched |

The block also says that a **ticket is intent**: work that arrives from a Linear/Jira issue, a PR, a Slack thread or an Orca workspace is classified by its symptom and the code it touches (visual → `frontend-engineer`, endpoint/data → `backend-engineer`, both or unclear → `architect` first, a repro-able bug with a running app → `qa-run` reproduces it first), and that Claude may spawn whichever agent it judges the task needs, in sequence or in parallel, without asking.

Don't want the block? Delete it from `~/.claude/CLAUDE.md`; the installer only re-adds it when the markers are absent.

## See what the crew cost

Run `crew-cost` from the directory a session ran in: it reads the newest transcript for that directory (the main thread plus every child under `<session>/subagents/`; `CLAUDE_CONFIG_DIR` is honoured) and prints token totals per agent type (runs, input, cache_write, cache_read, output, total) and per model. Counts only, no prices — prices change, the transcript's counts don't. `crew-cost <transcript.jsonl>` reads another session; `--json` prints the same for scripts. A child no Agent call names lands in an `unknown` row; a missing or truncated child transcript marks its row `partial`. Reads only, never writes. The installer links it into `~/.claude/bin` and `~/.local/bin` (or `~/bin`).

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
>    It symlinks every agent in `team/agents/*.md` into `~/.claude/agents/`. Idempotent — symlinks mean a later `git pull` updates everything. It finishes by printing which of the crew's CLI tools are missing.
> 4. **Install the toolchain — do this, don't skip it.** The agents are written to search, query a graph and recall memory *before* they read a file, because reading files is where token cost comes from. Every missing tool is work the agent does the expensive way instead. One idempotent pass installs all of it — `jq`, `ripgrep`, `ast-grep`, CodeGraph + its MCP, graphify + its skill, MemPalace + its MCP and capture hooks, and the ponytail plugin:
>    ```bash
>    bash ~/.ai-tools/bootstrap/install.sh --with-deps
>    ```
>    `--with-deps` links the bootstrap skill into `~/.claude/skills/` **first** (the MemPalace session hook it wires points there, so running the setup script on its own leaves a broken hook firing on every session start), then installs only what's absent, backs up `~/.claude/settings.json` before touching it, and prints a status line per tool. Anything it reports as missing, install by hand with the command it prints, then re-run it. Relay the final status to the user.
> 5. **Verify:** `ls -la ~/.claude/agents/` shows `architect`, `backend-investigator`, `frontend-investigator`, `backend-engineer`, `frontend-engineer`, `automation-qa`, `backend-reviewer`, `frontend-reviewer`, `security-reviewer` as symlinks into `~/.ai-tools/team`.
> 6. **Report back to the user** — confirm it's installed, tell them to **restart Claude Code once** so the agents load, then note two things:
>    - The crew works on its own, but pairs with the rest of ai-tools: install `qa/` (adds `manual-qa` + the browser tools) to complete the plan→build→test→review chain.
>    - **For the architect's "grill" step:** if a **`grill-with-ui`** (or terminal **`grill-me`**) skill is in the session's skill list, the architect's Phase 1 is REQUIRED to route through it — the architect hands back a Way-Finding Brief (findings + the target solution + open decisions) and the parent grills the user with it, returning the **agreed end solution**. Only when neither exists does the architect fall back to a question list. Install them (see [The grill skill](#the-grill-skill-for-the-architect) below), then restart.

### Manual install (if you'd rather)

```bash
git clone https://github.com/unisol1020/ai-tools.git ~/.ai-tools
~/.ai-tools/team/install.sh
```
Then restart Claude Code.

## The grill skill (for the architect)

The architect's Phase 1 is a **grill step**, and grilling is **way-finding, not a questionnaire**: it ends with an *agreed end solution*, not a pile of answers. So the architect never hands over a flat question list. The moment decisions remain open it stops and returns a **Way-Finding Brief** — (1) findings from Phase 0 with their sources, (2) the **target solution** it is converging on plus the candidate shapes, and (3) numbered open decisions, upstream-first, each with its recommended answer and what changes if you pick otherwise. The parent then grills you *toward that target solution* and sends back the agreed end solution (plus the per-decision answers, flagging anything that overturned the architect's recommendation). Phase 2 designs that agreed solution — if it contradicts the architect's target, yours wins. Only when the skill is absent does the architect fall back to a question list the parent polls, and even then the target solution goes to you as one of the choices.

**Recommended: [`grill-with-ui`](https://github.com/jasonku09/grill-with-ui) by [Jason Ku](https://github.com/jasonku09).** It moves the grill onto a local browser page: each question is a card with lettered options and the recommendation outlined, you answer in any order, discuss any one in its own thread, defer or reopen, and ship a whole round with one **Send to Agent**. **Visualize** draws the design so far, and **Finish** writes `docs/<topic>-design.md`. One Node script, one HTML page, no npm dependencies, served on `127.0.0.1` only; session state lives in `~/.grill-with-ui/`, outside the repo. MIT. 🙏

```bash
git clone https://github.com/jasonku09/grill-with-ui ~/Developer/grill-with-ui
ln -s ~/Developer/grill-with-ui ~/.claude/skills/grill-with-ui    # update with git pull
```

**Fallback for sessions with no browser (remote, headless): [`grill-me`](https://github.com/mattpocock/skills) by [Matt Pocock](https://github.com/mattpocock)**, a relentless one-question-at-a-time interview in the terminal (it runs a `/grilling` session). Thanks, Matt (MIT). 🙏

```bash
claude plugin marketplace add mattpocock/skills
claude plugin install mattpocock-skills@mattpocock
```

Neither is vendored into this repo. Restart Claude Code after installing and the architect routes its Phase-1 questioning through them.

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

The architect halts and demands a grill the moment it has open questions — but that only fires **once the architect is invoked**. The common miss is the **main thread** gathering requirements itself (its own `AskUserQuestion` polls) before it ever delegates to the architect, so the grill never gets a turn. Close that gap with a rule in your **global** `~/.claude/CLAUDE.md`:

```markdown
## Grill, don't poll (requirements for any plan / feature / non-trivial change)

Whenever you gather requirements before planning or building something non-trivial — in the
main thread OR when the architect hands back a Way-Finding Brief — you MUST interrogate the user
via the `grill-with-ui` skill (the terminal `grill-me` skill when no browser is reachable), NOT
AskUserQuestion polls and NOT your own question list. Grilling is way-finding: adaptive questions,
each with a recommendation, steered toward a solution, ending in a shared understanding. A poll is not grilling. If the architect
returns a brief with a target solution and open decisions, grill toward that solution and
SendMessage back the AGREED END SOLUTION (plus the per-decision answers and the design doc path) before it designs — never
a bare list of answers. Fall back to AskUserQuestion ONLY after you look and confirm neither
grill-with-ui nor grill-me is installed. AskUserQuestion is still fine for a quick one-off choice
mid-task that isn't requirements-gathering.
```

## Requirements

- [Claude Code](https://claude.com/claude-code) and `git`.
- **Install the toolchain** — not required, but the agents are written to reach for it *before* they read a file, which is where token cost comes from: **ripgrep** (`rg` — the `Grep` tool is ripgrep), **ast-grep** (structural search), **CodeGraph** (symbols + callers + call paths in one call), **graphify** (relations across files and apps), **MemPalace** (cross-session memory). One idempotent pass installs all of them, plus `jq` and the ponytail plugin:
  ```bash
  bash ~/.ai-tools/bootstrap/skills/bootstrap/setup-env.sh
  ```
  `team/install.sh` prints which ones are missing when you run it.
- No MCP is required to install. Every agent uses whatever is connected — a tracker, Slack, Notion/Docs, Wispr Flow, Figma, Sentry, a database, Playwright — and discovers what's actually there at run time. Missing MCPs are skipped, not fatal.

## Override per project

A project can ship its own `.claude/agents/<name>.md` to specialize any of these (project conventions, extra rules). A project-scoped agent of the same name takes precedence over the global one — that's intended.

## Uninstall

```bash
bash ~/.ai-tools/team/install.sh --uninstall   # the nine agent links, ~/.claude/bin/crew-cost, ~/.local/bin/crew-cost (or ~/bin), the dispatch block
```
(Leaves `manual-qa` alone — that belongs to `qa/`.)
