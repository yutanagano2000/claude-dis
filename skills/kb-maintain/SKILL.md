---
name: kb-maintain
description: Maintain the development knowledge base. Run analysis, merge similar solutions, apply time decay, promote high-scoring patterns, and generate intelligence reports.
disable-model-invocation: true
allowed-tools: Bash, Read, Write, Edit, Grep
---

# Knowledge Base Maintenance

知識ベースの分析・メンテナンス・昇格を実行するスキル。

## 手順

### Step 1: イベント集計
```bash
python3 ~/.claude/intelligence/scripts/aggregate.py
```
events テーブルのエラーを正規化し、solutions テーブルに集約。

### Step 2: 類似パターンマージ
```bash
python3 ~/.claude/intelligence/scripts/similarity.py --merge
```
TF-IDF類似度0.7以上のsolutionを統合し、スコアを加算。

### Step 3: スコア再計算（時間減衰）
```bash
python3 ~/.claude/intelligence/scripts/decay.py
```
λ=0.01 (半減期70日) の指数減衰を適用。score < 0.1 をアーカイブ。

### Step 4: レポート生成
```bash
python3 ~/.claude/intelligence/scripts/report.py
```
直近7日の統計、TOP 5エラーパターン、解決率、昇格候補を出力。

### Step 5: フィードバック昇格
```bash
python3 ~/.claude/intelligence/scripts/aggregate.py --promote-feedback
```
stability (= score * confirmation_count) >= 4 のフィードバックを patterns に自動昇格。

### Step 6: 昇格判断

レポートの「Promotion Candidates」セクションを確認し:

**solutions → patterns 昇格** (score >= 3.0 AND success_count >= 3):
```bash
sqlite3 ~/.claude/intelligence/dev.db "INSERT INTO patterns(pattern, description, solution, frequency, score, last_seen) SELECT error_pattern, 'Auto-promoted from solutions', solution, success_count, score * 1.5, last_used FROM solutions WHERE score >= 3.0 AND success_count >= 3 AND error_pattern NOT IN (SELECT pattern FROM patterns);"
```

**patterns → MEMORY.md 昇格提案** (score >= 5.0 AND frequency >= 5):
```bash
sqlite3 ~/.claude/intelligence/dev.db "SELECT pattern, description, solution, score, frequency FROM patterns WHERE score >= 5.0 AND frequency >= 5 AND promoted_to_memory = 0;"
```
該当パターンがあれば、MEMORY.mdに追記すべき内容をユーザーに提案。
承認後: `UPDATE patterns SET promoted_to_memory = 1 WHERE id = <id>;`

**patterns → .claude/rules/ 昇格提案** (プロジェクト固有で安定したパターン):
特定プロジェクトでscore >= 8.0 のパターンは、.claude/rules/ へのルール化を提案。

### Step 7: DB統計サマリー
```bash
sqlite3 ~/.claude/intelligence/dev.db "SELECT 'events' as tbl, COUNT(*) FROM events UNION ALL SELECT 'solutions', COUNT(*) FROM solutions UNION ALL SELECT 'patterns', COUNT(*) FROM patterns UNION ALL SELECT 'feedback', COUNT(*) FROM feedback UNION ALL SELECT 'sessions', COUNT(*) FROM sessions UNION ALL SELECT 'feeds', COUNT(*) FROM industry_feeds;"
```
