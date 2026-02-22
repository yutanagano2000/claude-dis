#!/usr/bin/env python3
"""DIS Quality Score (DQS) — コード品質の5軸統合計測。

Usage:
  measure-quality.py <file_or_dir> [--project <name>] [--json]
  measure-quality.py --diff          # git diff対象のみ計測
  measure-quality.py --baseline <dir> # ベースライン記録

Metrics:
  CDI  — Code Density Index (gzip圧縮率)
  SE   — Structural Entropy (Shannon Entropy of identifiers)
  CLS  — Cognitive Load Score (nesting depth + control flow)
  CRS  — Change Risk Score (complexity × churn × 1/ownership)
  DQS  — DIS Quality Score (5軸統合)
"""
import ast
import gzip
import json
import math
import os
import re
import sqlite3
import subprocess
import sys
from collections import Counter
from pathlib import Path

DB = os.path.expanduser("~/.claude/intelligence/dev.db")

# DQS weights
W_CDI = 0.15
W_SE = 0.15
W_CLS = 0.20
W_CRS = 0.15
W_DRS = 0.35

# ── CDI: Code Density Index ─────────────────────────────────

def measure_cdi(source: str) -> float:
    """gzip圧縮率でコード密度を計測。0.0-1.0 (高い=密度高い)。"""
    if not source.strip():
        return 0.0
    raw = source.encode("utf-8")
    compressed = gzip.compress(raw, compresslevel=9)
    ratio = 1.0 - (len(compressed) / len(raw))
    return round(max(0.0, min(1.0, ratio)), 4)


# ── SE: Structural Entropy ──────────────────────────────────

def extract_identifiers(source: str, lang: str) -> list[str]:
    """ソースコードから識別子を抽出。"""
    if lang == "python":
        try:
            tree = ast.parse(source)
            ids = []
            for node in ast.walk(tree):
                if isinstance(node, ast.Name):
                    ids.append(node.id)
                elif isinstance(node, ast.FunctionDef):
                    ids.append(node.name)
                elif isinstance(node, ast.ClassDef):
                    ids.append(node.name)
                elif isinstance(node, ast.Attribute):
                    ids.append(node.attr)
            return ids
        except SyntaxError:
            pass
    # Fallback: regex-based for TS/JS/Go/Rust/Swift/Python
    return re.findall(r'\b[a-zA-Z_]\w{2,}\b', source)


def measure_se(source: str, lang: str = "auto") -> float:
    """Shannon Entropy of identifiers。低い=一貫性高い。"""
    ids = extract_identifiers(source, lang)
    if len(ids) < 2:
        return 0.0
    counts = Counter(ids)
    total = sum(counts.values())
    entropy = 0.0
    for count in counts.values():
        p = count / total
        if p > 0:
            entropy -= p * math.log2(p)
    return round(entropy, 4)


# ── CLS: Cognitive Load Score ───────────────────────────────

CONTROL_FLOW_PATTERNS = re.compile(
    r'\b(if|else\s+if|elif|for|while|do|switch|case|catch|except|'
    r'try|finally|with|match)\b'
)
FLOW_BREAK_PATTERNS = re.compile(r'\b(break|continue|goto|return|throw|raise)\b')


def measure_cls_file(source: str) -> dict:
    """ファイル全体のCognitive Load Score。"""
    lines = source.split('\n')
    total_cls = 0
    max_cls = 0
    func_count = 0
    max_nesting = 0

    current_nesting = 0
    current_func_cls = 0
    in_function = False

    for line in lines:
        stripped = line.strip()
        if not stripped or stripped.startswith(('#', '//', '/*', '*', '--')):
            continue

        # Detect nesting level by indentation
        indent = len(line) - len(line.lstrip())
        nesting = indent // 2 if indent > 0 else 0  # rough estimate
        max_nesting = max(max_nesting, nesting)

        # Function detection
        if re.match(r'\s*(def |function |const \w+ = |async |export (default )?function|fn )', line):
            if in_function:
                max_cls = max(max_cls, current_func_cls)
            func_count += 1
            in_function = True
            current_func_cls = 0

        # Structural increments
        structural = len(CONTROL_FLOW_PATTERNS.findall(stripped))
        nesting_penalty = structural * max(0, nesting - 1)
        flow_breaks = len(FLOW_BREAK_PATTERNS.findall(stripped))

        line_cls = structural + nesting_penalty + flow_breaks
        total_cls += line_cls
        current_func_cls += line_cls

    if in_function:
        max_cls = max(max_cls, current_func_cls)

    return {
        "cls_total": total_cls,
        "cls_max": max_cls,
        "cls_avg": round(total_cls / max(func_count, 1), 2),
        "functions": func_count,
        "max_nesting": max_nesting,
    }


# ── CRS: Change Risk Score ──────────────────────────────────

def measure_crs(filepath: str) -> dict:
    """Git history-based Change Risk Score。"""
    try:
        # Churn: 過去30日の変更行数
        log = subprocess.run(
            ["git", "log", "--since=30 days ago", "--numstat", "--format=", "--", filepath],
            capture_output=True, text=True, timeout=5,
            cwd=os.path.dirname(os.path.abspath(filepath)) or "."
        )
        added, removed = 0, 0
        for line in log.stdout.strip().split('\n'):
            parts = line.split('\t')
            if len(parts) >= 2 and parts[0] != '-':
                added += int(parts[0] or 0)
                removed += int(parts[1] or 0)
        churn = added + removed

        # File size
        try:
            loc = sum(1 for _ in open(filepath))
        except Exception:
            loc = 1
        normalized_churn = churn / max(loc, 1)

        # Ownership: 変更者数
        authors = subprocess.run(
            ["git", "log", "--since=90 days ago", "--format=%aN", "--", filepath],
            capture_output=True, text=True, timeout=5,
            cwd=os.path.dirname(os.path.abspath(filepath)) or "."
        )
        unique_authors = len(set(a.strip() for a in authors.stdout.strip().split('\n') if a.strip()))
        ownership = max(unique_authors, 1)

        return {
            "churn_30d": churn,
            "normalized_churn": round(normalized_churn, 4),
            "authors_90d": ownership,
            "crs": round(normalized_churn / ownership, 4),
        }
    except Exception:
        return {"churn_30d": 0, "normalized_churn": 0.0, "authors_90d": 1, "crs": 0.0}


# ── DRS: DIS Reinforcement Score ────────────────────────────

def measure_drs(project: str = "") -> float:
    """DIS historyからRL報酬スコアを算出。"""
    if not os.path.exists(DB):
        return 0.5
    try:
        conn = sqlite3.connect(DB)
        cur = conn.cursor()

        # 過去テスト成功率
        cur.execute(
            "SELECT COUNT(*), SUM(CASE WHEN status IN ('pass','fixed') THEN 1 ELSE 0 END) "
            "FROM test_sessions WHERE project = ? AND ts >= datetime('now','-90 days')",
            (project,))
        row = cur.fetchone()
        test_total, test_pass = (row[0] or 0), (row[1] or 0)
        test_reward = test_pass / max(test_total, 1)

        # 過去レビュースコア平均
        cur.execute(
            "SELECT AVG(final_score) FROM review_sessions "
            "WHERE project = ? AND final_score IS NOT NULL AND ts >= datetime('now','-90 days')",
            (project,))
        avg_review = cur.fetchone()[0]
        review_reward = (avg_review or 50) / 100.0

        # 過去dev_sessions成功率
        cur.execute(
            "SELECT COUNT(*), SUM(CASE WHEN status='pass' THEN 1 ELSE 0 END) "
            "FROM dev_sessions WHERE project = ? AND ts >= datetime('now','-90 days')",
            (project,))
        row = cur.fetchone()
        dev_total, dev_pass = (row[0] or 0), (row[1] or 0)
        history_reward = dev_pass / max(dev_total, 1)

        conn.close()

        # DRS = α×test + β×review + δ×history (entropy=0 at this stage)
        drs = 0.35 * test_reward + 0.25 * review_reward + 0.15 * 0.5 + 0.25 * history_reward
        return round(drs, 4)
    except Exception:
        return 0.5


# ── DQS: Composite Score ────────────────────────────────────

def normalize(value: float, low: float, high: float) -> float:
    """Normalize to 0.0-1.0 range."""
    if high <= low:
        return 0.5
    return max(0.0, min(1.0, (value - low) / (high - low)))


def compute_dqs(cdi: float, se: float, cls_max: int, crs: float, drs: float) -> float:
    """5軸統合DQS。0.0-1.0 (1.0=best)。"""
    # CDI: 0.55-0.75 が理想。0.4以下/0.85以上はペナルティ
    cdi_norm = normalize(cdi, 0.3, 0.75)
    if cdi > 0.80:
        cdi_norm *= 0.8  # 過圧縮ペナルティ

    # SE: 低い方が良い (2.0-6.0 typical range)
    se_norm = normalize(6.0 - se, 0.0, 4.0)

    # CLS: 15以下が目標
    cls_norm = normalize(30 - cls_max, 0, 30)

    # CRS: 低い方が良い (0-2.0 typical)
    crs_norm = normalize(2.0 - crs, 0.0, 2.0)

    dqs = (W_CDI * cdi_norm + W_SE * se_norm + W_CLS * cls_norm +
           W_CRS * crs_norm + W_DRS * drs)
    return round(max(0.0, min(1.0, dqs)), 4)


def grade(dqs: float) -> str:
    if dqs >= 0.85:
        return "Excellent"
    elif dqs >= 0.70:
        return "Good"
    elif dqs >= 0.50:
        return "Needs Work"
    else:
        return "Poor"


# ── File Analysis ───────────────────────────────────────────

def detect_lang(filepath: str) -> str:
    ext = Path(filepath).suffix.lower()
    return {
        ".py": "python", ".ts": "typescript", ".tsx": "typescript",
        ".js": "javascript", ".jsx": "javascript", ".rs": "rust",
        ".go": "go", ".swift": "swift", ".rb": "ruby",
    }.get(ext, "auto")


def analyze_file(filepath: str, project: str = "") -> dict:
    """単一ファイルのDQS計測。"""
    try:
        source = open(filepath, encoding="utf-8", errors="replace").read()
    except Exception as e:
        return {"error": str(e), "file": filepath}

    lang = detect_lang(filepath)
    loc = source.count('\n') + 1

    cdi = measure_cdi(source)
    se = measure_se(source, lang)
    cls_data = measure_cls_file(source)
    crs_data = measure_crs(filepath)
    drs = measure_drs(project)

    dqs = compute_dqs(cdi, se, cls_data["cls_max"], crs_data["crs"], drs)

    return {
        "file": filepath,
        "loc": loc,
        "lang": lang,
        "cdi": cdi,
        "se": se,
        **cls_data,
        **crs_data,
        "drs": drs,
        "dqs": dqs,
        "grade": grade(dqs),
    }


def analyze_dir(dirpath: str, project: str = "") -> list[dict]:
    """ディレクトリの全ソースファイルを計測。"""
    extensions = {'.py', '.ts', '.tsx', '.js', '.jsx', '.rs', '.go', '.swift', '.rb'}
    skip_dirs = {'node_modules', '.next', 'dist', '.git', '__pycache__', 'venv', '.venv'}
    results = []

    for root, dirs, files in os.walk(dirpath):
        dirs[:] = [d for d in dirs if d not in skip_dirs]
        for f in files:
            if Path(f).suffix.lower() in extensions:
                fp = os.path.join(root, f)
                results.append(analyze_file(fp, project))

    return sorted(results, key=lambda x: x.get("dqs", 0))


def analyze_diff(project: str = "") -> list[dict]:
    """git diff対象ファイルのみ計測。"""
    try:
        result = subprocess.run(
            ["git", "diff", "--name-only", "HEAD"],
            capture_output=True, text=True, timeout=5)
        staged = subprocess.run(
            ["git", "diff", "--cached", "--name-only"],
            capture_output=True, text=True, timeout=5)
        files = set(result.stdout.strip().split('\n') + staged.stdout.strip().split('\n'))
        files = {f for f in files if f and Path(f).suffix.lower() in
                 {'.py', '.ts', '.tsx', '.js', '.jsx', '.rs', '.go', '.swift'}}
    except Exception:
        return []

    return [analyze_file(f, project) for f in files if os.path.exists(f)]


# ── DB Recording ────────────────────────────────────────────

def record_measurement(project: str, results: list[dict]):
    """DQS計測結果をquality_metricsテーブルに記録。"""
    if not os.path.exists(DB):
        return
    conn = sqlite3.connect(DB)
    cur = conn.cursor()

    # Ensure table exists
    cur.execute("""CREATE TABLE IF NOT EXISTS quality_metrics (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ts TEXT NOT NULL DEFAULT (datetime('now')),
        project TEXT NOT NULL,
        file TEXT NOT NULL,
        loc INTEGER,
        cdi REAL, se REAL, cls_max INTEGER, crs REAL, drs REAL, dqs REAL,
        grade TEXT,
        metrics_json TEXT
    )""")
    cur.execute("CREATE INDEX IF NOT EXISTS idx_qm_project ON quality_metrics(project)")
    cur.execute("CREATE INDEX IF NOT EXISTS idx_qm_dqs ON quality_metrics(dqs)")

    for r in results:
        if "error" in r:
            continue
        cur.execute(
            "INSERT INTO quality_metrics(project,file,loc,cdi,se,cls_max,crs,drs,dqs,grade,metrics_json) "
            "VALUES(?,?,?,?,?,?,?,?,?,?,?)",
            (project, r["file"], r.get("loc", 0),
             r["cdi"], r["se"], r["cls_max"], r["crs"], r["drs"], r["dqs"], r["grade"],
             json.dumps(r)))

    conn.commit()
    conn.close()


# ── CLI ─────────────────────────────────────────────────────

def format_result(r: dict) -> str:
    if "error" in r:
        return f"  ERROR: {r['file']} — {r['error']}"
    g = r["grade"]
    bar = "=" * int(r["dqs"] * 20) + "-" * (20 - int(r["dqs"] * 20))
    return (f"  {r['file']}\n"
            f"    DQS: {r['dqs']:.2f} [{bar}] {g}\n"
            f"    CDI={r['cdi']:.2f}  SE={r['se']:.2f}  CLS={r['cls_max']}  "
            f"CRS={r['crs']:.3f}  DRS={r['drs']:.2f}\n"
            f"    LOC={r['loc']}  funcs={r['functions']}  nesting={r['max_nesting']}  "
            f"churn={r['churn_30d']}")


def main():
    args = sys.argv[1:]
    output_json = "--json" in args
    args = [a for a in args if a != "--json"]

    project = ""
    if "--project" in args:
        idx = args.index("--project")
        project = args[idx + 1] if idx + 1 < len(args) else ""
        args = args[:idx] + args[idx+2:]

    if not project:
        try:
            project = subprocess.run(
                ["git", "rev-parse", "--show-toplevel"],
                capture_output=True, text=True, timeout=3
            ).stdout.strip().split('/')[-1]
        except Exception:
            project = os.path.basename(os.getcwd())

    if "--diff" in args:
        results = analyze_diff(project)
    elif args:
        target = args[0]
        if os.path.isdir(target):
            results = analyze_dir(target, project)
        elif os.path.isfile(target):
            results = [analyze_file(target, project)]
        else:
            print(f"Not found: {target}", file=sys.stderr)
            sys.exit(1)
    else:
        results = analyze_dir(".", project)

    # Record to DB
    if results:
        record_measurement(project, results)

    if output_json:
        print(json.dumps(results, indent=2))
    else:
        avg_dqs = sum(r.get("dqs", 0) for r in results if "error" not in r) / max(len(results), 1)
        print(f"{'=' * 50}")
        print(f"  DQS Report — {project}")
        print(f"  Files: {len(results)}  Avg DQS: {avg_dqs:.2f} [{grade(avg_dqs)}]")
        print(f"{'=' * 50}")
        for r in results:
            print(format_result(r))
        print(f"{'=' * 50}")

        # Warnings
        for r in results:
            if "error" in r:
                continue
            if r["cls_max"] > 15:
                print(f"  WARNING: {r['file']} CLS={r['cls_max']} > 15 — 関数分割を推奨")
            if r["dqs"] < 0.50:
                print(f"  WARNING: {r['file']} DQS={r['dqs']:.2f} — 再設計を推奨")
            if r.get("max_nesting", 0) > 4:
                print(f"  WARNING: {r['file']} nesting={r['max_nesting']} > 4 — フラット化を推奨")


if __name__ == "__main__":
    main()
