#!/bin/bash
# tri-review.sh — Stop Hook: Codex review + DIS統合
# 120s timeout 制限内で動作。Codex専用（Geminiなし = timeout安全）。
# DIS操作はバックグラウンドで実行。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/review-utils.sh"

CONFIG_FILE="$HOME/.claude/codex-review-config.json"
MIN_LINES=30
PASS_THRESHOLD=80

# 設定ファイル読み込み
if [ -f "$CONFIG_FILE" ]; then
  MIN_LINES=$(jq -r '.thresholds.min_lines_for_review // 30' "$CONFIG_FILE")
  PASS_THRESHOLD=$(jq -r '.scoring.pass_threshold // 80' "$CONFIG_FILE")
fi

# stdin から hook JSON を読み取り (cwd抽出)
HOOK_INPUT=$(cat)
CWD=$(echo "$HOOK_INPUT" | jq -r '.cwd // empty' 2>/dev/null || echo "")
if [ -n "$CWD" ] && [ -d "$CWD" ]; then
  cd "$CWD"
fi

# git リポジトリチェック
if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
  exit 0
fi

# 変更行数チェック
TOTAL=$(count_changed_lines)
if [ "$TOTAL" -lt "$MIN_LINES" ]; then
  exit 0
fi

PROJECT=$(get_project_name)
START_TIME=$(date +%s)

# ── レビュー実行 (Codex only, 90s timeout) ──
print_header "Codex Auto-Review" "Lines: ${TOTAL} | Threshold: ${PASS_THRESHOLD}/100"

REVIEW_OUTPUT=$(run_review "hook" 90) || {
  echo "Review skipped (Codex unavailable)"
  exit 0
}

# Claude adversarial は hook では使わない
if echo "$REVIEW_OUTPUT" | grep -q "__CLAUDE_ADVERSARIAL_NEEDED__"; then
  echo "Review skipped (no external reviewer available)"
  exit 0
fi

echo "$REVIEW_OUTPUT"

# ── スコア抽出 ──
SCORE_JSON=$(echo "$REVIEW_OUTPUT" | extract_score_json)
SCORE=$(echo "$SCORE_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['total_score'])")
CRITICAL=$(echo "$SCORE_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['critical'])")
HIGH=$(echo "$SCORE_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['high'])")
MEDIUM=$(echo "$SCORE_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['medium'])")
LOW=$(echo "$SCORE_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['low'])")
ISSUES_TOTAL=$(echo "$SCORE_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['issues_total'])")

# ── 結果判定 ──
if [ "$SCORE" -ge "$PASS_THRESHOLD" ] 2>/dev/null; then
  STATUS="pass"
  print_header "" ""
  print_result "$SCORE" "$PASS_THRESHOLD"
else
  STATUS="fail"

  # Issue 抽出
  ISSUES_JSON=$(echo "$REVIEW_OUTPUT" | extract_issues)

  # DIS操作 (バックグラウンド)
  {
    insert_review_events "$PROJECT" "$ISSUES_JSON" 2>/dev/null
    SOLUTIONS_JSON=$(lookup_review_solutions "$ISSUES_JSON" 2>/dev/null || echo "[]")
    write_review_queue "$ISSUES_JSON" "$SOLUTIONS_JSON" "$SCORE" "$PROJECT" 2>/dev/null
  } &

  print_header "" ""
  print_result "$SCORE" "$PASS_THRESHOLD"
  echo ""

  # 既知ソリューション表示
  SOLUTIONS_JSON=$(lookup_review_solutions "$ISSUES_JSON" 2>/dev/null || echo "[]")
  SOL_COUNT=$(echo "$SOLUTIONS_JSON" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
  if [ "$SOL_COUNT" -gt 0 ]; then
    echo "DIS: ${SOL_COUNT} known solution(s) found"
  fi
  echo ""
  echo "Run /review to fix issues (3-AI loop)"
fi

# ── DIS: review_sessions INSERT (バックグラウンド) ──
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
{
  insert_review_session "$PROJECT" "hook" "$SCORE" "$SCORE" \
    1 "[${SCORE}]" "$ISSUES_TOTAL" 0 \
    "$CRITICAL" "$HIGH" "$MEDIUM" "$LOW" \
    "$STATUS" "$REVIEW_MODELS" "$DURATION" 2>/dev/null
} &

# バックグラウンドジョブ完了待ち (最大5秒)
wait -n 2>/dev/null || true

exit 0
