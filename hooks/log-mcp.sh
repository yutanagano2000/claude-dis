#!/bin/bash
LOG_FILE=~/.claude/logs/mcp-usage.log
mkdir -p ~/.claude/logs

input=$(cat)
tool=$(echo "$input" | jq -r '.tool_name')
ts=$(date '+%Y-%m-%d %H:%M:%S')

echo "$ts | $tool" >> "$LOG_FILE"
exit 0
