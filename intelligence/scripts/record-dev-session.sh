#!/bin/bash
# DIS: 開発セッションをSQLiteに記録。/dev スキルから呼び出される。
# Usage:
#   record-dev-session.sh start <project> <requirement>
#   record-dev-session.sh update-phase <id> <phase> [files_changed_json] [lines_added] [lines_removed]
#   record-dev-session.sh complete <id> <status> [files_changed_json] [lines_added] [lines_removed] [test_session_id] [test_status] [review_score_initial] [review_score_final] [review_iterations] [dis_solutions_json] [dis_feedback_json] [dis_patterns_json] [new_feedback_json] [duration_seconds]
#   record-dev-session.sh lookup <project> <requirement>
set -euo pipefail

DB="$HOME/.claude/intelligence/dev.db"
CMD="${1:?Usage: record-dev-session.sh <start|update-phase|complete|lookup> ...}"
shift

esc() { echo "$1" | sed "s/'/''/g"; }

case "$CMD" in
  start)
    project="${1:?start: <project> <requirement>}"
    requirement="${2:?}"

    new_id=$(sqlite3 "$DB" "INSERT INTO dev_sessions(project, requirement, phase, status)
      VALUES(
        '$(esc "$project")',
        '$(esc "$requirement")',
        'prep',
        'running'
      );
      SELECT last_insert_rowid();")
    echo "STARTED|$new_id"
    ;;

  update-phase)
    id="${1:?update-phase: <id> <phase>}"
    phase="${2:?}"
    files_changed="${3:-}"
    lines_added="${4:-0}"
    lines_removed="${5:-0}"

    sql="UPDATE dev_sessions SET phase = '$(esc "$phase")'"
    [ -n "$files_changed" ] && sql="$sql, files_changed = '$(esc "$files_changed")'"
    [ "$lines_added" != "0" ] && sql="$sql, lines_added = $lines_added"
    [ "$lines_removed" != "0" ] && sql="$sql, lines_removed = $lines_removed"
    sql="$sql WHERE id = $id;"

    sqlite3 "$DB" "$sql"
    echo "UPDATED|$id|$phase"
    ;;

  complete)
    id="${1:?complete: <id> <status>}"
    status="${2:?}"
    files_changed="${3:-}"
    lines_added="${4:-0}"
    lines_removed="${5:-0}"
    test_session_id="${6:-}"
    test_status="${7:-}"
    review_score_initial="${8:-}"
    review_score_final="${9:-}"
    review_iterations="${10:-0}"
    dis_solutions="${11:-}"
    dis_feedback="${12:-}"
    dis_patterns="${13:-}"
    new_feedback="${14:-}"
    duration_seconds="${15:-0}"

    # score計算
    case "$status" in
      pass)
        # テスト+レビュー両方OK
        if [ -n "$review_score_final" ] && [ "$review_score_final" -ge 80 ] 2>/dev/null; then
          score="2.0"
        else
          score="1.0"
        fi
        ;;
      fixed)
        # テストfixed + レビューOK
        if [ -n "$review_score_final" ] && [ "$review_score_final" -ge 80 ] 2>/dev/null; then
          score="1.5"
        else
          score="1.0"
        fi
        ;;
      fail)   score="-0.5" ;;
      stalled) score="0.0" ;;
      *)      score="0.0" ;;
    esac

    # NULLable フィールド
    test_sid_sql="NULL"
    [ -n "$test_session_id" ] && test_sid_sql="$test_session_id"
    rev_init_sql="NULL"
    [ -n "$review_score_initial" ] && rev_init_sql="$review_score_initial"
    rev_final_sql="NULL"
    [ -n "$review_score_final" ] && rev_final_sql="$review_score_final"

    sqlite3 "$DB" "UPDATE dev_sessions SET
      status = '$(esc "$status")',
      phase = 'complete',
      files_changed = '$(esc "$files_changed")',
      lines_added = $lines_added,
      lines_removed = $lines_removed,
      test_session_id = $test_sid_sql,
      test_status = '$(esc "$test_status")',
      review_score_initial = $rev_init_sql,
      review_score_final = $rev_final_sql,
      review_iterations = $review_iterations,
      dis_solutions_used = '$(esc "$dis_solutions")',
      dis_feedback_used = '$(esc "$dis_feedback")',
      dis_patterns_used = '$(esc "$dis_patterns")',
      dis_new_feedback = '$(esc "$new_feedback")',
      score = $score,
      duration_seconds = $duration_seconds
      WHERE id = $id;"

    # pass/fixed: 参照したsolutionのsuccess_count加算
    if [ "$status" = "pass" ] || [ "$status" = "fixed" ]; then
      if [ -n "$dis_solutions" ] && [ "$dis_solutions" != "[]" ]; then
        sol_ids=$(echo "$dis_solutions" | python3 -c "import json,sys; [print(x) for x in json.load(sys.stdin)]" 2>/dev/null || true)
        for sol_id in $sol_ids; do
          sqlite3 "$DB" "UPDATE solutions SET success_count = success_count + 1, last_used = datetime('now') WHERE id = $sol_id;" 2>/dev/null || true
        done
      fi
    fi

    # new_feedbackがあればfeedbackテーブルに記録
    if [ -n "$new_feedback" ] && [ "$new_feedback" != "[]" ]; then
      project=$(sqlite3 "$DB" "SELECT project FROM dev_sessions WHERE id = $id;")
      echo "$new_feedback" | python3 -c "
import json, sys, sqlite3, os
DB = os.path.expanduser('~/.claude/intelligence/dev.db')
conn = sqlite3.connect(DB)
cur = conn.cursor()
project = '$project'
for fb in json.load(sys.stdin):
    cat = fb.get('category', 'general')
    wrong = fb.get('wrong', '')
    correct = fb.get('correct', '')
    cur.execute('''INSERT INTO feedback(category, wrong_approach, correct_approach, project, score, last_seen)
      VALUES(?, ?, ?, ?, 1.5, datetime('now'))''', (cat, wrong, correct, project))
conn.commit()
conn.close()
" 2>/dev/null || true
    fi

    echo "COMPLETED|$id|$status|$score"
    ;;

  lookup)
    project="${1:?lookup: <project> <requirement>}"
    requirement="${2:?}"

    # Helper: sqlite3 -json が空結果時に [] を返すようにする
    json_or_empty() { local r; r=$(sqlite3 -json "$DB" "$1" 2>/dev/null); echo "${r:-[]}"; }

    # 1) 同一projectの過去dev_sessions
    past_dev=$(json_or_empty "SELECT id, requirement, status, score, files_changed, test_status, review_score_final, duration_seconds
      FROM dev_sessions
      WHERE project = '$(esc "$project")'
        AND status IN ('pass', 'fixed', 'fail')
      ORDER BY score DESC, ts DESC
      LIMIT 5;")

    # 2) similarity.py でsolutions検索
    similar_solutions=$(python3 -c "
import sys
sys.path.insert(0, '$HOME/.claude/intelligence/scripts')
from similarity import find_similar
import json
results = find_similar('$(esc "$requirement")', threshold=0.3, limit=5)
print(json.dumps(results))
" 2>/dev/null || echo "[]")

    # 3) feedback テーブルから関連検索
    related_feedback=$(json_or_empty "SELECT id, category, wrong_approach, correct_approach, score
      FROM feedback
      WHERE (wrong_approach LIKE '%$(esc "$requirement")%'
        OR correct_approach LIKE '%$(esc "$requirement")%'
        OR category LIKE '%$(esc "$requirement")%')
        AND score > 0.5
      ORDER BY score DESC
      LIMIT 5;")

    # 4) patterns テーブルから関連検索
    related_patterns=$(json_or_empty "SELECT id, pattern, solution, score
      FROM patterns
      WHERE (pattern LIKE '%$(esc "$requirement")%'
        OR solution LIKE '%$(esc "$requirement")%')
        AND score > 0.5
      ORDER BY score DESC
      LIMIT 5;")

    # 5) test_sessions テーブルから関連検索
    related_tests=$(json_or_empty "SELECT id, perspective, test_type, status, score, error_pattern
      FROM test_sessions
      WHERE project = '$(esc "$project")'
        AND perspective LIKE '%$(esc "$requirement")%'
        AND status IN ('pass', 'fixed', 'fail')
      ORDER BY score DESC
      LIMIT 5;")

    # 6) questions テーブルから関連検索
    related_questions=$(json_or_empty "SELECT id, question, answer, status, score
      FROM questions
      WHERE (question LIKE '%$(esc "$requirement")%'
        OR context LIKE '%$(esc "$requirement")%'
        OR answer LIKE '%$(esc "$requirement")%')
        AND score > 0.5
      ORDER BY score DESC
      LIMIT 5;")

    cat <<EOF
{"past_dev_sessions": $past_dev, "related_solutions": $similar_solutions, "related_feedback": $related_feedback, "related_patterns": $related_patterns, "related_test_sessions": $related_tests, "related_questions": $related_questions}
EOF
    ;;

  *)
    echo "Unknown command: $CMD" >&2
    echo "Usage: record-dev-session.sh <start|update-phase|complete|lookup> ..." >&2
    exit 1
    ;;
esac
