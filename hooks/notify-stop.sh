#!/bin/bash
# Claude Code 終了時にntfyへ要約通知を送るスクリプト

# 標準入力からJSONを読み取る
input=$(cat)

# 最後のアシスタントメッセージから要約を抽出（最大100文字）
# transcriptから最後のassistantメッセージを取得
summary=$(echo "$input" | jq -r '
  .transcript
  | map(select(.type == "assistant"))
  | last
  | .message.content
  | if type == "array" then
      map(select(.type == "text") | .text) | join("")
    else
      . // "完了"
    end
' 2>/dev/null | head -c 200 | tr '\n' ' ')

# 要約が空または"null"の場合のフォールバック
if [ -z "$summary" ] || [ "$summary" = "null" ]; then
  summary="タスク完了"
fi

# 先頭100文字に切り詰め、末尾に...を追加
if [ ${#summary} -gt 100 ]; then
  summary="${summary:0:97}..."
fi

# ntfyに送信
curl -s \
  -H "Title: Claude Code 完了 ✅" \
  -d "$summary" \
  "${NTFY_TOPIC:-ntfy.sh/claude-dis-notify}" > /dev/null 2>&1
