tool_used Agent '"subagent_type"\s*:\s*"(backend|frontend)-investigator"'
cite='[A-Za-z0-9_./-]+\.(ts|tsx|sql|json):[0-9]+'
if ere "$cite" < "$REPLY" || grep -rEq "$cite" "$WORK/.claude/tasks" "$WORK/docs/plans" 2>/dev/null; then
  pass "reply or plan file cites path:line"
else
  fail "reply or plan file cites path:line"
fi
