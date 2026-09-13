---
name: morning
description: Your morning briefing in one command. Pulls the three things you wake up to and triages each into a scannable digest — (1) open GitHub PRs in your repos that aren't yours and you haven't approved yet, reviewed against each project's CLAUDE.md + logic + quality via the review-prs skill; (2) your Linear/Jira tickets assigned to you, sorted by a real urgency-then-effort order (so urgent items and quick wins surface first) and grouped by project, each with a one-line what-it-is and a how-big-and-hard chip; (3) Slack — every mention of you, DM, and urgent thread, plus a compact summary of unread, sorted the same way. Gathers your repos + watched Slack channels once and remembers them per machine; degrades gracefully when a tracker or Slack MCP isn't connected. Use when the user says "morning routine", "do my morning", "morning briefing", "what's on my plate", or invokes /morning. Runs in the MAIN thread so it can ask once and confirm before any PR comment is posted.
---

# morning — the morning conductor

You (the **main thread**) turn "do my morning routine" into one scannable briefing across the three places work lands overnight: **PRs to review**, **tickets assigned to me**, and **Slack**. You triage each — sorted and compacted so the user can see, at a glance, what's urgent, what's small, and what's worth opening. You only orchestrate: PR review is the `review-prs` skill, tickets come from the connected tracker, Slack from the Slack MCP. **Read-everything by default; the only thing that writes is a PR comment, and that goes through review-prs's confirm gate.**

## Config (per machine)
State lives in `~/.claude/morning.local.json` (machine-level, since "my repos" and "my channels" follow the person, not a repo). Ask only for what's missing; remember `declined` so you never re-ask.

```jsonc
{
  "version": 1,
  "github":  { "repos": ["org/web", "org/api"] },   // repos to scan for PRs; [] or "current" = the repo you're in
  "prFilter": "is:open -author:@me",                  // which PRs are "mine to review"; gh search syntax. PRs you've already approved are dropped on top of this (step 2) — search can't express "not approved by me"
  "slack":   { "status": "set|declined", "channels": ["#eng", "#bugs"], "handle": "@max", "userId": "U…" },
  "review":  { "postMode": "confirm" }                // confirm (default) | auto — passed through to review-prs
}
```

Tracker (Linear/Jira) + team/project are **not** stored here — reuse the `ticket` skill's `<repo>/.claude/tickets.local.json`, or detect the connected tracker MCP and ask once (the same gate `ticket` uses).

## Use any MCP you can see
Discover what's connected **this session** (`claude mcp list` + this session's deferred-tool list) and load schemas with **ToolSearch** before calling. Each section uses what's there and **skips with a one-line note** if its MCP is absent — never block the whole briefing on one missing integration:
- **GitHub** — `gh` CLI (always present if installed).
- **Tracker — Linear *or* Jira** — `list_issues`/`get_issue` (Linear) or the Jira equivalent; reuse the saved mapping.
- **Slack** — `slack_search_public_and_private`, `slack_read_channel`, `slack_read_thread`, `slack_search_users`, `slack_read_user_profile`.

## Memory

Before step 1 run `"${CLAUDE_CONFIG_DIR:-$HOME/.claude}/bin/agent-memory" context --skill morning` and follow what it prints — it carries this skill's memory protocol and the indexes to Read.
Capture surprises to the inbox it names as you go, run its End step before the final report, and end the report with the `memory:` stats line.
If the command is missing, skip this section.

## Steps

1. **Resolve config + identity.** Read `~/.claude/morning.local.json`. Fill gaps once (AskUserQuestion): which **repos** to scan (offer the current repo + any you can infer), which **Slack channels** matter (or "just mentions + DMs"). Resolve "me": GitHub `gh api user --jq .login`; Linear current user (`get_user` "me"); Slack handle via `slack_search_users` on the user's name/email (`max.levchuk@fiveirongolf.com`) — cache the ids. Save.

2. **Section A — PRs to review.** For each configured repo, `gh pr list --repo <r> --state open --search "<prFilter>" --json number,title,author,url,latestReviews`, then **drop any PR you've already approved** — GitHub search has no `approved-by` qualifier, so cut them client-side: `--jq '[.[] | select((.latestReviews // []) | any(.author.login == "<me>" and .state == "APPROVED") | not)]'`. These are the PRs still *awaiting your review* (default: open, not authored by you, not yet approved by you). A PR you approved and that was then pushed to still reads as approved here and stays dropped until you re-review — that's intended for a morning glance. For each, run the **review-prs** skill to analyze the PR — it scopes the CLAUDE.md rules to the changed paths, cross-checks the linked ticket, and finds logic/quality issues, reusing the reviewer agents. Its confirm gate already holds every comment, so **nothing is posted from the briefing** — surface a one-line verdict per PR (looks good / N blocking / nits) with the top issue, then list the PRs that have findings and offer "post the review comments?" rather than posting silently. Many PRs → review the highest-traffic / oldest-waiting first and say how many you covered.

3. **Section B — My tickets, logically sorted.** Pull issues **assigned to me** in an actionable state (Todo / In Progress / current cycle or sprint; skip Done/Canceled) via the tracker. For each, capture: project, priority, estimate/points if set, due date, and a **one-line plain-English "what it is"** (from the title + first lines of the description — not a paste). Then **sort and group** (see the sort model below) and present as a grouped checklist with dimension chips so the user can see urgency, effort, and size at a glance. Don't start implementing anything unprompted.

4. **Section C — Slack, compacted.** Using the Slack MCP:
   - **Mentions of me** — `slack_search_public_and_private` for the user's handle/`<@userId>` since ~last working day; read each in context (`slack_read_thread`) enough to summarize the ask.
   - **DMs + urgent** — direct messages and anything with urgency markers (asked a direct question, "blocker", "urgent", "can you", a deadline, ping in an incident channel).
   - **Unread digest** — for the watched channels, a compact summary of unread: who needs what, decisions made, threads worth opening. Don't transcribe — summarize.
   - Sort the same way as tickets (most-urgent / needs-a-reply-from-me first), each as one line: who · channel/DM · the ask · link.

5. **Assemble the briefing, then humanize.** One scannable digest, three sections, urgent-first within each. Keep it tight — this is a glance-and-go, not a report. End with a short **"do first"** suggestion (the 1–3 highest-leverage items across all three) and the open offers (post the PR comments?). If a section's MCP wasn't connected, show the section header with a one-line "not connected — skipped" so the user knows it wasn't forgotten. **Run the assembled prose** (the section summaries and the Slack/ticket one-liners — not the chips, links, or ids) **through the `humanizer` skill** so it reads like notes you'd jot for yourself, not an AI digest. (PR comments are already humanized inside review-prs.)

```
☀️  Morning — Mon Jun 29

PRs TO REVIEW (3 awaiting your review)
  #214  Fix coupon over-charge        alice   → 1 blocker (orders.ts:88), matches ENG-123
  #209  Admin table redesign          bob     → 2 nits, clean otherwise
  #201  Bump deps                     carol   → looks good
  → post review comments? (held for your OK)

YOUR TICKETS (6 assigned)
 Web app
  - [ ] ENG-123  Coupon over-charges on checkout     🔴 Urgent · ~S · in PR review
  - [ ] ENG-140  CSV export on reports page          🟠 High   · ~M · design linked
 Billing
  - [ ] ENG-151  Investigate webhook retry spikes     🟠 High   · ~M · research
  - [ ] ENG-160  Rename invoice fields                ⚪ Low    · ~S · quick win
  → pick any to work next?

SLACK (4 need you)
  • alice  #eng    "can you review #214 today?"            → thread
  • lead   DM      "are we still on for the 2pm?"          → DM
  • #bugs          3 unread — one new P1 on the importer   → thread
  • #random        12 unread — nothing for you

DO FIRST →  review #214 (alice's blocker + she's waiting) · reply to lead's 2pm · ENG-160 is a 5-min win
```

## Sort model (tickets and Slack)
Rank so the user sees the shape of the day, not just a flat list:
1. **Urgency first** — explicit priority (Urgent > High > Med > Low), then due-date/SLA, then "blocks someone else" or "a person is waiting on a reply". A direct question in Slack or a reviewer waiting on a PR counts as urgent.
2. **Within an urgency band, surface quick wins** — small/low-effort items before big ones, so the user can clear easy things fast. Flag the genuinely **big/hard** ones (large estimate, vague scope, cross-system) so they're planned, not started cold.
3. **Group by project** (tickets) / by channel-vs-DM (Slack) so context-switching is visible.
4. **Show the dimensions, don't hide them** — every item carries chips: `[project] [priority] [~effort S/M/L] [state]`. Effort = the tracker's estimate/points if set, else your S/M/L read of how big **and** how hard the scope is — call it an estimate. The order is a suggestion; the chips let the user re-prioritize at a glance.

## Rules
- **Read-only by default.** The briefing only reads. The single thing that can write — a PR review comment — is held behind review-prs's confirm gate; never post, reply in Slack, or change a ticket without the user asking.
- **Ask once, remember forever.** Repos, channels, and the post mode are gathered on first run and saved; `declined` is permanent. The user edits `~/.claude/morning.local.json` to change them.
- **Degrade, don't fail.** No tracker MCP → skip Section B with a note. No Slack MCP → skip Section C with a note. No repos configured → use the current repo. One missing piece never kills the briefing.
- **Compact over complete.** Summarize Slack and ticket descriptions to one line each; the user opens the link for detail. A morning briefing that takes five minutes to read defeats the purpose.
- **Humanize the prose.** The assembled briefing runs through the `humanizer` skill (step 5) so it reads human, not AI-generated — prose only; ids, links, and chips stay verbatim. PR comments are humanized within review-prs.
- **Nothing silently dropped.** If you cap PRs reviewed or unread channels summarized, say how many you covered and what's left.
- **Reuse the pieces.** PR review = `review-prs`; tracker mapping = the `ticket` skill's config. You orchestrate and sort; you don't reimplement any of them.
