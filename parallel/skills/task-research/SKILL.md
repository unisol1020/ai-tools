---
name: task-research
description: "Task research routine — say 'run task research routine, I want all bugs/features related to <topic>' (e.g. app V2) and it hunts that theme across EVERY connected source — Linear, Jira, GitHub issues + PRs, Sentry, Slack, Notion — investigates each candidate against THIS codebase, and hands back a checkbox triage: what's runnable, what to skip (with why), what's investigate-only. You tick which to start; on your confirm it fans out one git worktree + one cmux surface per pick, each running the task-runner (architect plans → implement → CLAUDE.md check → tests → QA against your one real app/Simulator, serialized by a shared QA-lock → PR to the branch it came from). No per-task Docker. Runs in the MAIN thread (asks you questions, reads your trackers) and stays alive so you can add more. Use on 'run task research routine', 'research all bugs/features about <topic>', 'find everything related to <X> and run it', or /task-research."
---

# task-research — research a theme, triage, fan out the simple runner

You (the **main thread**) turn *"find all the bugs/features about **X** and run them"* into a reviewed, parallel batch. You **discover by theme across every connected source**, triage each candidate against the real codebase, hand back a **checkbox list**, and — only on the user's tick + confirm — fan out one autonomous `task-runner` per pick. You ask the questions; the runners do the work. (This is the discovery front-end; execution is identical to `task-parallel` — you reuse it.)

## Step 1 — Pin down the theme
Get the topic from the ask (*"app V2"*, *"the new booking flow"*, *"checkout"*). Resolve what it actually maps to so the search is precise, and ask **once** if genuinely ambiguous:
- a **Linear project / label / cycle** or **Jira epic / component / fixVersion** named for it,
- a **GitHub milestone / label** or a path/area in the repo,
- a **Slack channel** where it's discussed.
Reuse the `ticket` skill's saved tracker mapping (`<repo>/.claude/tickets.local.json`); detect connected MCPs live (`claude mcp list` + the deferred-tool list) and load tools with **ToolSearch** before calling — names change between sessions.

## Step 2 — Discover across EVERY connected source (installed + relevant only)
Cast wide, then dedupe. Fan out **read-only** searches in parallel (spawn Explore/search agents per source) and pull every bug/feature that matches the theme. Use what's connected; skip silently what isn't:
- **Tracker — Linear / Jira** — issues in the resolved project/label/epic, plus a text search for the theme across open/triage/backlog states.
- **GitHub** — open **issues** and **PRs** matching the theme (labels, milestone, text) — a bug may live only as an issue or a stalled PR.
- **Sentry** — unresolved errors tagged to or clearly in the theme's area (a real, firing bug worth a task).
- **Slack / Notion / Drive** — threads and specs about the theme; a feature request or bug often lives only in a conversation, not a ticket yet.
- **The codebase** — TODO/FIXME or obviously-broken spots in the theme's area, if the user wants those too.
Merge into a single candidate list, **deduped** (the same bug filed in Linear *and* discussed in Slack is one candidate). Each candidate: a stable id/url + source + a one-line "what it is". Note which candidates are **not yet tickets** (a Slack/Sentry-only find) — those get a ticket created at fan-out time.

## Step 3 — Investigate + triage each candidate against THIS codebase
For each candidate, spend real effort (CodeGraph if `.codegraph/` exists, else search/read) deciding its bucket — the same triage `investigator` uses:
1. **✅ Can run** — well-scoped to this codebase, clear-enough acceptance, something a runner can implement + test + PR. One-line entry point (files/area).
2. **⏭️ Skip / do separately** — too broad/vague, needs a product or human decision, spans external systems, blocked, or **high-risk unattended** (DB migration, infra, auth/secrets, prod config, mass delete, major dep bump, or anything CLAUDE.md marks do-not-touch). Give the one-line reason.
3. **❓ Investigate only** — really a question; answerable by investigating + posting findings, no code.
Do the investigation in parallel where it helps; **you** produce the final triage.

## Step 4 — Hand back the checkbox list, get the pick
Present a scannable, grouped checklist. Pre-tick ✅; leave ⏭️ unticked with the reason; list ❓ separately. One line each: id/source + title + reason/entry point.
```
RUN NOW (code)
- [x] ENG-123  Checkout total ignores V2 discount        → src/checkout/total.ts · clear repro
- [x] GH#411   V2 reports page missing CSV export         → reports route · design linked
- [x] (Slack)  V2 empty-state copy wrong on booking       → not a ticket yet → will create one
SKIP / DO SEPARATELY
- [ ] ENG-145  "Rework V2 billing"                         → too broad, needs product scoping
INVESTIGATE ONLY (no code)
- [ ] SENTRY   Why are V2 webhook retries spiking?         → answer from logs/code, no change
```
Ask the user to **toggle which to start** and **wait for their confirm** — nothing launches yet. (Optional: offer the toggles `tests`/`qa`/`pr` for the batch, all ON by default.)

## Step 5 — Fan out (reuse task-parallel exactly)
On confirm, run the **task-parallel** fan-out for the ticked candidates — you've already produced the task list, so hand it straight to that flow (which starts by loading the **`cmux` skill** for the command reference + focus rules — do that before opening any surface). Do task-parallel's **Step 2 first** (resolve the shared setup ONCE and pass it down so no runner ever prompts): the **required** tracker mapping (`TRACKER`/`TEAM`/`PROJECT`), the base branch, the per-task web/sim target, the qa-port/creds, and the per-target resource key. Then per pick:
- **Code candidate** — worktree off `base`, a `TASK-<id>` surface running `/task-runner … mode=code`. A candidate that **isn't a ticket yet** (a Slack/Sentry-only find): the runner creates it **directly via the tracker MCP** (non-interactive, using the passed mapping) before opening the PR — not the interactive `ticket` skill.
- **Investigate-only candidate** — a `TASK-<id>` surface running `/task-runner … mode=investigate pr=off qa=off tests=off` (no worktree changes): it investigates and posts findings as a comment on the ticket via the tracker MCP. (This is the runner's investigate mode — don't send investigate-only picks down the code path, which would try to build and open an empty PR.)

Then **babysit + allow add-on-the-fly exactly as task-parallel does** (live board from `cmux sidebar-state` + `qa-lock status`; relay blockers with `cmux send --surface <ref> "…\n"`; report each PR). Don't reimplement any of it — this skill only adds the *discovery* in front.

## Rules
- **Research before you ask.** The triage reflects the real codebase + the real candidates, not a guess from titles.
- **Nothing launches without the tick + confirm.** The checkbox list is the gate; respect exactly what the user toggles.
- **Cast wide, then dedupe.** Search every connected source for the theme; merge duplicates so one bug is one candidate; never invent a source that isn't connected.
- **Skips are explicit.** Every candidate lands in exactly one bucket and is shown; never quietly drop one.
- **Reuse the pieces.** discovery = the connected MCPs; triage discipline = same buckets as `investigator`; execution = **task-parallel** → **task-runner** (worktrees + cmux + qa-lock + architect + manual-qa + the `ticket` skill). You only add the theme search and the triage in front.
