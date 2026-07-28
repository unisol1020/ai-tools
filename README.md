# claude-tools

My kit of **Claude Code** tools — agents, skills, and config that install into `~/.claude` and work in any local project. Each one is a top-level folder with its own README and a one-line installer. Take the whole set, or just the one you want, by sending a README to Claude Code and saying *"install this"*.

The set has a shape: **bootstrap** gets a machine and a repo ready, **cmux** is the desktop environment you run Claude Code in, **qa**, **tickets**, and **morning** are the everyday helpers, **team** is the crew of planner/engineer/reviewer/tester subagents the rest lean on, and **loop** is the autonomous capstone that reuses qa, tickets, and the team to take a ticket all the way to an approved PR on its own.

## How the tools fit together

```mermaid
flowchart TD
  subgraph setup["Set up once"]
    BOOT["bootstrap — /bootstrap<br/>ready a repo + machine"]
    CMUX["cmux — terminal + editor +<br/>statusline (macOS)"]
  end
  CC["Claude Code, in any repo"]
  subgraph daily["Everyday, on demand"]
    QA["qa — does it work?<br/>does it match the design?<br/>web browser or iOS Simulator"]
    TIX["tickets — human-readable<br/>Linear / Jira tickets"]
  end
  TEAM["team — crew of subagents:<br/>plan · build · review · test"]
  LOOP["loop — autonomous:<br/>investigate → build → QA → PR → review"]
  BOOT --> CC
  CMUX --> CC
  CC --> QA
  CC --> TIX
  CC --> TEAM
  CC --> LOOP
  LOOP -->|its QA step| QA
  LOOP -->|its ticket step| TIX
  LOOP -->|dispatches| TEAM
  LOOP -->|one surface per task| CMUX
```

## Tools

| Tool | What it does | Install by link |
|------|--------------|-----------------|
| [**bootstrap**](bootstrap/README.md) | `/bootstrap` — one command that readies a repo and a fresh machine: installs/verifies the toolchain it expects (ripgrep, CodeGraph + MCP, graphify, ponytail, claude-mem), builds the CodeGraph index, offers `/graphify`, augments `CLAUDE.md`, and records the repo so the session-start nudge stops. Start here when onboarding. | *"install this: https://github.com/unisol1020/claude-tools/blob/main/bootstrap/README.md"* |
| [**cmux**](cmux/README.md) | A full **cmux + Ghostty + Claude Code** environment, captured 1:1 — glass terminal (Catppuccin, transparent/blurred), file-opens routed into **Cursor** at the git repo root, a colored statusline, merged Claude settings, and a `db-tui` terminal SQL-client launcher. Also ships the **`cmux` driver skill**, so Claude can drive workspaces / panes / surfaces / the built-in browser itself — that's what `parallel` uses to lay out its runners. Backs up every file it touches; macOS only. | *"install this: https://github.com/unisol1020/claude-tools/blob/main/cmux/README.md"* |
| [**qa**](qa/README.md) | A `manual-qa` agent that drives your running app to check a feature *works* (functional) or *matches the design* (Figma / pixel-perfect) — on the **web** (real browser, via Playwright) or on **native iOS** (booted Simulator, via the Xcode MCP + `simctl`). Say *"test the native app"*, or let it infer the platform from the change. Remembers per-project URL + login + DB, asks once. | *"install this: https://github.com/unisol1020/claude-tools/blob/main/qa/README.md"* |
| [**tickets**](tickets/README.md) | A `ticket` skill that writes **human-readable** Linear / Jira tickets (not AI slop) — repro + how-to-verify + where the problem lives — pulls Figma/Sentry/Slack context from connected MCPs, and posts test results as a comment. | *"install this: https://github.com/unisol1020/claude-tools/blob/main/tickets/README.md"* |
| [**morning**](morning/README.md) | A `morning` skill — *"do my morning routine"* / `/morning` — that triages the three things you wake up to into one scannable briefing: open PRs in your repos that aren't yours (reviewed against each project's `CLAUDE.md` + the linked ticket + logic/quality), your assigned Linear/Jira tickets sorted urgency-then-effort and grouped by project, and Slack mentions / DMs / unread. Ships a standalone **`review-prs`** skill too — *"review all PRs"* / *"review this PR: <url>"*. PR comments are held for your OK before anything posts. Reuses qa's reviewer agents, the `ticket` config, and `loop`. | *"install this: https://github.com/unisol1020/claude-tools/blob/main/morning/README.md"* |
| [**team**](team/README.md) | The **crew of subagents** Claude Code delegates to — `architect` (plans), `backend-engineer` / `frontend-engineer` (build), `automation-qa` (writes tests), and `backend-reviewer` / `frontend-reviewer` / `security-reviewer` (review). Claude picks the right one automatically; the `loop` and the architect's babysit protocol dispatch exactly this crew. (`manual-qa` lives in `qa/`, `devops` in `loop/`.) | *"install this: https://github.com/unisol1020/claude-tools/blob/main/team/README.md"* |
| [**loop**](loop/README.md) | An autonomous **loop engine** + an **investigator**. Say *"get 10 tickets from Linear and check them"* → it triages into a checkbox list (run / skip / investigate-only), and on your OK fans out one loop per ticket. Each loop: plan once → implement → `CLAUDE.md` rule-check → manual QA → PR to the dev branch → poll comments → stop on approval. Per-task git worktree + isolated Docker stack (own DB, own ports). Reuses **qa**, **tickets**, and `/loop`. | *"install this: https://github.com/unisol1020/claude-tools/blob/main/loop/README.md"* |
| [**parallel**](parallel/README.md) | The **simple, no-Docker** sibling of `loop`. *"run task research routine — all bugs/features about V2"* discovers a theme across every connected tracker/GitHub/Slack/Sentry, triages, and on your pick fans out; *"run these in parallel: &lt;links&gt;"* skips discovery. Each task = its own git worktree + cmux surface running a `task-runner` (architect plans → build → `CLAUDE.md` check → tests → QA against your **one** real app/Simulator, serialized by a filesystem **QA-lock** → PR to the branch it came from). The coordinator stays live so you can add tasks on the fly. Reuses **team**, **qa**, **tickets**, `cmux`. | *"install this: https://github.com/unisol1020/claude-tools/blob/main/parallel/README.md"* |

Each tool's README has its own self-install block, so you can install them one at a time. The `loop` tool reuses `qa` and `tickets`, so install those alongside it.

## Install everything — just send this README to Claude Code

You don't run anything. Paste this file (or its URL) into **Claude Code** and say *"install this"*.

> **🤖 Claude Code — if a user sent you this README, install every tool in this repo now. Do not ask setup questions (each tool gathers its own per-project setup on first use, not at install). Steps:**
>
> 1. **Preflight.** Confirm `git` and the `claude` CLI are on PATH. If either is missing, stop and tell the user to install it first.
> 2. **Clone (idempotent):**
>    ```bash
>    git clone https://github.com/unisol1020/claude-tools.git ~/.claude-tools 2>/dev/null \
>      || git -C ~/.claude-tools pull --ff-only
>    ```
> 3. **Run every tool's installer:**
>    ```bash
>    for f in ~/.claude-tools/*/install.sh; do echo "== $f =="; bash "$f"; done
>    ```
>    Each installer symlinks its agent/skill into `~/.claude/` (so a later `git pull` updates everything) and registers or checks for the MCP it needs. They're idempotent — safe to re-run.
> 4. **Verify:** `ls -la ~/.claude/agents ~/.claude/skills` shows symlinks pointing into `~/.claude-tools/*`.
> 5. **Report back to the user** — confirm what installed (bootstrap, cmux, qa, tickets, morning, team, loop), call out any `✗` dependency lines an installer printed (with the `brew`/`npm` fix), tell them to **restart Claude Code once** so agents / skills / MCP tools load, then summarize each tool in a line or two (paraphrase the per-tool READMEs; keep it short).
>
> Update later with `git -C ~/.claude-tools pull` (symlinks pick it up). Uninstall: see each tool's README, or the bottom of this file.

Requirements: [Claude Code](https://claude.com/claude-code) and `git` for everything. Node.js (`npx`) for the Playwright MCP that `qa` uses. The `loop` tool also wants Docker + `jq` + `gh`, and `cmux` is macOS-only. Per-tool requirements are in each tool's README.

### Manual install (if you'd rather)

```bash
git clone https://github.com/unisol1020/claude-tools.git ~/.claude-tools
for f in ~/.claude-tools/*/install.sh; do bash "$f"; done
```
Then restart Claude Code.

## cmux CLI facts these skills depend on

Verified against the live CLI, not assumed — each one silently broke a fan-out before it was pinned down. Keep them true if you edit `parallel/` or `cmux/`:

- **`--command` is typed into a plain login shell, not into Claude.** A **CLI-created** workspace does not honour `newWorkspaceCommand: "claude"` from `cmux.json` — that only fires for workspaces created from the UI's global `+`. So a bare `/task-runner …` dies as `no such file or directory` and you get an idle shell that *looks* like a running agent. Launch it yourself: `--command "claude '<prompt>'"`, then confirm with `read-screen` before reporting the task as started.
- **`cmux --json` ref shape is not uniform.** `new-pane` / `new-surface` return **flat** top-level keys (`.pane_ref`, `.surface_ref`), not `.result.*`. Pipe through `jq .` once before scripting against a command you haven't checked.
- **`sidebar-state --json` reports only the caller's own workspace.** It cannot enumerate other workspaces, so a status board must come from `list-workspaces` + `read-screen`.
- **`send --surface` / `list-pane-surfaces`** are the real command names (not `send-surface` / `list-surfaces`).
- **The CLI cannot close a workspace** — `Cannot close the last surface`, and `workspace-action` only offers close-others/above/below, which would take the user's real ones. So never create throwaway workspaces; the user has to close them by hand.
- **Short refs are volatile, and a stale one fails silently if you let it.** `workspace:2` / `surface:7` get reassigned when surfaces move, so a ref captured at launch goes stale and `send --surface` fails with `not_found`. Pipe that to `/dev/null` and you have dropped a message while believing it was delivered. Re-resolve by tab name from `cmux tree` each time, and require the send to print `OK`.
- **A multi-line `send` does not submit itself.** Long text arrives as a collapsed paste and sits in the input buffer until it gets its own `send-key … enter`. Confirm the input line is empty afterwards; `Press up to edit queued messages` means it went through and the agent will pick it up when its current turn ends.

**Layout rule for parallel runners:** put them in the **caller's workspace as labeled tabs in one pane**, and `rename-tab` every one. Both alternatives were tried and failed — a separate workspace per task gets buried in a crowded sidebar, and one pane per task is ~15 characters wide and physically unreadable.

**Env rule for parallel runners:** `qa.env` is **`source`d** by the launch command, so **every value must be quoted**. An unquoted value containing a space is *executed*, not assigned — `DEV_CMD=bunx expo start --web` sets `DEV_CMD=bunx` and then runs `expo start --web`. The failing source then short-circuits the `&& claude …` chain, so you get a bare shell that looks exactly like a launched agent. A workspace-level `--env-file` parses `KEY=VALUE` safely and needs no quoting, but it cannot carry N different port/cred sets, which is why per-tab fan-out sources instead. Verify before launching:

```bash
bash -n <(printf 'set -a\n'; cat "$state/qa.env"; printf 'set +a\n')
```

## Adding a new tool to this repo

Each tool is a top-level directory with its own `README.md` (including a `🤖`-prefixed self-install block), an executable `install.sh` that symlinks its pieces into `~/.claude/`, and a `skills/` and/or `agents/` directory. Mirror an existing tool's layout and the repo-level installer loop above picks it up automatically.

## Uninstall

Run each tool's uninstall (see its README), then optionally remove the clone:

```bash
rm -rf ~/.claude-tools
```
