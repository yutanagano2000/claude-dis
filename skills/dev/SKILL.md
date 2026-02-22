---
name: dev
description: Full development orchestrator with DIS integration. Use when user invokes /dev with a requirement (e.g., "/dev バリデーション関数を追加"). Runs prep→design→implement→test→review→record→report pipeline automatically.
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Task
---

# Dev Skill — DIS-Integrated Development Orchestrator

要件からDIS知見検索 → 設計 → 実装 → テスト → レビュー → DIS記録 → レポートを一気通貫で行う。

## Input Format

```
/dev <要件>
/dev バリデーション関数を追加
/dev ログインAPIのエラーハンドリングを改善
/dev --no-test ドキュメントコメントを追加
/dev --no-review 型定義を修正
/dev --test-only ユーザー登録のテストを追加
```

## Flags

| Flag | Effect |
|------|--------|
| `--no-test` | Phase 4 (テスト) をスキップ |
| `--no-review` | Phase 5 (レビュー) をスキップ |
| `--test-only` | Phase 3 (実装) をスキップ、テスト生成のみ |

## Workflow

<dev-skill>
Execute the following workflow when this skill is invoked.

### Step 0: Initialize

Parse input: extract `<requirement>` and flags (`--no-test`, `--no-review`, `--test-only`).

```bash
PROJECT=$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")
START_TIME=$(date +%s)
```

Start DIS session:
```bash
RESULT=$(~/.claude/intelligence/scripts/record-dev-session.sh start "$PROJECT" "<requirement>")
SESSION_ID=$(echo "$RESULT" | cut -d'|' -f2)
```

Initialize tracking:
- `ITERATION = 0`
- `MAX_REVIEW_RETRIES = 2`
- `DIS_SOLUTIONS_USED = []`
- `DIS_FEEDBACK_USED = []`
- `DIS_PATTERNS_USED = []`
- `DIS_NEW_FEEDBACK = []`
- `TEST_SESSION_ID = ""`
- `TEST_STATUS = "skipped"`
- `REVIEW_SCORE_INITIAL = ""`
- `REVIEW_SCORE_FINAL = ""`
- `REVIEW_ITERATIONS = 0`
- `DQS_BEFORE = ""`
- `DQS_AFTER = ""`

### Phase 0: Baseline Measurement (DQS計測)

Measure current quality of target files before changes:
```bash
DQS_BASELINE=$(python3 ~/.claude/intelligence/scripts/measure-quality.py --diff --project "$PROJECT" --json 2>/dev/null || echo "[]")
```

If target files are known, measure them directly. Parse average DQS and store as `DQS_BEFORE`.

Display baseline if available:
```
Baseline DQS: <avg_dqs> [<grade>]
  CDI=<n>  SE=<n>  CLS=<n>  CRS=<n>
```

### Phase 1: DIS Prep (過去知見の全量検索)

```bash
~/.claude/intelligence/scripts/record-dev-session.sh update-phase "$SESSION_ID" "prep"
DIS_CONTEXT=$(~/.claude/intelligence/scripts/record-dev-session.sh lookup "$PROJECT" "<requirement>")
```

Parse the JSON output:
- `past_dev_sessions`: 過去の同種開発セッション（成功/失敗パターン）
- `related_solutions`: similarity.py による類似エラー解決策
- `related_feedback`: カテゴリ別の実装フィードバック
- `related_patterns`: 昇格済みパターン
- `related_test_sessions`: 過去テスト結果

**Display DIS context** if any results found:
```
DIS Knowledge:
  - Past sessions: <n> found
  - Solutions: <n> relevant
  - Feedback: <n> entries
  - Patterns: <n> matched
  - Test history: <n> sessions
```

Track referenced IDs in `DIS_SOLUTIONS_USED`, `DIS_FEEDBACK_USED`, `DIS_PATTERNS_USED`.

### Phase 2: Design (設計 + 影響範囲特定)

```bash
~/.claude/intelligence/scripts/record-dev-session.sh update-phase "$SESSION_ID" "design"
```

1. Analyze the requirement and identify affected files using Glob/Grep
2. Incorporate DIS knowledge into approach decisions:
   - Avoid patterns that failed in past sessions
   - Prefer approaches that succeeded (high-score solutions)
   - Apply feedback corrections (wrong_approach → correct_approach)
3. Present design to user:

```
Design:
  Approach: <brief description>
  Files to modify:
  - <file1> — <what changes>
  - <file2> — <what changes>
  DIS insights applied:
  - <insight from past session/feedback/pattern>
```

If `--test-only`, skip to Phase 4.

### Phase 3: Implement (コード生成/修正)

```bash
~/.claude/intelligence/scripts/record-dev-session.sh update-phase "$SESSION_ID" "implement"
```

1. Apply code changes using Edit/Write tools
2. Run type check:
```bash
npx tsc --noEmit 2>&1
```
3. On type errors: analyze error, search DIS for known fix, apply correction (max 3 attempts)
4. Track `files_changed`, `lines_added`, `lines_removed`

On type error retry loop:
- Parse error message
- Check DIS solutions for similar errors
- Apply fix
- Re-run typecheck
- If 3 failures, report to user and continue

### Phase 3.5: Quality Gate (DQS検証)

Measure quality after implementation changes:
```bash
DQS_AFTER_JSON=$(python3 ~/.claude/intelligence/scripts/measure-quality.py --diff --project "$PROJECT" --json 2>/dev/null || echo "[]")
```

Calculate `DQS_AFTER` (average of changed files) and `DQS_DELTA = DQS_AFTER - DQS_BEFORE`.

**Quality Gate rules:**
- `DQS_DELTA < -0.05` → Display warning, suggest auto-refactoring of degraded files
- `CLS > 15` on any function → Suggest function splitting
- `max_nesting > 4` → Suggest flattening

If quality degradation detected:
```
Quality Gate WARNING:
  DQS: <before> → <after> (delta: <delta>)
  Issues:
  - <file>: CLS=<n> > 15 (split function recommended)
  - <file>: nesting=<n> > 4 (flatten recommended)
```

Apply automatic fixes for CLS/nesting issues if straightforward, then re-measure.

### Phase 4: Test (内包 — /test ワークフロー)

Skip if `--no-test` flag is set. Set `TEST_STATUS = "skipped"`.

```bash
~/.claude/intelligence/scripts/record-dev-session.sh update-phase "$SESSION_ID" "test"
```

**Test type estimation** (same rules as /test skill):

| Keywords | Type |
|----------|------|
| 画面, リダイレクト, E2E, ブラウザ, フロー | e2e |
| API, route, エンドポイント, fetch, handler | integration |
| Default | unit |

**Execute test workflow:**
1. Start test session:
```bash
TEST_RESULT=$(~/.claude/intelligence/scripts/record-test-session.sh start "$PROJECT" "<requirement>" "<test_type>" '<files_changed_json>' "<test_file>")
TEST_SESSION_ID=$(echo "$TEST_RESULT" | cut -d'|' -f2)
```

2. Generate tests based on changed files (Vitest for unit/integration, Playwright for e2e)
3. Run tests:
```bash
# unit/integration
npx vitest run <test_file> --reporter=verbose 2>&1

# e2e
npx playwright test <test_file> --reporter=list 2>&1
```

4. **Retry loop** (max 3 iterations):
   - Parse error output
   - Fix test code only (never modify implementation in this phase)
   - Re-run
   - Track fix_history: `[{iteration, error, fix, result}]`

5. Complete test session:
```bash
TEST_END=$(date +%s)
TEST_DURATION=$((TEST_END - TEST_START))
~/.claude/intelligence/scripts/record-test-session.sh complete \
  "$TEST_SESSION_ID" "<status>" "$PASS_COUNT" "$FAIL_COUNT" \
  "$ITERATION" "<error_output>" "<error_pattern>" \
  '<fix_history_json>' '<used_solutions_json>' "$TEST_DURATION"
```

6. Set `TEST_STATUS` (pass/fixed/fail)

**Important:** If implementation bugs are suspected, report to user rather than modifying implementation code.

### Phase 5: Review (内包 — セルフレビュー)

Skip if `--no-review` flag is set. Set `REVIEW_SCORE_INITIAL = ""`.

```bash
~/.claude/intelligence/scripts/record-dev-session.sh update-phase "$SESSION_ID" "review"
```

**Execute review workflow using review-utils.sh:**
```bash
source ~/.claude/hooks/lib/review-utils.sh
REVIEW_OUTPUT=$(run_review "skill" 90)
SCORE_JSON=$(echo "$REVIEW_OUTPUT" | extract_score_json)
```

Parse score and set `REVIEW_SCORE_INITIAL`.

**Review-fix loop** (max `MAX_REVIEW_RETRIES` = 2):

If score < 80:
1. Extract issues from review output
2. Fix CRITICAL → HIGH → MEDIUM issues
3. Re-run review
4. Track `REVIEW_ITERATIONS`

Set `REVIEW_SCORE_FINAL`.

**If score stays < 80 after retries:** continue to Phase 6 (don't block the flow).

### Phase 6: Record (DIS永続化)

```bash
~/.claude/intelligence/scripts/record-dev-session.sh update-phase "$SESSION_ID" "complete"
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
```

Determine overall status:
- `pass`: Tests passed (or skipped) AND review >= 80 (or skipped)
- `fixed`: Tests needed retries but eventually passed
- `fail`: Tests failed after all retries
- `stalled`: User interrupted or unresolvable issue

```bash
~/.claude/intelligence/scripts/record-dev-session.sh complete \
  "$SESSION_ID" "<status>" '<files_changed_json>' \
  "$LINES_ADDED" "$LINES_REMOVED" \
  "$TEST_SESSION_ID" "<test_status>" \
  "$REVIEW_SCORE_INITIAL" "$REVIEW_SCORE_FINAL" "$REVIEW_ITERATIONS" \
  '<dis_solutions_json>' '<dis_feedback_json>' '<dis_patterns_json>' \
  '<new_feedback_json>' "$DURATION"
```

Run aggregation and RL reward:
```bash
python3 ~/.claude/intelligence/scripts/aggregate.py 2>/dev/null || true

# RL Reward計算
RL_RESULT=$(python3 ~/.claude/intelligence/scripts/self-improve.py reward "$SESSION_ID" 2>/dev/null || echo "{}")
```

Update dev_sessions with DQS data:
```bash
sqlite3 ~/.claude/intelligence/dev.db "UPDATE dev_sessions SET dqs_before=$DQS_BEFORE, dqs_after=$DQS_AFTER, dqs_delta=$DQS_DELTA WHERE id=$SESSION_ID;"
```

### Phase 7: Report (統合レポート)

Output the final report:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Dev Complete
   要件: <requirement>
   状態: <PASS|FIXED|FAIL|STALLED>
   変更: <n>ファイル (+<add>/-<del>行)
   テスト: <pass|fixed|fail|skipped> (<pass>/<total>)
   レビュー: <initial> → <final> (iterations: <n>)
   DQS: <before> → <after> (delta: <delta>) [<grade>]
   DRS: <drs> (test=<t> review=<r> entropy=<e> history=<h>)
   DIS: <n> solutions参照, <n> feedback参照, <n> 新規記録
   所要時間: <duration>秒
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

If quality degraded (DQS_DELTA < 0):
```
   Quality Warning:
   - DQS decreased by <delta>
   - Run: python3 self-improve.py suggest <project>
```

If failed, include:
```
   未解決:
   - <description of unresolved issue>
   推奨:
   - `/feedback` で学びを記録
   - 手動で修正後 `/test` で再検証
```

</dev-skill>

## Constraints

- Phase 3 (Implement) では型チェック最大3回リトライ
- Phase 4 (Test) ではテスト最大3回リトライ、実装コード変更禁止
- Phase 5 (Review) ではレビュー修正最大2回リトライ
- error_output は2000文字に切り詰めてDISに記録
- ファイルは500行を超えないように分割する
- 各Phaseの開始時に `update-phase` を呼び出してセッションを追跡する
