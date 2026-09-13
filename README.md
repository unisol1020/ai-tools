# ai-tools

My kit of **Claude Code** tools — agents, skills, and config that install into `~/.claude` and work in any local project. Each one is a top-level folder with its own README and a one-line installer. Take the whole set, or just the one you want, by sending a README to Claude Code and saying *"install this"*.

The set has a shape: **bootstrap** gets a machine and a repo ready; **worktree-graphs** keeps that setup working once you branch out into worktrees; **qa**, **tickets**, and **morning** are the everyday helpers; **team** is the crew of planner/engineer/reviewer/tester subagents the rest lean on.

## How the tools fit together

```mermaid
flowchart TD
  subgraph setup["Set up once"]
    BOOT["bootstrap — /bootstrap<br/>ready a repo + machine"]
    WTG["worktree-graphs — graphs status<br/>keep code graphs alive in every worktree"]
  end
  CC["Claude Code, in any repo"]
  subgraph daily["Everyday, on demand"]
    QA["qa — does it work?<br/>does it match the design?<br/>web browser or iOS Simulator"]
    TIX["tickets — human-readable<br/>Linear / Jira tickets"]
    MORN["morning — PRs + tickets + Slack<br/>in one briefing"]
  end
  TEAM["team — crew of subagents:<br/>plan · build · review · test"]
  BOOT --> WTG
  WTG --> CC
  CC --> QA
  CC --> TIX
  CC --> MORN
  CC --> TEAM
  MORN -->|reuses reviewers| TEAM
  QA -->|manual-qa pairs with| TEAM
```

## Tools

| Tool | What it does | Install by link |
|------|--------------|-----------------|
| [**bootstrap**](bootstrap/README.md) | `/bootstrap` — one command that readies a repo and a fresh machine: installs/verifies the toolchain it expects (ripgrep, CodeGraph + MCP, graphify, ponytail, MemPalace), builds the CodeGraph index, offers `/graphify`, augments `CLAUDE.md`, and records the repo so the session-start nudge stops. Start here when onboarding. | *"install this: https://github.com/unisol1020/ai-tools/blob/main/bootstrap/README.md"* |
| [**qa**](qa/README.md) | A `manual-qa` agent that drives your running app to check a feature *works* (functional) or *matches the design* (Figma / pixel-perfect) — on the **web** (real browser, via Playwright) or on **native iOS** (booted Simulator, via Orca emulator when available, else Xcode MCP + `simctl`). Say *"test the native app"*, or let it infer the platform from the change. Remembers per-project URL + login + DB, asks once. | *"install this: https://github.com/unisol1020/ai-tools/blob/main/qa/README.md"* |
| [**tickets**](tickets/README.md) | A `ticket` skill that writes **human-readable** Linear / Jira tickets (not AI slop) — repro + how-to-verify + where the problem lives — pulls Figma/Sentry/Slack context from connected MCPs, and posts test results as a comment. | *"install this: https://github.com/unisol1020/ai-tools/blob/main/tickets/README.md"* |
| [**morning**](morning/README.md) | A `morning` skill — *"do my morning routine"* / `/morning` — that triages the three things you wake up to into one scannable briefing: open PRs in your repos that aren't yours (reviewed against each project's `CLAUDE.md` + the linked ticket + logic/quality), your assigned Linear/Jira tickets sorted urgency-then-effort and grouped by project, and Slack mentions / DMs / unread. Ships a standalone **`review-prs`** skill too — *"review all PRs"* / *"review this PR: \<url\>"*. PR comments are held for your OK before anything posts. | *"install this: https://github.com/unisol1020/ai-tools/blob/main/morning/README.md"* |
| [**team**](team/README.md) | The **crew of subagents** Claude Code delegates to — `architect` (plans), `backend-engineer` / `frontend-engineer` (build), `automation-qa` (writes tests), and `backend-reviewer` / `frontend-reviewer` / `security-reviewer` (review). Claude picks the right one automatically; the architect's babysit protocol dispatches this crew. (`manual-qa` lives in `qa/`.) | *"install this: https://github.com/unisol1020/ai-tools/blob/main/team/README.md"* |
| [**worktree-graphs**](worktree-graphs/README.md) | `graphs status` — every git worktree gets a working **CodeGraph index + Graphify graph**, instead of silently falling back to grep. Worktrees are fresh checkouts, so both gitignored graphs are missing; this reflink-clones main's index (3 copies of a 251 MB db = 8 KB) and syncs the branch delta on the session that opens there. Also fixes graphify going stale after `git pull`. | *"install this: https://github.com/unisol1020/ai-tools/blob/main/worktree-graphs/README.md"* |

Each tool's README has its own self-install block, so you can install them one at a time.

## Install everything — just send this README to Claude Code

You don't run anything. Paste this file (or its URL) into **Claude Code** and say *"install this"*.

> **🤖 Claude Code — if a user sent you this README, install every tool in this repo now. Do not ask setup questions (each tool gathers its own per-project setup on first use, not at install). Steps:**
>
> 1. **Preflight.** Confirm `git` and the `claude` CLI are on PATH. If either is missing, stop and tell the user to install it first.
> 2. **Clone (idempotent):**
>    ```bash
>    git clone https://github.com/unisol1020/ai-tools.git ~/.ai-tools 2>/dev/null \
>      || git -C ~/.ai-tools pull --ff-only
>    ```
>    If an older `~/.ai-tools` clone exists, move it: `mv ~/.ai-tools ~/.ai-tools` and update the remote to `https://github.com/unisol1020/ai-tools.git`.
> 3. **Run every tool's installer:**
>    ```bash
>    for f in ~/.ai-tools/*/install.sh; do echo "== $f =="; bash "$f"; done
>    ```
>    Each installer symlinks its agent/skill into `~/.claude/` (so a later `git pull` updates everything) and registers or checks for the MCP it needs. They're idempotent — safe to re-run.
> 4. **Verify:** `ls -la ~/.claude/agents ~/.claude/skills` shows symlinks pointing into `~/.ai-tools/*`.
> 5. **Report back to the user** — confirm what installed (bootstrap, qa, tickets, morning, team), call out any `✗` dependency lines an installer printed (with the `brew`/`npm` fix), tell them to **restart Claude Code once** so agents / skills / MCP tools load, then summarize each tool in a line or two (paraphrase the per-tool READMEs; keep it short).
>
> Update later with `git -C ~/.ai-tools pull` (symlinks pick it up). Uninstall: see each tool's README, or the bottom of this file.

Requirements: [Claude Code](https://claude.com/claude-code) and `git` for everything. Node.js (`npx`) for the Playwright MCP that `qa` uses. Per-tool requirements are in each tool's README.

### Manual install (if you'd rather)

```bash
git clone https://github.com/unisol1020/ai-tools.git ~/.ai-tools
for f in ~/.ai-tools/*/install.sh; do bash "$f"; done
```
Then restart Claude Code.

## Adding a new tool to this repo

Each tool is a top-level directory with its own `README.md` (including a `🤖`-prefixed self-install block), an executable `install.sh` that symlinks its pieces into `~/.claude/`, and a `skills/` and/or `agents/` directory. Mirror an existing tool's layout and the repo-level installer loop above picks it up automatically.

## Uninstall

Run each tool's uninstall (see its README), then optionally remove the clone:

```bash
rm -rf ~/.ai-tools
```
