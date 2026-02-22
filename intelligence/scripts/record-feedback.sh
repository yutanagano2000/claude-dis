#!/bin/bash
# DIS: フィードバックをSQLiteに記録。/feedback スキルから呼び出される。
# Usage: record-feedback.sh <category> <wrong> <correct> [context] [project] [scope]
set -euo pipefail

DB="$HOME/.claude/intelligence/dev.db"

category="${1:?Usage: record-feedback.sh <category> <wrong> <correct> [context] [project] [scope]}"
wrong="${2:?}"
correct="${3:?}"
context="${4:-}"
project="${5:-unknown}"
scope="${6:-project}"

# SQLエスケープ (シングルクォート)
esc() { echo "$1" | sed "s/'/''/g"; }

# 重複チェック: 同一 wrong_approach + correct_approach + project があればスコア加算
existing=$(sqlite3 "$DB" "SELECT id, score, confirmation_count FROM feedback WHERE wrong_approach = '$(esc "$wrong")' AND correct_approach = '$(esc "$correct")' AND project = '$(esc "$project")' LIMIT 1;" 2>/dev/null)

if [ -n "$existing" ]; then
  eid=$(echo "$existing" | cut -d'|' -f1)
  old_score=$(echo "$existing" | cut -d'|' -f2)
  old_count=$(echo "$existing" | cut -d'|' -f3)
  new_score=$(echo "$old_score + 1.5" | bc)
  new_count=$((old_count + 1))
  sqlite3 "$DB" "UPDATE feedback SET score = $new_score, confirmation_count = $new_count, last_seen = datetime('now') WHERE id = $eid;"
  echo "UPDATED|$eid|$category|$new_score|$new_count"
else
  sqlite3 "$DB" "INSERT INTO feedback(category, wrong_approach, correct_approach, context, project, scope) VALUES(
    '$(esc "$category")',
    '$(esc "$wrong")',
    '$(esc "$correct")',
    '$(esc "$context")',
    '$(esc "$project")',
    '$(esc "$scope")'
  );"
  new_id=$(sqlite3 "$DB" "SELECT last_insert_rowid();")
  echo "INSERTED|$new_id|$category|1.5|1"
fi
