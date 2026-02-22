---
name: que
description: Record, search, and resolve development questions with DIS integration. Use when user invokes /que to ask a question, search past questions, or mark a question as resolved. Other skills reference questions via record-dev-session.sh lookup (related_questions field).
allowed-tools: Bash, Read, Grep
---

# Question Skill — DIS-Integrated Question Tracker

開発中の質問を永続化し、解決済み回答を他スキルから参照可能にする。

## Input Format

```
/que <質問>                          — 質問を記録
/que --search <キーワード>           — 過去の質問を検索
/que --resolve <id> <回答>           — 質問を解決済みにする
/que --list                          — 未解決質問の一覧
/que --list --all                    — 全質問の一覧（解決済み含む）
```

## Workflow

<que-skill>
Execute the following workflow when this skill is invoked.

### Input Parsing

Parse the input to determine the subcommand:

| Pattern | Subcommand |
|---------|-----------|
| `--search <query>` | search |
| `--resolve <id> <answer>` | resolve |
| `--list [--all]` | list |
| `<question text>` (default) | ask |

```bash
PROJECT=$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")
```

### Subcommand: ask

1. Record the question:
```bash
RESULT=$(~/.claude/intelligence/scripts/record-question.sh ask "<question>" "$PROJECT" "<context>" '<tags_json>')
```

Parse result: `INSERTED|<id>|<score>` or `UPDATED|<id>|<score>`

2. Automatically search for related past knowledge:
```bash
SEARCH=$(~/.claude/intelligence/scripts/record-question.sh search "<question>" "$PROJECT")
```

3. Display result:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Question Recorded (#<id>)
   質問: <question>
   プロジェクト: <project>
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

If related questions/solutions found:
```
   関連知見:
   - [Q#<id>] <past_question> → <answer> (score: <n>)
   - [S#<id>] <solution> (similarity: <n>)
```

4. **Context detection**: Use the current conversation context (recent errors, files being worked on) to auto-fill `context` field.

5. **Tag inference**: Auto-infer tags from question content:

| Keywords | Tag |
|----------|-----|
| API, endpoint, route, fetch | api |
| component, React, UI, render | frontend |
| DB, SQL, query, migration | database |
| test, Vitest, Playwright | testing |
| deploy, CI, build, Docker | infra |
| auth, login, token, session | auth |
| type, TypeScript, interface | typing |
| performance, slow, memory | performance |

### Subcommand: search

```bash
RESULT=$(~/.claude/intelligence/scripts/record-question.sh search "<query>" "$PROJECT")
```

Parse JSON and display:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Question Search: "<query>"
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Questions:
  #<id> [<status>] <question>
        → <answer or "未解決">
        (score: <n>, project: <p>)

Related Solutions:
  #<id> <error_pattern> → <solution>
        (score: <n>, similarity: <n>)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### Subcommand: resolve

```bash
~/.claude/intelligence/scripts/record-question.sh resolve <id> "<answer>"
```

Display:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Question Resolved (#<id>)
   回答: <answer>
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### Subcommand: list

```bash
# 未解決のみ
sqlite3 -json ~/.claude/intelligence/dev.db "SELECT id, question, status, score, project, ts FROM questions WHERE status = 'open' ORDER BY score DESC, ts DESC LIMIT 20;"

# --all: 全件
sqlite3 -json ~/.claude/intelligence/dev.db "SELECT id, question, answer, status, score, project, ts FROM questions ORDER BY ts DESC LIMIT 30;"
```

Display:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Open Questions (<n>件)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  #<id> <question> (score: <n>, <project>, <date>)
  #<id> <question> (score: <n>, <project>, <date>)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

</que-skill>

## Other Skills Integration

他スキルは以下の方法で questions テーブルを参照する:

1. **`/dev` (record-dev-session.sh lookup)**: `related_questions` フィールドで自動検索
2. **`/kb-lookup`**: similarity.py が solutions を検索する際、質問の answer も参照可能
3. **直接SQL**: `sqlite3 ~/.claude/intelligence/dev.db "SELECT question, answer FROM questions WHERE status='resolved' AND question LIKE '%keyword%';"`

## Constraints

- 質問テキストは2000文字以内に切り詰め
- 重複質問は score を加算して統合（同一 question + project）
- resolved 質問のみアーカイブ対象 (open は保持)
- タグは JSON 配列形式 (`["api", "auth"]`)
