#!/usr/bin/env bash
# qa-lock.sh — serialize QA across parallel worktree tasks that share ONE test target.
#
# The simple (no-Docker) path: tasks BUILD in parallel, each in its own git
# worktree, but TEST one-at-a-time against a single shared resource — the one
# running dev server / QA port, or the one iOS Simulator. This lock is the arbiter:
# a finished task grabs it, tests, releases; no babysitting parent RPC.
#
# A lock is a DIRECTORY (mkdir is atomic on POSIX). Keyed by RESOURCE, so web tasks
# (shared dev port) and native tasks (shared Simulator) serialize independently and
# can run at the same time. The KEY must identify the physical target (e.g.
# "web-3100" for the qa-port, "sim-<udid>" for the Simulator) — the CALLER passes it;
# every task sharing one target must pass the SAME key or serialization won't happen.
#
# A holder is reclaimed only when it is actually GONE: the runner's pid is recorded and
# `kill -0` decides liveness (same host — these are local tasks), with TTL as an absolute
# backstop on the heartbeat age for a holder that is alive but stuck. A long-but-alive QA
# (cold native build) is NOT stolen — `refresh` (and `wait`'s own polling) heartbeat it.
#
# PID, and why a dead one gets a grace period: an agent harness runs each shell command
# in a THROWAWAY shell, so `--pid $$` records a pid that is dead a second later — the
# holder then looks crashed and two tasks end up driving one Simulator. So: pass the
# LONG-LIVED agent pid (`--pid $PPID` from a Claude Code Bash call = the `claude`
# process), and a dead pid only frees the lock after QA_LOCK_DEAD_GRACE (90s) without a
# heartbeat. A live holder that refreshes is never stolen; a truly crashed one is gone
# in ~90s instead of an hour. Omit --pid and the script infers the caller's parent.
#
# Usage:
#   qa-lock acquire <task-id> --resource <key> [--pid <pid>]  # try ONCE: exit 0 = got it, 1 = busy
#   qa-lock wait    <task-id> --resource <key> [--pid <pid>] [--timeout <s>] [--interval <s>]
#                                                             # BLOCK until acquired: 0 = holding, 3 = still queued
#   qa-lock refresh <task-id> --resource <key>                # heartbeat a long hold so it isn't reclaimed
#   qa-lock release <task-id> --resource <key>                # release only if you hold it
#   qa-lock phase   <task-id> <phase> [note …]                # publish what this task is doing (for the board)
#   qa-lock board   [--follow <s>]                            # every task's phase + the QA lane; --follow blocks until something changes
#   qa-lock status  [--resource <key>]                        # holder + age + liveness + who's waiting (all if omitted)
#   qa-lock whoami  [--resource <key>]                        # current holder(s) ("" if free)
#   qa-lock selfcheck                                          # offline assertions incl. a real concurrency race
#
# `wait` is the one that sleeps — run it in the BACKGROUND from an agent (Claude Code:
# `run_in_background: true`, which re-invokes the agent when it exits) so a queued task
# is woken the moment its turn comes instead of dying in a foreground sleep. `acquire`
# never sleeps, for callers that want to drive their own loop.
#
# Env: PARALLEL_LOCK_DIR (default ~/.cache/parallel-tasks), QA_LOCK_TTL fallback-staleness
# secs (3600), QA_LOCK_GRACE secs before a meta-less (crashed mid-init) lock is reclaimable
# (30), QA_LOCK_DEAD_GRACE secs a dead-pid holder keeps the lock (90).
set -euo pipefail

DIR="${PARALLEL_LOCK_DIR:-$HOME/.cache/parallel-tasks}"
TTL="${QA_LOCK_TTL:-3600}"
GRACE="${QA_LOCK_GRACE:-30}"
DEAD_GRACE="${QA_LOCK_DEAD_GRACE:-90}"
mkdir -p "$DIR"

now()  { date +%s; }
die()  { echo "qa-lock: $*" >&2; exit 2; }
ok_name() { case "$1" in ''|*[!a-z0-9._-]*) return 1;; *) return 0;; esac; }  # no /, no .., safe for paths
lockdir() { echo "$DIR/qa-${1}.lock"; }
waitdir() { echo "$DIR/qa-${1}.waiting"; }
mtime()   { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0; }  # macOS || linux

res_from_args() { local r=""; while [ $# -gt 0 ]; do case "$1" in --resource) r="${2:-}"; shift 2;; *) shift;; esac; done; echo "$r"; }
pid_from_args() { local p=""; while [ $# -gt 0 ]; do case "$1" in --pid) p="${2:-}"; shift 2;; *) shift;; esac; done; echo "$p"; }
opt_from_args() { local k="$1" d="$2" v=""; shift 2; while [ $# -gt 0 ]; do [ "$1" = "$k" ] && { v="${2:-}"; shift 2; continue; }; shift; done; case "$v" in ''|*[!0-9]*) echo "$d";; *) echo "$v";; esac; }
has_res()       { while [ $# -gt 0 ]; do [ "$1" = --resource ] && return 0; shift; done; return 1; }
has_flag()      { local f="$1"; shift; while [ $# -gt 0 ]; do [ "$1" = "$f" ] && return 0; shift; done; return 1; }

# The caller's shell is usually a throwaway one spawned per command, so its parent (the
# long-lived agent/terminal process) is the better default identity. Pass --pid to be sure.
default_pid() { local gp; gp="$(ps -o ppid= -p "$PPID" 2>/dev/null | tr -d ' ')"; case "$gp" in ''|0|*[!0-9]*) echo "$PPID";; *) echo "$gp";; esac; }

alive() { [ -n "${1:-}" ] && kill -0 "$1" 2>/dev/null; }   # is that pid still running on this host?

write_meta() { # <lockdir> <task> <pid> — atomic: write to temp then rename, so meta is never half-present
  local ld="$1" task="$2" pid="$3" tmp="$1/.meta.$$"
  printf '%s\n%s\n%s\n' "$task" "$(now)" "$pid" > "$tmp"
  mv -f "$tmp" "$ld/meta"
}

# is the current holder reclaimable? echoes "steal" | "busy" | "free"
holder_state() { # <lockdir>
  local ld="$1" holder ts pid dirage
  if [ ! -e "$ld/meta" ]; then
    # meta absent: either a winner mid-init (fresh dir -> wait) or a crash before meta (old dir -> reclaim)
    dirage="$(( $(now) - $(mtime "$ld") ))"
    [ "$dirage" -ge "$GRACE" ] && echo steal || echo busy
    return
  fi
  holder="$(sed -n 1p "$ld/meta" 2>/dev/null || echo)"
  ts="$(sed -n 2p "$ld/meta" 2>/dev/null || echo)"
  pid="$(sed -n 3p "$ld/meta" 2>/dev/null || echo)"
  case "$ts" in ''|*[!0-9]*) ts="$(mtime "$ld")";; esac
  local age=$(( $(now) - ts ))
  if [ "$age" -ge "$TTL" ]; then
    echo steal                                       # nothing heartbeat it for TTL: stuck, whatever the pid says
  elif [ -n "$pid" ]; then
    # liveness decides, but a dead pid still gets DEAD_GRACE without a heartbeat, so a
    # mis-recorded (throwaway-shell) pid can't hand one Simulator to two testers at once.
    alive "$pid" && echo busy || { [ "$age" -ge "$DEAD_GRACE" ] && echo steal || echo busy; }
  else
    echo busy                                        # no pid: only the TTL backstop above frees it
  fi
}

holder_of() { sed -n 1p "$(lockdir "$1")/meta" 2>/dev/null || echo; }

acquire() { # <task> <res> <pid>
  local task="$1" res="$2" pid="$3" ld; ld="$(lockdir "$res")"
  if mkdir "$ld" 2>/dev/null; then
    write_meta "$ld" "$task" "$pid"
    rm -f "$(waitdir "$res")/$task" 2>/dev/null || true
    echo "acquired qa-lock[$res] for $task"; return 0
  fi
  local holder; holder="$(sed -n 1p "$ld/meta" 2>/dev/null || echo)"
  [ "$holder" = "$task" ] && { write_meta "$ld" "$task" "$pid"; echo "already holding qa-lock[$res]"; return 0; }
  if [ "$(holder_state "$ld")" = steal ]; then
    # atomic steal: only one racer's rename of THIS dir can succeed; losers hit ENOENT and fall through to busy
    local dead="$ld.dead.$$"
    if mv "$ld" "$dead" 2>/dev/null; then
      rm -rf "$dead"
      if mkdir "$ld" 2>/dev/null; then
        write_meta "$ld" "$task" "$pid"
        rm -f "$(waitdir "$res")/$task" 2>/dev/null || true
        echo "stole dead qa-lock[$res] (was ${holder:-?}) for $task"; return 0
      fi
    fi
  fi
  mkdir -p "$(waitdir "$res")"; printf '%s\n' "$pid" > "$(waitdir "$res")/$task"   # pid so a dead waiter can be pruned
  echo "busy: qa-lock[$res] held by ${holder:-?} — retry"; return 1
}

# BLOCK until the lock is ours. The ONLY sleeping command — run it in the background from
# an agent so a queued task is re-woken the moment its turn comes. 0 = holding, 3 = timed out.
wait_lock() { # <task> <res> <pid> <timeout> <interval>
  local task="$1" res="$2" pid="$3" timeout="$4" iv="$5" start ela out
  start="$(now)"
  while :; do
    if out="$(acquire "$task" "$res" "$pid")"; then
      ela=$(( $(now) - start ))
      phase_write "$task" qa "holding qa-lock[$res] (waited ${ela}s)"
      echo "$out${ela:+ after ${ela}s}"; return 0
    fi
    ela=$(( $(now) - start ))
    if [ "$ela" -ge "$timeout" ]; then
      phase_write "$task" qa-wait "queued ${ela}s for [$res] behind $(holder_of "$res") — re-run qa-lock wait"
      echo "still queued for qa-lock[$res] after ${ela}s — holder: $(holder_of "$res"). NOT done: run wait again."
      return 3
    fi
    phase_write "$task" qa-wait "queued ${ela}s for [$res] behind $(holder_of "$res")"
    echo "⏳ ${ela}s waiting for qa-lock[$res] — holder: $(holder_of "$res")"
    sleep "$iv"
  done
}

refresh() { # <task> <res>
  local task="$1" res="$2" ld holder; ld="$(lockdir "$res")"
  holder="$(sed -n 1p "$ld/meta" 2>/dev/null || echo)"
  [ "$holder" = "$task" ] || { echo "qa-lock[$res] not held by $task — nothing to refresh" >&2; return 1; }
  write_meta "$ld" "$task" "$(sed -n 3p "$ld/meta" 2>/dev/null || echo)"
  echo "refreshed qa-lock[$res] for $task"
}

release() { # <task> <res>
  local task="$1" res="$2" ld holder; ld="$(lockdir "$res")"
  holder="$(sed -n 1p "$ld/meta" 2>/dev/null || echo)"
  rm -f "$(waitdir "$res")/$task" 2>/dev/null || true
  [ -z "$holder" ] && { echo "qa-lock[$res] already free"; return 0; }
  [ "$holder" != "$task" ] && { echo "qa-lock[$res] held by $holder, not $task — NOT releasing" >&2; return 1; }
  rm -rf "$ld"
  # keep the board honest even if the runner forgets to report its next phase
  [ -e "$DIR/$task/STATUS" ] && case "$(sed -n 1p "$DIR/$task/STATUS")" in
    qa|qa-wait) phase_write "$task" post-qa "released qa-lock[$res]";;
  esac
  echo "released qa-lock[$res] for $task"
}

status() { # <res|"">   empty => all resources
  local only="$1" any=0 ld r holder ts pid wd w wpid live
  shopt -s nullglob
  for ld in "$DIR"/qa-*.lock; do
    [ -d "$ld" ] || continue
    r="$(basename "$ld" | sed 's/^qa-//; s/\.lock$//')"
    [ -n "$only" ] && [ "$r" != "$only" ] && continue
    any=1
    holder="$(sed -n 1p "$ld/meta" 2>/dev/null || echo)"
    ts="$(sed -n 2p "$ld/meta" 2>/dev/null || echo)"; case "$ts" in ''|*[!0-9]*) ts="$(mtime "$ld")";; esac
    pid="$(sed -n 3p "$ld/meta" 2>/dev/null || echo)"
    live=$(alive "$pid" && echo alive || echo "dead?")
    echo "🔒 [$r] testing: ${holder:-?}  ($(( $(now) - ts ))s, $live)"
    wd="$(waitdir "$r")"
    for w in "$wd"/*; do
      [ -e "$w" ] || continue
      [ "$(basename "$w")" = "$holder" ] && continue   # don't list the holder as also waiting
      wpid="$(sed -n 1p "$w" 2>/dev/null || echo)"
      alive "$wpid" || { rm -f "$w"; continue; }        # prune a waiter that died in the queue
      echo "   ⏳ waiting: $(basename "$w")"
    done
  done
  # `if`, not `[ … ] && echo`: that trailing test made `status` exit 1 whenever a lock WAS
  # held, killing any caller that chains on it under `set -e`.
  if [ "$any" = 0 ]; then echo "no QA in progress${only:+ for [$only]} (free)"; fi
}

# --- task board: what every task is doing, for the coordinator ---------------------

phase_write() { # <task> <phase> [note …]
  local task="$1" ph="$2"; shift 2 2>/dev/null || true
  ok_name "$task" || return 0
  mkdir -p "$DIR/$task"
  printf '%s\n%s\n%s\n' "$ph" "$(now)" "${*:-}" > "$DIR/$task/.status.$$"
  mv -f "$DIR/$task/.status.$$" "$DIR/$task/STATUS"
  printf '%s  %-10s %s\n' "$(date +%H:%M:%S)" "$ph" "${*:-}" >> "$DIR/$task/LOG"
}

phase_icon() { case "$1" in qa) echo 🔒;; qa-wait) echo ⏳;; done) echo ✅;; blocked|failed) echo 🛑;; *) echo "•";; esac; }

board() {
  local s ph ts note task n=0
  shopt -s nullglob
  for s in "$DIR"/*/STATUS; do
    task="$(basename "$(dirname "$s")")"
    ph="$(sed -n 1p "$s" 2>/dev/null || echo ?)"
    ts="$(sed -n 2p "$s" 2>/dev/null || echo)"; case "$ts" in ''|*[!0-9]*) ts="$(mtime "$s")";; esac
    note="$(sed -n 3p "$s" 2>/dev/null || echo)"
    n=$((n+1))
    printf '  %s %-14s %-9s %4sm  %s\n' "$(phase_icon "$ph")" "$task" "$ph" "$(( ( $(now) - ts ) / 60 ))" "$note"
  done
  if [ "$n" = 0 ]; then echo "  (no task has reported a phase yet — runners call: qa-lock phase <task-id> <phase> [note])"; fi
  echo "── QA lane ──"
  status ""
  return 0
}

board_sig() { # fingerprint of everything the board shows, to detect a change
  local s; shopt -s nullglob
  for s in "$DIR"/*/STATUS "$DIR"/qa-*.lock/meta; do [ -e "$s" ] && cat "$s"; done
  for s in "$DIR"/qa-*.waiting/*; do [ -e "$s" ] && echo "$s"; done
}

board_follow() { # <timeout> — block until anything changes, then print. 0 = changed, 3 = quiet
  local timeout="$1" start sig
  start="$(now)"; sig="$(board_sig)"
  while [ "$(( $(now) - start ))" -lt "$timeout" ]; do
    sleep 5
    if [ "$(board_sig)" != "$sig" ]; then echo "── board changed after $(( $(now) - start ))s ──"; board; return 0; fi
  done
  echo "── no change in ${timeout}s ──"; board; return 3
}

whoami_all() { # <res|"">  empty => every resource's holder
  local only="$1" ld r; shopt -s nullglob
  for ld in "$DIR"/qa-*.lock; do
    [ -d "$ld" ] || continue
    r="$(basename "$ld" | sed 's/^qa-//; s/\.lock$//')"
    [ -n "$only" ] && [ "$r" != "$only" ] && continue
    echo "$r $(sed -n 1p "$ld/meta" 2>/dev/null || echo)"
  done
}

selfcheck() {
  local tmp; tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' RETURN
  export PARALLEL_LOCK_DIR="$tmp"; DIR="$tmp"
  # 1. exclusivity + independent resources + whoami
  acquire t1 web "$$" >/dev/null            || die "FAIL: t1 acquire"
  acquire t2 web "$$" >/dev/null            && die "FAIL: t2 acquired a held lock"
  [ "$(whoami_all web)" = "web t1" ]        || die "FAIL: whoami web != t1"
  acquire t2 sim "$$" >/dev/null            || die "FAIL: sim independent"
  # 2. release contract
  release t2 web >/dev/null 2>&1            && die "FAIL: t2 released t1's lock"
  release t1 web >/dev/null                 || die "FAIL: t1 release"
  [ -z "$(sed -n 1p "$(lockdir web)/meta" 2>/dev/null || echo)" ] || die "FAIL: web not free"
  # (TTL/DEAD_GRACE are read once at startup, so tests set the globals directly)
  local ttl0="$TTL" dg0="$DEAD_GRACE"
  # 3. a LIVE holder is NOT stolen even long past DEAD_GRACE (a 40-min native build)
  acquire t1 web "$$" >/dev/null
  printf 't1\n%s\n%s\n' "$(( $(now) - 3000 ))" "$$" > "$(lockdir web)/meta"   # alive, silent 50min
  DEAD_GRACE=1; acquire t3 web "$$" >/dev/null && die "FAIL: stole a LIVE holder"
  DEAD_GRACE="$dg0"
  # …but TTL is an absolute backstop for a live-yet-stuck holder
  TTL=1; acquire t3 web "$$" >/dev/null || die "FAIL: TTL backstop didn't free a stuck holder"
  TTL="$ttl0"; release t3 web >/dev/null
  # 4. a DEAD holder keeps the lock for DEAD_GRACE (a mis-recorded throwaway pid must not
  #    hand one Simulator to two testers), then is reclaimed
  local deadpid=999999
  acquire t1 web "$deadpid" >/dev/null
  acquire t3 web "$$" >/dev/null            && die "FAIL: stole a just-dead holder inside DEAD_GRACE"
  DEAD_GRACE=0; acquire t3 web "$$" >/dev/null || die "FAIL: dead holder not reclaimed after grace"
  DEAD_GRACE="$dg0"
  [ "$(whoami_all web)" = "web t3" ]        || die "FAIL: stealer not holder"
  release t3 web >/dev/null
  # 5. an EMPTY (mid-init) fresh lock is NOT stolen, but an old orphan IS
  mkdir -p "$(lockdir emptyfresh)"
  [ "$(holder_state "$(lockdir emptyfresh)")" = busy ] || die "FAIL: fresh meta-less lock treated as stealable"
  # 6. CONCURRENCY: N racers, exactly one winner
  local n=25 i wins
  for i in $(seq 1 $n); do ( acquire "r$i" race "$$" >/dev/null 2>&1 && echo won > "$tmp/.win$i" ) & done
  wait
  wins=$(ls "$tmp"/.win* 2>/dev/null | wc -l | tr -d ' ')
  [ "$wins" = 1 ] || die "FAIL: concurrency race had $wins winners (want 1)"
  # 7. wait: takes a free lock, and on a busy one returns 3 (KEEP WAITING) — never 0
  local rc=0
  wait_lock w1 waitres "$$" 1 1 >/dev/null  || die "FAIL: wait didn't take a free lock"
  set +e; wait_lock w2 waitres "$$" 1 1 >/dev/null; rc=$?; set -e
  [ "$rc" = 3 ]                             || die "FAIL: wait on a busy lock exited $rc (want 3 = still queued)"
  [ "$(sed -n 1p "$DIR/w2/STATUS")" = qa-wait ] || die "FAIL: a queued waiter didn't publish its qa-wait phase"
  release w1 waitres >/dev/null
  # 8. phase + board round-trip (the coordinator's only source of progress)
  phase_write b1 implement "wiring the settings screen"
  board > "$tmp/.board"                     # no pipe: pipefail + grep's early exit = SIGPIPE
  grep -q "wiring the settings screen" "$tmp/.board" || die "FAIL: board doesn't show a reported phase"
  grep -q "w2" "$tmp/.board"                || die "FAIL: board doesn't show the queued task"
  echo "qa-lock selfcheck: OK (incl. $n-way race → 1 winner, wait/board contract)"
}

cmd="${1:-}"; shift 2>/dev/null || true
case "$cmd" in
  acquire)   [ $# -ge 1 ] || die "usage: acquire <task-id> --resource <key> [--pid <pid>]"
             r="$(res_from_args "${@:2}")"; ok_name "$1" || die "bad task id"; ok_name "$r" || die "bad --resource (need [a-z0-9._-])"
             p="$(pid_from_args "${@:2}")"; acquire "$1" "$r" "${p:-$(default_pid)}" ;;
  wait)      [ $# -ge 1 ] || die "usage: wait <task-id> --resource <key> [--pid <pid>] [--timeout <s>] [--interval <s>]"
             r="$(res_from_args "${@:2}")"; ok_name "$1" || die "bad task id"; ok_name "$r" || die "bad --resource (need [a-z0-9._-])"
             p="$(pid_from_args "${@:2}")"
             wait_lock "$1" "$r" "${p:-$(default_pid)}" "$(opt_from_args --timeout 1800 "${@:2}")" "$(opt_from_args --interval 20 "${@:2}")" ;;
  phase)     [ $# -ge 2 ] || die "usage: phase <task-id> <phase> [note …]"
             ok_name "$1" || die "bad task id"; phase_write "$@" ;;
  board)     if has_flag --follow "$@"; then board_follow "$(opt_from_args --follow 300 "$@")"; else board; fi ;;
  refresh)   [ $# -ge 1 ] || die "usage: refresh <task-id> --resource <key>"
             r="$(res_from_args "${@:2}")"; ok_name "$r" || die "bad --resource"; refresh "$1" "$r" ;;
  release)   [ $# -ge 1 ] || die "usage: release <task-id> --resource <key>"
             r="$(res_from_args "${@:2}")"; ok_name "$r" || die "bad --resource"; release "$1" "$r" ;;
  status)    if has_res "$@"; then r="$(res_from_args "$@")"; ok_name "$r" || die "bad --resource"; status "$r"; else status ""; fi ;;
  whoami)    if has_res "$@"; then r="$(res_from_args "$@")"; ok_name "$r" || die "bad --resource"; whoami_all "$r"; else whoami_all ""; fi ;;
  selfcheck) selfcheck ;;
  *) die "usage: qa-lock acquire|wait|refresh|release|phase|board|status|whoami|selfcheck  (see header)" ;;
esac
