#!/usr/bin/env python3
"""DIS Self-Improvement Engine — 自己改善的コード品質RL。

Usage:
  self-improve.py analyze <project>        # DQSトレンド分析 + 改善提案
  self-improve.py reward <dev_session_id>  # RL報酬を計算してdev_sessionsに記録
  self-improve.py suggest <project>        # リファクタリング候補を自動提案
  self-improve.py trend <project> [days]   # DQS時系列トレンド

Self-Improvement Loop:
  1. measure-quality.py で計測 → quality_metrics に記録
  2. self-improve.py reward で DRS を算出 → dev_sessions に統合
  3. self-improve.py analyze で傾向分析 → 改善提案を生成
  4. 提案が feedback テーブルに自動記録 → 次回の /dev で参照
  → これが繰り返されることで品質が自己改善的に向上
"""
import json
import math
import os
import sqlite3
import sys
from datetime import datetime, timedelta

DB = os.path.expanduser("~/.claude/intelligence/dev.db")

# RL weights
ALPHA = 0.35   # test reward
BETA = 0.25    # review reward
GAMMA = 0.15   # entropy reward (ΔSE improvement)
DELTA = 0.25   # history reward


def get_conn():
    return sqlite3.connect(DB)


# ── RL Reward Calculation ───────────────────────────────────

def compute_reward(dev_session_id: int) -> dict:
    """dev_sessionのRL報酬を算出。"""
    conn = get_conn()
    cur = conn.cursor()

    cur.execute("SELECT * FROM dev_sessions WHERE id = ?", (dev_session_id,))
    cols = [d[0] for d in cur.description]
    row = cur.fetchone()
    if not row:
        conn.close()
        return {"error": f"Session {dev_session_id} not found"}

    session = dict(zip(cols, row))
    project = session["project"]

    # Test Reward
    test_reward = 0.0
    if session.get("test_status") == "pass":
        test_reward = 1.0
    elif session.get("test_status") == "fixed":
        test_reward = 0.75
    elif session.get("test_status") == "fail":
        test_reward = -0.5
    elif session.get("test_status") == "skipped":
        # Use historical average
        cur.execute(
            "SELECT AVG(CASE WHEN status IN ('pass','fixed') THEN 1.0 ELSE 0.0 END) "
            "FROM test_sessions WHERE project = ?", (project,))
        avg = cur.fetchone()[0]
        test_reward = avg if avg else 0.5

    # Review Reward
    review_reward = 0.5  # default
    if session.get("review_score_final"):
        review_reward = session["review_score_final"] / 100.0

    # Entropy Reward (ΔSE from quality_metrics)
    entropy_reward = 0.5
    if session.get("metrics_json"):
        try:
            metrics = json.loads(session["metrics_json"])
            if "delta_se" in metrics:
                # Negative ΔSE = improvement
                entropy_reward = min(1.0, max(0.0, 0.5 + (-metrics["delta_se"]) * 0.5))
        except (json.JSONDecodeError, KeyError):
            pass

    # History Reward (past success rate in similar tasks)
    cur.execute(
        "SELECT COUNT(*), SUM(CASE WHEN status='pass' THEN 1 ELSE 0 END) "
        "FROM dev_sessions WHERE project = ? AND id < ? AND status != 'running'",
        (project, dev_session_id))
    row = cur.fetchone()
    total, passes = (row[0] or 0), (row[1] or 0)
    history_reward = passes / max(total, 1)

    # Composite DRS
    drs = (ALPHA * test_reward + BETA * review_reward +
           GAMMA * entropy_reward + DELTA * history_reward)
    drs = round(max(-1.0, min(1.0, drs)), 4)

    result = {
        "session_id": dev_session_id,
        "test_reward": round(test_reward, 4),
        "review_reward": round(review_reward, 4),
        "entropy_reward": round(entropy_reward, 4),
        "history_reward": round(history_reward, 4),
        "drs": drs,
        "weights": {"alpha": ALPHA, "beta": BETA, "gamma": GAMMA, "delta": DELTA},
    }

    conn.close()
    return result


# ── Trend Analysis ──────────────────────────────────────────

def analyze_trend(project: str, days: int = 30) -> dict:
    """DQSトレンド分析。"""
    conn = get_conn()
    cur = conn.cursor()

    cutoff = (datetime.utcnow() - timedelta(days=days)).isoformat()

    # quality_metrics からDQSトレンド
    cur.execute(
        "SELECT ts, AVG(dqs), COUNT(*), MIN(dqs), MAX(dqs) "
        "FROM quality_metrics WHERE project = ? AND ts >= ? "
        "GROUP BY date(ts) ORDER BY ts",
        (project, cutoff))
    daily_dqs = [{"date": r[0][:10], "avg_dqs": round(r[1], 4),
                  "files": r[2], "min": round(r[3], 4), "max": round(r[4], 4)}
                 for r in cur.fetchall()]

    # dev_sessions からセッションサマリ
    cur.execute(
        "SELECT COUNT(*), "
        "SUM(CASE WHEN status='pass' THEN 1 ELSE 0 END), "
        "SUM(CASE WHEN status='fail' THEN 1 ELSE 0 END), "
        "AVG(dqs_delta), AVG(score) "
        "FROM dev_sessions WHERE project = ? AND ts >= ?",
        (project, cutoff))
    row = cur.fetchone()
    sessions = {
        "total": row[0] or 0,
        "pass": row[1] or 0,
        "fail": row[2] or 0,
        "avg_dqs_delta": round(row[3], 4) if row[3] else 0.0,
        "avg_score": round(row[4], 4) if row[4] else 0.0,
    }

    # 最悪ファイル top 5 (直近計測)
    cur.execute(
        "SELECT file, dqs, cdi, se, cls_max, crs "
        "FROM quality_metrics WHERE project = ? "
        "AND ts = (SELECT MAX(ts) FROM quality_metrics WHERE project = ?) "
        "ORDER BY dqs ASC LIMIT 5",
        (project, project))
    worst_files = [{"file": r[0], "dqs": r[1], "cdi": r[2], "se": r[3],
                    "cls_max": r[4], "crs": r[5]} for r in cur.fetchall()]

    # DQS変化の方向
    if len(daily_dqs) >= 2:
        first_half = [d["avg_dqs"] for d in daily_dqs[:len(daily_dqs)//2]]
        second_half = [d["avg_dqs"] for d in daily_dqs[len(daily_dqs)//2:]]
        avg_first = sum(first_half) / max(len(first_half), 1)
        avg_second = sum(second_half) / max(len(second_half), 1)
        direction = "improving" if avg_second > avg_first else "declining" if avg_second < avg_first else "stable"
    else:
        direction = "insufficient_data"

    conn.close()
    return {
        "project": project,
        "period_days": days,
        "direction": direction,
        "daily_dqs": daily_dqs,
        "sessions": sessions,
        "worst_files": worst_files,
    }


# ── Improvement Suggestions ─────────────────────────────────

def generate_suggestions(project: str) -> list[dict]:
    """DQSデータに基づくリファクタリング提案。"""
    conn = get_conn()
    cur = conn.cursor()

    suggestions = []

    # 1. CLS > 15: 関数分割が必要
    cur.execute(
        "SELECT DISTINCT file, cls_max FROM quality_metrics "
        "WHERE project = ? AND cls_max > 15 "
        "AND ts = (SELECT MAX(ts) FROM quality_metrics WHERE project = ?) "
        "ORDER BY cls_max DESC LIMIT 10",
        (project, project))
    for f, cls in cur.fetchall():
        suggestions.append({
            "type": "split_function",
            "priority": "HIGH" if cls > 25 else "MEDIUM",
            "file": f,
            "reason": f"Cognitive Load {cls} > 15",
            "action": "ネスト深い関数を extract method で分割",
            "expected_impact": round(min(0.15, (cls - 15) * 0.005), 4),
        })

    # 2. CDI < 0.4: コードが冗長
    cur.execute(
        "SELECT DISTINCT file, cdi, loc FROM quality_metrics "
        "WHERE project = ? AND cdi < 0.4 "
        "AND ts = (SELECT MAX(ts) FROM quality_metrics WHERE project = ?) "
        "ORDER BY cdi ASC LIMIT 10",
        (project, project))
    for f, cdi, loc in cur.fetchall():
        suggestions.append({
            "type": "reduce_redundancy",
            "priority": "MEDIUM",
            "file": f,
            "reason": f"CDI {cdi:.2f} < 0.40 (LOC={loc})",
            "action": "重複コードの抽出、ボイラープレートの共通化",
            "expected_impact": round(min(0.10, (0.4 - cdi) * 0.3), 4),
        })

    # 3. SE > 5.0: 命名の一貫性が低い
    cur.execute(
        "SELECT DISTINCT file, se FROM quality_metrics "
        "WHERE project = ? AND se > 5.0 "
        "AND ts = (SELECT MAX(ts) FROM quality_metrics WHERE project = ?) "
        "ORDER BY se DESC LIMIT 10",
        (project, project))
    for f, se in cur.fetchall():
        suggestions.append({
            "type": "improve_naming",
            "priority": "LOW",
            "file": f,
            "reason": f"Structural Entropy {se:.2f} > 5.0",
            "action": "識別子の命名規則を統一、不要な変数を削除",
            "expected_impact": round(min(0.08, (se - 5.0) * 0.02), 4),
        })

    # 4. CRS > 1.0: 変更リスクが高い
    cur.execute(
        "SELECT DISTINCT file, crs FROM quality_metrics "
        "WHERE project = ? AND crs > 1.0 "
        "AND ts = (SELECT MAX(ts) FROM quality_metrics WHERE project = ?) "
        "ORDER BY crs DESC LIMIT 10",
        (project, project))
    for f, crs in cur.fetchall():
        suggestions.append({
            "type": "reduce_churn",
            "priority": "HIGH",
            "file": f,
            "reason": f"Change Risk {crs:.2f} > 1.0",
            "action": "頻繁に変更されるロジックを安定したモジュールに分離",
            "expected_impact": round(min(0.12, (crs - 1.0) * 0.1), 4),
        })

    # 5. DQS < 0.50: 全体的に品質が低い
    cur.execute(
        "SELECT DISTINCT file, dqs FROM quality_metrics "
        "WHERE project = ? AND dqs < 0.50 "
        "AND ts = (SELECT MAX(ts) FROM quality_metrics WHERE project = ?) "
        "ORDER BY dqs ASC LIMIT 5",
        (project, project))
    for f, dqs in cur.fetchall():
        suggestions.append({
            "type": "redesign",
            "priority": "CRITICAL",
            "file": f,
            "reason": f"DQS {dqs:.2f} < 0.50",
            "action": "ファイル全体の再設計を検討",
            "expected_impact": 0.20,
        })

    # Auto-record to feedback for DIS learning
    for s in suggestions[:5]:  # Top 5 only
        cur.execute(
            "INSERT OR IGNORE INTO feedback(category, wrong_approach, correct_approach, context, project, scope) "
            "VALUES(?, ?, ?, ?, ?, 'project')",
            ("refactoring",
             f"{s['type']}: {s['file']} ({s['reason']})",
             s["action"],
             f"DQS auto-suggestion, priority={s['priority']}",
             project))

    conn.commit()
    conn.close()

    return sorted(suggestions, key=lambda x: {"CRITICAL": 0, "HIGH": 1, "MEDIUM": 2, "LOW": 3}[x["priority"]])


# ── CLI ─────────────────────────────────────────────────────

def print_trend(trend: dict):
    """トレンドレポート表示。"""
    arrow = {"improving": "^", "declining": "v", "stable": "=", "insufficient_data": "?"}
    d = trend["direction"]
    s = trend["sessions"]
    print(f"{'=' * 55}")
    print(f"  DQS Trend — {trend['project']} ({trend['period_days']}d)")
    print(f"  Direction: {d} {arrow.get(d, '?')}")
    print(f"  Sessions: {s['total']} (pass={s['pass']}, fail={s['fail']})")
    print(f"  Avg DQS Delta: {s['avg_dqs_delta']:+.4f}")
    print(f"{'=' * 55}")

    if trend["daily_dqs"]:
        print("  Date       | Avg DQS | Files | Range")
        print("  " + "-" * 47)
        for d in trend["daily_dqs"]:
            bar = "#" * int(d["avg_dqs"] * 20)
            print(f"  {d['date']} | {d['avg_dqs']:.3f}  | {d['files']:>5} | {d['min']:.2f}-{d['max']:.2f} {bar}")

    if trend["worst_files"]:
        print(f"\n  Worst Files:")
        for f in trend["worst_files"]:
            print(f"    {f['dqs']:.2f} {f['file']}  (CDI={f['cdi']:.2f} SE={f['se']:.2f} CLS={f['cls_max']} CRS={f['crs']:.2f})")

    print(f"{'=' * 55}")


def print_suggestions(suggestions: list[dict]):
    """改善提案表示。"""
    print(f"{'=' * 55}")
    print(f"  Improvement Suggestions ({len(suggestions)} items)")
    print(f"{'=' * 55}")
    for i, s in enumerate(suggestions, 1):
        print(f"  [{s['priority']}] {s['file']}")
        print(f"    Type: {s['type']}")
        print(f"    Reason: {s['reason']}")
        print(f"    Action: {s['action']}")
        print(f"    Expected DQS Impact: +{s['expected_impact']:.3f}")
        print()
    print(f"{'=' * 55}")


def main():
    if len(sys.argv) < 2:
        print("Usage: self-improve.py <analyze|reward|suggest|trend> <project|session_id> [days]")
        sys.exit(1)

    cmd = sys.argv[1]

    if cmd == "analyze":
        project = sys.argv[2] if len(sys.argv) > 2 else ""
        trend = analyze_trend(project)
        print_trend(trend)
        suggestions = generate_suggestions(project)
        if suggestions:
            print()
            print_suggestions(suggestions)

    elif cmd == "reward":
        session_id = int(sys.argv[2]) if len(sys.argv) > 2 else 0
        result = compute_reward(session_id)
        print(json.dumps(result, indent=2))

    elif cmd == "suggest":
        project = sys.argv[2] if len(sys.argv) > 2 else ""
        suggestions = generate_suggestions(project)
        print_suggestions(suggestions)

    elif cmd == "trend":
        project = sys.argv[2] if len(sys.argv) > 2 else ""
        days = int(sys.argv[3]) if len(sys.argv) > 3 else 30
        trend = analyze_trend(project, days)
        if "--json" in sys.argv:
            print(json.dumps(trend, indent=2))
        else:
            print_trend(trend)

    else:
        print(f"Unknown command: {cmd}")
        sys.exit(1)


if __name__ == "__main__":
    main()
