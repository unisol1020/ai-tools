tool_used Agent '"subagent_type"\s*:\s*"(backend|frontend)-investigator"'
cite='[A-Za-z0-9_./-]+\.(ts|tsx|sql|json):[0-9]+'
if ere "$cite" < "$REPLY" || grep -rEq "$cite" "$WORK/.claude/tasks" "$WORK/docs/plans" 2>/dev/null; then
  pass "reply or plan file cites path:line"
else
  fail "reply or plan file cites path:line"
fi
brief=$(find "$WORK/.claude/tasks" "$WORK/docs/plans" -name plan-brief.html 2>/dev/null | head -n 1)
if [ -n "$brief" ] && find "$(dirname "$brief")" -maxdepth 1 -name '*.md' | grep -q .; then
  pass "plan-brief.html beside the plan"
  page=$(tr -d '\n' < "$brief")
  if printf '%s' "$page" | grep -q 'var(--foreground'; then pass "brief uses T3 theme vars"; else fail "brief uses T3 theme vars"; fi
  if printf '%s' "$page" | grep -q "http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'"; then pass "brief keeps the skeleton CSP"; else fail "brief keeps the skeleton CSP"; fi
  if printf '%s' "$page" | grep -Eq '[0-9.][dls]?vh([^a-z-]|$)'; then fail "brief has no vh units"; else pass "brief has no vh units"; fi
  if printf '%s' "$page" | grep -Eq '(^|[^.#[:alnum:]_-])(html|body)[[:space:]]*(,[[:space:]]*(html|body)[[:space:]]*)*\{[^}]*(background|height:[[:space:]]*100%)'; then fail "brief styles no bare html/body background"; else pass "brief styles no bare html/body background"; fi
else
  fail "plan-brief.html beside the plan"
fi
