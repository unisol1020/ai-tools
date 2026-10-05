#!/usr/bin/env bash
# SessionStart hook — nudge Claude to run /bootstrap when this project has not
# been bootstrapped yet. Bootstrapped projects are recorded (one absolute path
# per line) in ~/.claude/.bootstrapped-projects; /bootstrap appends to it on
# completion, so the nudge stops firing once a repo is set up.
#
# A hook cannot *force* a slash command — it injects this instruction via
# SessionStart additionalContext; Claude then acts on it.

reg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.bootstrapped-projects"

# Resolve the project root: CLAUDE_PROJECT_DIR, else .cwd from stdin JSON, else $PWD.
d="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$d" ]; then
  input="$(cat 2>/dev/null)"
  d="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
fi
[ -z "$d" ] && d="$PWD"

# Only act in real code projects — never nag in $HOME or scratch dirs.
is_project=0
[ -d "$d/.git" ] && is_project=1
for f in package.json Cargo.toml go.mod pyproject.toml pom.xml build.gradle Gemfile composer.json deno.json; do
  [ -f "$d/$f" ] && is_project=1
done
[ "$is_project" -eq 0 ] && exit 0

# Already bootstrapped? (exact line match)
if [ -f "$reg" ] && grep -qxF "$d" "$reg" 2>/dev/null; then
  exit 0
fi

# Not bootstrapped → inject the instruction.
msg="This project is NOT yet bootstrapped (absent from ~/.claude/.bootstrapped-projects). Before other work, run the /bootstrap flow for this repo: install/verify the required extensions (jq, ripgrep, ast-grep, CodeGraph + its MCP, graphify, MemPalace + its MCP and hooks, the ponytail plugin) via the bundled setup script, build the CodeGraph index (ask before indexing a large repo), offer to run /graphify, create or augment CLAUDE.md, then append \"$d\" as a new line to ~/.claude/.bootstrapped-projects (create the file if missing, no duplicates). If the user gave an urgent task, ask whether to bootstrap first or proceed; if they decline, skip and do not re-offer this session."
jq -cn --arg c "$msg" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$c}}'
