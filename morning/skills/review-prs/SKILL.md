---
name: review-prs
description: Review GitHub PRs against the project's CLAUDE.md (monorepo-aware — root + the per-app/nested CLAUDE.md that actually govern the changed paths) plus logic and code quality, then post the findings as PR review comments — confirming before anything public is posted. One PR ("review this PR: <url>") or every open PR in a repo ("review all PRs"). Scopes the rule check to the CLAUDE.md files that govern each changed file, cross-checks the diff against its linked Linear/Jira ticket to see whether the logic matches intent, and leans on the project's frontend / backend / security reviewer agents where present. Writes short, specific, human comments (file:line + the exact rule or bug) — never AI slop. Use when the user says "review all PRs", "review this PR: <link>", "review open PRs in <repo>", "review PRs not assigned to me", or invokes /review-prs. Runs in the MAIN thread so it can confirm before posting.
---

# review-prs — CLAUDE.md-aware PR reviewer

You (the **main thread**) review one or more GitHub PRs the way a careful teammate would: against the project's **own rules** (`CLAUDE.md`), against what the **ticket** actually asked for, and for plain **logic and quality** bugs — then leave **short, specific, human** comments. The whole point is signal: a few real findings cited at `file:line`, not a wall of AI slop. **Nothing public is posted until the user confirms** (these comments land on other people's PRs).

## Use any tool you can see
GitHub goes through the **`gh` CLI** (always works — `gh pr list/view/diff`, `gh api`). Discover other MCPs **live this session** (`claude mcp list` + this session's deferred-tool list — names change) and load schemas with **ToolSearch** before calling:
- **Tracker — Linear *or* Jira** (whichever `tickets.local.json` says, or whichever is connected): read the PR's linked ticket for intent.
- **Reviewer agents** — if the repo/global config ships `frontend-reviewer`, `backend-reviewer`, `security-reviewer`, or the `code-review` skill, use them as the quality engine (see step 5). Never require any of these — fall back to reading the diff yourself.

## Config
This skill is mostly stateless. It reads the **tracker** mapping from `<root>/.claude/tickets.local.json` (the `ticket` skill's config) and an optional **post default** from `<root>/.claude/morning.local.json` (`review.postMode: "confirm" | "auto"`, default `confirm`). It writes nothing required.

## Memory

Before step 1 run `"${CLAUDE_CONFIG_DIR:-$HOME/.claude}/bin/agent-memory" context --skill review-prs` and follow what it prints — it carries this skill's memory protocol and the indexes to Read.
Capture surprises to the inbox it names as you go, run its End step before the final report, and end the report with the `memory:` stats line.
If the command is missing, skip this section.

## Steps

1. **Resolve the targets.** From the ask:
   - **A specific PR** — a PR URL, `#<n>`, or "this PR" (the current branch's PR via `gh pr view --json number,url`). Parse `owner/repo/number` from a URL; otherwise default the repo to the current one (`gh repo view --json nameWithOwner`).
   - **All open PRs in a repo** — `gh pr list --repo <owner/repo> --state open --json number,title,author,assignees,headRefName,url --limit 50`. Apply the filter from the ask: default for "review all PRs" / "not mine" = **not authored by me** (`--search "is:open -author:@me"`); honor "assigned to me" / "not assigned to me" (`-assignee:@me`) / a named author if asked. State the filter you used.
   - List what you're about to review (PR #, title, author) before diving in, so the scope is visible.

2. **Pull each PR.** `gh pr view <n> --json title,body,author,baseRefName,headRefName,files,url` and `gh pr diff <n>`. From `files` get the changed paths; from `body` + `headRefName` look for the linked ticket (next step). Skip drafts unless asked. For a very large diff, review the highest-signal files first and say what you skipped — never silently truncate.

3. **Scope the CLAUDE.md rules to the changed paths (monorepo-aware).** The rules that apply to a changed file = the `CLAUDE.md` ancestry of that file: the repo-root `CLAUDE.md` **plus** every `CLAUDE.md` in a directory on the path from root down to the file. So a change under `apps/admin/` is judged against root `CLAUDE.md` **and** `apps/admin/CLAUDE.md`; a change under `apps/api/` against root **and** `apps/api/CLAUDE.md`. Build the set once for the PR:
   ```bash
   # all CLAUDE.md that govern any changed file in this PR (deduped)
   git -C <repo> ls-files '**/CLAUDE.md' 'CLAUDE.md'   # candidates that exist
   ```
   Then, per changed file, keep the root one + any whose directory is a prefix of the file's path. Read each kept `CLAUDE.md` (also honor a global `~/.claude/CLAUDE.md` if its rules are general). If the PR touches a path with its own `CLAUDE.md`, **that file's rules are in scope for those changes** — don't judge `apps/api` code by `apps/admin`'s rules.

4. **Find the linked ticket and read the intent.** Look in the PR body and branch name for a tracker id (`ENG-123`, `PROJ-45`, "Closes …", a Linear/Jira URL). If found, fetch it via the connected tracker MCP (`get_issue` / Jira get-issue) for the **intended behavior + acceptance criteria**. You'll use this in step 5 to check the code actually does what was asked — and to flag scope drift (PR does more or less than the ticket). No ticket linked → note it (a missing ticket link is itself a small finding) and review on the diff alone.

5. **Review the diff — three lenses, verified before kept.** For each PR, cover:
   - **a. CLAUDE.md conformance** — go rule by rule through the in-scope `CLAUDE.md` set (step 3): conventions, comment policy, structure, naming, anything it mandates. Every violation cites the exact file:line and the rule it breaks.
   - **b. Logic / correctness** — does the change do what the ticket (step 4) asked? Off-by-one, wrong branch, unhandled error/null, broken edge case, race, missing await, security-sensitive input at a trust boundary, scope drift vs the ticket.
   - **c. Code quality** — clarity, dead code, duplication, an obvious simpler form, missing test for non-trivial logic. (Keep quality nits few and high-value; don't bikeshed.)

   **Reuse the specialized reviewers** as the engine where they exist: run them in parallel, scoped to the changed areas — `frontend-reviewer` for frontend paths, `backend-reviewer` for backend/API/db paths, `security-reviewer` whenever the diff touches auth, routes, secrets, uploads, redirects, or untrusted input. Give each the diff + the relevant file list. You own the two things they don't: the **CLAUDE.md-rule** pass and the **ticket-intent** cross-check. Then **adversarially verify before keeping a finding** — re-read the cited lines and drop anything you can't defend from the actual code (a wrong public review comment is worse than a missed nit). Each surviving finding: `file:line` · one-line problem · severity **blocking** / **nit**.

6. **Draft the comments (anti-slop), then humanize.** Turn surviving findings into review comments a good engineer would leave — see the style block below. Group by PR. Inline comments for line-specific findings; one short summary comment per PR for the overall verdict. If there are zero real findings, say so (an approving one-liner) — don't manufacture comments to look busy. **Then run the drafted comment text through the `humanizer` skill** (invoke it via the Skill tool on the assembled comments) as the final pass before step 7 — it strips the AI tells the style block can't fully catch (rule-of-three, em-dash overuse, "comprehensive/robust/seamless"-class vocab, negative parallelisms, filler). These comments land publicly on someone's PR, so they must read like a teammate typed them. Keep every concrete `file:line` and code reference exactly as written — humanize the prose, never the facts.

7. **Confirm, then post.** Show the drafted comments per PR and the proposed action. Then:
   - **`postMode: "confirm"` (default)** — post **only** after the user okays it (they can edit/drop any comment first). This is the guard against putting AI slop on a colleague's PR.
   - **`postMode: "auto"`** or the user said "post them" / "post directly" — for a **single PR**, post without the extra prompt. For the **bulk "all PRs"** path, `auto` is the riskiest mode (one run scatters AI-drafted comments across many colleagues' PRs, tedious to retract) — still show the PR list + total comment count and post on **one batch OK**; don't fan out public comments to a dozen people with zero human in the loop.
   - Post with `gh`: inline line comments via `gh api repos/{owner}/{repo}/pulls/{n}/comments` (or `gh pr review <n> --comment -F <body>` for a single review with the summary). Use `--comment` (a neutral review), **not** `--approve` / `--request-changes`, unless the user explicitly asked you to approve or block. Reviewing your **own** PR can't request changes anyway — post as comments.

8. **Report.** One line per PR: # + title + N comments posted (or drafted, if not confirmed) + the verdict (looks good / has blocking issues / nits only). For "review all PRs", a short table; name any PR you skipped (draft, too large, no diff) so nothing is silently dropped.

## The anti-slop review comment
Write like a teammate dropping a note on a line — short, specific, kind, actionable. Same bar as the `ticket` skill.

- **Inline, blocking** — name the problem and the fix in a sentence or two:
  > `apps/api/src/orders.ts:88` — `total` is summed before the discount is applied, so coupon orders over-charge. Move the discount subtraction above the `round()`. (Ticket ENG-123 says the coupon must apply to the line total.)
- **Inline, CLAUDE.md rule** — quote the rule:
  > `apps/admin/src/Table.tsx:40` — `apps/admin/CLAUDE.md` says no inline styles; this uses `style={{…}}`. Move it to the stylesheet/util.
- **Inline, nit** — flag it as optional: prefix `nit:` so the author knows it's not blocking.
- **Summary comment** — 2–4 lines: what the PR does, the verdict, and the blocking items by reference. Example: *"Does what ENG-123 asks. One blocker (orders.ts:88 over-charges coupon orders) + 2 nits. Logic otherwise reads clean."*

Rules for the prose: plain present tense, like a Slack message. No *comprehensive / robust / seamless / leverage / utilize*, no emoji spam, no "As an AI", no praise padding. Cite real `file:line`, real symbols. One finding per comment. If it isn't actionable, don't post it.

## Rules
- **Nothing public without consent.** Default `postMode: confirm` — show drafts, post only on the user's OK. `auto` only when configured or the user said so this run, and even then the **bulk** "all PRs" path keeps a single batch confirmation (count + PR list) — `auto` skips the prompt for a single PR, never for a fan-out across many people's PRs. Never `--approve` / `--request-changes` unless explicitly asked.
- **Right rules for the right code.** A changed file is judged against its own `CLAUDE.md` ancestry (root + nested), never another app's. Scope it per file (step 3).
- **Verify before you post.** Re-read the cited lines; drop any finding you can't defend from the actual diff. A confidently wrong comment on someone's PR is the failure mode to avoid.
- **Signal over volume.** A few real findings beat twenty nits. Zero issues → say it in one line; don't invent comments.
- **Humanize before it's public.** Every drafted comment goes through the `humanizer` skill before it's shown or posted (step 6). The style block sets the bar; the humanizer is the final pass that removes AI tells. It rewrites prose only — `file:line`, symbols, and code snippets stay verbatim.
- **Check intent, not just syntax.** When a ticket is linked, the most useful finding is "this doesn't do what the ticket asked" / "this does more than the ticket asked" — look for it.
- **Reuse, don't reinvent.** Use the project's reviewer agents / `code-review` skill as the quality engine; this skill adds the CLAUDE.md-rule pass, the ticket cross-check, target resolution, and posting. Discover MCPs live and degrade gracefully when one's absent.
