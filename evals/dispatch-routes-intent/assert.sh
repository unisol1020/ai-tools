case $SUB in
  a)
    if tool_matches Skill '"skill"\s*:\s*"qa-run"' || tool_matches Agent '"subagent_type"\s*:\s*"manual-qa"'; then
      pass "tool_used Skill qa-run OR Agent manual-qa"
    else
      fail "tool_used Skill qa-run OR Agent manual-qa"
    fi ;;
  b) tool_used Agent '"subagent_type"\s*:\s*"backend-engineer"' ;;
  c) tool_used Agent '"subagent_type"\s*:\s*"frontend-engineer"' ;;
  *) fail "unknown sub-run '$SUB'" ;;
esac
