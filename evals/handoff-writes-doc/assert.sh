doc=$(cd "$WORK" && ls -1 .claude/handoffs/*.md 2>/dev/null | head -n 1)
file_exists '.claude/handoffs/*.md'
file_has "$doc" '^## Goal'
file_has "$doc" '^## Next steps'
file_has "$doc" '^## Verify'
reply_has '/handoff resume'
