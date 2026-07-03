#!/usr/bin/env bash
#
# cron-claude — overnight batch planner.
# For each task file in ~/cron-claude/tasks/, runs Claude Code in plan mode
# (read-only) and writes a Markdown plan to ~/cron-claude/plans/, then archives
# the source task to tasks/done/.
#
# Intended to be driven by cron (see README.md), but safe to run by hand.

set -uo pipefail

# cron runs with a minimal PATH; ensure the claude CLI is reachable.
export PATH="$HOME/.local/bin:$HOME/bin:/usr/local/bin:$PATH"

ROOT="${CRON_CLAUDE_HOME:-$HOME/cron-claude}"
TASKS_DIR="$ROOT/tasks"
DONE_DIR="$TASKS_DIR/done"
PLANS_DIR="$ROOT/plans"
LOGS_DIR="$ROOT/logs"
CONFIG="$ROOT/.config"

# --- precedence: explicit env > .config > defaults ------------------------
# snapshot any of our keys that were already set in the environment.
declare -A _ENV
for k in MODEL EFFORT PROJECT_DIR PLAN_TIMEOUT ENFORCE_WINDOW WINDOW_START WINDOW_END; do
  [[ -n "${!k+set}" ]] && _ENV["$k"]="${!k}"
done

# --- defaults --------------------------------------------------------------
MODEL="opus"
EFFORT="high"
PROJECT_DIR="$HOME"
PLAN_TIMEOUT=1200
ENFORCE_WINDOW=1
WINDOW_START=20
WINDOW_END=8

# --- load config: read only KEY=VALUE lines, ignore everything else -------
if [[ -f "$CONFIG" ]]; then
  while IFS='=' read -r key val; do
    key="${key%%[[:space:]]*}"          # trim trailing space
    [[ -z "$key" || "$key" == \#* ]] && continue
    val="${val%%#*}"                    # strip inline comments
    val="$(echo "$val" | xargs)"        # trim surrounding whitespace
    case "$key" in
      MODEL|EFFORT|PROJECT_DIR|PLAN_TIMEOUT|ENFORCE_WINDOW|WINDOW_START|WINDOW_END)
        printf -v "$key" '%s' "$val" ;;
    esac
  done < "$CONFIG"
fi

# re-apply env overrides so they win over .config.
for k in "${!_ENV[@]}"; do printf -v "$k" '%s' "${_ENV[$k]}"; done

mkdir -p "$TASKS_DIR" "$DONE_DIR" "$PLANS_DIR" "$LOGS_DIR"

STAMP="$(date +%Y%m%d-%H%M%S)"
RUN_LOG="$LOGS_DIR/run-$STAMP.log"

log() { echo "[$(date '+%F %T')] $*" | tee -a "$RUN_LOG"; }

# --- overnight window guard ------------------------------------------------
if [[ "$ENFORCE_WINDOW" == "1" ]]; then
  hour=$(( 10#$(date +%H) ))
  # window wraps midnight: active if hour >= START OR hour < END
  if (( hour < WINDOW_START && hour >= WINDOW_END )); then
    log "Outside overnight window (${WINDOW_START}:00–${WINDOW_END}:00, now ${hour}:00). Exiting."
    exit 0
  fi
fi

if ! command -v claude >/dev/null 2>&1; then
  log "ERROR: 'claude' not found in PATH ($PATH). Aborting."
  exit 1
fi

# --- collect pending tasks (top level only, skip done/) --------------------
shopt -s nullglob
mapfile -d '' TASKS < <(find "$TASKS_DIR" -maxdepth 1 -type f \
  \( -name '*.md' -o -name '*.txt' \) ! -name 'README*' -print0 | sort -z)

if (( ${#TASKS[@]} == 0 )); then
  log "No pending tasks in $TASKS_DIR. Nothing to do."
  exit 0
fi

log "Found ${#TASKS[@]} task(s). model=$MODEL effort=$EFFORT timeout=${PLAN_TIMEOUT}s"

PROMPT_TEMPLATE='You are planning work for an engineer who is away from the keyboard.
Read the task/issue below and produce a detailed, actionable implementation plan
in Markdown. Investigate the codebase as needed, but DO NOT make any changes —
research and plan only.

IMPORTANT: There is no interactive user to approve anything. Do NOT call
ExitPlanMode. Write the complete plan directly as your final response in Markdown,
structured as: Summary, Affected files/areas, Step-by-step approach,
Risks & open questions, and Verification steps.

===== TASK =====
'

for task in "${TASKS[@]}"; do
  name="$(basename "$task")"
  base="${name%.*}"
  out="$PLANS_DIR/${base}.plan-${STAMP}.md"

  # per-task cwd override on the first line. Accepts, leniently:
  #   <!-- cwd: /path -->   |   cwd: /path   |   cwd /path
  # (paths may contain '-', so we capture the rest of the line and trim).
  cwd="$PROJECT_DIR"
  first="$(head -n1 "$task")"
  if [[ "$first" == *cwd* ]]; then
    cand="${first#*cwd}"      # drop everything up to & including 'cwd'
    cand="${cand#:}"          # optional leading colon
    cand="${cand%-->}"        # drop trailing HTML-comment close, if any
    cand="$(echo "$cand" | xargs)"   # trim surrounding whitespace
    [[ -n "$cand" && -d "$cand" ]] && cwd="$cand"
  fi
  [[ -d "$cwd" ]] || cwd="$HOME"

  log "Planning '$name'  (cwd=$cwd) -> $(basename "$out")"

  prompt="$PROMPT_TEMPLATE$(cat "$task")"

  {
    echo "# Plan: $name"
    echo
    echo "> Generated $(date '+%F %T') · model=$MODEL · effort=$EFFORT · cwd=$cwd"
    echo
  } > "$out"

  if ( cd "$cwd" && timeout "$PLAN_TIMEOUT" claude -p "$prompt" \
        --permission-mode plan \
        --model "$MODEL" \
        --effort "$EFFORT" ) >> "$out" 2>>"$RUN_LOG"; then
    log "  OK: $(basename "$out")"
    mv -f "$task" "$DONE_DIR/$name"
  else
    rc=$?
    log "  FAILED (rc=$rc): $name — left in place, see $RUN_LOG"
    echo -e "\n\n> ⚠️ Planning failed (rc=$rc). Task left in tasks/ for retry." >> "$out"
  fi
done

log "Run complete."
