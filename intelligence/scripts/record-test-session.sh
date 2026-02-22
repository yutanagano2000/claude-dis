#!/bin/bash
# DIS: テストセッションをSQLiteに記録。/test スキルから呼び出される。
# Usage:
#   record-test-session.sh start <project> <perspective> <test_type> [target_files_json] [test_file]
#   record-test-session.sh complete <id> <status> <pass_count> <fail_count> [iterations] [error_output] [error_pattern] [fix_history_json] [used_solutions_json] [duration_seconds] [coverage_before] [coverage_after]
#   record-test-session.sh lookup <project> <perspective>
set -euo pipefail

DB="$HOME/.claude/intelligence/dev.db"
CMD="${1:?Usage: record-test-session.sh <start|complete|lookup> ...}"
shift

esc() { echo "$1" | sed "s/'/''/g"; }
truncate_text() { echo "$1" | head -c 2000; }

case "$CMD" in
  start)
    project="${1:?start: <project> <perspective> <test_type>}"
    perspective="${2:?}"
    test_type="${3:?}"
    target_files="${4:-}"
    test_file="${5:-}"

    new_id=$(sqlite3 "$DB" "INSERT INTO test_sessions(project, perspective, test_type, target_files, test_file, status)
      VALUES(
        '$(esc "$project")',
        '$(esc "$perspective")',
        '$(esc "$test_type")',
        '$(esc "$target_files")',
        '$(esc "$test_file")',
        'running'
      );
      SELECT last_insert_rowid();")
    echo "STARTED|$new_id"
    ;;

  complete)
    id="${1:?complete: <id> <status> <pass_count> <fail_count>}"
    status="${2:?}"
    pass_count="${3:?}"
    fail_count="${4:?}"
    iterations="${5:-1}"
    error_output="${6:-}"
    error_pattern="${7:-}"
    fix_history="${8:-}"
    used_solutions="${9:-}"
    duration_seconds="${10:-0}"
    coverage_before="${11:-}"
    coverage_after="${12:-}"

    # truncate error_output
    error_output_trunc=$(truncate_text "$error_output")

    # score計算
    case "$status" in
      pass)   score="1.0" ;;
      fixed)  score="1.5" ;;
      fail)   score="-0.5" ;;
      *)      score="0.0" ;;
    esac

    # coverage カラム (NULLable)
    cov_before_sql="NULL"
    cov_after_sql="NULL"
    [ -n "$coverage_before" ] && cov_before_sql="$coverage_before"
    [ -n "$coverage_after" ] && cov_after_sql="$coverage_after"

    sqlite3 "$DB" "UPDATE test_sessions SET
      status = '$(esc "$status")',
      pass_count = $pass_count,
      fail_count = $fail_count,
      iterations = $iterations,
      error_output = '$(esc "$error_output_trunc")',
      error_pattern = '$(esc "$error_pattern")',
      fix_history = '$(esc "$fix_history")',
      score = $score,
      used_past_solutions = '$(esc "$used_solutions")',
      duration_seconds = $duration_seconds,
      coverage_before = $cov_before_sql,
      coverage_after = $cov_after_sql
      WHERE id = $id;"

    # pass/fixed: 参照したsolutionのsuccess_count加算
    if [ "$status" = "pass" ] || [ "$status" = "fixed" ]; then
      if [ -n "$used_solutions" ] && [ "$used_solutions" != "[]" ]; then
        sol_ids=$(echo "$used_solutions" | python3 -c "import json,sys; [print(x) for x in json.load(sys.stdin)]" 2>/dev/null || true)
        for sol_id in $sol_ids; do
          sqlite3 "$DB" "UPDATE solutions SET success_count = success_count + 1, last_used = datetime('now') WHERE id = $sol_id;" 2>/dev/null || true
        done
      fi
    fi

    # fail: error_pattern を solutions に新規記録
    if [ "$status" = "fail" ] && [ -n "$error_pattern" ]; then
      existing=$(sqlite3 "$DB" "SELECT id FROM solutions WHERE error_pattern = '$(esc "$error_pattern")' LIMIT 1;" 2>/dev/null)
      if [ -z "$existing" ]; then
        project=$(sqlite3 "$DB" "SELECT project FROM test_sessions WHERE id = $id;")
        sqlite3 "$DB" "INSERT INTO solutions(error_pattern, solution, project, score, last_used)
          VALUES(
            '$(esc "$error_pattern")',
            'Test failure: $(esc "$error_output_trunc" | head -c 200)',
            '$(esc "$project")',
            0.5,
            datetime('now')
          );"
      fi
    fi

    echo "COMPLETED|$id|$status|$score"
    ;;

  lookup)
    project="${1:?lookup: <project> <perspective>}"
    perspective="${2:?}"

    # 1) 同一project+perspectiveの過去セッション
    past_sessions=$(sqlite3 -json "$DB" "SELECT id, perspective, test_type, status, iterations, score, error_pattern, fix_history
      FROM test_sessions
      WHERE project = '$(esc "$project")'
        AND perspective LIKE '%$(esc "$perspective")%'
        AND status IN ('pass', 'fixed', 'fail')
      ORDER BY score DESC, ts DESC
      LIMIT 5;" 2>/dev/null || echo "[]")

    # 2) similarity.py でエラーパターン検索
    similar_json=$(python3 -c "
import sys
sys.path.insert(0, '$HOME/.claude/intelligence/scripts')
from similarity import find_similar
import json
results = find_similar('$perspective', threshold=0.3, limit=5)
print(json.dumps(results))
" 2>/dev/null || echo "[]")

    # JSON出力
    cat <<EOF
{"past_sessions": $past_sessions, "similar_solutions": $similar_json}
EOF
    ;;

  *)
    echo "Unknown command: $CMD" >&2
    echo "Usage: record-test-session.sh <start|complete|lookup> ..." >&2
    exit 1
    ;;
esac
