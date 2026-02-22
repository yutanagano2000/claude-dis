#!/bin/bash
# DIS: 質問をSQLiteに記録。/que スキルから呼び出される。
# Usage:
#   record-question.sh ask <question> [project] [context] [tags_json]
#   record-question.sh resolve <id> <answer>
#   record-question.sh search <query> [project]
set -euo pipefail

DB="$HOME/.claude/intelligence/dev.db"
CMD="${1:?Usage: record-question.sh <ask|resolve|search> ...}"
shift

esc() { echo "$1" | sed "s/'/''/g"; }

# sqlite3 -json が空結果時に [] を返す
json_or_empty() { local r; r=$(sqlite3 -json "$DB" "$1" 2>/dev/null); echo "${r:-[]}"; }

case "$CMD" in
  ask)
    question="${1:?ask: <question>}"
    project="${2:-unknown}"
    context="${3:-}"
    tags="${4:-[]}"

    # 重複チェック: 同一質問+projectがあればスコア加算
    existing=$(sqlite3 "$DB" "SELECT id, score FROM questions WHERE question = '$(esc "$question")' AND project = '$(esc "$project")' LIMIT 1;" 2>/dev/null)

    if [ -n "$existing" ]; then
      eid=$(echo "$existing" | cut -d'|' -f1)
      old_score=$(echo "$existing" | cut -d'|' -f2)
      new_score=$(echo "$old_score + 1.0" | bc)
      sqlite3 "$DB" "UPDATE questions SET score = $new_score, last_seen = datetime('now'), context = '$(esc "$context")' WHERE id = $eid;"
      echo "UPDATED|$eid|$new_score"
    else
      new_id=$(sqlite3 "$DB" "INSERT INTO questions(project, question, context, tags)
        VALUES(
          '$(esc "$project")',
          '$(esc "$question")',
          '$(esc "$context")',
          '$(esc "$tags")'
        );
        SELECT last_insert_rowid();")
      echo "INSERTED|$new_id|1.0"
    fi
    ;;

  resolve)
    id="${1:?resolve: <id> <answer>}"
    answer="${2:?}"

    sqlite3 "$DB" "UPDATE questions SET
      answer = '$(esc "$answer")',
      status = 'resolved',
      resolved_at = datetime('now'),
      score = score + 1.0,
      last_seen = datetime('now')
      WHERE id = $id;"
    echo "RESOLVED|$id"
    ;;

  search)
    query="${1:?search: <query> [project]}"
    project="${2:-}"

    # 1) テキスト検索 (open + resolved)
    project_filter=""
    [ -n "$project" ] && project_filter="AND project = '$(esc "$project")'"

    results=$(json_or_empty "SELECT id, question, answer, status, tags, score, project, ts
      FROM questions
      WHERE (question LIKE '%$(esc "$query")%'
        OR context LIKE '%$(esc "$query")%'
        OR answer LIKE '%$(esc "$query")%'
        OR tags LIKE '%$(esc "$query")%')
        $project_filter
      ORDER BY score DESC, ts DESC
      LIMIT 10;")

    # 2) similarity.py でsolutions内の関連知見も検索
    similar=$(python3 -c "
import sys
sys.path.insert(0, '$HOME/.claude/intelligence/scripts')
from similarity import find_similar
import json
results = find_similar('$(esc "$query")', threshold=0.3, limit=3)
print(json.dumps(results))
" 2>/dev/null || echo "[]")

    cat <<EOF
{"questions": $results, "related_solutions": $similar}
EOF
    ;;

  *)
    echo "Unknown command: $CMD" >&2
    echo "Usage: record-question.sh <ask|resolve|search> ..." >&2
    exit 1
    ;;
esac
