#!/bin/bash
# DIS: セッション統計をSQLiteに記録 (Stop hook)
DB="$HOME/.claude/intelligence/dev.db"
[ ! -f "$DB" ] && exit 0

input=$(cat)
cwd=$(echo "$input" | jq -r '.cwd // ""')
project=$(basename "$cwd")

# 直近セッション中のイベント統計を集計
errors_total=$(sqlite3 "$DB" "SELECT COUNT(*) FROM events WHERE project='$(echo "$project" | sed "s/'/''/g")' AND ts >= datetime('now', '-4 hours');" 2>/dev/null || echo 0)
errors_resolved=$(sqlite3 "$DB" "SELECT COUNT(*) FROM events WHERE project='$(echo "$project" | sed "s/'/''/g")' AND resolved=1 AND ts >= datetime('now', '-4 hours');" 2>/dev/null || echo 0)

sqlite3 "$DB" "INSERT INTO sessions(project, errors_encountered, errors_resolved) VALUES(
  '$(echo "$project" | sed "s/'/''/g")',
  $errors_total,
  $errors_resolved
);" 2>/dev/null

exit 0
