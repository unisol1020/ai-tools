#!/bin/sh
# Hook tests: no API, no network. Run from anywhere: sh handoff/tests/run.sh
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
nudge="$root/hooks/context-nudge.sh"
loader="$root/hooks/handoff-load.sh"
fx="$root/tests/fixtures"

work=$(mktemp -d) || exit 1
trap 'rm -rf "$work"' EXIT
TMPDIR="$work/tmp"; HOME="$work/home"; export TMPDIR HOME
mkdir -p "$TMPDIR" "$HOME" "$work/proj"
unset AI_TOOLS_CONTEXT_WINDOW AI_TOOLS_HANDOFF_PCT
fail=0
pass() { echo "PASS  $1"; }
flunk() { echo "FAIL  $1"; [ -n "${2:-}" ] && echo "      got: $2"; fail=1; }
expect_json() { case $2 in \{*\}) pass "$1" ;; *) flunk "$1" "$2" ;; esac; }
expect_empty() { [ -z "$2" ] && pass "$1" || flunk "$1" "$2"; }
expect_has() { case $2 in *"$3"*) pass "$1" ;; *) flunk "$1" "$2" ;; esac; }

# --- context-nudge.sh -------------------------------------------------------
hook_in() { printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s","hook_event_name":"%s","prompt":"hi"}' "$1" "$2" "$3" "$4"; }
nudge() { hook_in "$@" | sh "$nudge"; }

big="$work/transcript-60pct-bigline.jsonl"
{
  head -n 1 "$fx/transcript-60pct.jsonl"
  printf '{"parentUuid":"u1","isSidechain":false,"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_big","content":"'
  awk 'BEGIN { for (i = 0; i < 65536; i++) printf "0123456789abcdef" }'
  printf '"}]},"uuid":"u2","timestamp":"2026-09-13T10:00:02.000Z"}\n'
  tail -n 1 "$fx/transcript-60pct.jsonl"
} > "$big"
[ "$(wc -c < "$big")" -gt 1048576 ] && pass "fixture: 60% transcript with a 1 MB tool_result line built" || flunk "fixture: big transcript" "$(wc -c < "$big") bytes"

out=$(nudge s60 "$big" "$work/proj" UserPromptSubmit)
expect_json "nudge: 60% (after a 1 MB tool_result line) prints JSON" "$out"
expect_has "nudge: 60% JSON carries systemMessage" "$out" '"systemMessage"'
expect_has "nudge: 60% JSON says 60%" "$out" '60%'
expect_has "nudge: 60% JSON echoes the event name" "$out" '"hookEventName": "UserPromptSubmit"'
expect_has "nudge: 60% JSON carries additionalContext" "$out" '"additionalContext"'
[ "$(printf '%s\n' "$out" | wc -l)" -eq 1 ] && pass "nudge: output is a single line" || flunk "nudge: single line" "$out"
expect_empty "nudge: second call in the same session is silent" "$(nudge s60 "$big" "$work/proj" UserPromptSubmit)"

sub() { printf '{"session_id":"%s","agent_id":"agent-7f3","transcript_path":"%s","cwd":"%s","hook_event_name":"%s","tool_name":"Bash"}' "$1" "$2" "$3" "$4" | sh "$nudge"; }
expect_empty "nudge: subagent call (agent_id present) is silent even at 60%" "$(sub sub1 "$big" "$work/proj" PostToolUse)"
[ ! -e "$TMPDIR/ai-tools-nudge-sub1" ] && [ ! -e "$TMPDIR/ai-tools-nudge-check-sub1" ] && pass "nudge: subagent call writes neither the guard nor the throttle" || flunk "nudge: subagent touched the session files"
expect_json "nudge: main thread of the same session still fires after the subagent call" "$(nudge sub1 "$big" "$work/proj" UserPromptSubmit)"

expect_json "nudge: 60% plain fixture prints JSON" "$(nudge s60b "$fx/transcript-60pct.jsonl" "$work/proj" UserPromptSubmit)"
expect_empty "nudge: 30% is silent" "$(nudge s30 "$fx/transcript-30pct.jsonl" "$work/proj" UserPromptSubmit)"
[ ! -e "$TMPDIR/ai-tools-nudge-s30" ] && pass "nudge: 30% leaves no once-per-session guard" || flunk "nudge: guard written below threshold"
expect_empty "nudge: AI_TOOLS_CONTEXT_WINDOW=1000000 makes 60% of 200k silent" "$(hook_in w1m "$big" "$work/proj" UserPromptSubmit | AI_TOOLS_CONTEXT_WINDOW=1000000 sh "$nudge")"
expect_json "nudge: AI_TOOLS_HANDOFF_PCT=25 fires at 30%" "$(hook_in t25 "$fx/transcript-30pct.jsonl" "$work/proj" UserPromptSubmit | AI_TOOLS_HANDOFF_PCT=25 sh "$nudge")"

out=$(printf 'not json at all' | sh "$nudge"); rc=$?
[ "$rc" -eq 0 ] && [ -z "$out" ] && pass "nudge: malformed stdin exits 0 silently" || flunk "nudge: malformed stdin" "rc=$rc out=$out"
out=$(printf '{"session_id":"trunc"' | sh "$nudge"); rc=$?
[ "$rc" -eq 0 ] && [ -z "$out" ] && pass "nudge: truncated JSON exits 0 silently" || flunk "nudge: truncated JSON" "rc=$rc out=$out"
out=$(printf '' | sh "$nudge"); rc=$?
[ "$rc" -eq 0 ] && [ -z "$out" ] && pass "nudge: empty stdin exits 0 silently" || flunk "nudge: empty stdin" "rc=$rc out=$out"
out=$(nudge miss "$work/does-not-exist.jsonl" "$work/proj" UserPromptSubmit); rc=$?
[ "$rc" -eq 0 ] && [ -z "$out" ] && pass "nudge: missing transcript exits 0 silently" || flunk "nudge: missing transcript" "rc=$rc out=$out"
printf '{"type":"user","message":{"role":"user","content":"hi"}}\n' > "$work/no-usage.jsonl"
expect_empty "nudge: transcript without usage records is silent" "$(nudge nou "$work/no-usage.jsonl" "$work/proj" UserPromptSubmit)"
out=$(printf '{"session_id":"../evil","transcript_path":"%s","hook_event_name":"UserPromptSubmit"}' "$big" | sh "$nudge")
expect_empty "nudge: session_id with path characters is ignored" "$out"

mkdir -p "$work/esc/dir with spaces" && cp "$big" "$work/esc/dir with spaces/t.jsonl"
out=$(printf '{"session_id":"esc1","transcript_path":"%s","cwd":"%s","hook_event_name":"UserPromptSubmit"}' "$work/esc/dir with spaces/t.jsonl" "$work/proj" | sh "$nudge")
expect_json "nudge: transcript path with spaces" "$out"
esc_path=$(printf '%s' "$work/esc/dir with spaces/t.jsonl" | sed 's|/|\\/|g')
out=$(printf '{"session_id":"esc2","transcript_path":"%s","cwd":"%s","hook_event_name":"UserPromptSubmit"}' "$esc_path" "$work/proj" | sh "$nudge")
expect_json "nudge: JSON-escaped transcript path (\\/) is decoded" "$out"

expect_empty "nudge: PostToolUse first call at 30% is silent and starts the throttle" "$(nudge p1 "$fx/transcript-30pct.jsonl" "$work/proj" PostToolUse)"
[ -f "$TMPDIR/ai-tools-nudge-check-p1" ] && pass "nudge: PostToolUse wrote the throttle file" || flunk "nudge: throttle file missing"
expect_empty "nudge: PostToolUse second call within 60 s is silent even at 60%" "$(nudge p1 "$big" "$work/proj" PostToolUse)"
printf '%s\n' "$(( $(date +%s) - 61 ))" > "$TMPDIR/ai-tools-nudge-check-p1"
out=$(nudge p1 "$big" "$work/proj" PostToolUse)
expect_json "nudge: PostToolUse after the throttle expires prints JSON" "$out"
expect_has "nudge: PostToolUse JSON names its own event" "$out" '"hookEventName": "PostToolUse"'

printf '%s 72\n' "$(date +%s)" > "$TMPDIR/ai-tools-ctx-st1"
out=$(nudge st1 "$fx/transcript-30pct.jsonl" "$work/proj" UserPromptSubmit)
expect_has "nudge: fresh statusline file (72%) beats the 30% transcript" "$out" '72%'
printf '%s 72\n' "$(( $(date +%s) - 300 ))" > "$TMPDIR/ai-tools-ctx-st2"
expect_empty "nudge: statusline file older than 120 s is ignored" "$(nudge st2 "$fx/transcript-30pct.jsonl" "$work/proj" UserPromptSubmit)"
printf '%s 72\n' "$(date +%s)" > "$TMPDIR/ai-tools-ctx-other"
expect_empty "nudge: statusline file for another session is ignored" "$(nudge st3 "$fx/transcript-30pct.jsonl" "$work/proj" UserPromptSubmit)"

mkdir -p "$work/p1m/.claude" "$work/p2/.claude" "$work/p3/.claude" "$HOME/.claude"
printf '{"model":"claude-x[1m]"}\n' > "$work/p1m/.claude/settings.json"
expect_empty "nudge: [1m] model in ./.claude/settings.json means a 1M window" "$(nudge m1 "$big" "$work/p1m" UserPromptSubmit)"
printf '{"model":"claude-x[1m]"}\n' > "$work/p2/.claude/settings.local.json"
printf '{"model":"claude-x"}\n' > "$work/p2/.claude/settings.json"
expect_empty "nudge: settings.local.json outranks settings.json" "$(nudge m2 "$big" "$work/p2" UserPromptSubmit)"
printf '{"model":"claude-x"}\n' > "$work/p3/.claude/settings.local.json"
printf '{"model":"claude-x[1m]"}\n' > "$work/p3/.claude/settings.json"
expect_json "nudge: a plain model in settings.local.json wins over [1m] below it" "$(nudge m3 "$big" "$work/p3" UserPromptSubmit)"
printf '{"model":"claude-x[1m]"}\n' > "$HOME/.claude/settings.json"
expect_empty "nudge: [1m] in ~/.claude/settings.json is the last fallback" "$(nudge m4 "$big" "$work/proj" UserPromptSubmit)"
rm -f "$HOME/.claude/settings.json"

bindir="$work/bin"; mkdir -p "$bindir"
for t in cat grep head sed date; do ln -s "$(command -v "$t")" "$bindir/$t"; done
out=$(hook_in nopy "$big" "$work/proj" UserPromptSubmit | PATH="$bindir" /bin/sh "$nudge"); rc=$?
[ "$rc" -eq 0 ] && [ -z "$out" ] && pass "nudge: no python3 on PATH exits 0 silently" || flunk "nudge: no python3" "rc=$rc out=$out"

# --- handoff-load.sh --------------------------------------------------------
load() { printf '{"session_id":"%s","cwd":"%s","hook_event_name":"SessionStart","source":"startup"}' "$1" "$2" | sh "$loader"; }
repo="$work/repo"; mkdir -p "$repo/.claude/handoffs"
git -C "$repo" init -q && git -C "$repo" symbolic-ref HEAD refs/heads/feat/example
doc="$repo/.claude/handoffs/2026-09-13-1140-feat-example.md"

cp "$fx/handoff-open.md" "$doc"
out=$(load l1 "$repo")
expect_json "load: open handoff on the current branch prints JSON" "$out"
expect_has "load: JSON names the file" "$out" "$doc"
expect_has "load: JSON states open" "$out" "(open, "
expect_has "load: JSON is a SessionStart hookSpecificOutput" "$out" '"hookEventName":"SessionStart"'
case $out in *"## Goal"*|*"Export CSV"*) flunk "load: body must never be printed" "$out" ;; *) pass "load: body is not printed" ;; esac
[ "$(printf '%s\n' "$out" | wc -l)" -le 3 ] && pass "load: output is at most 3 lines" || flunk "load: too many lines" "$out"

sed 's/^status: open$/status: active/' "$fx/handoff-open.md" > "$doc"
expect_has "load: active handoff is reported as active" "$(load l2 "$repo")" "(active, "

cp "$fx/handoff-done.md" "$doc"
expect_empty "load: status: done is silent" "$(load l3 "$repo")"

cp "$fx/handoff-open.md" "$doc"
stamp=$(date -v-8d +%Y%m%d%H%M 2>/dev/null || date -d '8 days ago' +%Y%m%d%H%M)
touch -t "$stamp" "$doc"
expect_empty "load: 8-day-old open handoff is silent" "$(load l4 "$repo")"
touch "$doc"

git -C "$repo" symbolic-ref HEAD refs/heads/other-branch
expect_empty "load: open handoff for another branch is silent" "$(load l5 "$repo")"
git -C "$repo" symbolic-ref HEAD refs/heads/feat/example

cp "$fx/handoff-open.md" "$repo/.claude/handoffs/2026-09-14-0900-feat-example.md"
expect_has "load: newest of two open handoffs wins" "$(load l6 "$repo")" "2026-09-14-0900-feat-example.md"
rm -f "$repo/.claude/handoffs/2026-09-14-0900-feat-example.md"

mkdir -p "$work/plain"
out=$(load l7 "$work/plain"); rc=$?
[ "$rc" -eq 0 ] && [ -z "$out" ] && pass "load: outside a git repo exits 0 silently" || flunk "load: non-git" "rc=$rc out=$out"
out=$(printf 'garbage' | sh "$loader"); rc=$?
[ "$rc" -eq 0 ] && [ -z "$out" ] && pass "load: malformed stdin exits 0 silently" || flunk "load: malformed stdin" "rc=$rc out=$out"

echo
[ "$fail" -eq 0 ] && echo "hooks: all cases passed" || echo "hooks: FAILURES above"
exit "$fail"
