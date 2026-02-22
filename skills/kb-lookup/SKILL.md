---
name: kb-lookup
description: Search past errors and solutions from the development knowledge base. Use when encountering build errors, test failures, type errors, or debugging issues to find previously resolved similar problems.
allowed-tools: Bash, Read, Grep
---

# Knowledge Base Lookup

エラー発生時に過去の解決策を検索するスキル。

## 手順

1. ユーザーから渡されたエラーメッセージ（または直前のBashエラー出力）を取得

2. SQLiteから直接マッチを検索:
```bash
sqlite3 ~/.claude/intelligence/dev.db "SELECT error_pattern, solution, score FROM solutions WHERE error_pattern LIKE '%<keyword>%' ORDER BY score DESC LIMIT 5;"
```

3. TF-IDF類似度検索で幅広いマッチを取得:
```bash
python3 ~/.claude/intelligence/scripts/similarity.py "<error_message>"
```

4. 結果を解析し、上位3件の解決策をスコア順で提示:
   - 各解決策のスコア・出現頻度・最終使用日時を表示
   - 具体的な修正手順を推奨

5. 解決策が見つからない場合:
   - 「新規エラーパターン」として報告
   - 汎用的なデバッグ手順を提案

6. 解決後のフィードバック:
   - 解決策が有効だった場合: `sqlite3 ~/.claude/intelligence/dev.db "UPDATE solutions SET success_count = success_count + 1, score = score + 1.0, last_used = datetime('now') WHERE id = <id>;"`
   - 解決策が無効だった場合: `sqlite3 ~/.claude/intelligence/dev.db "UPDATE solutions SET fail_count = fail_count + 1, score = score - 0.5 WHERE id = <id>;"`
