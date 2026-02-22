#!/usr/bin/env python3
"""DIS: 開発インテリジェンスレポート生成。"""
import sqlite3
import os
from datetime import datetime

DB = os.path.expanduser("~/.claude/intelligence/dev.db")


def generate_report():
    conn = sqlite3.connect(DB)
    cur = conn.cursor()

    print("=" * 60)
    print("  Development Intelligence Report")
    print(f"  Generated: {datetime.utcnow().strftime('%Y-%m-%d %H:%M UTC')}")
    print("=" * 60)

    # 直近7日のイベント統計
    cur.execute("SELECT COUNT(*) FROM events WHERE ts >= datetime('now', '-7 days')")
    events_7d = cur.fetchone()[0]
    cur.execute("SELECT type, COUNT(*) FROM events WHERE ts >= datetime('now', '-7 days') GROUP BY type ORDER BY COUNT(*) DESC")
    type_counts = cur.fetchall()

    print(f"\n## Events (last 7 days): {events_7d}")
    for t, c in type_counts:
        print(f"  - {t}: {c}")

    # TOP 5 頻出エラーパターン
    cur.execute("""
        SELECT error_pattern, success_count, score, project
        FROM solutions ORDER BY success_count DESC LIMIT 5
    """)
    top_patterns = cur.fetchall()
    print("\n## Top 5 Error Patterns:")
    for i, (pat, cnt, score, proj) in enumerate(top_patterns, 1):
        print(f"  {i}. [{proj}] (count={cnt}, score={score:.2f})")
        print(f"     {pat[:100]}")

    # セッション統計
    cur.execute("SELECT COUNT(*), SUM(errors_encountered), SUM(errors_resolved) FROM sessions WHERE ts >= datetime('now', '-7 days')")
    sess = cur.fetchone()
    total_sess = sess[0] or 0
    total_err = sess[1] or 0
    total_res = sess[2] or 0
    resolve_rate = (total_res / total_err * 100) if total_err > 0 else 0

    print(f"\n## Sessions (last 7 days): {total_sess}")
    print(f"  - Errors encountered: {total_err}")
    print(f"  - Errors resolved: {total_res}")
    print(f"  - Resolution rate: {resolve_rate:.1f}%")

    # 昇格候補
    cur.execute("""
        SELECT error_pattern, success_count, score, project
        FROM solutions WHERE score >= 3.0 AND success_count >= 3
        ORDER BY score DESC LIMIT 10
    """)
    candidates = cur.fetchall()
    print(f"\n## Promotion Candidates (score>=3.0, freq>=3): {len(candidates)}")
    for pat, cnt, score, proj in candidates:
        print(f"  - [{proj}] score={score:.2f} count={cnt}")
        print(f"    {pat[:100]}")

    # フィードバック統計
    cur.execute("SELECT COUNT(*) FROM feedback")
    fb_total = cur.fetchone()[0]
    cur.execute("""
        SELECT category, wrong_approach, correct_approach, score, confirmation_count,
               score * confirmation_count as stability
        FROM feedback ORDER BY stability DESC LIMIT 5
    """)
    fb_entries = cur.fetchall()
    print(f"\n## Feedback: {fb_total} entries")
    for cat, wrong, correct, score, conf, stab in fb_entries:
        status = " ** PROMOTE **" if stab >= 4 else ""
        print(f"  - [{cat}] {wrong} → {correct} (score={score:.1f}, confirmed={conf}, stability={stab:.1f}){status}")

    # 業界フィード統計
    cur.execute("SELECT COUNT(*) FROM industry_feeds WHERE analyzed = 0")
    unread = cur.fetchone()[0]
    cur.execute("SELECT source, COUNT(*) FROM industry_feeds GROUP BY source ORDER BY COUNT(*) DESC")
    feed_counts = cur.fetchall()
    print(f"\n## Industry Feeds: {unread} unanalyzed")
    for src, cnt in feed_counts:
        print(f"  - {src}: {cnt}")

    # DQS品質ダッシュボード
    try:
        cur.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='quality_metrics'")
        if cur.fetchone():
            cur.execute("""
                SELECT project, COUNT(DISTINCT file), ROUND(AVG(dqs), 3),
                       ROUND(MIN(dqs), 3), ROUND(MAX(dqs), 3),
                       ROUND(AVG(cdi), 3), ROUND(AVG(se), 3),
                       ROUND(AVG(cls_max), 1), ROUND(AVG(crs), 3)
                FROM quality_metrics
                WHERE ts >= datetime('now', '-7 days')
                GROUP BY project ORDER BY AVG(dqs)
            """)
            qm_rows = cur.fetchall()
            print(f"\n## DQS Quality Dashboard (last 7 days):")
            if qm_rows:
                for proj, files, avg_dqs, min_dqs, max_dqs, avg_cdi, avg_se, avg_cls, avg_crs in qm_rows:
                    grade = "Excellent" if avg_dqs >= 0.85 else "Good" if avg_dqs >= 0.70 else "Needs Work" if avg_dqs >= 0.50 else "Poor"
                    bar = "#" * int(avg_dqs * 20) + "-" * (20 - int(avg_dqs * 20))
                    print(f"  [{proj}] DQS={avg_dqs:.3f} [{bar}] {grade}")
                    print(f"    Files={files}  Range={min_dqs:.2f}-{max_dqs:.2f}")
                    print(f"    CDI={avg_cdi:.3f}  SE={avg_se:.3f}  CLS={avg_cls:.0f}  CRS={avg_crs:.3f}")
            else:
                print("  No quality measurements yet. Run: python3 measure-quality.py <dir>")

            # DQS trend (dev_sessions with dqs_delta)
            cur.execute("""
                SELECT project, COUNT(*),
                       ROUND(AVG(CASE WHEN dqs_delta IS NOT NULL THEN dqs_delta ELSE 0 END), 4),
                       SUM(CASE WHEN status='pass' THEN 1 ELSE 0 END),
                       SUM(CASE WHEN status='fail' THEN 1 ELSE 0 END)
                FROM dev_sessions
                WHERE ts >= datetime('now', '-30 days')
                GROUP BY project
            """)
            ds_rows = cur.fetchall()
            if ds_rows:
                print(f"\n## Dev Session Quality Trend (last 30 days):")
                for proj, total, avg_delta, passes, fails in ds_rows:
                    arrow = "^" if avg_delta > 0.01 else "v" if avg_delta < -0.01 else "="
                    print(f"  [{proj}] {total} sessions (pass={passes}, fail={fails})"
                          f"  DQS trend: {avg_delta:+.4f} {arrow}")
    except Exception:
        pass  # quality_metrics may not exist yet

    # Self-improvement suggestions summary
    try:
        cur.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='quality_metrics'")
        if cur.fetchone():
            cur.execute("""
                SELECT COUNT(*) FROM quality_metrics
                WHERE cls_max > 15
                AND ts = (SELECT MAX(ts) FROM quality_metrics)
            """)
            high_cls = cur.fetchone()[0]
            cur.execute("""
                SELECT COUNT(*) FROM quality_metrics
                WHERE dqs < 0.50
                AND ts = (SELECT MAX(ts) FROM quality_metrics)
            """)
            low_dqs = cur.fetchone()[0]
            if high_cls or low_dqs:
                print(f"\n## Self-Improvement Alerts:")
                if high_cls:
                    print(f"  - {high_cls} files with CLS > 15 (function splitting needed)")
                if low_dqs:
                    print(f"  - {low_dqs} files with DQS < 0.50 (redesign needed)")
                print(f"  Run: python3 self-improve.py suggest <project>")
    except Exception:
        pass

    conn.close()
    print("\n" + "=" * 60)


if __name__ == "__main__":
    generate_report()
