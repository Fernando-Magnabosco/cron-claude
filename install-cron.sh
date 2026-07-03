#!/usr/bin/env bash
# Installs (or refreshes) the cron-claude schedule: 20:00, 01:00, 06:00 daily.
set -euo pipefail

ROOT="${CRON_CLAUDE_HOME:-$HOME/cron-claude}"
LINE="0 18,23,3 * * * $ROOT/run.sh >> $ROOT/logs/cron.log 2>&1"
MARK="# cron-claude"

# keep every existing line except a previous cron-claude entry, then re-add.
current="$(crontab -l 2>/dev/null | grep -v "$MARK" | grep -v "$ROOT/run.sh" || true)"
{
  [[ -n "$current" ]] && printf '%s\n' "$current"
  echo "$MARK (overnight planner: 6PM/11PM/3AM)"
  echo "$LINE"
} | crontab -

echo "Installed. Current crontab:"
crontab -l | sed 's/^/  /'
