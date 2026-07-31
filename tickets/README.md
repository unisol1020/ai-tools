# ai-tickets

A Claude Code skill that turns a request — or a chunk of the conversation you're already in — into a Linear or Jira ticket that reads like a person wrote it. Short, specific, scannable. No wall of bullets, no "comprehensive solution to streamline the workflow". You ask in plain words; the skill figures out the tracker, mines the chat for the actual problem, pulls in design and error context from whatever MCPs you have connected, shows you the draft, and files it.

## How it works

It runs in the **main thread** (no subagent, no browser) so it can read your live conversation and ask the occasional question before it commits anything.

```mermaid
flowchart TD
    A[You ask: file a ticket] --> B{Tracker known<br/>for this project?}
    B -- no --> C[Detect Linear vs Jira<br/>from MCP + repo signals]
    C --> D[Ask once: which team/project<br/>save to .claude/tickets.local.json]
    B -- yes --> E
    D --> E[Mine the conversation:<br/>problem, where it lives, repro/test steps]
    E --> F[Enrich from connected MCPs:<br/>Figma frame, Sentry trace, Slack thread, PR]
    F --> G{Bug or feature?}
    G -- bug --> H[Draft with bug template]
    G -- feature --> I[Draft with feature template]
    H --> J{Confirm draft}
    I --> J
    J -- approved --> K[Create issue +<br/>attach designs]
    K --> L[Post test results as a comment]
    J -- rejected --> M[Don't create]
```

The first time you file in a given repo, it detects which tracker you use (a connected Linear or Atlassian MCP, plus repo hints like `ABC-123` branch names) and asks once which team and project to file under. After that it just remembers. For every ticket it reads the conversation for the real content, attaches any Figma/screenshot links you shared, picks the bug or feature template based on what you're filing, shows you the draft, and only then creates the issue. Recent test output and long stack traces go on as a comment so the description stays clean.

## What you get

| Piece | Role |
|-------|------|
| `skills/ticket/SKILL.md` | The whole skill: detect tracker → map team/project once → mine the chat → enrich from MCPs → draft → confirm → create + comment |
| `templates/tickets.local.json.example` | Sample per-project config (tracker + team/project mapping) you can copy and commit |
| `install.sh` | Symlinks the skill into `~/.claude/skills/` and checks for a connected tracker MCP |

## Install — send this README to Claude Code

You don't run anything by hand. Paste this file (or its URL) into Claude Code and say *"install this"*.

> **🤖 Claude Code — if a user sent you this README, install the skill now. Do not ask for tracker/team details (those are gathered per-project on the first ticket, not at install). Steps:**
>
> 1. **Preflight.** Confirm `git` and the `claude` CLI are on PATH. If missing, stop and tell the user to install them.
> 2. **Clone (idempotent):**
>    ```bash
>    git clone https://github.com/unisol1020/ai-tools.git ~/.ai-tools 2>/dev/null \
>      || git -C ~/.ai-tools pull --ff-only
>    ```
> 3. **Run the installer:**
>    ```bash
>    bash ~/.ai-tools/tickets/install.sh
>    ```
>    It symlinks the `ticket` skill into `~/.claude/skills/` and checks whether a Linear or Atlassian (Jira) MCP is connected.
> 4. **Verify:** `ls -la ~/.claude/skills/ticket` is a symlink into `~/.ai-tools/tickets`.
> 5. **Report back to the user** — confirm it's installed, then explain briefly (paraphrase, keep it short):
>
>    > ✅ **Installed.** Restart Claude Code once so the skill loads.
>    >
>    > **How to use it — just ask, no commands:**
>    > 1. Connect a **Linear** or **Atlassian (Jira)** MCP if you haven't (claude.ai integrations, or `claude mcp add`).
>    > 2. Say what to file, in plain words: *"create a ticket for this bug"*, *"file a Linear issue for the discount bug we found"*, *"open a Jira ticket: add CSV export to reports"* — or `/ticket`.
>    > 3. **First time in a project** I ask once which tracker + which team/project to use, then remember it in `.claude/tickets.local.json`.
>    > 4. I draft a **short, human-readable** ticket from our conversation — what's happening, where the problem is, repro steps, and how to verify — and show it to you before creating.
>    > 5. Any **Figma / design / screenshot** links from our chat get attached to the ticket; the latest **test results** go on as a comment.
>    >
>    > Try: *"create a ticket for the bug we just found"*.
>
> Update later with `git -C ~/.ai-tools pull` (the symlink picks it up). Uninstall: see the bottom of this file.

### Manual install (if you'd rather)

```bash
git clone https://github.com/unisol1020/ai-tools.git ~/.ai-tools
~/.ai-tools/tickets/install.sh
```
Then restart Claude Code.

## Requirements

[Claude Code](https://claude.com/claude-code), `git`, and a connected **Linear** or **Atlassian (Jira)** MCP. Connect one through the claude.ai integrations panel or with `claude mcp add`.

## Use it

In any project, ask Claude Code in plain words:

- *"create a ticket for this bug"*
- *"file a Linear issue for the checkout discount bug we found"*
- *"open a Jira ticket to add CSV export to the reports page"*
- *"log these three issues as separate tickets"* (you get one ticket per distinct problem)

First run in a repo, it detects the tracker and asks which team/project (Linear) or project + issue type (Jira) to file under, then remembers it. After that it just drafts from the conversation, shows you the draft, and on your OK creates the ticket — attaching any design links and posting the latest test results as a comment.

### Why it doesn't read like AI slop

The skill is rule-bound when it drafts:

- a title that names the actual thing (≤ ~70 chars) — *"Checkout total ignores discount code"*, not *"Implement a comprehensive solution for…"*;
- plain present-tense voice, like a message to a teammate;
- real file paths, symbols, URLs, and numbers — never "the relevant module";
- only the sections that have content — a small bug is a few lines;
- one problem per ticket; multi-part requests split into separate tickets;
- full logs and traces go in a comment, keeping the description scannable.

### What it pulls from connected MCPs

It uses an MCP only when it's installed *and* relevant to the ticket in front of it — otherwise it's skipped silently.

- **Figma** — renders the actual frame (`get_screenshot`) and reads the intended layout/tokens (`get_design_context`, `get_metadata`, `get_variable_defs`) so a bare link becomes a real Design section.
- **Sentry** — the real exception, top frames, and affected releases (`get_issue_full_context`); one line in the body, full trace in the comment.
- **Slack** — reads the originating thread and links it as the source.
- **GitHub / git** — links the related PR, commit, or branch.
- **PostHog / Grafana / Supabase** — one concrete number when the ticket is about metrics or data, not a dashboard dump.
- **Notion / Google Drive** — links a referenced spec instead of paraphrasing it.

## Per-project config

The tracker choice and team/project mapping live in `<project>/.claude/tickets.local.json` (see `templates/tickets.local.json.example`). The skill writes and reads it for you. It holds **no secrets**, so a team can commit it as `.claude/tickets.json` to share the mapping — the skill reads both, and `tickets.local.json` wins. Change your mind by editing the file.

To make this global skill **stand down** in a repo that has its own ticket workflow, list that repo (matched against its `remote.origin.url`) in `~/.claude/ticket-defer-repos.txt`, one per line. That file is local and uncommitted, so private repo names never leave your machine. A project-scoped skill named `ticket` under the repo's `.claude/skills/` already overrides this one automatically.

## Uninstall

```bash
rm ~/.claude/skills/ticket
rm -rf ~/.ai-tools   # only if nothing else in this repo is installed
```
