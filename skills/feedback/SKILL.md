---
name: feedback
description: Record user implementation feedback to the knowledge base. Use when the user invokes /feedback to log a coding correction or preference (e.g., "/feedback useEffectじゃなくてuseMemoにして").
allowed-tools: Bash, Read
---

# Feedback Recording

ユーザーの実装フィードバック（訂正・好み）をSQLiteに記録するスキル。

## 入力フォーマット

ユーザーは自由形式で入力する:
```
/feedback useEffectじゃなくてuseMemoにして（derived stateの計算）
/feedback コンポーネントは50行超えたら分割
/feedback このプロジェクトではReduxではなくZustandを使う
```

## 処理手順

### Step 1: フィードバックを構造化

ユーザーの入力から以下を抽出:
- **wrong_approach**: やめてほしいこと（例: "useEffect for derived state"）
- **correct_approach**: こうしてほしいこと（例: "useMemo for derived state"）
- **category**: 以下から最適なものを選択
  - `react_pattern` / `state_management` / `data_fetching`
  - `async_pattern` / `error_handling`
  - `code_style` / `naming` / `file_structure`
  - `architecture` / `dependency_policy`
  - `typing` / `testing_pattern`
  - `performance` / `security`
  - `general`
- **context**: 関連するファイル・コンポーネント（わかれば）
- **scope**: `project`（デフォルト）/ `user`（個人嗜好）/ `global`（普遍的ルール）

### Step 2: record-feedback.sh で記録

```bash
~/.claude/intelligence/scripts/record-feedback.sh \
  "<category>" \
  "<wrong_approach>" \
  "<correct_approach>" \
  "<context>" \
  "<project_name>" \
  "<scope>"
```

project_name は現在の作業ディレクトリから `basename` で取得。

### Step 3: 結果を報告

スクリプトの出力をパースして報告:
- `INSERTED|<id>|<category>|<score>|<count>` → 新規記録
- `UPDATED|<id>|<category>|<score>|<count>` → 既存エントリにスコア加算（重複検出）

出力例:
```
記録しました: [react_pattern] useEffect→useMemo (score=1.5, project=lepac)
```

重複時:
```
既存エントリを強化: [react_pattern] useEffect→useMemo (score=3.0, 確認回数=2, project=lepac)
```

### Step 4: 昇格チェック

`stability = score * confirmation_count` を計算:
- stability >= 4 → 「patterns テーブルへの昇格候補です。`/kb-maintain` で昇格処理できます」と通知
- stability < 4 → 通知なし

## 昇格パイプライン

```
/feedback → feedback table (Tier 2)
  ↓ stability >= 4
/kb-maintain → patterns table (Tier 3)
  ↓ score >= 5.0 && freq >= 5
/kb-maintain → MEMORY.md 提案 (Tier 4)
  ↓ プロジェクト固有で安定
/kb-maintain → .claude/rules/ 提案 (Tier 5)
```
