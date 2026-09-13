#!/usr/bin/env bash
# SessionStart hook: inject MemPalace wake-up context into the session.
#
# MemPalace's own session-start hook only initialises tracking state and always
# returns {} — it injects nothing, because MemPalace expects the model to pull
# memory on demand through MCP tools. claude-mem instead pushed context in at
# session start. This wrapper restores that behaviour: it still runs MemPalace's
# real hook (so session state is tracked), then appends `mempalace wake-up`
# (~800 tokens of L0/L1 context) as additionalContext.
set -uo pipefail

MP="$HOME/.local/bin/mempalace"
command -v mempalace >/dev/null 2>&1 && MP="$(command -v mempalace)"
[ -x "$MP" ] || { printf '{}\n'; exit 0; }

INPUT="$(cat 2>/dev/null || true)"
printf '%s' "$INPUT" | "$MP" hook run --hook session-start --harness claude-code >/dev/null 2>&1 || true

CTX="$("$MP" wake-up 2>/dev/null || true)"
[ -z "${CTX// }" ] && { printf '{}\n'; exit 0; }

MEMPALACE_CTX="$CTX" python3 -c '
import json, os
ctx = os.environ.get("MEMPALACE_CTX", "").strip()
if not ctx:
    print("{}"); raise SystemExit
print(json.dumps({"hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "# MemPalace memory (recalled automatically)\n\n"
                         + ctx
                         + "\n\nSearch deeper with the mempalace_search MCP tool when this is not enough.",
}}))
' 2>/dev/null || printf '{}\n'
