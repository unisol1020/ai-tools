if AGENT_MEMORY_SMOKE_DIR="$WORK/smoke" bash "$KIT/memory/tests/smoke.sh"; then
  pass "memory/tests/smoke.sh"
else
  fail "memory/tests/smoke.sh (transcript under $WORK/smoke)"
fi
