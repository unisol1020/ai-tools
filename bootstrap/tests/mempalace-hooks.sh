#!/bin/sh
# Repo resolution for MemPalace wings, and hook wiring idempotence. Needs git, python3, jq; not mempalace.
set -u
REPO=$(cd "$(dirname "$0")/../.." && pwd -P)
SK="$REPO/bootstrap/skills/bootstrap"
# Fixtures live outside /tmp: temp dirs deliberately resolve to no project.
TMP=$(mkdir -p "$REPO/.test-tmp" && cd "$(mktemp -d "$REPO/.test-tmp/mp-hooks.XXXXXX")" && pwd -P); trap 'rm -rf "$TMP"; rmdir "$REPO/.test-tmp" 2>/dev/null' EXIT
fail=0
ok() { name=$1; shift; if "$@" >/dev/null 2>&1; then echo "PASS  $name"; else echo "FAIL  $name"; fail=1; fi; }

git init -q "$TMP/code/acme-app" && git -C "$TMP/code/acme-app" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
git -C "$TMP/code/acme-app" worktree add -q "$TMP/wt/acme-app/feature-x" 2>/dev/null
mkdir -p "$TMP/code/acme-app/src"
git init -q --bare "$TMP/code/widget/.bare" && git -C "$TMP/code/widget/.bare" -c user.email=t@t -c user.name=t worktree add -q --orphan -b main "$TMP/code/widget/main" 2>/dev/null \
  || { git clone -q "$TMP/code/acme-app" "$TMP/seed" && git -C "$TMP/seed" push -q "$TMP/code/widget/.bare" HEAD:main && git -C "$TMP/code/widget/.bare" worktree add -q "$TMP/code/widget/main" main; }

root() { HOME="$TMP/home" python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import mempalace_hooks as m; print(m.repo_root(sys.argv[2]))' "$SK" "$1"; }
ok "repo root of a subdir"            [ "$(root "$TMP/code/acme-app/src")" = "$TMP/code/acme-app" ]
ok "worktree maps to its main repo"   [ "$(root "$TMP/wt/acme-app/feature-x")" = "$TMP/code/acme-app" ]
ok "bare-repo worktree -> project dir" [ "$(root "$TMP/code/widget/main")" = "$TMP/code/widget" ]
ok "deleted T3 worktree -> repo dir"  [ "$(root "/nowhere/.t3/worktrees/mono/t3-abc")" = "/nowhere/.t3/worktrees/mono" ]
ok "deleted Orca workspace -> repo"   [ "$(root "/nowhere/orca/workspaces/mono/bug-x/apps")" = "/nowhere/orca/workspaces/mono" ]
ok "claude worktree -> project"       [ "$(root "/nowhere/proj/.claude/worktrees/wt1")" = "/nowhere/proj" ]
ok "T3 scratch -> home"               [ "$(root "/nowhere/.t3/scratch/2026-10-19-x")" = "$TMP/home" ]
ok "temp dir -> home"                 [ "$(root "/private/tmp/claude-501/evals/x")" = "$TMP/home" ]

S="$TMP/claude/settings.json"; mkdir -p "$TMP/claude"
cat > "$S" <<'JSON'
{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"[ -x \"$HOME/.local/bin/mempalace\" ] && \"$HOME/.local/bin/mempalace\" hook run --hook stop --harness claude-code || printf '{}\\n'"}]},{"hooks":[{"type":"command","command":"other-stop.sh"}]}],
 "SessionStart":[{"matcher":"startup","hooks":[{"type":"command","command":"shared-start.sh"},{"type":"command","command":"bash mempalace-session-start.sh"}]}]}}
JSON
CLAUDE_CONFIG_DIR="$TMP/claude" bash "$SK/mempalace-wire-hooks.sh" >/dev/null
CLAUDE_CONFIG_DIR="$TMP/claude" bash "$SK/mempalace-wire-hooks.sh" >/dev/null
n() { jq --arg e "$1" '[.hooks[$e][]?.hooks[]?.command | select(contains("mempalace"))] | length' "$S"; }
ok "old Stop hook replaced, not duplicated" [ "$(n Stop)" = 1 ]
ok "Stop goes through mempalace-hook.sh"    jq -e '.hooks.Stop | map(.hooks[].command) | any(contains("mempalace-hook.sh\" hook stop"))' "$S"
ok "unrelated Stop hook kept"               jq -e '.hooks.Stop | map(.hooks[].command) | index("other-stop.sh")' "$S"
ok "hook sharing a group with mempalace kept" jq -e '.hooks.SessionStart | map(select(.matcher == "startup") | .hooks[].command) | index("shared-start.sh")' "$S"
for e in SessionStart SessionEnd PreCompact UserPromptSubmit; do ok "$e wired once" [ "$(n $e)" = 1 ]; done

mkdir -p "$TMP/bad" && printf '{bad' > "$TMP/bad/settings.json"
ok "invalid settings.json fails loudly" sh -c '! CLAUDE_CONFIG_DIR="$1" bash "$2"' _ "$TMP/bad" "$SK/mempalace-wire-hooks.sh"
ok "invalid settings.json left as is"   [ "$(cat "$TMP/bad/settings.json")" = '{bad' ]

exit $fail
