#!/usr/bin/env python3
"""DIS: 時間減衰によるスコア再計算。λ=0.01 (半減期約70日)。"""
import math
import sqlite3
import os
from datetime import datetime

DB = os.path.expanduser("~/.claude/intelligence/dev.db")
LAMBDA = 0.01  # 半減期 ≈ ln(2)/0.01 ≈ 69.3日
ARCHIVE_THRESHOLD = 0.1


def apply_decay():
    conn = sqlite3.connect(DB)
    cur = conn.cursor()
    now = datetime.utcnow()

    # solutions の減衰
    cur.execute("SELECT id, score, last_used FROM solutions WHERE score > ?", (ARCHIVE_THRESHOLD,))
    sol_count = 0
    for sid, score, last_used in cur.fetchall():
        if not last_used:
            continue
        try:
            last_dt = datetime.fromisoformat(last_used)
            days = (now - last_dt).days
            new_score = score * math.exp(-LAMBDA * days)
            cur.execute("UPDATE solutions SET score = ? WHERE id = ?", (round(new_score, 4), sid))
            sol_count += 1
        except (ValueError, TypeError):
            continue

    # patterns の減衰
    cur.execute("SELECT id, score, last_seen FROM patterns WHERE score > ?", (ARCHIVE_THRESHOLD,))
    pat_count = 0
    for pid, score, last_seen in cur.fetchall():
        if not last_seen:
            continue
        try:
            last_dt = datetime.fromisoformat(last_seen)
            days = (now - last_dt).days
            new_score = score * math.exp(-LAMBDA * days)
            cur.execute("UPDATE patterns SET score = ? WHERE id = ?", (round(new_score, 4), pid))
            pat_count += 1
        except (ValueError, TypeError):
            continue

    # feedback の減衰 (λ=0.005、半減期約140日 — フィードバックはより長く保持)
    FB_LAMBDA = 0.005
    cur.execute("SELECT id, score, last_seen FROM feedback WHERE score > ?", (ARCHIVE_THRESHOLD,))
    fb_count = 0
    for fid, score, last_seen in cur.fetchall():
        if not last_seen:
            continue
        try:
            last_dt = datetime.fromisoformat(last_seen)
            days = (now - last_dt).days
            new_score = score * math.exp(-FB_LAMBDA * days)
            cur.execute("UPDATE feedback SET score = ? WHERE id = ?", (round(new_score, 4), fid))
            fb_count += 1
        except (ValueError, TypeError):
            continue

    # test_sessions の減衰 (λ=0.008、半減期約87日)
    TS_LAMBDA = 0.008
    cur.execute("SELECT id, score, ts FROM test_sessions WHERE score > ?", (ARCHIVE_THRESHOLD,))
    ts_count = 0
    for tid, score, ts in cur.fetchall():
        if not ts:
            continue
        try:
            last_dt = datetime.fromisoformat(ts)
            days = (now - last_dt).days
            new_score = score * math.exp(-TS_LAMBDA * days)
            cur.execute("UPDATE test_sessions SET score = ? WHERE id = ?", (round(new_score, 4), tid))
            ts_count += 1
        except (ValueError, TypeError):
            continue

    # dev_sessions の減衰 (λ=0.006、半減期約116日 — 長期保持)
    DS_LAMBDA = 0.006
    cur.execute("SELECT id, score, ts FROM dev_sessions WHERE score > ?", (ARCHIVE_THRESHOLD,))
    ds_count = 0
    for did, score, ts in cur.fetchall():
        if not ts:
            continue
        try:
            last_dt = datetime.fromisoformat(ts)
            days = (now - last_dt).days
            new_score = score * math.exp(-DS_LAMBDA * days)
            cur.execute("UPDATE dev_sessions SET score = ? WHERE id = ?", (round(new_score, 4), did))
            ds_count += 1
        except (ValueError, TypeError):
            continue

    # questions の減衰 (λ=0.005、半減期約140日 — 質問は長期保持)
    Q_LAMBDA = 0.005
    cur.execute("SELECT id, score, last_seen FROM questions WHERE score > ?", (ARCHIVE_THRESHOLD,))
    q_count = 0
    for qid, score, last_seen in cur.fetchall():
        if not last_seen:
            continue
        try:
            last_dt = datetime.fromisoformat(last_seen)
            days = (now - last_dt).days
            new_score = score * math.exp(-Q_LAMBDA * days)
            cur.execute("UPDATE questions SET score = ? WHERE id = ?", (round(new_score, 4), qid))
            q_count += 1
        except (ValueError, TypeError):
            continue

    # アーカイブ（低スコア削除）
    cur.execute("DELETE FROM solutions WHERE score < ? AND score > 0", (ARCHIVE_THRESHOLD,))
    archived_sol = cur.rowcount
    cur.execute("DELETE FROM patterns WHERE score < ? AND score > 0 AND promoted_to_memory = 0", (ARCHIVE_THRESHOLD,))
    archived_pat = cur.rowcount
    cur.execute("DELETE FROM feedback WHERE score < ? AND score > 0", (ARCHIVE_THRESHOLD,))
    archived_fb = cur.rowcount
    cur.execute("DELETE FROM test_sessions WHERE score < ? AND score > 0", (ARCHIVE_THRESHOLD,))
    archived_ts = cur.rowcount
    cur.execute("DELETE FROM dev_sessions WHERE score < ? AND score > 0", (ARCHIVE_THRESHOLD,))
    archived_ds = cur.rowcount
    cur.execute("DELETE FROM questions WHERE score < ? AND score > 0 AND status = 'resolved'", (ARCHIVE_THRESHOLD,))
    archived_q = cur.rowcount

    conn.commit()
    conn.close()
    print(f"Decay applied: {sol_count} solutions, {pat_count} patterns, {fb_count} feedback, {ts_count} test_sessions, {ds_count} dev_sessions, {q_count} questions")
    print(f"Archived: {archived_sol} solutions, {archived_pat} patterns, {archived_fb} feedback, {archived_ts} test_sessions, {archived_ds} dev_sessions, {archived_q} questions (score < {ARCHIVE_THRESHOLD})")


if __name__ == "__main__":
    apply_decay()
