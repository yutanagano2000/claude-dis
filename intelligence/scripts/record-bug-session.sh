#!/bin/bash
# DIS: バグセッションをSQLiteに記録。/bug スキルから呼び出される。
# Usage:
#   record-bug-session.sh start <project> <description>
#   record-bug-session.sh update-phase <id> <phase>
#   record-bug-session.sh complete <id> <status> [severity] [bug_category] [reproduction_steps] [expected_behavior] [actual_behavior] [error_output] [error_pattern] [root_cause] [root_cause_file] [root_cause_line] [hypothesis_history] [fix_description] [files_changed] [lines_added] [lines_removed] [fix_type] [test_session_id] [verification_method] [verification_result] [dis_solutions_used] [dis_bugs_similar] [related_dev_session_id] [duration_seconds] [diagnosis_seconds] [prevention_suggestion]
#   record-bug-session.sh lookup <project> <description>
set -euo pipefail

DB="$HOME/.claude/intelligence/dev.db"
CMD="${1:?Usage: record-bug-session.sh <start|update-phase|complete|lookup> ...}"
shift

esc() { echo "$1" | sed "s/'/''/g"; }
truncate_2k() { echo "$1" | head -c 2000; }

case "$CMD" in
  start)
    project="${1:?start: <project> <description>}"
    description="${2:?}"

    new_id=$(sqlite3 "$DB" "INSERT INTO bug_sessions(project, description, phase, status)
      VALUES(
        '$(esc "$project")',
        '$(esc "$description")',
        'triage',
        'running'
      );
      SELECT last_insert_rowid();")
    echo "STARTED|$new_id"
    ;;

  update-phase)
    id="${1:?update-phase: <id> <phase>}"
    phase="${2:?}"

    sqlite3 "$DB" "UPDATE bug_sessions SET phase = '$(esc "$phase")' WHERE id = $id;"
    echo "UPDATED|$id|$phase"
    ;;

  complete)
    id="${1:?complete: <id> <status>}"
    status="${2:?}"
    severity="${3:-medium}"
    bug_category="${4:-}"
    reproduction_steps="${5:-}"
    expected_behavior="${6:-}"
    actual_behavior="${7:-}"
    error_output_raw="${8:-}"
    error_pattern="${9:-}"
    root_cause="${10:-}"
    root_cause_file="${11:-}"
    root_cause_line="${12:-0}"
    hypothesis_history="${13:-}"
    fix_description="${14:-}"
    files_changed="${15:-}"
    lines_added="${16:-0}"
    lines_removed="${17:-0}"
    fix_type="${18:-}"
    test_session_id="${19:-}"
    verification_method="${20:-}"
    verification_result="${21:-}"
    dis_solutions="${22:-}"
    dis_bugs_similar="${23:-}"
    related_dev_session_id="${24:-}"
    duration_seconds="${25:-0}"
    diagnosis_seconds="${26:-0}"
    prevention_suggestion="${27:-}"

    # error_output を2000文字に切り詰め
    error_output=$(truncate_2k "$error_output_raw")

    # スコア計算
    case "$status" in
      fixed)
        case "$severity" in
          critical) score="2.5" ;;
          high)     score="2.0" ;;
          *)        score="2.0" ;;
        esac
        ;;
      fixed_unverified) score="1.0" ;;
      diagnosed)        score="1.5" ;;
      workaround)       score="0.5" ;;
      fail)             score="-0.5" ;;
      *)                score="0.0" ;;
    esac

    # NULLable フィールド
    test_sid_sql="NULL"
    [ -n "$test_session_id" ] && test_sid_sql="$test_session_id"
    root_line_sql="NULL"
    [ "$root_cause_line" != "0" ] && root_line_sql="$root_cause_line"
    related_dev_sql="NULL"
    [ -n "$related_dev_session_id" ] && related_dev_sql="$related_dev_session_id"

    sqlite3 "$DB" "UPDATE bug_sessions SET
      status = '$(esc "$status")',
      phase = 'complete',
      severity = '$(esc "$severity")',
      bug_category = '$(esc "$bug_category")',
      reproduction_steps = '$(esc "$reproduction_steps")',
      expected_behavior = '$(esc "$expected_behavior")',
      actual_behavior = '$(esc "$actual_behavior")',
      error_output = '$(esc "$error_output")',
      error_pattern = '$(esc "$error_pattern")',
      root_cause = '$(esc "$root_cause")',
      root_cause_file = '$(esc "$root_cause_file")',
      root_cause_line = $root_line_sql,
      hypothesis_history = '$(esc "$hypothesis_history")',
      fix_description = '$(esc "$fix_description")',
      files_changed = '$(esc "$files_changed")',
      lines_added = $lines_added,
      lines_removed = $lines_removed,
      fix_type = '$(esc "$fix_type")',
      test_session_id = $test_sid_sql,
      verification_method = '$(esc "$verification_method")',
      verification_result = '$(esc "$verification_result")',
      dis_solutions_used = '$(esc "$dis_solutions")',
      dis_bugs_similar = '$(esc "$dis_bugs_similar")',
      related_dev_session_id = $related_dev_sql,
      score = $score,
      duration_seconds = $duration_seconds,
      diagnosis_seconds = $diagnosis_seconds,
      prevention_suggestion = '$(esc "$prevention_suggestion")'
      WHERE id = $id;"

    # DIS自動連携: fixed/diagnosed の場合
    if [ "$status" = "fixed" ] || [ "$status" = "diagnosed" ]; then
      project=$(sqlite3 "$DB" "SELECT project FROM bug_sessions WHERE id = $id;")

      # solutions INSERT: error_pattern → fix_description
      if [ -n "$error_pattern" ] && [ -n "$fix_description" ]; then
        sqlite3 "$DB" "INSERT INTO solutions(error_pattern, solution, files, project, score, last_used)
          VALUES(
            '$(esc "$error_pattern")',
            '[bug-fix] $(esc "$fix_description")',
            '$(esc "$files_changed")',
            '$(esc "$project")',
            1.0,
            datetime('now')
          );" 2>/dev/null || true
      fi

      # solutions UPDATE: 参照したsolutionのsuccess_count加算
      if [ -n "$dis_solutions" ] && [ "$dis_solutions" != "[]" ]; then
        sol_ids=$(echo "$dis_solutions" | python3 -c "import json,sys; [print(x) for x in json.load(sys.stdin)]" 2>/dev/null || true)
        for sol_id in $sol_ids; do
          sqlite3 "$DB" "UPDATE solutions SET success_count = success_count + 1, last_used = datetime('now') WHERE id = $sol_id;" 2>/dev/null || true
        done
      fi

      # feedback INSERT: prevention_suggestion → bug_prevention
      if [ -n "$prevention_suggestion" ]; then
        sqlite3 "$DB" "INSERT INTO feedback(category, wrong_approach, correct_approach, project, score, last_seen)
          VALUES(
            'bug_prevention',
            '$(esc "$root_cause")',
            '$(esc "$prevention_suggestion")',
            '$(esc "$project")',
            1.5,
            datetime('now')
          );" 2>/dev/null || true
      fi
    fi

    echo "COMPLETED|$id|$status|$score"
    ;;

  lookup)
    project="${1:?lookup: <project> <description>}"
    description="${2:?}"

    # Helper: sqlite3 -json が空結果時に [] を返すようにする
    json_or_empty() { local r; r=$(sqlite3 -json "$DB" "$1" 2>/dev/null); echo "${r:-[]}"; }

    # 1) 同一projectの過去bug_sessions
    past_bugs=$(json_or_empty "SELECT id, description, status, score, severity, bug_category, root_cause, root_cause_file, fix_description, prevention_suggestion
      FROM bug_sessions
      WHERE project = '$(esc "$project")'
        AND status IN ('fixed', 'fixed_unverified', 'diagnosed', 'workaround', 'fail')
      ORDER BY score DESC, ts DESC
      LIMIT 5;")

    # 2) similarity.py でsolutions検索
    similar_solutions=$(python3 -c "
import sys
sys.path.insert(0, '$HOME/.claude/intelligence/scripts')
from similarity import find_similar
import json
results = find_similar('$(esc "$description")', threshold=0.3, limit=5)
print(json.dumps(results))
" 2>/dev/null || echo "[]")

    # 3) feedback テーブルから関連検索
    related_feedback=$(json_or_empty "SELECT id, category, wrong_approach, correct_approach, score
      FROM feedback
      WHERE (wrong_approach LIKE '%$(esc "$description")%'
        OR correct_approach LIKE '%$(esc "$description")%'
        OR category LIKE '%$(esc "$description")%'
        OR category = 'bug_prevention')
        AND score > 0.5
      ORDER BY score DESC
      LIMIT 5;")

    # 4) dev_sessions テーブルから関連検索
    related_dev=$(json_or_empty "SELECT id, requirement, status, score, files_changed
      FROM dev_sessions
      WHERE project = '$(esc "$project")'
        AND (requirement LIKE '%$(esc "$description")%'
          OR files_changed LIKE '%$(esc "$description")%')
      ORDER BY score DESC, ts DESC
      LIMIT 5;")

    # 5) events テーブルから最近のエラー
    recent_events=$(json_or_empty "SELECT id, type, error, cwd
      FROM events
      WHERE project = '$(esc "$project")'
        AND error IS NOT NULL
        AND error != ''
      ORDER BY ts DESC
      LIMIT 5;")

    cat <<EOF
{"past_bugs": $past_bugs, "solutions": $similar_solutions, "feedback": $related_feedback, "dev_sessions": $related_dev, "events": $recent_events}
EOF
    ;;

  *)
    echo "Unknown command: $CMD" >&2
    echo "Usage: record-bug-session.sh <start|update-phase|complete|lookup> ..." >&2
    exit 1
    ;;
esac
