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
# A holder is reclaimed only when it is actually GONE: the runner's pid is recorded
# and `kill -0` decides liveness (same host — these are local tasks); TTL is just a
# backstop when the pid can't be checked. A long-but-alive QA (cold native build) is
# NOT stolen — call `refresh` to heartbeat it.
#
# Usage:
#   qa-lock acquire <task-id> --resource <key> [--pid <pid>]  # try ONCE: exit 0 = got it, 1 = busy
#   qa-lock refresh <task-id> --resource <key>                # heartbeat a long hold so it isn't reclaimed
#   qa-lock release <task-id> --resource <key>                # release only if you hold it
#   qa-lock status  [--resource <key>]                        # holder + age + liveness + who's waiting (all if omitted)
#   qa-lock whoami  [--resource <key>]                        # current holder(s) ("" if free)
#   qa-lock selfcheck                                          # offline assertions incl. a real concurrency race
#
# The caller loops on `acquire` itself (so it can show "waiting for QA" between
# tries) — this helper never sleeps. Env: PARALLEL_LOCK_DIR (default
# ~/.cache/parallel-tasks), QA_LOCK_TTL fallback-staleness secs (default 3600),
# QA_LOCK_GRACE secs before a meta-less (crashed mid-init) lock is reclaimable (30).
set -euo pipefail

DIR="${PARALLEL_LOCK_DIR:-$HOME/.cache/parallel-tasks}"
TTL="${QA_LOCK_TTL:-3600}"
GRACE="${QA_LOCK_GRACE:-30}"
mkdir -p "$DIR"

now()  { date +%s; }
die()  { echo "qa-lock: $*" >&2; exit 2; }
ok_name() { case "$1" in ''|*[!a-z0-9._-]*) return 1;; *) return 0;; esac; }  # no /, no .., safe for paths
lockdir() { echo "$DIR/qa-${1}.lock"; }
waitdir() { echo "$DIR/qa-${1}.waiting"; }
mtime()   { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0; }  # macOS || linux

res_from_args() { local r=""; while [ $# -gt 0 ]; do case "$1" in --resource) r="${2:-}"; shift 2;; *) shift;; esac; done; echo "$r"; }
pid_from_args() { local p=""; while [ $# -gt 0 ]; do case "$1" in --pid) p="${2:-}"; shift 2;; *) shift;; esac; done; echo "$p"; }
has_res()       { while [ $# -gt 0 ]; do [ "$1" = --resource ] && return 0; shift; done; return 1; }

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
  if [ -n "$pid" ]; then
    alive "$pid" && echo busy || echo steal          # pid known: liveness is authoritative
  else
    [ "$(( $(now) - ts ))" -ge "$TTL" ] && echo steal || echo busy   # no pid: TTL backstop
  fi
}

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
  mkdir -p "$(waitdir "$res")"; : > "$(waitdir "$res")/$task"
  echo "busy: qa-lock[$res] held by ${holder:-?} — retry"; return 1
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
  rm -rf "$ld"; echo "released qa-lock[$res] for $task"
}

status() { # <res|"">   empty => all resources
  local only="$1" any=0 ld r holder ts pid wd w live
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
      echo "   ⏳ waiting: $(basename "$w")"
    done
  done
  [ "$any" = 0 ] && echo "no QA in progress${only:+ for [$only]} (free)"
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
  # 3. a LIVE holder past TTL is NOT stolen (heartbeat semantics): live pid, ancient ts
  acquire t1 web "$$" >/dev/null
  printf 't1\n1\n%s\n' "$$" > "$(lockdir web)/meta"    # ts=1 (ancient) but pid=$$ is alive
  QA_LOCK_TTL=1 acquire t3 web "$$" >/dev/null && die "FAIL: stole a LIVE holder"
  release t1 web >/dev/null
  # 4. a DEAD holder is reclaimed: use a pid that isn't running
  local deadpid=999999
  acquire t1 web "$deadpid" >/dev/null
  acquire t3 web "$$" >/dev/null            || die "FAIL: dead holder not reclaimed"
  [ "$(whoami_all web)" = "web t3" ]        || die "FAIL: stealer not holder"
  release t3 web >/dev/null
  # 5. an EMPTY (mid-init) fresh lock is NOT stolen, but an old orphan IS
  mkdir -p "$(lockdir emptyfresh)"
  [ "$(holder_state "$(lockdir emptyfresh)")" = busy ] || die "FAIL: fresh meta-less lock treated as stealable"
  # 6. CONCURRENCY: N racers, exactly one winner
  local n=25 i wins
  for i in $(seq 1 $n); do ( acquire "r$i" race "$$" >/dev/null 2>&1 && echo won > "$tmp/w$i" ) & done
  wait
  wins=$(ls "$tmp"/w* 2>/dev/null | wc -l | tr -d ' ')
  [ "$wins" = 1 ] || die "FAIL: concurrency race had $wins winners (want 1)"
  echo "qa-lock selfcheck: OK (incl. $n-way race → 1 winner)"
}

cmd="${1:-}"; shift 2>/dev/null || true
case "$cmd" in
  acquire)   [ $# -ge 1 ] || die "usage: acquire <task-id> --resource <key> [--pid <pid>]"
             r="$(res_from_args "${@:2}")"; ok_name "$1" || die "bad task id"; ok_name "$r" || die "bad --resource (need [a-z0-9._-])"
             p="$(pid_from_args "${@:2}")"; acquire "$1" "$r" "${p:-$PPID}" ;;
  refresh)   [ $# -ge 1 ] || die "usage: refresh <task-id> --resource <key>"
             r="$(res_from_args "${@:2}")"; ok_name "$r" || die "bad --resource"; refresh "$1" "$r" ;;
  release)   [ $# -ge 1 ] || die "usage: release <task-id> --resource <key>"
             r="$(res_from_args "${@:2}")"; ok_name "$r" || die "bad --resource"; release "$1" "$r" ;;
  status)    if has_res "$@"; then r="$(res_from_args "$@")"; ok_name "$r" || die "bad --resource"; status "$r"; else status ""; fi ;;
  whoami)    if has_res "$@"; then r="$(res_from_args "$@")"; ok_name "$r" || die "bad --resource"; whoami_all "$r"; else whoami_all ""; fi ;;
  selfcheck) selfcheck ;;
  *) die "usage: qa-lock acquire|refresh|release|status|whoami|selfcheck  (see header)" ;;
esac
