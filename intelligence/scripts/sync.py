#!/usr/bin/env python3
"""DIS: ローカルSQLite ↔ Turso クラウド双方向同期。
標準ライブラリのみ使用。Turso HTTP API (Hrana over HTTP) で通信。
"""
import json
import os
import sqlite3
import sys
import urllib.request
from datetime import datetime

DB = os.path.expanduser("~/.claude/intelligence/dev.db")
ENV_FILE = os.path.expanduser("~/.claude/intelligence/.turso-env")

# 同期対象テーブルと各カラム定義
TABLES = {
    "events": ["id", "ts", "type", "cmd", "error", "cwd", "project", "resolved"],
    "solutions": ["id", "ts", "error_pattern", "solution", "files", "project",
                   "success_count", "fail_count", "score", "last_used"],
    "patterns": ["id", "ts", "pattern", "description", "solution", "frequency",
                  "score", "promoted_to_memory", "last_seen"],
    "feedback": ["id", "ts", "category", "wrong_approach", "correct_approach",
                  "context", "project", "scope", "confirmation_count", "score", "last_seen"],
    "sessions": ["id", "ts", "project", "files_changed", "errors_encountered",
                  "errors_resolved", "duration_turns"],
    "industry_feeds": ["id", "ts", "source", "title", "url", "summary",
                        "fetched_at", "analyzed", "relevant", "action_taken"],
    "review_sessions": ["id", "ts", "project", "mode", "initial_score", "final_score",
                         "iterations", "score_history", "issues_found", "issues_fixed",
                         "critical_count", "high_count", "medium_count", "low_count",
                         "status", "models_used", "duration_seconds"],
    "test_sessions": ["id", "ts", "project", "perspective", "test_type", "target_files",
                       "test_file", "iterations", "max_iterations", "status", "pass_count",
                       "fail_count", "error_output", "error_pattern", "fix_history",
                       "score", "used_past_solutions", "duration_seconds",
                       "coverage_before", "coverage_after"],
    "dev_sessions": ["id", "ts", "project", "requirement", "phase", "status",
                      "files_changed", "lines_added", "lines_removed",
                      "test_session_id", "test_status",
                      "review_score_initial", "review_score_final", "review_iterations",
                      "dis_solutions_used", "dis_feedback_used", "dis_patterns_used",
                      "dis_new_feedback", "score", "duration_seconds", "total_iterations",
                      "dqs_before", "dqs_after", "dqs_delta", "metrics_json"],
    "quality_metrics": ["id", "ts", "project", "file", "loc", "cdi", "se",
                         "cls_max", "crs", "drs", "dqs", "grade", "metrics_json"],
    "questions": ["id", "ts", "project", "question", "context", "answer",
                   "tags", "status", "resolved_at", "score", "last_seen"],
}


def load_env() -> tuple[str, str]:
    """Turso URL とトークンを .turso-env から読み込み。"""
    env = {}
    with open(ENV_FILE) as f:
        for line in f:
            line = line.strip()
            if "=" in line and not line.startswith("#"):
                k, v = line.split("=", 1)
                env[k.strip()] = v.strip()
    url = env.get("TURSO_URL", "")
    token = env.get("TURSO_TOKEN", "")
    if not url or not token:
        print("ERROR: TURSO_URL or TURSO_TOKEN not found in .turso-env")
        sys.exit(1)
    # libsql:// → https:// 変換
    http_url = url.replace("libsql://", "https://")
    return http_url, token


def turso_execute(http_url: str, token: str, statements: list[dict]) -> list[dict]:
    """Turso HTTP API でステートメントを実行。"""
    payload = json.dumps({"requests": statements}).encode()
    req = urllib.request.Request(
        f"{http_url}/v3/pipeline",
        data=payload,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            return json.loads(resp.read().decode())
    except Exception as e:
        print(f"Turso API error: {e}")
        return {}


def push_table(local_cur, http_url: str, token: str, table: str, cols: list[str]):
    """ローカルの新規レコードをTursoにpush。"""
    local_cur.execute(f"SELECT last_sync_id FROM sync_meta WHERE table_name = ?", (table,))
    row = local_cur.fetchone()
    last_id = row[0] if row else 0

    local_cur.execute(f"SELECT {','.join(cols)} FROM {table} WHERE id > ? ORDER BY id", (last_id,))
    rows = local_cur.fetchall()
    if not rows:
        return 0

    statements = []
    max_id = last_id
    for row in rows:
        placeholders = ",".join(["?" for _ in cols])
        col_names = ",".join(cols)
        # Turso HTTP API format
        args = []
        for v in row:
            if v is None:
                args.append({"type": "null"})
            elif isinstance(v, int):
                args.append({"type": "integer", "value": str(v)})
            elif isinstance(v, float):
                args.append({"type": "float", "value": v})
            else:
                args.append({"type": "text", "value": str(v)})

        stmt = {
            "type": "execute",
            "stmt": {
                "sql": f"INSERT OR REPLACE INTO {table}({col_names}) VALUES({placeholders})",
                "args": args,
            },
        }
        statements.append(stmt)
        if row[0] > max_id:
            max_id = row[0]

    # バッチ実行 (50件ずつ)
    pushed = 0
    for i in range(0, len(statements), 50):
        batch = statements[i:i+50]
        batch.append({"type": "close"})
        result = turso_execute(http_url, token, batch)
        if result:
            pushed += len(batch) - 1  # close を除く

    # sync_meta 更新
    if pushed > 0:
        now = datetime.utcnow().isoformat()
        local_cur.execute(
            "UPDATE sync_meta SET last_sync_id = ?, last_sync_ts = ? WHERE table_name = ?",
            (max_id, now, table),
        )

    return pushed


def pull_table(local_cur, http_url: str, token: str, table: str, cols: list[str]):
    """Tursoからローカルにないレコードをpull。"""
    local_cur.execute(f"SELECT MAX(id) FROM {table}")
    local_max = local_cur.fetchone()[0] or 0

    # リモートの max(id) を取得
    result = turso_execute(http_url, token, [
        {"type": "execute", "stmt": {"sql": f"SELECT MAX(id) FROM {table}", "args": []}},
        {"type": "close"},
    ])

    if not result or "results" not in result:
        return 0

    try:
        remote_max_row = result["results"][0]["response"]["result"]["rows"]
        remote_max = int(remote_max_row[0][0]["value"]) if remote_max_row and remote_max_row[0][0]["value"] else 0
    except (KeyError, IndexError, TypeError, ValueError):
        return 0

    if remote_max <= local_max:
        return 0

    # ローカルにない分をpull
    col_names = ",".join(cols)
    result = turso_execute(http_url, token, [
        {"type": "execute", "stmt": {
            "sql": f"SELECT {col_names} FROM {table} WHERE id > ? ORDER BY id LIMIT 500",
            "args": [{"type": "integer", "value": str(local_max)}],
        }},
        {"type": "close"},
    ])

    if not result or "results" not in result:
        return 0

    try:
        rows = result["results"][0]["response"]["result"]["rows"]
    except (KeyError, IndexError):
        return 0

    pulled = 0
    for row in rows:
        values = []
        for cell in row:
            if cell["type"] == "null":
                values.append(None)
            elif cell["type"] == "integer":
                values.append(int(cell["value"]))
            elif cell["type"] == "float":
                values.append(float(cell["value"]))
            else:
                values.append(cell["value"])

        placeholders = ",".join(["?" for _ in cols])
        try:
            local_cur.execute(
                f"INSERT OR REPLACE INTO {table}({col_names}) VALUES({placeholders})",
                values,
            )
            pulled += 1
        except sqlite3.Error:
            continue

    return pulled


def ensure_remote_schema(http_url: str, token: str, local_cur):
    """ローカルDBのスキーマをTursoにも適用 (CREATE TABLE IF NOT EXISTS)。"""
    local_cur.execute("SELECT sql FROM sqlite_master WHERE type='table' AND sql IS NOT NULL")
    ddl_stmts = []
    for (sql,) in local_cur.fetchall():
        if not sql or "sqlite_" in sql:
            continue
        # CREATE TABLE → CREATE TABLE IF NOT EXISTS
        safe_sql = sql.replace("CREATE TABLE ", "CREATE TABLE IF NOT EXISTS ", 1)
        ddl_stmts.append({"type": "execute", "stmt": {"sql": safe_sql, "args": []}})

    # インデックスも送信
    local_cur.execute("SELECT sql FROM sqlite_master WHERE type='index' AND sql IS NOT NULL")
    for (sql,) in local_cur.fetchall():
        if not sql:
            continue
        safe_sql = sql.replace("CREATE INDEX ", "CREATE INDEX IF NOT EXISTS ", 1)
        ddl_stmts.append({"type": "execute", "stmt": {"sql": safe_sql, "args": []}})

    if ddl_stmts:
        ddl_stmts.append({"type": "close"})
        result = turso_execute(http_url, token, ddl_stmts)
        ok = bool(result and "results" in result)
        print(f"  Schema sync: {len(ddl_stmts)-1} DDL statements → {'OK' if ok else 'FAILED'}")
    return len(ddl_stmts) - 1 if ddl_stmts else 0


def sync():
    http_url, token = load_env()
    conn = sqlite3.connect(DB)
    cur = conn.cursor()

    print(f"DIS Sync: {datetime.utcnow().strftime('%Y-%m-%d %H:%M UTC')}")
    print(f"Remote: {http_url}")
    print()

    # Phase 0: DDL同期 (リモートにテーブルがなければ作成)
    ensure_remote_schema(http_url, token, cur)

    # sync_meta に新テーブルのエントリがなければ追加
    for table in TABLES:
        cur.execute("SELECT 1 FROM sync_meta WHERE table_name = ?", (table,))
        if not cur.fetchone():
            cur.execute("INSERT INTO sync_meta(table_name, last_sync_id, last_sync_ts) VALUES(?, 0, '')", (table,))
    conn.commit()
    print()

    total_pushed = 0
    total_pulled = 0

    for table, cols in TABLES.items():
        pushed = push_table(cur, http_url, token, table, cols)
        pulled = pull_table(cur, http_url, token, table, cols)
        if pushed or pulled:
            print(f"  {table}: pushed={pushed}, pulled={pulled}")
        total_pushed += pushed
        total_pulled += pulled

    conn.commit()
    conn.close()

    print(f"\nTotal: pushed={total_pushed}, pulled={total_pulled}")
    if total_pushed == 0 and total_pulled == 0:
        print("Already in sync.")


if __name__ == "__main__":
    sync()
