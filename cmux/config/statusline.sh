#!/usr/bin/env bash
# Claude Code statusline — Catppuccin Mocha palette, · dividers:
#   dir · ⎇ branch · ⇡push ⇣pull · ±files +adds -dels · context% · model 1M · effort · ⬡ codegraph · [PONYTAIL]
input=$(cat)

dir=$(printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // empty' 2>/dev/null)
[ -z "$dir" ] && dir="$PWD"
cd "$dir" 2>/dev/null || true
model=$(printf '%s' "$input" | jq -r '.model.display_name // empty' 2>/dev/null)

R=$'\033[0m'
SEP=$' \033[38;5;245m·\033[0m '   # middle-dot divider (Overlay1)
# fg colors — Catppuccin Mocha
C_DIR=$'\033[38;5;111m'; C_BR=$'\033[38;5;183m'; C_PUSH=$'\033[38;5;114m'        # Blue / Mauve / Green
C_PULL=$'\033[38;5;117m'; C_SYNC=$'\033[38;5;114m'; C_FILE=$'\033[38;5;215m'      # Sky / Green / Peach
C_ADD=$'\033[38;5;114m'; C_DEL=$'\033[38;5;211m'; C_CLEAN=$'\033[38;5;114m'; C_MOD=$'\033[38;5;146m'  # Green / Red / Green / Subtext
C_CG=$'\033[38;5;116m'; C_CG_OFF=$'\033[38;5;243m'; C_CG_WARN=$'\033[38;5;215m'   # Teal / Overlay / Peach
C_1M=$'\033[38;5;183m'  # 1M-context badge (Mauve)
C_PONY=$'\033[1m\033[38;5;218m'  # ponytail badge (bold Pink)

segs=()
segs+=("${C_DIR}$(basename "$dir")${R}")

branch=$(git symbolic-ref --short -q HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null)
if [ -n "$branch" ]; then
  segs+=("${C_BR}⎇ ${branch}${R}")

  ab=$(git rev-list --left-right --count '@{upstream}...HEAD' 2>/dev/null)
  if [ -n "$ab" ]; then
    behind=$(printf '%s' "$ab" | awk '{print $1}'); ahead=$(printf '%s' "$ab" | awk '{print $2}')
    up="${C_PUSH}⇡${R}";   [ "${ahead:-0}"  -gt 0 ] 2>/dev/null && up="${C_PUSH}⇡${ahead}${R}"
    down="${C_PULL}⇣${R}"; [ "${behind:-0}" -gt 0 ] 2>/dev/null && down="${C_PULL}⇣${behind}${R}"
    segs+=("${up} ${down}")
  fi

  files=$(git status --porcelain 2>/dev/null | grep -c .)
  # tracked changes vs HEAD (covers staged + unstaged); empty on a repo with no commits
  shortstat=$(git diff HEAD --shortstat 2>/dev/null)
  tadds=$(printf '%s' "$shortstat" | grep -oE '[0-9]+ insertion' | grep -oE '[0-9]+')
  dels=$(printf '%s' "$shortstat" | grep -oE '[0-9]+ deletion' | grep -oE '[0-9]+')
  # NEW/untracked files: git diff never counts them, so add their inserted lines.
  # numstat vs /dev/null matches git's own counting and reports binaries as "-" (skipped).
  uadds=$(git ls-files --others --exclude-standard 2>/dev/null | head -n 500 | while IFS= read -r f; do
            git diff --numstat --no-index -- /dev/null "$f" 2>/dev/null
          done | awk '$1 ~ /^[0-9]+$/ {s+=$1} END{print s+0}')
  adds=$(( ${tadds:-0} + ${uadds:-0} )); dels=${dels:-0}
  if [ "${files:-0}" -gt 0 ] 2>/dev/null || [ "$adds" -gt 0 ] || [ "$dels" -gt 0 ]; then
    chg="${C_FILE}±${files}${R}"
    [ "$adds" -gt 0 ] && chg="${chg} ${C_ADD}+${adds}${R}"
    [ "$dels" -gt 0 ] && chg="${chg} ${C_DEL}-${dels}${R}"
    segs+=("$chg")
  else
    segs+=("${C_CLEAN}✓ clean${R}")
  fi
fi

# context usage — the payload carries the real window + usage (context_window, CC 2.1+);
# transcript parse kept only as fallback for older builds (guesses the window from model id).
win=$(printf '%s' "$input" | jq -r '.context_window.context_window_size // empty' 2>/dev/null)
pct=$(printf '%s' "$input" | jq -r '.context_window.used_percentage // empty' 2>/dev/null)
if [ -z "$pct" ]; then
  tp=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)
  if [ -n "$tp" ] && [ -f "$tp" ]; then
    last_usage=$(grep '"usage"' "$tp" 2>/dev/null | grep -v '"isSidechain":true' | tail -1)
    used=$(printf '%s' "$last_usage" | jq -r '(.message.usage // {}) | ((.input_tokens//0)+(.cache_read_input_tokens//0)+(.cache_creation_input_tokens//0))' 2>/dev/null)
    if [ -n "$used" ] && [ "$used" -gt 0 ] 2>/dev/null; then
      case "$(printf '%s' "$input" | jq -r '.model.id // empty' 2>/dev/null)" in
        *'[1m]'*|*1M*) win=1000000 ;;
        *)             win=200000 ;;
      esac
      pct=$(( used * 100 / win ))
    fi
  fi
fi
if [ -n "$pct" ] && [ "$pct" -ge 0 ] 2>/dev/null; then
  if   [ "$pct" -ge 80 ]; then C_CTX=$'\033[38;5;211m'   # Red
  elif [ "$pct" -ge 50 ]; then C_CTX=$'\033[38;5;215m'   # Peach
  else                         C_CTX=$'\033[38;5;114m'   # Green
  fi
  segs+=("${C_CTX}${pct}%${R}")
fi

if [ -n "$model" ]; then
  mname=${model%% (*}
  [ "${win:-0}" -ge 1000000 ] 2>/dev/null && mname="${mname} ${C_1M}1M${R}${C_MOD}"
  segs+=("${C_MOD}${mname}${R}")
fi

# reasoning effort — payload doesn't carry it, so read the live merged settings
# (precedence: project-local > project > user, matching Claude Code's own merge).
eff=$(printf '%s' "$input" | jq -r '.effortLevel // empty' 2>/dev/null)
if [ -z "$eff" ]; then
  eff_root=$(git rev-parse --show-toplevel 2>/dev/null || printf '%s' "$dir")
  for f in "$eff_root/.claude/settings.local.json" "$eff_root/.claude/settings.json" "$HOME/.claude/settings.json"; do
    [ -f "$f" ] || continue
    eff=$(jq -r '.effortLevel // empty' "$f" 2>/dev/null); [ -n "$eff" ] && break
  done
fi
if [ -n "$eff" ]; then
  case "$eff" in
    max)    C_EFF=$'\033[38;5;211m' ;;  # Red
    xhigh)  C_EFF=$'\033[38;5;215m' ;;  # Peach
    high)   C_EFF=$'\033[38;5;223m' ;;  # Yellow
    medium) C_EFF=$'\033[38;5;117m' ;;  # Sky
    *)      C_EFF=$'\033[38;5;245m' ;;  # Overlay (low/unknown)
  esac
  segs+=("${C_EFF}${eff}${R}")
fi

# codegraph index status — trailing (sits near the badge so it doesn't
# crowd the git/context segments). cheap: only invoke the binary when an index db
# exists, so non-indexed repos stay instant. perl alarm = 2s safety timeout (no `timeout` on macOS).
if command -v codegraph >/dev/null 2>&1; then
  cg_root=$(git rev-parse --show-toplevel 2>/dev/null || printf '%s' "$dir")
  if [ -f "$cg_root/.codegraph/codegraph.db" ]; then
    cg_json=$(perl -e 'alarm 2; exec @ARGV' codegraph status --json 2>/dev/null)
    cg=$(printf '%s' "$cg_json" | jq -r '
      if .initialized != true then "OFF||"
      else
        (((.pendingChanges.added // 0) + (.pendingChanges.modified // 0) + (.pendingChanges.removed // 0))) as $p |
        (if (.index.reindexRecommended // false) then "REINDEX" elif $p > 0 then "STALE" else "OK" end) as $s |
        "\($s)|\(.fileCount // 0)f \(.nodeCount // 0)n|\($p)"
      end' 2>/dev/null)
    cg_state=${cg%%|*}; cg_rest=${cg#*|}; cg_stat=${cg_rest%%|*}; cg_pend=${cg_rest#*|}
    case "$cg_state" in
      OK)      segs+=("${C_CG}⬡ ✓${R}") ;;
      STALE)   segs+=("${C_CG_WARN}⬡ ⚠${cg_pend}${R}") ;;
      REINDEX) segs+=("${C_CG_WARN}⬡ reindex${R}") ;;
      *)       segs+=("${C_CG_OFF}⬡ off${R}") ;;
    esac
  else
    segs+=("${C_CG_OFF}⬡ —${R}")
  fi
fi

# ponytail badge — static trailing label (ponytail has no statusline hook to call).
segs+=("${C_PONY}[PONYTAIL]${R}")

# join segments with the · divider
out=""
for i in "${!segs[@]}"; do
  [ "$i" -eq 0 ] && out="${segs[$i]}" || out="${out}${SEP}${segs[$i]}"
done

printf '%s' "$out"
