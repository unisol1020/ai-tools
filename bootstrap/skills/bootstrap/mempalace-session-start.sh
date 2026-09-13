#!/usr/bin/env bash
# SessionStart hook: inject MemPalace wake-up context for the CURRENT project.
#
# Two things MemPalace does not do on its own:
#   1. Its session-start hook injects nothing — it only initialises tracking
#      state and returns {}. Memory is expected to be pulled via MCP tools,
#      whereas claude-mem pushed it in at session start.
#   2. `wake-up` with no --wing returns whatever wing it likes, ignoring cwd.
# This wrapper runs the real hook, resolves the wing from the repo you are in,
# and injects that project's wake-up text.
set -uo pipefail

MP="$HOME/.local/bin/mempalace"
command -v mempalace >/dev/null 2>&1 && MP="$(command -v mempalace)"
[ -x "$MP" ] || { printf '{}\n'; exit 0; }

INPUT="$(cat 2>/dev/null || true)"
printf '%s' "$INPUT" | "$MP" hook run --hook session-start --harness claude-code >/dev/null 2>&1 || true

CWD="$(printf '%s' "$INPUT" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("cwd","") or "")
except Exception: print("")' 2>/dev/null || true)"
[ -z "$CWD" ] && CWD="$PWD"
WING="$(cd "$CWD" 2>/dev/null && basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" 2>/dev/null || true)"

CTX=""
[ -n "$WING" ] && CTX="$("$MP" wake-up --wing "$WING" 2>/dev/null || true)"
# An unknown wing yields an empty/identity-only body; fall back to unscoped.
case "$CTX" in *"ESSENTIAL STORY"*) ;; *) CTX="$("$MP" wake-up 2>/dev/null || true)" ;; esac
[ -z "${CTX// }" ] && { printf '{}\n'; exit 0; }

MEMPALACE_CTX="$CTX" MEMPALACE_WING="${WING:-all}" python3 -c '
import json, os
ctx = os.environ.get("MEMPALACE_CTX", "").strip()
if not ctx:
    print("{}"); raise SystemExit
wing = os.environ.get("MEMPALACE_WING", "all")
print(json.dumps({"hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": f"# MemPalace memory — project: {wing}\n\n"
                         + ctx
                         + "\n\nThis is a summary. Search the full palace with the "
                           "mempalace_search MCP tool before answering about past work.",
}}))
' 2>/dev/null || printf '{}\n'
