---
name: task-parallel
description: Run several tasks in parallel from links you already have — no research step. Give it Linear/Jira URLs or ids (or plain descriptions) and it fans out one git worktree + one cmux surface per task, each running the task-runner (architect plans → implement → CLAUDE.md check → tests → QA against your one real app/Simulator, serialized by a shared QA-lock → PR to the branch it came from). No per-task Docker — the simple path. It runs in the MAIN thread and stays alive as the coordinator, so you can watch every task in the cmux sidebar and drop in MORE tasks on the fly ("also run this one: <link>") and it spins up another worktree that joins the same pool. Use on "run these tasks in parallel", "run this task in parallel: <links>", "kick these off in parallel", "add this task", or /task-parallel.
---

# task-parallel — fan out tasks into worktrees, babysit them, add more on the fly

You (the **main thread**) are the **coordinator**. You take tasks you're *given* (no research — that's `task-research`), launch one autonomous `task-runner` per task in its own worktree + cmux surface, keep them visible, and stay alive so the user can add more while the batch runs. Each runner does the work; you set them up, lay them out, and watch. Testing is serialized for you automatically by the shared **QA-lock** — you don't arbitrate it.

## Step 1 — Collect the tasks
Parse what the user gave: **ticket URLs / ids** (Linear or Jira) and/or **plain descriptions**, each with its **constraints/lenses**. Capture enough to name each task and pick its base branch (you don't need full issue bodies — the runner fetches those).

## Step 2 — Resolve the shared setup ONCE (required before any fan-out; then remember it)
These gates would hang an unattended runner, so **resolve them up front** (AskUserQuestion), reuse saved config, and pass the answers down so no child ever prompts:
- **Tracker mapping — REQUIRED.** Read `<repo>/.claude/tickets.local.json` (the `ticket` skill's config) for tracker (Linear/Jira) + team/project. If unset, ask **once** now and save. Runners receive `TRACKER`/`TEAM`/`PROJECT` and create/link tickets non-interactively — never make a child hit the ticket skill's confirm/mapping prompt.
- **Base branch** — the branch tasks **branch from and PR back to**. Default = the repo's integration branch (`develop` → `dev` → `main`, or what CLAUDE.md / open PRs target). Honor a branch the user names. This `base` is each runner's cut-from point and PR target. (Mixed batch — e.g. a hotfix that should go to `main` — set that task's base per-task.)
- **Web QA config** (if any web task) — reuse `qa-run`'s saved dev URL + login creds for the app, and pick a dedicated **qa-port distinct from the port the user runs the app on** (so a task's QA never disturbs their own running app), plus the **dev-cmd** to serve a worktree on it and a **ready path** that returns 200. Native tasks: the **booted Simulator UDID** + the Xcode project/scheme.
- **Resource key per target** — build the QA-lock key from the *physical* target so every task sharing it serializes and distinct targets run concurrently: web → **`web-<qa-port>`**, native → **`sim-<udid>`**. You assign it; the runner uses it verbatim.

## Step 3 — Fan out (one worktree + one visible cmux surface per task)
**First, load the cmux driver.** Invoke the **`cmux` skill (Skill tool)** so you have its exact commands (`new-workspace`, `send`, `set-status`, `sidebar-state`, `notify`) and — critically — its **non-disruptive-automation rules**: anchor to `CMUX_WORKSPACE_ID`, always `--focus false`, build layout additively, and only ever send input to a surface you spawned. Everything below assumes those rules.

Then, per task: worktree off `base`, write its brief + env **outside the repo** (so they can't be committed), and launch a runner. Keep the `--command` **short and single-line** (no long/quoted text on the command line — that breaks the shell); pass the description/constraints as a file and secrets/config as an env-file.
```bash
root="$(git rev-parse --show-toplevel)"; id="<task-id>"                 # ticket key lowercased, else a slug
wt="../$(basename "$root")-worktrees/$id"
git worktree add "$wt" -b "$id" "<base>"                                # plain worktree — no Docker

state="${PARALLEL_LOCK_DIR:-$HOME/.cache/parallel-tasks}/$id"; mkdir -p "$state"
# BRIEF.md: the task description + EVERY constraint/lens + ticket id/url + design links (multi-line, quotes — all safe here)
printf '%s\n' "<task + constraints + ticket + design links>" > "$state/BRIEF.md"
# qa.env: config + creds, loaded into the child's environment (not on the command line, so no leak / no quoting)
cat > "$state/qa.env" <<EOF
QA_PORT=<port>
DEV_CMD=<dev-cmd>
QA_READY_PATH=<ready-path>
QA_USER=<user>
QA_PASS=<pass>
SIM_UDID=<udid>
XCODE_PROJECT=<proj>
XCODE_SCHEME=<scheme>
TRACKER=<linear|jira>
TEAM=<team>
PROJECT=<project>
EOF

cmux new-workspace --name "TASK-$id" --cwd "$wt" --focus false --env-file "$state/qa.env" \
  --command "/task-runner brief=$state/BRIEF.md worktree=$wt branch=$id base=<base> resource=<web-PORT|sim-UDID> mode=code tests=on qa=on pr=on"
```
- The `--command` lands as the new Claude's **first message** (cmux auto-launches `claude` on a new workspace). Keep it to the short pointer above; the runner reads `BRIEF.md` and the env-file for the rest.
- `--focus false` so focus isn't stolen; **stagger** launches a second or two apart so `git worktree add` calls don't race.
- The named `TASK-<id>` workspaces show in the sidebar with each runner's live status/progress — that's the "watch them all" view. To cluster them, add `--group <ref>` (or use `--layout '{…}'` to stack them as panes in one window). One surface per task, no more.

## Step 4 — Babysit: keep it legible, don't interfere
You stay in the main thread. You do **not** arbitrate testing (the QA-lock does) — you make the batch legible and step in only when a runner needs a human:
- **Live board on request / on events**, from what's already there:
  ```bash
  cmux sidebar-state --json     # each TASK-<id>: phase, progress, needs-input
  qa-lock status                # who's testing the shared app/Sim + who's queued
  ```
  Render a tight board: each task → phase (plan/implement/check/tests/qa/PR/done) + the QA lane (🔒 testing: X · ⏳ waiting: Y).
- **Surface blockers.** A runner that hits a true blocker (missing creds, a high-risk change, QA not converging) `cmux notify`s and sets a needs-input status. Relay it to the user, then pass their answer to **that surface only**:
  ```bash
  cmux send --surface <its-surface-ref> "<the answer>\n"     # \n submits; only a surface YOU spawned
  ```
- **Report as each finishes.** When a runner opens its PR (or stops with "no PR, because …"), note it: task → PR url + base, or the reason it skipped. Nothing silently dropped.

## Step 5 — Add tasks on the fly
The point of staying alive: while the batch runs, the user can say *"also run this: <link>"* / *"add ENG-321"*. Run **Step 3 once more** for it — a new worktree off `base`, a new `TASK-<id>` surface. It **joins the pool automatically**: the shared QA-lock already serializes its testing against the running batch, so no extra coordination is needed. Confirm the addition + its resource key, then launch. Keep adding as long as the coordinator session is open.

## Rules
- **You're given the tasks — you don't research them.** (Theme discovery is `task-research`, which hands its picks to this exact fan-out.)
- **Resolve the interactive gates up front** (tracker mapping, base, QA creds/port) and pass them down — an unattended runner must never reach an AskUserQuestion.
- **One runner, one worktree, one surface, per task**, off `base`; never touch another task's branch/worktree.
- **No per-task Docker.** Plain worktrees; QA against the user's one real app / one Simulator, serialized by `qa-lock` keyed on the physical target. (Full isolation = `loop-engine`.)
- **Don't steal focus.** `--focus false`, additive layout, anchor to `CMUX_WORKSPACE_ID`; only ever `cmux send` to a surface you spawned.
- **Brief as a file, secrets as an env-file, command short.** Never inline long/quoted task text or creds on the launch command.
- **The lock arbitrates testing, not you.** You display the QA lane; you don't hand out turns.
- **Reuse the pieces.** per-task work → **task-runner**; surfaces/status → **cmux**; QA creds/URL → **qa-run** config; serialization → **qa-lock**. You orchestrate and keep it visible.
