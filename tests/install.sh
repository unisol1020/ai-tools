#!/bin/sh
# Runs every */install.sh against a throwaway HOME: install twice, then each --uninstall.
# `claude`, `codegraph`, `graphify` and `npx` are shimmed to no-ops, so nothing real runs.
set -u

REPO=$(cd "$(dirname "$0")/.." && pwd -P)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/ai-tools-install.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
H="$TMP/home"; C="$H/.claude"; S="$C/settings.json"; MD="$C/CLAUDE.md"; SHIM="$TMP/shim"
fail=0

ok()   { name=$1; shift; if "$@" >/dev/null 2>&1; then echo "PASS  $name"; else echo "FAIL  $name"; fail=1; fi; }
skip() { echo "SKIP  $1"; }
links_to() { [ -L "$1" ] && [ "$(readlink "$1")" = "$2" ]; }
hook_count() { jq -r --arg s "$1" '[.hooks[]?[]?.hooks[]?.command // ""] | map(select(contains($s))) | length' "$S" 2>/dev/null; }
run_installer() { HOME="$H" CLAUDE_CONFIG_DIR="$C" GIT_CONFIG_GLOBAL="$TMP/gitconfig" PATH="$SHIM:$PATH" bash "$@"; }
install_all() {
  rc=0
  for f in "$REPO"/*/install.sh; do
    t=$(basename "$(dirname "$f")")
    [ "$t" = tests ] && continue
    if run_installer "$f" > "$TMP/log-$t.txt" 2>&1; then echo "PASS  $t/install.sh exits 0 ($1 run)"
    else echo "FAIL  $t/install.sh exits 0 ($1 run)"; sed 's/^/        /' "$TMP/log-$t.txt" | tail -n 15; rc=1; fi
  done
  return $rc
}
has_uninstall() { [ -f "$REPO/$1/install.sh" ] && grep -q -- '--uninstall' "$REPO/$1/install.sh"; }

mkdir -p "$SHIM" "$C"
for c in claude codegraph graphify npx; do printf '#!/bin/sh\nexit 0\n' > "$SHIM/$c"; chmod +x "$SHIM/$c"; done
printf '{\n  "model": "sonnet",\n  "hooks": {"Stop": [{"hooks": [{"type": "command", "command": "echo keep-me"}]}]}\n}\n' > "$S"

install_all first || fail=1

ok "settings.json parses" jq . "$S"
ok "foreign Stop hook survives install" test "$(hook_count 'echo keep-me')" = 1
ok "model setting survives install" test "$(jq -r .model "$S")" = sonnet

n=0; bad=""
for a in "$REPO"/team/agents/*.md; do
  n=$((n + 1)); links_to "$C/agents/$(basename "$a")" "$a" || bad="$bad $(basename "$a")"
done
ok "team: all $n agents symlinked into the repo${bad:+ (missing:$bad)}" test -z "$bad"
ok "qa: manual-qa agent symlinked" links_to "$C/agents/manual-qa.md" "$REPO/qa/agents/manual-qa.md"
ok "memory: memory-curator agent symlinked" links_to "$C/agents/memory-curator.md" "$REPO/memory/agents/memory-curator.md"

for s in bootstrap/skills/bootstrap qa/skills/qa-run qa/skills/playwright-qa tickets/skills/ticket \
         morning/skills/morning morning/skills/review-prs memory/skills/evolve worktree-graphs/skills/worktree-graphs; do
  ok "skill $(basename "$s") symlinked" links_to "$C/skills/$(basename "$s")" "$REPO/$s"
done
if [ -d "$REPO/handoff/skills/handoff" ]; then ok "skill handoff symlinked" links_to "$C/skills/handoff" "$REPO/handoff/skills/handoff"
else skip "skill handoff symlinked (handoff/ not in repo)"; fi

for b in worktree-graphs/bin/graphs memory/bin/agent-memory team/bin/crew-cost; do
  ok "bin $(basename "$b") symlinked into ~/.claude/bin" links_to "$C/bin/$(basename "$b")" "$REPO/$b"
  ok "bin $(basename "$b") symlinked into ~/.local/bin" links_to "$H/.local/bin/$(basename "$b")" "$REPO/$b"
done
ok "hook bootstrap-check.sh symlinked" links_to "$C/hooks/bootstrap-check.sh" "$REPO/bootstrap/hooks/bootstrap-check.sh"
for h in "$REPO"/handoff/hooks/*.sh; do
  [ -e "$h" ] || { skip "handoff hooks symlinked (handoff/ not in repo)"; break; }
  ok "hook $(basename "$h") symlinked" links_to "$C/hooks/$(basename "$h")" "$h"
done

ok "bootstrap-check hook wired once" test "$(hook_count 'bootstrap-check.sh')" = 1
ok "graphs ensure hook wired once with matcher startup|resume" \
  test "$(hook_count 'ensure >/dev/null')" = 1 -a "$(jq -r '[.hooks.SessionStart[]? | select(any(.hooks[]?; (.command // "") | contains("graphs"))) | .matcher] | .[0]' "$S")" = 'startup|resume'
ok "graphs ensure replaces bootstrap's unlocked codegraph sync" test "$(hook_count '" sync')" = 0
for ev in session-start subagent-start subagent-stop; do
  ok "agent-memory $ev hook wired once" test "$(hook_count "agent-memory\" $ev")" = 1
done
ok "dispatch block appears once in CLAUDE.md" test "$(grep -c 'ai-tools:dispatch:start' "$MD")" = 1
ok "global git excludes gained the project-tier line" grep -qxF '.claude/agent-memory-local/' "$H/.gitignore_global"
ok "real ~/.gitconfig untouched" test ! -e "$H/.gitconfig"

cp "$S" "$TMP/after-first.json"; cp "$MD" "$TMP/after-first.md"
install_all second || fail=1
ok "second run leaves settings.json byte-identical" cmp -s "$S" "$TMP/after-first.json"
ok "second run leaves CLAUDE.md byte-identical" cmp -s "$MD" "$TMP/after-first.md"
ok "second run reports the memory hooks already present" test "$(grep -c 'already present' "$TMP/log-memory.txt")" = 3
ok "second run reports the graphs hook already present" grep -q 'already present' "$TMP/log-worktree-graphs.txt"

for t in memory handoff team; do
  if ! has_uninstall "$t"; then
    [ -f "$REPO/$t/install.sh" ] && skip "$t/install.sh --uninstall (no such flag)" || skip "$t/install.sh --uninstall (not in repo)"
    continue
  fi
  if run_installer "$REPO/$t/install.sh" --uninstall > "$TMP/log-$t-uninstall.txt" 2>&1; then echo "PASS  $t/install.sh --uninstall exits 0"
  else echo "FAIL  $t/install.sh --uninstall exits 0"; sed 's/^/        /' "$TMP/log-$t-uninstall.txt" | tail -n 15; fail=1; fi
  ok "$t uninstall keeps the foreign Stop hook" test "$(hook_count 'echo keep-me')" = 1
  ok "$t uninstall leaves settings.json parseable" jq . "$S"
done
if has_uninstall memory; then
  ok "memory uninstall removes its hooks" test "$(hook_count 'agent-memory')" = 0
  ok "memory uninstall removes its symlinks" test ! -L "$C/bin/agent-memory" -a ! -L "$C/agents/memory-curator.md" -a ! -L "$C/skills/evolve"
  ok "memory uninstall keeps the graphs hook" test "$(hook_count 'ensure >/dev/null')" = 1
fi
if has_uninstall team; then
  ok "team uninstall removes its symlinks" test ! -L "$C/agents/architect.md" -a ! -L "$C/bin/crew-cost" -a ! -L "$H/.local/bin/crew-cost"
  ok "team uninstall keeps manual-qa" test -L "$C/agents/manual-qa.md"
  ok "team uninstall strips the dispatch block" test "$(grep -c 'ai-tools:dispatch' "$MD")" = 0
fi
if has_uninstall handoff; then
  ok "handoff uninstall removes its hooks" test "$(hook_count 'handoff')" = 0
  ok "handoff uninstall keeps the graphs hook" test "$(hook_count 'ensure >/dev/null')" = 1
fi

exit $fail
