#!/usr/bin/env bash
# Live acceptance test for agent-memory: one real `claude -p` run inside a scratch worktree,
# asserting that a memory-enabled project agent received the protocol, wrote one memory, and
# that the memory landed in the main checkout. Spends tokens; run it by hand.
#
# Env: AGENT_MEMORY_SMOKE_DIR (scratch root, default mktemp), AGENT_MEMORY_SMOKE_MODEL
# (default claude-sonnet-5). Needs memory/install.sh already run into the active CLAUDE_CONFIG_DIR.
set -uo pipefail

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
MODEL="${AGENT_MEMORY_SMOKE_MODEL:-claude-sonnet-5}"
ROOT="${AGENT_MEMORY_SMOKE_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/agent-memory-smoke.XXXXXX")}"
MAIN="$ROOT/repo"
WT="$MAIN/.claude/worktrees/wt1"
MEM="$MAIN/.claude/agent-memory-local"
TRANSCRIPT="$ROOT/transcript.txt"
FAILS=0

fail() { echo "  FAIL: $*"; FAILS=$((FAILS + 1)); }
ok()   { echo "  ok:   $*"; }
die()  { echo "FAIL: $*"; exit 1; }

command -v claude >/dev/null 2>&1 || die "claude CLI not on PATH"
command -v jq >/dev/null 2>&1 || die "jq not on PATH"
[ -x "$CLAUDE_DIR/bin/agent-memory" ] || die "$CLAUDE_DIR/bin/agent-memory missing — run memory/install.sh first"
for ev in SessionStart SubagentStart SubagentStop; do
  jq -e --arg ev "$ev" '[.hooks[$ev][]?.hooks[]?.command // ""] | any(contains("agent-memory"))' \
    "$CLAUDE_DIR/settings.json" >/dev/null 2>&1 || die "$ev hook not wired in $CLAUDE_DIR/settings.json — run memory/install.sh first"
done

rm -rf "$MAIN"; mkdir -p "$MAIN"
git -C "$MAIN" init -q -b main 2>/dev/null || { git -C "$MAIN" init -q && git -C "$MAIN" checkout -q -b main; }
git -C "$MAIN" config user.email smoke@example.com
git -C "$MAIN" config user.name smoke
echo "# agent-memory smoke repo" > "$MAIN/README.md"
printf '.claude/worktrees/\n.claude/agent-memory-local/\n' > "$MAIN/.gitignore"
git -C "$MAIN" add -A && git -C "$MAIN" commit -qm "init" || die "could not create the scratch commit"

mkdir -p "$MAIN/.claude/agents" "$MAIN/.claude/worktrees"
cat > "$MAIN/.claude/agents/memsmoke.md" <<'AGENT'
---
name: memsmoke
description: Throwaway agent that proves the agent-memory hooks work. Only memory/tests/smoke.sh invokes it.
tools: Read, Bash, Glob
model: inherit
memory: local
---

You are **memsmoke**. Do exactly the steps below, using Bash for every file operation, then stop. Do not explore the repo.

1. Find the section of your context whose first line starts with `# Memory protocol`. If there is none, reply with the single line `MEMORY_CONTEXT_MISSING` and stop. Otherwise keep that first line verbatim for step 5.
2. Take `PROJECT_DIR` from that protocol: the PROJECT tier path, which ends in `/.claude/agent-memory-local/memsmoke`. Create it if needed. Append exactly one line to `<PROJECT_DIR>/inbox.md` in the protocol's inbox format: kind `recipe`, scope `project`, audience `self`, fact `the agent-memory smoke test ran here`, evidence `memory/tests/smoke.sh`.
3. Run the protocol's End step on that one line as an ADD: write `<PROJECT_DIR>/smoke-test-ran.md` with the protocol's frontmatter (`name: smoke-test-ran`, `metadata.type: project`, `kind: recipe`, `scope: project`, `audience: self`, `seen: 2`, today's dates, `source` from the protocol) and a one-sentence fact with **Why** and **How to apply** lines; append exactly one line to `<PROJECT_DIR>/MEMORY.md`: `- [Smoke test ran](smoke-test-ran.md) — the agent-memory smoke test wrote this entry`; then remove the inbox line so `inbox.md` is empty.
4. `cat` `MEMORY.md` and `inbox.md` to confirm: MEMORY.md has exactly one line, inbox.md is empty.
5. Your final message is exactly these three lines and nothing else:
   PROTOCOL: <the first line from step 1, verbatim>
   FILES: <PROJECT_DIR>/smoke-test-ran.md, <PROJECT_DIR>/MEMORY.md
   memory: recalled <index entries that were in your context> used 0 saved 1 repeats 0
AGENT

git -C "$MAIN" worktree add -q "$WT" -b wt1 || die "could not create the worktree"
mkdir -p "$WT/.claude/agents"
ln -s "$MAIN/.claude/agents/memsmoke.md" "$WT/.claude/agents/memsmoke.md"

PROMPT="Invoke the memsmoke subagent (Agent tool, subagent_type memsmoke) with the prompt 'go'. Return its final message verbatim."
echo "Scratch repo: $MAIN"
echo "Worktree:     $WT"
echo "Running claude -p ($MODEL) inside the worktree ..."
# The prompt goes on stdin: --allowedTools is variadic and would swallow a trailing positional.
( cd "$WT" && printf '%s\n' "$PROMPT" | env -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT \
    claude -p --model "$MODEL" --max-turns 10 --output-format text \
      --allowedTools "Agent,Task,Read,Bash,Glob" ) > "$TRANSCRIPT" 2> "$ROOT/stderr.txt"
rc=$?
echo "claude exited $rc; transcript: $TRANSCRIPT"
echo

echo "Assertions:"
if [ -L "$WT/.claude/agent-memory-local" ]; then
  target="$(cd "$WT/.claude" && cd "$(readlink agent-memory-local)" 2>/dev/null && pwd -P)"
  want="$(cd "$MEM" 2>/dev/null && pwd -P)"
  if [ -n "$target" ] && [ "$target" = "$want" ]; then
    ok "worktree .claude/agent-memory-local is a symlink to the main checkout's"
  else
    fail "worktree symlink points at '$(readlink "$WT/.claude/agent-memory-local")', expected $MEM"
  fi
else
  fail "$WT/.claude/agent-memory-local is not a symlink ($(ls -ld "$WT/.claude/agent-memory-local" 2>&1))"
fi

idx="$MEM/memsmoke/MEMORY.md"
if [ -f "$idx" ]; then
  n="$(grep -c '[^[:space:]]' "$idx")"
  if [ "$n" = 1 ] && grep -q '^- \[' "$idx"; then
    ok "MEMORY.md exists in the main checkout with one index line: $(cat "$idx")"
  else
    fail "MEMORY.md has $n non-blank lines (expected 1):"; sed 's/^/        /' "$idx"
  fi
else
  fail "$idx missing"
fi

topics="$(find "$MEM/memsmoke" -maxdepth 1 -name '*.md' ! -name MEMORY.md ! -name inbox.md 2>/dev/null | wc -l | tr -d ' ')"
[ "$topics" = 1 ] && ok "exactly one memory file written" || fail "expected 1 memory file, found $topics"
if [ -s "$MEM/memsmoke/inbox.md" ] && grep -q '[^[:space:]]' "$MEM/memsmoke/inbox.md"; then
  fail "inbox.md still has unprocessed lines"
else
  ok "inbox.md empty or absent"
fi

stats="$MEM/memsmoke/stats.tsv"
if [ -f "$stats" ] && grep -q '[0-9]' "$stats"; then
  ok "stats.tsv row appended: $(tail -n1 "$stats")"
else
  fail "stats.tsv missing or empty at $stats (SubagentStop hook did not record the memory: line)"
fi

if grep -q 'MEMORY_CONTEXT_MISSING' "$TRANSCRIPT"; then
  fail "agent reported MEMORY_CONTEXT_MISSING (SubagentStart hook injected nothing)"
elif grep -q '# Memory protocol' "$TRANSCRIPT"; then
  ok "agent quoted the protocol: $(grep -m1 '# Memory protocol' "$TRANSCRIPT")"
else
  fail "transcript has no '# Memory protocol' quote"
fi
grep -q 'memory: recalled [0-9]* used [0-9]* saved [0-9]* repeats [0-9]*' "$TRANSCRIPT" \
  && ok "agent ended with the memory: stats line" || fail "no memory: stats line in the transcript"

reg="$CLAUDE_DIR/agent-memory/.registry"
[ -f "$reg" ] && grep -vxF "$MAIN" "$reg" > "$reg.tmp" && mv "$reg.tmp" "$reg"

echo
if [ "$FAILS" = 0 ]; then
  echo "PASS — transcript: $TRANSCRIPT"
  exit 0
fi
echo "FAIL ($FAILS) — transcript: $TRANSCRIPT  stderr: $ROOT/stderr.txt"
echo "--- transcript tail ---"; tail -n 30 "$TRANSCRIPT"
echo "--- stderr tail ---"; tail -n 15 "$ROOT/stderr.txt"
exit 1
