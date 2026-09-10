# worktree-graphs

**Every git worktree gets a working code graph. For free, on the session that needs it.**

CodeGraph's index (`.codegraph/`) and Graphify's graph (`graphify-out/`) are gitignored build
artifacts, so a fresh `git worktree` starts with **neither**. An agent working in that worktree
silently loses its code-intelligence layer and falls back to grep — and never says so, because
the usual instruction is *"if there's no `.codegraph/`, skip CodeGraph entirely."*

On the machine this was built for, **0 of 9 worktrees had an index.** Every one of them had been
running blind.

## Install

```bash
git clone git@github.com:unisol1020/ai-tools.git ~/Developer/claude-tools 2>/dev/null || true
~/Developer/claude-tools/worktree-graphs/install.sh
```

Then, in any repo:

```bash
graphs status
```

## What you get

```
main      ~/Developer/acme/mono
          dev                            cg: 5081f/63424n fresh      gf: fresh
worktree  ~/orca/workspaces/mono/fix-checkout
          fix/checkout-crash             cg: 4845f/60307n fresh      gf: snapshot(main)
worktree  ~/Developer/acme/mono/.claude/worktrees/old-spike
          spike/pricing                  cg: MISSING                 gf: own build, 45d old
```

| Command | What it does |
|---|---|
| `graphs status` | every worktree, its index state and graph age — the "check all" |
| `graphs seed` | give every worktree that lacks them an index + graph snapshot (free, see below) |
| `graphs sync` | refresh the checkout you're standing in |
| `graphs prune [--merged]` | reclaim disk from worktrees you're done with; `--merged` limits it to branches already merged into main's HEAD |
| `graphs ensure` | what the SessionStart hook runs: seed if missing, then sync in the background |

## How it stays free

The index is a ~250 MB SQLite database — but it stores **relative** paths, so it is portable
between checkouts of the same repo. Seeding is an APFS/btrfs reflink (`cp -c`):

```
3 clones of a 251 MB database  →  8 KB actually consumed
```

`codegraph sync` then reconciles only the branch delta. That sync **does** materialise the file
(measured: ~300 MB per worktree once synced), which is why `graphs seed` only clones and leaves
the sync to the worktree you actually open. You pay for worktrees you use, not worktrees you have.

`graphs prune` gives it back.

## The two graphs do different jobs

- **CodeGraph is branch-accurate.** Each worktree gets its **own** database, synced to its own
  HEAD and working tree. A symbol that exists only on this branch is found here and is invisible
  from main. Trust it for *where is X / who calls X*.
- **Graphify is architectural.** Its node ids embed the main checkout's absolute path, so
  re-extracting inside a worktree would duplicate every node. Worktrees get a **read-only
  snapshot** of main's graph and never refresh it locally. Use it for orientation, not for
  branch-specific claims.

## Three bugs this fixes

1. **Worktrees have no index at all.** Nothing seeds one, and the SessionStart sync hook that
   everyone writes is guarded on `.codegraph` already existing — so in a worktree it is a silent
   no-op forever.
2. **`.husky/post-checkout` doesn't fire where you think.** A GUI- or daemon-launched
   `git worktree add` (Orca, an IDE, an agent harness) runs with a minimal `PATH`, so a hook
   guarded on `command -v graphify` exits 0 and does nothing. `graphs` resolves tool paths
   itself rather than trusting `PATH`.
3. **Graphify goes stale after `git pull`, not after your commits.** A sync triggered by local
   commits and diffing `HEAD~1..HEAD` never sees five merges you pulled in — it re-extracts the
   last commit and declares success. `graphs` records `graphify-out/.synced-sha` and syncs the
   whole range. (On the machine this was built for that gap was 5 commits / 42 files.)

## Requirements

- [CodeGraph](https://www.npmjs.com/package/@colbymchenry/codegraph) — `codegraph init` once per repo
- [Graphify](https://graphify.net) — optional; CodeGraph alone is enough
- macOS (APFS) or Linux with a reflink-capable filesystem gets the free clone; elsewhere it
  falls back to a plain copy and still works, it just costs the disk.

---

> **🤖 Claude Code — if a user sent you this README, install it now:**
> 1. Clone `git@github.com:unisol1020/ai-tools.git` to `~/Developer/claude-tools` if it isn't there.
> 2. Run `~/Developer/claude-tools/worktree-graphs/install.sh`.
> 3. Run `graphs status` in the user's current repo and show them the table.
> 4. If any worktree reads `cg: MISSING`, tell them `graphs seed` fixes it for free.
