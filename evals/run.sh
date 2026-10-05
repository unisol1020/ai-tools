#!/bin/sh
# Live behavioural evals: one `claude -p` per case in a scratch git repo, then that case's assert.sh
# against the reply and the session transcript. Spends tokens; run by hand, never in CI.
#
#   evals/run.sh [--yes] [case ...]        default: every case; --yes skips the cost pause
#
# Env: AI_TOOLS_EVAL_DIR (scratch root, default mktemp), MODEL (default claude-sonnet-5, a case.env can
# override it). HOME is never overridden: cases exercise the INSTALLED stack under ~/.claude.
set -u

KIT=$(cd "$(dirname "$0")/.." && pwd -P)
EVALS="$KIT/evals"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
yes=0; cases=""
for a in "$@"; do
  case $a in
    --yes|-y) yes=1;;
    -h|--help) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) cases="$cases ${a%/}";;
  esac
done
[ -n "$cases" ] || cases=$(cd "$EVALS" && for d in */; do [ -f "$d/assert.sh" ] && printf '%s ' "${d%/}"; done)

command -v claude >/dev/null 2>&1 || { echo "evals: claude CLI not on PATH" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "evals: jq not on PATH" >&2; exit 2; }

if [ $yes -eq 0 ]; then
  echo "Each case runs the live model (Sonnet by default) and spends tokens: $cases"
  echo "Starting in 3 seconds; ctrl-c to abort, --yes to skip this pause."
  sleep 3
fi

ROOT="${AI_TOOLS_EVAL_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/ai-tools-evals.XXXXXX")}"
mkdir -p "$ROOT" "$EVALS/results"
LOG="$EVALS/results/$(date +%Y-%m-%d).log"
echo "Scratch root: $ROOT"
echo "Results log:  $LOG"

PASSES=0; FAILS=0
pass() { PASSES=$((PASSES + 1)); printf 'PASS  %s\n' "$*"; }
fail() { FAILS=$((FAILS + 1)); printf 'FAIL  %s\n' "$*"; }
ere() {  # grep -E with a leading (?i) honoured as -i, so a case can write PCRE-style patterns
  case $1 in '(?i)'*) grep -Eiq -- "${1#"(?i)"}";; *) grep -Eq -- "$1";; esac
}
tool_inputs() {  # every tool_use input of tool $1, compact JSON one per line, main transcript + every subagent depth
  for f in "$TRANSCRIPT" $([ -d "$SUBAGENTS" ] && find "$SUBAGENTS" -name '*.jsonl'); do
    [ -f "$f" ] || continue
    jq -R -c --arg t "$1" 'fromjson? | select(.type == "assistant") | .message.content[]?
      | select(type == "object" and .type == "tool_use" and .name == $t) | .input' "$f" 2>/dev/null
  done
}
tool_matches() { tool_inputs "$1" | ere "$2"; }
tool_used()     { if tool_matches "$1" "$2"; then pass "tool_used $1 $2"; else fail "tool_used $1 $2"; fi; }
tool_not_used() { if tool_matches "$1" "$2"; then fail "tool_not_used $1 $2"; else pass "tool_not_used $1 $2"; fi; }
assistant_text() {  # every assistant text block, main transcript + every subagent depth: what an agent actually said
  for f in "$TRANSCRIPT" $([ -d "$SUBAGENTS" ] && find "$SUBAGENTS" -name '*.jsonl'); do
    [ -f "$f" ] || continue
    jq -R -r 'fromjson? | select(.type == "assistant") | .message.content[]?
      | select(type == "object" and .type == "text") | .text' "$f" 2>/dev/null
  done
}
# A subagent's report can reach the user summarised; assert against what the agent said, not only the final reply.
said_has() { if assistant_text | ere "$1"; then pass "said_has $1"; else fail "said_has $1"; fi; }
reply_has()   { if ere "$1" < "$REPLY"; then pass "reply_has $1"; else fail "reply_has $1"; fi; }
reply_lacks() { if ere "$1" < "$REPLY"; then fail "reply_lacks $1"; else pass "reply_lacks $1"; fi; }
file_exists() {
  f=$(cd "$WORK" 2>/dev/null && ls -1d $1 2>/dev/null | head -n 1)
  if [ -n "$f" ]; then pass "file_exists $1 ($f)"; else fail "file_exists $1"; fi
}
file_has() {
  if [ -n "$1" ] && [ -f "$WORK/$1" ] && ere "$2" < "$WORK/$1"; then pass "file_has $1 $2"; else fail "file_has ${1:-<none>} $2"; fi
}

scratch_repo() {
  rm -rf "$1"; mkdir -p "$1"
  [ -d "$2" ] && cp -R "$2/." "$1/"
  git -C "$1" init -q -b main 2>/dev/null || { git -C "$1" init -q && git -C "$1" checkout -q -b main; }
  [ -e "$1/README.md" ] || echo "# eval fixture" > "$1/README.md"
  git -C "$1" add -A && git -C "$1" -c user.name=evals -c user.email=evals@example.com commit -qm "fixture" || return 1
}
forget_repo() {  # the memory session-start hook registers every repo it sees; a scratch one must not linger
  reg="$CLAUDE_DIR/agent-memory/.registry"
  [ -f "$reg" ] || return 0
  { grep -vxF "$1" "$reg" || :; } > "$reg.tmp" && mv "$reg.tmp" "$reg"
}
run_claude() {  # $1 work dir, $2 prompt file; exec so the watchdog's kill reaches claude itself
  ( cd "$1" && exec env -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT \
      claude -p --model "$MODEL" --max-turns "$MAX_TURNS" --output-format text --allowedTools "$ALLOWED_TOOLS" ) \
    < "$2" > "$1/reply.txt" 2> "$1/stderr.txt" &
  pid=$!
  ( sleep "$TIMEOUT_SECONDS"; kill "$pid" 2>/dev/null ) & wd=$!
  wait "$pid"; rc=$?
  pkill -P "$wd" 2>/dev/null; kill "$wd" 2>/dev/null; wait "$wd" 2>/dev/null
  return $rc
}
find_transcript() {  # newest *.jsonl under ~/.claude/projects/<cwd with every / replaced by ->
  d="$CLAUDE_DIR/projects/$(printf '%s' "$1" | tr / -)"
  [ -d "$d" ] || return 1
  ls -t "$d"/*.jsonl 2>/dev/null | head -n 1
}

run_one() {  # $1 case, $2 prompt file or "", $3 sub-run label or ""
  CASE=$1; SUB=$3
  WORK="$ROOT/$CASE${SUB:+/$SUB}"
  MODEL=${MODEL:-claude-sonnet-5}; MAX_TURNS=20; TIMEOUT_SECONDS=900
  ALLOWED_TOOLS="Agent,Task,Read,Glob,Grep,Skill,Bash,Write,Edit"
  [ -f "$EVALS/$CASE/case.env" ] && . "$EVALS/$CASE/case.env"
  label="$CASE${SUB:+/$SUB}"
  echo; echo "== $label"
  scratch_repo "$WORK" "$EVALS/$CASE/fixtures" || { echo "evals: could not create $WORK" >&2; return 1; }
  WORK=$(cd "$WORK" && pwd -P)
  REPLY="$WORK/reply.txt"; TRANSCRIPT=""; SUBAGENTS=""
  : > "$REPLY"
  if [ -n "$2" ]; then
    echo "   claude -p ($MODEL, max $MAX_TURNS turns, ${TIMEOUT_SECONDS}s) in $WORK"
    run_claude "$WORK" "$2"; rc=$?
    echo "   claude exited $rc; reply: $REPLY"
    TRANSCRIPT=$(find_transcript "$WORK") || echo "   no transcript found under $CLAUDE_DIR/projects for $WORK"
    [ -n "$TRANSCRIPT" ] && { SUBAGENTS="${TRANSCRIPT%.jsonl}/subagents"; echo "   transcript: $TRANSCRIPT"; }
    forget_repo "$WORK"
  fi
  export KIT CASE SUB WORK REPLY TRANSCRIPT SUBAGENTS
  before_p=$PASSES; before_f=$FAILS
  . "$EVALS/$CASE/assert.sh"
  p=$((PASSES - before_p)); f=$((FAILS - before_f))
  [ $f -eq 0 ] && verdict=PASS || verdict=FAIL
  echo "-- $label: $verdict ($p passed, $f failed)"
  printf '%s  %-40s %s  passed=%s failed=%s  work=%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$label" "$verdict" "$p" "$f" "$WORK" >> "$LOG"
  [ $f -eq 0 ]
}

any_fail=0
for c in $cases; do
  dir="$EVALS/$c"
  [ -f "$dir/assert.sh" ] || { echo "evals: no such case $c (needs evals/$c/assert.sh)" >&2; any_fail=1; continue; }
  if [ -f "$dir/prompt.md" ]; then
    (run_one "$c" "$dir/prompt.md" "") || any_fail=1
  elif ls "$dir"/prompt-*.md >/dev/null 2>&1; then
    for p in "$dir"/prompt-*.md; do
      sub=$(basename "$p" .md); sub=${sub#prompt-}
      (run_one "$c" "$p" "$sub") || any_fail=1
    done
  else
    (run_one "$c" "" "") || any_fail=1
  fi
done

echo
[ "$any_fail" -eq 0 ] && echo "all cases passed" || echo "some cases FAILED (see $LOG)"
exit "$any_fail"
