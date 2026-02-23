---
name: bug
description: Bug diagnosis and fix orchestrator with DIS integration. Use when user invokes /bug with a bug description (e.g., "/bug フォームバリデーションが効かない"). Runs triage→lookup→diagnose→fix→verify→record pipeline automatically.
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Task
---

# Bug Skill — DIS-Integrated Bug Diagnosis & Fix Orchestrator

症状からDIS知見検索 → 再現・診断 → 最小修正 → 検証 → DIS記録 → レポートを一気通貫で行う。

## Input Format

```
/bug <バグの説明>
/bug --severity critical 決済が二重計上される
/bug --skip-verify フォームバリデーションが効かない
```

## Flags

| Flag | Effect |
|------|--------|
| `--severity <level>` | critical/high/medium/low を明示指定 |
| `--skip-verify` | Phase 4 (検証) をスキップ |

## Workflow

<bug-skill>
Execute the following workflow when this skill is invoked.

### Step 0: Initialize (Triage)

Parse input: extract `<description>` and flags (`--severity`, `--skip-verify`).

```bash
PROJECT=$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")
START_TIME=$(date +%s)
```

Auto-detect severity if not specified:
- Keywords: `crash`, `データ消失`, `セキュリティ`, `本番` → critical
- Keywords: `エラー`, `失敗`, `動かない`, `ブロック` → high
- Keywords: `表示`, `レイアウト`, `警告` → low
- Default → medium

Start DIS session:
```bash
RESULT=$(~/.claude/intelligence/scripts/record-bug-session.sh start "$PROJECT" "<description>")
SESSION_ID=$(echo "$RESULT" | cut -d'|' -f2)
```

Initialize tracking:
- `DIAG_START = 0`
- `DIS_SOLUTIONS_USED = []`
- `DIS_BUGS_SIMILAR = []`
- `HYPOTHESIS_HISTORY = []`
- `BUG_CATEGORY = ""`
- `TEST_SESSION_ID = ""`
- `VERIFICATION_METHOD = ""`
- `VERIFICATION_RESULT = ""`

### Phase 1: DIS Lookup (過去知見検索)

```bash
~/.claude/intelligence/scripts/record-bug-session.sh update-phase "$SESSION_ID" "lookup"
DIS_CONTEXT=$(~/.claude/intelligence/scripts/record-bug-session.sh lookup "$PROJECT" "<description>")
```

Parse the JSON output:
- `past_bugs`: 過去の類似バグセッション
- `solutions`: similarity.py による類似エラー解決策
- `feedback`: bug_prevention を含むフィードバック
- `dev_sessions`: 関連する開発セッション
- `events`: 最近のエラーイベント

**Display DIS context** if any results found:
```
DIS Knowledge:
  - Past bugs: <n> found
  - Solutions: <n> relevant
  - Feedback: <n> entries (bug_prevention: <n>)
  - Dev sessions: <n> related
  - Recent events: <n> errors
```

Track referenced IDs in `DIS_SOLUTIONS_USED`, `DIS_BUGS_SIMILAR`.

If a past bug with same root cause exists (score > 1.5), display:
```
Similar bug found: #<id> (<status>)
  Root cause: <root_cause>
  Fix: <fix_description>
  Prevention: <prevention_suggestion>
```

### Phase 2: Reproduce & Diagnose (再現+根本原因分析)

```bash
~/.claude/intelligence/scripts/record-bug-session.sh update-phase "$SESSION_ID" "diagnose"
DIAG_START=$(date +%s)
```

1. **Locate relevant files** using Glob/Grep based on error messages and description
2. **Check recent changes** that may have introduced the bug:
```bash
git log --oneline -10 2>/dev/null || true
git diff HEAD~3 --stat 2>/dev/null || true
```
3. **Hypothesis-Evidence-Verdict cycle** (max 5 iterations):
   - Form a hypothesis about the root cause
   - Gather evidence (Read files, check logic, trace data flow)
   - Verdict: confirmed / rejected / needs-more-info
   - Record in `HYPOTHESIS_HISTORY`: `[{hypothesis, evidence, verdict}]`

4. **Auto-detect bug_category** from 11 categories:

| Category | Indicators |
|----------|-----------|
| `logic_error` | Wrong conditional, incorrect calculation |
| `type_error` | TypeScript type mismatch, wrong cast |
| `state_bug` | Stale state, missing update, race in useState |
| `race_condition` | Async timing, concurrent modification |
| `api_mismatch` | Request/response shape mismatch, wrong endpoint |
| `ui_regression` | Visual break, layout shift, missing render |
| `data_corruption` | Wrong transform, encoding issue |
| `config_error` | Wrong env var, misconfigured setting |
| `boundary_error` | Off-by-one, empty array, null edge case |
| `null_reference` | Undefined access, missing null check |
| `async_error` | Unhandled promise, missing await, stale closure |

5. Record diagnosis time:
```bash
DIAG_END=$(date +%s)
DIAGNOSIS_SECONDS=$((DIAG_END - DIAG_START))
```

Present diagnosis:
```
Diagnosis:
  Category: <bug_category>
  Root cause: <root_cause>
  Location: <root_cause_file>:<root_cause_line>
  Hypotheses tested: <n>
  Time: <diagnosis_seconds>s
```

### Phase 3: Fix (最小修正)

```bash
~/.claude/intelligence/scripts/record-bug-session.sh update-phase "$SESSION_ID" "fix"
```

**Rules:**
- Fix the root cause only (no refactoring, no "improvements")
- Determine `fix_type`: patch / refactor / config / revert
- If 3+ files need changes, confirm with user before proceeding

1. Apply minimal fix using Edit tool
2. Run type check:
```bash
npx tsc --noEmit 2>&1
```
3. On type errors: fix and retry (max 3 attempts)
4. Track `files_changed`, `lines_added`, `lines_removed`

### Phase 4: Verify (修正検証)

Skip if `--skip-verify` flag is set. Set `VERIFICATION_METHOD = "skipped"`.

```bash
~/.claude/intelligence/scripts/record-bug-session.sh update-phase "$SESSION_ID" "verify"
```

1. Check if existing tests cover the bug location:
```bash
# Find related test files
```

2. If tests exist:
   - Run them: `npx vitest run <test_file> --reporter=verbose 2>&1`
   - Set `VERIFICATION_METHOD = "test"`

3. If no tests exist:
   - Generate a minimal regression test for the bug
   - Run it
   - Set `VERIFICATION_METHOD = "both"`

4. Set `VERIFICATION_RESULT` (pass/fail)

If verification fails, report to user and set status to `fixed_unverified`.

### Phase 5: Record & Report (DIS記録+レポート)

```bash
~/.claude/intelligence/scripts/record-bug-session.sh update-phase "$SESSION_ID" "complete"
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
```

Determine overall status:
- `fixed`: Bug fixed AND verification passed
- `fixed_unverified`: Bug fixed but verification skipped/failed
- `diagnosed`: Root cause found but fix not applied (user chose not to)
- `workaround`: Temporary fix applied, root cause unresolved
- `fail`: Could not diagnose or fix

Generate `prevention_suggestion` based on bug_category:
- `null_reference` → "Optional chaining or null check at call site"
- `type_error` → "Stricter type constraints or runtime validation"
- `state_bug` → "Consolidate state into reducer or custom hook"
- `async_error` → "Add error boundary or await guard"
- etc. (generate contextually appropriate suggestion)

```bash
~/.claude/intelligence/scripts/record-bug-session.sh complete \
  "$SESSION_ID" "<status>" "<severity>" "<bug_category>" \
  '<reproduction_steps_json>' "<expected_behavior>" "<actual_behavior>" \
  "<error_output>" "<error_pattern>" \
  "<root_cause>" "<root_cause_file>" "<root_cause_line>" \
  '<hypothesis_history_json>' "<fix_description>" \
  '<files_changed_json>' "$LINES_ADDED" "$LINES_REMOVED" "<fix_type>" \
  "$TEST_SESSION_ID" "<verification_method>" "<verification_result>" \
  '<dis_solutions_json>' '<dis_bugs_similar_json>' \
  "$RELATED_DEV_SESSION_ID" "$DURATION" "$DIAGNOSIS_SECONDS" \
  "<prevention_suggestion>"
```

Run aggregation:
```bash
python3 ~/.claude/intelligence/scripts/aggregate.py 2>/dev/null || true
```

Output the final report:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Bug Fixed
   説明: <description>
   状態: <FIXED|FIXED_UNVERIFIED|DIAGNOSED|WORKAROUND|FAIL>
   深刻度: <severity> | カテゴリ: <bug_category>
   根本原因: <root_cause> (<root_cause_file>:<line>)
   修正: <fix_description> (<fix_type>)
   変更: <n>ファイル (+<add>/-<del>)
   検証: <pass|fail|skipped> (<verification_method>)
   時間: 診断<n>秒 / 合計<n>秒
   DIS: <n> solutions参照, <n> past bugs参照
   予防策: <prevention_suggestion>
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

If failed, include:
```
   未解決:
   - <description of unresolved issue>
   推奨:
   - 手動で再現手順を確認
   - `/feedback` で学びを記録
   - `/dev` で関連機能を再実装
```

</bug-skill>

## Constraints

- Phase 2 (Diagnose) では仮説サイクル最大5回
- Phase 3 (Fix) では型チェック最大3回リトライ
- Phase 3 (Fix) では根本原因のみ修正、リファクタリング禁止
- Phase 3 (Fix) で3ファイル超の変更時はユーザー確認
- error_output は2000文字に切り詰めてDISに記録
- 各Phaseの開始時に `update-phase` を呼び出してセッションを追跡する
