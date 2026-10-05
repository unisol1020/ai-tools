# Paste into ~/.claude/statusline.sh right after the block that finalises `pct`
# (before `if [ -n "$pct" ]`). Needs `$input` (the statusline JSON) and `$pct`.
sid=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
case $sid in
  ''|*[!A-Za-z0-9._-]*) ;;
  *) t=${TMPDIR:-/tmp}; [ -n "$pct" ] && printf '%s %s\n' "$(date +%s)" "$pct" > "${t%/}/ai-tools-ctx-$sid" 2>/dev/null ;;
esac
# Optional, inside the `pct -ge 50` branch:  segs+=("${C_CTX}${pct}% → /handoff${R}")
