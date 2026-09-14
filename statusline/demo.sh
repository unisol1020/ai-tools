#!/usr/bin/env bash
# Preview every state the status line can render — and assert it never dies.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SL="$DIR/statusline.py"
NOW=$(date +%s)

show() { printf '\n\033[2m── %s ──\033[0m\n' "$1"; printf '%s' "$2" | COLORTERM=truecolor SL_WIDTH="${SL_WIDTH:-110}" python3 "$SL"; printf '\n'; }

BASE='"model":{"id":"claude-opus-5","display_name":"Opus 5"},"workspace":{"current_dir":"'"$PWD"'"},"effort":{"level":"xhigh"},"thinking":{"enabled":true}'
show "fresh session"      "{$BASE,\"context_window\":{\"used_percentage\":0,\"context_window_size\":1000000},\"cost\":{\"total_cost_usd\":0,\"total_duration_ms\":0}}"
show "mid-session"        "{$BASE,\"context_window\":{\"used_percentage\":63,\"context_window_size\":1000000,\"total_input_tokens\":155000,\"total_output_tokens\":12000},\"cost\":{\"total_duration_ms\":1843000,\"total_api_duration_ms\":412000,\"total_lines_added\":312,\"total_lines_removed\":87},\"prompt_cache\":{\"warm\":true,\"hit_ratio\":0.93,\"ttl\":\"1h\",\"expires_at\":$((NOW+2400))},\"pr\":{\"number\":42,\"review_state\":\"pending\"}}"
show "context nearly full" "{$BASE,\"context_window\":{\"used_percentage\":94,\"context_window_size\":1000000},\"cost\":{\"total_duration_ms\":5400000,\"total_api_duration_ms\":1900000},\"prompt_cache\":{\"warm\":false,\"hit_ratio\":0.41}}"
show "subagent"          "{$BASE,\"context_window\":{\"used_percentage\":38,\"context_window_size\":200000},\"agent\":{\"name\":\"security-reviewer\"}}"
show "worktree"          "{$BASE,\"context_window\":{\"used_percentage\":38,\"context_window_size\":1000000},\"worktree\":{\"name\":\"feat-login\",\"branch\":\"worktree-feat-login\"}}"
show "narrow (80 cols)"  "{$BASE,\"context_window\":{\"used_percentage\":63,\"context_window_size\":1000000}}" 

printf '\n\033[2m── self-check ──\033[0m\n'
fail=0
for bad in '' '{' 'null' '[]' '"s"' '{"context_window":{"used_percentage":null}}' '{"cost":{"total_duration_ms":-5}}'; do
  out=$(printf '%s' "$bad" | python3 "$SL" 2>&1); rc=$?
  if [ $rc -ne 0 ] || printf '%s' "$out" | grep -q Traceback; then
    echo "  FAIL on input: ${bad:-<empty>}"; fail=1
  fi
done
out=$(cat /dev/null | PYTHONIOENCODING=ascii python3 "$SL" 2>&1) || fail=1
printf '%s' "$out" | grep -q Traceback && { echo "  FAIL on non-UTF-8 stdout"; fail=1; }
[ $fail -eq 0 ] && echo "  ok — survives empty, malformed, null and non-UTF-8 output"
exit $fail
