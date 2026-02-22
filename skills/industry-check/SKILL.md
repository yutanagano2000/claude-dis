---
name: industry-check
description: Check latest AI industry updates and suggest improvements to development workflow. Analyzes unread entries from Anthropic, OpenAI, DeepMind, xAI, Cursor, Devin blogs and changelogs.
allowed-tools: Bash, Read, Write, Edit, Grep, WebFetch
---

# Industry Intelligence Check

AI業界の最新動向をチェックし、開発ワークフロー改善を提案するスキル。

## 手順

### Step 1: ソースデータ取得
```bash
python3 ~/.claude/intelligence/scripts/fetch_sources.py
```
Anthropic, OpenAI, DeepMind, xAI, Cursor, Devin のブログ/changelogを取得。

### Step 2: 未分析エントリ取得
```bash
sqlite3 ~/.claude/intelligence/dev.db "SELECT id, source, title, url, summary FROM industry_feeds WHERE analyzed = 0 ORDER BY ts DESC LIMIT 20;"
```

### Step 3: 各エントリを分析
未分析エントリごとに以下を判断:

1. **開発手法の革新があるか？**
   - 新しいコーディングパターンやベストプラクティス
   - パフォーマンス改善テクニック

2. **DIS設定に影響する変更があるか？**
   - Claude Code の新機能（hooks, skills, MCPの変更）
   - 推奨設定の変更

3. **ワークフロー改善の示唆があるか？**
   - テスト手法の改善
   - CI/CDパイプラインの最適化
   - 新ツールの導入推奨

重要な記事はWebFetchで詳細を取得して分析。

### Step 4: 分析結果の記録
```bash
# relevant=1 をセット（開発に関連するエントリ）
sqlite3 ~/.claude/intelligence/dev.db "UPDATE industry_feeds SET analyzed = 1, relevant = 1, action_taken = '<具体的なアクション>' WHERE id = <id>;"

# relevant=0 をセット（関連なし）
sqlite3 ~/.claude/intelligence/dev.db "UPDATE industry_feeds SET analyzed = 1 WHERE id = <id>;"
```

### Step 5: 更新提案出力
分析結果をまとめてユーザーに提示:
- 重要な更新のサマリー
- 推奨アクション（具体的な設定変更・ファイル更新）
- 優先度（高/中/低）

## 出力フォーマット
```
## 🔍 Industry Intelligence Report

### 重要な更新
1. [source] title — 影響と推奨アクション

### 推奨アクション
- [ ] 高: 具体的な変更内容
- [ ] 中: 具体的な変更内容
- [ ] 低: 具体的な変更内容

### 統計
- 取得エントリ: N件
- 開発関連: N件
- 要アクション: N件
```
