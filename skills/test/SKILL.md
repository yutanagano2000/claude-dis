---
name: test
description: Generate, run, and auto-fix tests with DIS integration. Use when the user invokes /test with a test perspective (e.g., "/test バリデーション計算が正しいか"). Estimates test type, generates tests, runs them with a retry loop, and records results to the knowledge base.
allowed-tools: Bash, Read, Write, Edit, Glob, Grep
---

# Test Skill — DIS-Integrated Test Automation

テスト観点から対象ファイル推定 → テスト生成 → 実行 → 再帰修正 → DIS記録を一気通貫で行う。

## 入力フォーマット

```
/test <テスト観点>
/test バリデーション計算が正しいか
/test ログインAPIが401を返すか
/test 画面遷移フローが正常か
```

## ワークフロー

<test-skill>
Execute the following workflow when this skill is invoked.

### Step 1: 観点解析

ユーザー入力 `<perspective>` から以下を判定:

**test_type 推定ルール:**

| キーワード | タイプ |
|-----------|--------|
| 画面, リダイレクト, E2E, ブラウザ, フロー, ナビゲーション | e2e |
| API, route, エンドポイント, fetch, POST, GET, handler | integration |
| それ以外 (計算, バリデーション, hook, util, 変換, フォーマット) | unit |

**対象ファイル特定:**
1. perspective のキーワードで Glob/Grep を使い関連ファイルを検索
2. プロジェクトの src/ ディレクトリ構造を確認
3. 既存テストファイルの有無を確認 (`*.test.ts`, `*.test.tsx`, `*.spec.ts`)

**プロジェクト情報取得:**
```bash
PROJECT=$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")
```

### Step 2: DIS検索

過去のテストセッションと類似解決策を検索:

```bash
~/.claude/intelligence/scripts/record-test-session.sh lookup "$PROJECT" "<perspective>"
```

出力JSONをパースし:
- `past_sessions`: 過去の同種テストの結果・エラーパターン・修正履歴
- `similar_solutions`: 類似エラーの解決策

これらをテスト生成のコンテキストとして活用する。

### Step 2.5: DQS Baseline

Measure quality of target files before test generation:
```bash
DQS_BASELINE=$(python3 ~/.claude/intelligence/scripts/measure-quality.py <target_file_or_dir> --project "$PROJECT" --json 2>/dev/null || echo "[]")
```
Parse average DQS as `DQS_BEFORE`.

### Step 3: DISセッション開始 + テスト生成

```bash
RESULT=$(~/.claude/intelligence/scripts/record-test-session.sh start "$PROJECT" "<perspective>" "<test_type>" '<target_files_json>' "<test_file>")
SESSION_ID=$(echo "$RESULT" | cut -d'|' -f2)
START_TIME=$(date +%s)
```

テストコード生成ルール:
- テストフレームワーク: Vitest (unit/integration), Playwright (e2e)
- 既存テストファイルがあれば追記、なければ新規作成
- DIS過去知見があればコンテキストに注入（既知エラーの回避策など）
- AAA パターン (Arrange/Act/Assert) を使用
- テスト対象ファイルと同階層に `__tests__/` または `.test.ts` 配置

### Step 4: テスト実行

```bash
# unit / integration
npx vitest run <test_file> --reporter=verbose 2>&1

# e2e
npx playwright test <test_file> --reporter=list 2>&1
```

実行結果からパース:
- `pass_count`: 成功テスト数
- `fail_count`: 失敗テスト数
- `error_output`: エラー出力 (先頭2000文字)

### Step 5: 再帰修正ループ (最大3回)

**ループ条件:** `fail_count > 0 && iteration < 3`

**エラー種別と修正対象の判定:**

| エラー種別 | 修正対象 |
|-----------|----------|
| TypeError, Cannot find module, mock設定不備 | テスト側を修正 |
| Expected X received Y (期待値が仕様的に正しい場合) | ユーザーに確認 (実装バグの可能性) |
| Timeout, ECONNREFUSED | 環境/モック設定をテスト側で修正 |
| SyntaxError, import エラー | テスト側を修正 |

各イテレーション:
1. エラー出力を分析
2. fix_history に `{iteration, error, fix, result}` を追記
3. テストコードを修正 (Edit tool)
4. 再実行

**重要:** 実装側のバグが疑われる場合は修正せず、ユーザーに報告して確認を取る。

### Step 6: DIS記録

```bash
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

~/.claude/intelligence/scripts/record-test-session.sh complete \
  "$SESSION_ID" \
  "<status>" \
  "$PASS_COUNT" \
  "$FAIL_COUNT" \
  "$ITERATION" \
  "<error_output>" \
  "<error_pattern>" \
  '<fix_history_json>' \
  '<used_solutions_json>' \
  "$DURATION" \
  "<coverage_before>" \
  "<coverage_after>"
```

**status 判定:**
- 全テスト初回パス → `pass`
- リトライで全テストパス → `fixed`
- 3回リトライ後も失敗あり → `fail`

### Step 6.5: DQS After + Self-Improvement

Measure quality after test code is written:
```bash
DQS_AFTER_JSON=$(python3 ~/.claude/intelligence/scripts/measure-quality.py <target_file_or_dir> --project "$PROJECT" --json 2>/dev/null || echo "[]")
```
Calculate `DQS_AFTER` and `DQS_DELTA`. Run self-improvement suggestions:
```bash
python3 ~/.claude/intelligence/scripts/self-improve.py suggest "$PROJECT" 2>/dev/null || true
```

### Step 7: レポート出力

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Test Complete
   観点: <perspective>
   タイプ: <unit|integration|e2e>
   結果: <PASS|FAIL> (iterations: <n>/3)
   テスト: <pass>/<total> passed
   カバレッジ: <before>% → <after>%
   DQS: <before> → <after> (delta: <delta>)
   DIS: <n> solutions参照, <n> 新規記録
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

失敗時は追加情報:
```
   未解決エラー:
   - <error_pattern>
   推奨アクション:
   - 実装側の修正を検討 (`/feedback` で記録推奨)
```

</test-skill>

## 制約

- テスト側のみ修正する。実装コードは変更しない（バグ疑い時はユーザーに報告）
- 最大リトライ3回でループを必ず終了する
- error_output は2000文字に切り詰めてDISに記録する
- テストファイルは500行を超えないように分割する
