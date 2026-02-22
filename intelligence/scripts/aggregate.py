#!/usr/bin/env python3
"""DIS: events → solutions への集計。エラーメッセージを正規化し、同一パターンをカウント。"""
import re
import sqlite3
import os
from datetime import datetime

DB = os.path.expanduser("~/.claude/intelligence/dev.db")


def normalize_error(error: str) -> str:
    """エラーメッセージからパス・行番号・一時的な値を除去して正規化。"""
    s = error
    # ファイルパスを除去 (/Users/xxx/... → <path>)
    s = re.sub(r"/[\w/.-]+\.(ts|tsx|js|jsx|py|rs|go)", "<path>", s)
    # 行番号・カラム番号を除去
    s = re.sub(r":\d+:\d+", ":<line>", s)
    s = re.sub(r"line \d+", "line <n>", s, flags=re.IGNORECASE)
    # ハッシュ値・UUIDを除去
    s = re.sub(r"[0-9a-f]{8,}", "<hash>", s)
    # 連続空白を圧縮
    s = re.sub(r"\s+", " ", s).strip()
    # 先頭200文字に制限
    return s[:200]


def aggregate():
    conn = sqlite3.connect(DB)
    cur = conn.cursor()

    # 未集計のイベントを取得（resolved=0のもの）
    cur.execute("""
        SELECT id, error, project FROM events
        WHERE error IS NOT NULL AND error != ''
        ORDER BY ts DESC LIMIT 500
    """)
    events = cur.fetchall()

    if not events:
        print("No events to aggregate.")
        conn.close()
        return

    pattern_counts = {}
    for eid, error, project in events:
        pattern = normalize_error(error)
        key = (pattern, project or "unknown")
        if key not in pattern_counts:
            pattern_counts[key] = {"count": 0, "sample_error": error[:500]}
        pattern_counts[key]["count"] += 1

    # solutions テーブルへ UPSERT
    now = datetime.utcnow().isoformat()
    upserted = 0
    for (pattern, project), info in pattern_counts.items():
        if info["count"] < 1:
            continue
        cur.execute(
            "SELECT id, success_count FROM solutions WHERE error_pattern = ? AND project = ?",
            (pattern, project),
        )
        row = cur.fetchone()
        if row:
            cur.execute(
                "UPDATE solutions SET success_count = success_count + ?, last_used = ? WHERE id = ?",
                (info["count"], now, row[0]),
            )
        else:
            cur.execute(
                """INSERT INTO solutions(error_pattern, solution, project, success_count, last_used)
                   VALUES(?, ?, ?, ?, ?)""",
                (pattern, f"[auto] Observed {info['count']}x: {info['sample_error'][:200]}", project, info["count"], now),
            )
        upserted += 1

    conn.commit()
    conn.close()
    print(f"Aggregated: {len(events)} events → {upserted} solution patterns")


def promote_feedback():
    """stability >= 4 のフィードバックを patterns テーブルに昇格。"""
    conn = sqlite3.connect(DB)
    cur = conn.cursor()

    cur.execute("""
        SELECT id, category, wrong_approach, correct_approach, project, scope, score, confirmation_count
        FROM feedback
        WHERE score * confirmation_count >= 4
    """)
    candidates = cur.fetchall()

    promoted = 0
    for fid, cat, wrong, correct, project, scope, score, conf_count in candidates:
        pattern_name = f"[{cat}] {wrong} → {correct}"
        # 既にpatternsに存在するか
        cur.execute("SELECT id FROM patterns WHERE pattern = ?", (pattern_name,))
        if cur.fetchone():
            continue
        cur.execute(
            """INSERT INTO patterns(pattern, description, solution, frequency, score, last_seen)
               VALUES(?, ?, ?, ?, ?, datetime('now'))""",
            (pattern_name, f"User feedback ({scope}): avoid {wrong}", correct, conf_count, score * 1.5),
        )
        promoted += 1

    conn.commit()
    conn.close()
    if promoted:
        print(f"Promoted {promoted} feedback entries to patterns")
    else:
        print("No feedback ready for promotion")


if __name__ == "__main__":
    import sys
    if len(sys.argv) > 1 and sys.argv[1] == "--promote-feedback":
        promote_feedback()
    else:
        aggregate()
