#!/bin/bash
# DIS: エラーイベントをSQLiteに記録 (PostToolUse Bash hook)
DB="$HOME/.claude/intelligence/dev.db"
[ ! -f "$DB" ] && exit 0

input=$(cat)
exit_code=$(echo "$input" | jq -r '.tool_result.exit_code // 0')
[ "$exit_code" = "0" ] && exit 0

cmd=$(echo "$input" | jq -r '.tool_input.command // ""')
# 短いコマンド（ls, pwd等）やgit系は無視
[ ${#cmd} -lt 5 ] && exit 0
echo "$cmd" | grep -qE '^(git |ls |pwd|echo |cd )' && exit 0

error=$(echo "$input" | jq -r '(.tool_result.stderr // .tool_result.stdout // "") | tostring' | head -c 2000)
[ -z "$error" ] && exit 0

cwd=$(echo "$input" | jq -r '.cwd // ""')
project=$(basename "$cwd")

# エラータイプを自動分類
type="unknown"
if echo "$error" | grep -qiE 'build|compile|module not found|cannot find'; then
  type="build_error"
elif echo "$error" | grep -qiE 'test|expect|assert|FAIL'; then
  type="test_failure"
elif echo "$error" | grep -qiE 'lint|eslint|prettier'; then
  type="lint_error"
elif echo "$error" | grep -qiE 'type|typescript|tsc|TS[0-9]'; then
  type="type_error"
fi

sqlite3 "$DB" "INSERT INTO events(type,cmd,error,cwd,project) VALUES(
  '$(echo "$type" | sed "s/'/''/g")',
  '$(echo "$cmd" | sed "s/'/''/g")',
  '$(echo "$error" | sed "s/'/''/g")',
  '$(echo "$cwd" | sed "s/'/''/g")',
  '$(echo "$project" | sed "s/'/''/g")'
);" 2>/dev/null

exit 0
