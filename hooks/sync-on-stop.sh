#!/bin/bash
# DIS: セッション終了時にTurso syncをバックグラウンド実行
python3 ~/.claude/intelligence/scripts/sync.py >> ~/.claude/intelligence/sync.log 2>&1 &
exit 0
