# Paste into ~/.claude/statusline.sh right after the block that finalises `pct`
# (before `if [ -n "$pct" ]`). Needs `$input` (the statusline JSON) and `$pct`.
# (~/.claude/statusline.py from this kit already does this; skip the snippet there.)
sid=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
size=$(printf '%s' "$input" | jq -r '.context_window.context_window_size // empty' 2>/dev/null)
case $sid in
  ''|*[!A-Za-z0-9._-]*) ;;
  *) t=${TMPDIR:-/tmp}; f="${t%/}/ai-tools-ctx-$sid"
     printf '%s %s %s\n' "$(date +%s)" "${pct:--1}" "$size" > "$f.$$" 2>/dev/null && mv -f "$f.$$" "$f" 2>/dev/null ;;
esac
# Optional, inside the `pct -ge 50` branch:  segs+=("${C_CTX}${pct}% → /handoff${R}")
