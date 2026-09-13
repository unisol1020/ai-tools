---
name: bootstrap
description: One command to make a repo (and a fresh machine) fully ready for this Claude Code setup. Installs and configures the required extensions if they're missing — ripgrep, CodeGraph + its MCP, graphify, and the ponytail plugin — then builds the CodeGraph index, optionally builds the graphify knowledge graph, augments CLAUDE.md, and records the repo as bootstrapped so the session-start nudge stops. Use when onboarding a project or a teammate's machine, when the session-start hook says the repo isn't bootstrapped, or when the user runs /bootstrap.
---

# bootstrap — one-command project + environment setup

Run this to take a repo (and a fresh machine) from nothing to fully set up for this stack. The point: a teammate clones a repo, runs `/bootstrap`, and every extension the projects here expect is installed, configured, and indexed — no hunting for what to install or how to wire it up.

## What it sets up

- **ripgrep** (`rg`) — fast search.
- **CodeGraph** — the `@colbymchenry/codegraph` CLI + its MCP server in Claude Code, then a built index of this repo.
- **graphify** — the `graphifyy` PyPI package (provides the `graphify` CLI; Python 3.10+, installed via uv/pipx) + the `/graphify` skill, plus an optional **per-commit auto-sync** that keeps the graph fresh with zero tokens.
- **ponytail** — the ponytail Claude Code plugin (lazy-senior-dev mode: YAGNI, stdlib-first, fewest lines).
- **MemPalace** — the [MemPalace](https://github.com/MemPalace/mempalace) memory engine (`mempalace` PyPI package, installed via uv/pipx) + its MCP server + its **automatic capture hooks** (`SessionStart` loads memory, `Stop`/`SessionEnd`/`PreCompact` save it). Stores verbatim text with **local embeddings — no API key, no per-session LLM call, no quota to exhaust**.
  The hooks are the part that makes memory automatic. The MCP alone only exposes tools the model *may* call; without the hooks nothing is saved on its own.
- **Standard code-comment policy** — writes the required `## Code Comments` rules (no comments by default; one-line `why` only) into the repo's `CLAUDE.md` and any existing `AGENTS.md` / `AGENT.md`, so every project enforces the same standard.

Only what's missing is installed; re-running is safe.

## Steps

1. **Resolve repo + bootstrapped state.** `root = $(git rev-parse --show-toplevel 2>/dev/null || pwd)`. If `root` is already a line in `~/.claude/.bootstrapped-projects`, tell the user it's already bootstrapped and ask whether to re-run (refresh deps / re-index) or stop.

2. **Install + configure the extensions.** Run the bundled setup script — it detects what's present and installs only the gaps, idempotently:
   ```bash
   bash ~/.claude/skills/bootstrap/setup-env.sh
   ```
   Relay what it installed vs what was already there. It handles ripgrep, the CodeGraph CLI + MCP, graphify + its skill, MemPalace + its MCP, and writes the ponytail plugin into `~/.claude/settings.json`. The plugin + the CodeGraph/MemPalace MCPs only surface after a **Claude Code restart** — note that for the end.

3. **Build the CodeGraph index.** If `$root/.codegraph/` doesn't exist:
   - **Large repo** (lots of files / a big monorepo)? **Ask first** — indexing can take a while and spins up workers. On confirm (or for a normal-size repo): `codegraph init "$root"`.
   - Already indexed → `codegraph sync "$root"` to catch up.

4. **Build the graphify knowledge graph (optional, heavy).** Offer to run `/graphify` on the repo — a heavier pipeline (extraction, clustering, may download models). **Ask before running**; run on confirm, skip otherwise. Never kick it off silently.

5. **Install the graphify per-commit auto-sync (only if a graph was built).** Skip if `$root/graphify-out/graph.json` doesn't exist. This adds a Claude Code `PostToolUse` hook that, after every `git commit`, runs a silent, **zero-token** AST pass refreshing `graph.json` from the commit's changed code files — the model is never involved, and generated/native/vendor dirs (`node_modules`, `ios`, `android`, `Pods`, `dist`, `build`, …) are excluded by path segment. It writes to the repo's gitignored `.claude/` (personal, per-dev — never imposed on teammates via shared git/Husky hooks). **Ask before enabling** (it reacts to your commits), then on confirm:
   ```bash
   bash ~/.claude/skills/bootstrap/install-graphify-sync.sh "$root"
   ```
   Idempotent — re-running won't duplicate the hook. The hook only takes effect after a **Claude Code restart** (note it for the end). Tell the user: code changes stay fresh automatically and free; **doc/README/spec changes still need a manual `/graphify --update`** (those are the only token-costing files). If the installer warns that `.claude/` isn't gitignored, relay it.

6. **Prime MemPalace's memory (optional, heavy — but free).** Offer to file the repo into the palace:
   ```bash
   mempalace init "$root" --yes --no-llm
   mempalace mine "$root"
   ```
   This is **zero-token** — embeddings run locally, the model is never called. It is still CPU/RAM heavy and can take a while on a big repo, so **ask before running**; run on confirm, skip otherwise. Check the dry run first (`mempalace mine "$root" --dry-run`) and relay the drawer count — if it reports *files skipped (chunk cap)*, say so rather than letting oversized files drop silently.

7. **Augment CLAUDE.md + enforce the comment policy.** Two parts, both non-destructive (back up each file before editing):
   - **a. Stack note.** Create or update `$root/CLAUDE.md` with a short note that CodeGraph is indexed and should be reached for before grep/find on code questions (mirror the user's global convention), plus the detected stack. Don't duplicate a note that's already there.
   - **b. Standard Code Comments policy (always, by default).** Insert the canonical block from `~/.claude/skills/bootstrap/code-comments.md` **verbatim** into the repo's agent-instruction files. Targets: `$root/CLAUDE.md` (create it if missing) **and every existing** `CLAUDE.md` / `AGENTS.md` / `AGENT.md` already in the repo — root and nested (so a monorepo's per-app files get it too). Don't create new `AGENTS.md`/`AGENT.md` where none exists; only update the ones that are there. For each target: if it already has a `## Code Comments` section, **replace that whole section** with the canonical block (keeps the standard current as it evolves); otherwise **append** the block. Insert it exactly as written — it's a fixed standard, never paraphrase or adapt it per repo.

8. **Migrate from claude-mem (only if `~/.claude-mem/claude-mem.db` exists).** Offer to run:
   ```bash
   bash ~/.claude/skills/bootstrap/mempalace-migrate.sh
   ```
   It exports every claude-mem observation to month-split markdown (read-only, **no LLM calls**), mines it into the palace, and wires the capture hooks. Add `--remove-claude-mem` to disable the old plugin afterwards (its database is kept), or `--purge-claude-mem` to delete `~/.claude-mem` outright — **only offer purge once the user confirms recall works**. `--with-cloud` additionally installs the third-party MemPalace Cloud plugin; do not add it by default (see the README note — it auto-saves to `api.mempalace.cloud`, not the local palace).

   **Ask before running** — mining is CPU-heavy. Relay the dry-run's skipped-file count if it reports one: files over the chunk cap are dropped **silently**, so an unreported skip means memories quietly did not migrate.

9. **Record completion.** Append `root` as a new line to `~/.claude/.bootstrapped-projects` (create the file if missing; no duplicates). This stops the session-start nudge for this repo.

10. **Report.** What was installed, whether the index built, whether graphify ran, whether the per-commit auto-sync was enabled, whether MemPalace was primed (and any files it skipped at the chunk cap), which files got the Code Comments policy (created vs updated), and: **restart Claude Code once** so the ponytail plugin + CodeGraph/MemPalace MCPs load.

## Rules

- **Idempotent + non-destructive.** Install only the gaps; back up `settings.json` / `CLAUDE.md` before editing; don't re-index a fresh index without a reason.
- **Ask before the heavy/slow steps** — indexing a large repo, running `/graphify`, and priming with `mempalace mine`. Don't start them silently.
- **Keep private data local.** `~/.claude/.bootstrapped-projects` lists real repo paths; it lives under `~/.claude` and is never committed to any repo.
- **No secrets, no prod actions.** This only installs dev tooling and indexes locally.
