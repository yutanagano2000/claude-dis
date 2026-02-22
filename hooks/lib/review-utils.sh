#!/bin/bash
# review-utils.sh — 統合レビューシステム共通ユーティリティ
# tri-review.sh (hook) と /review skill の両方が source する

DIS_DB="$HOME/.claude/intelligence/dev.db"
DIS_SCRIPTS="$HOME/.claude/intelligence/scripts"
REVIEW_QUEUE="/tmp/review-queue.json"

# macOS互換 timeout (GNU coreutils不要)
_timeout() {
  local secs="$1"; shift
  if command -v gtimeout &>/dev/null; then
    gtimeout "$secs" "$@"
  elif command -v timeout &>/dev/null; then
    timeout "$secs" "$@"
  else
    # perl fallback (macOS標準)
    perl -e '
      use POSIX ":sys_wait_h";
      my $timeout = shift @ARGV;
      my $pid = fork();
      if ($pid == 0) { exec @ARGV; exit 127; }
      eval {
        local $SIG{ALRM} = sub { kill "TERM", $pid; die "timeout\n"; };
        alarm $timeout;
        waitpid($pid, 0);
        alarm 0;
      };
      if ($@ =~ /timeout/) { waitpid($pid, WNOHANG); exit 124; }
      exit ($? >> 8);
    ' "$secs" "$@"
  fi
}

# ── ユーティリティ ──

count_changed_lines() {
  local stats
  stats=$(git diff --stat 2>/dev/null | tail -1)
  [ -z "$stats" ] && stats=$(git diff --cached --stat 2>/dev/null | tail -1)
  local ins dels
  ins=$(echo "$stats" | grep -oE '[0-9]+ insertion' | grep -oE '[0-9]+' || echo "0")
  dels=$(echo "$stats" | grep -oE '[0-9]+ deletion' | grep -oE '[0-9]+' || echo "0")
  echo $((ins + dels))
}

print_header() {
  local title="$1" detail="$2"
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "$title"
  [ -n "$detail" ] && echo "   $detail"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

print_result() {
  local score="$1" threshold="${2:-80}"
  if [ "$score" = "??" ]; then
    echo "Score: ??/100 (parse failed)"
  elif [ "$score" -ge "$threshold" ]; then
    echo "Score: ${score}/100 PASS"
  else
    echo "Score: ${score}/100 FAIL (threshold: ${threshold})"
  fi
}

get_project_name() {
  basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
}

# ── レビュー実行 (3段フォールバック) ──
# 引数: モード ("hook" or "skill")
# 出力: stdout にレビュー結果、REVIEW_MODELS にモデル名配列 (グローバル)

REVIEW_MODELS="[]"

run_review() {
  local mode="${1:-hook}"
  local timeout_sec="${2:-90}"
  local output=""

  # 1. Codex (Primary)
  if command -v codex &>/dev/null; then
    output=$(_timeout "$timeout_sec" codex review --uncommitted 2>&1) && {
      REVIEW_MODELS='["codex"]'
      echo "$output"
      return 0
    }
    # rate limit / timeout check
    if echo "$output" | grep -qi "rate.limit\|429\|too many"; then
      : # fall through to gemini
    elif [ $? -eq 124 ]; then
      : # timeout, fall through
    fi
  fi

  # 2. Gemini (Fallback)
  if command -v gemini &>/dev/null; then
    local prompt
    prompt="Review this code for issues. Score format: Security N/25, Correctness N/25, Performance N/20, Maintainability N/20, Testing N/10. Issues format: [CRITICAL|HIGH|MEDIUM|LOW] file:line - description. Be thorough."
    local diff_content
    # ソースファイルのみ (生成ファイル・バイナリ除外)
    local src_filter=':(exclude)*.xml' ':(exclude)*.lock' ':(exclude)*.snap'
    diff_content=$(git diff --no-color -- '*.ts' '*.tsx' '*.js' '*.jsx' '*.py' '*.swift' '*.go' '*.rs' '*.css' '*.scss' 2>/dev/null)
    [ -z "$diff_content" ] && diff_content=$(git diff --cached --no-color -- '*.ts' '*.tsx' '*.js' '*.jsx' '*.py' '*.swift' '*.go' '*.rs' '*.css' '*.scss' 2>/dev/null)
    output=$(echo "$diff_content" | _timeout "$timeout_sec" gemini -p "$prompt" 2>&1) && {
      REVIEW_MODELS='["gemini"]'
      echo "$output"
      return 0
    }
  fi

  # 3. Claude adversarial (skill only, not hook)
  if [ "$mode" = "skill" ]; then
    REVIEW_MODELS='["opus-adversarial"]'
    echo "__CLAUDE_ADVERSARIAL_NEEDED__"
    return 0
  fi

  # All failed (hook mode)
  return 1
}

# ── スコア抽出 → JSON ──
# 引数: レビュー出力テキスト (stdin or $1=ファイルパス)

extract_score_json() {
  python3 << 'PYEOF' "$@"
import re, sys, json

if len(sys.argv) > 1 and sys.argv[1] != "-":
    content = open(sys.argv[1]).read()
else:
    content = sys.stdin.read()

# Mode 1: "Security N/25" direct parse
patterns = {
    "security":       (r'[Ss]ecurity\s*[:\s]*(\d+)\s*/\s*25', 25),
    "correctness":    (r'[Cc]orrectness\s*[:\s]*(\d+)\s*/\s*25', 25),
    "performance":    (r'[Pp]erformance\s*[:\s]*(\d+)\s*/\s*20', 20),
    "maintainability":(r'[Mm]aintainability\s*[:\s]*(\d+)\s*/\s*20', 20),
    "testing":        (r'[Tt]esting\s*[:\s]*(\d+)\s*/\s*10', 10),
}
scores = {}
for key, (pat, max_val) in patterns.items():
    matches = re.findall(pat, content)
    if matches:
        scores[key] = min(int(matches[-1]), max_val)

if len(scores) >= 3:
    scores.setdefault("security", 20)
    scores.setdefault("correctness", 20)
    scores.setdefault("performance", 15)
    scores.setdefault("maintainability", 15)
    scores.setdefault("testing", 5)
    total = sum(scores.values())
else:
    # Mode 2: "Total: XX" pattern
    m = re.findall(r'Total:\s*(\d+)', content)
    if m:
        total = int(m[-1])
        scores = {"total_parsed": True}
    else:
        # Mode 3: Keyword deduction
        crit = len(re.findall(r'\[CRITICAL\]|\[P0\]|CRITICAL:', content, re.I))
        high = len(re.findall(r'\[HIGH\]|\[P1\]|\[ERROR\]', content, re.I))
        med  = len(re.findall(r'\[MEDIUM\]|\[P2\]|\[WARNING\]', content, re.I))
        low  = len(re.findall(r'\[LOW\]|\[P3\]', content, re.I))
        total = max(0, 100 - crit*20 - high*10 - med*5 - low*2)
        scores = {"deducted": True}

# Count issues
crit_c = len(re.findall(r'\[CRITICAL\]|\[P0\]|CRITICAL:', content, re.I))
high_c = len(re.findall(r'\[HIGH\]|\[P1\]|\[ERROR\]', content, re.I))
med_c  = len(re.findall(r'\[MEDIUM\]|\[P2\]|\[WARNING\]', content, re.I))
low_c  = len(re.findall(r'\[LOW\]|\[P3\]', content, re.I))

result = {
    "total_score": total,
    "breakdown": scores if "total_parsed" not in scores and "deducted" not in scores else {},
    "critical": crit_c, "high": high_c, "medium": med_c, "low": low_c,
    "issues_total": crit_c + high_c + med_c + low_c,
    "pass": total >= 80
}
print(json.dumps(result))
PYEOF
}

# ── Issue 抽出 → JSON 配列 ──

extract_issues() {
  python3 << 'PYEOF'
import re, sys, json

content = sys.stdin.read()
issues = []

# Pattern: [SEVERITY] file:line - description
for m in re.finditer(
    r'\[(CRITICAL|HIGH|MEDIUM|LOW|P[0-3]|ERROR|WARNING)\]\s*'
    r'(?:([^\s:]+(?:\.\w+)):?(\d+)?)?'
    r'\s*[-–—]?\s*(.+)',
    content, re.IGNORECASE
):
    sev_raw = m.group(1).upper()
    sev_map = {"P0":"critical","P1":"high","P2":"medium","P3":"low",
               "CRITICAL":"critical","HIGH":"high","MEDIUM":"medium","LOW":"low",
               "ERROR":"high","WARNING":"medium"}
    issues.append({
        "severity": sev_map.get(sev_raw, "medium"),
        "file": m.group(2) or "",
        "line": int(m.group(3)) if m.group(3) else 0,
        "description": m.group(4).strip()
    })

print(json.dumps(issues))
PYEOF
}

# ── DIS: issues → events テーブル INSERT ──

insert_review_events() {
  local project="$1"
  local issues_json="$2"  # JSON array string

  python3 - "$project" "$issues_json" << 'PYEOF'
import json, sys, sqlite3, os

DB = os.path.expanduser("~/.claude/intelligence/dev.db")
project = sys.argv[1]
issues = json.loads(sys.argv[2])

conn = sqlite3.connect(DB)
cur = conn.cursor()
for issue in issues:
    sev = issue.get("severity", "medium")
    desc = issue.get("description", "")
    f = issue.get("file", "")
    ln = issue.get("line", 0)
    error_text = f"[{sev}] {f}:{ln} {desc}" if f else f"[{sev}] {desc}"
    cur.execute(
        "INSERT INTO events(type, cmd, error, project) VALUES(?, ?, ?, ?)",
        (f"review_{sev}", "codex review", error_text[:500], project)
    )
conn.commit()
conn.close()
print(f"Inserted {len(issues)} review events")
PYEOF
}

# ── DIS: 既知ソリューション検索 ──

lookup_review_solutions() {
  local issues_json="$1"  # JSON array string

  python3 - "$issues_json" << 'PYEOF'
import json, sys, os
sys.path.insert(0, os.path.expanduser("~/.claude/intelligence/scripts"))
from similarity import find_similar

issues = json.loads(sys.argv[1])
results = []
for issue in issues:
    desc = issue.get("description", "")
    if not desc:
        continue
    similar = find_similar(desc, threshold=0.4, limit=2)
    if similar:
        results.append({
            "issue": desc[:100],
            "solutions": [{"pattern": s["pattern"][:80], "solution": s["solution"][:200], "sim": s["similarity"]} for s in similar]
        })

print(json.dumps(results, ensure_ascii=False))
PYEOF
}

# ── Queue 書き出し ──

write_review_queue() {
  local issues_json="$1"
  local solutions_json="$2"
  local score="$3"
  local project="$4"

  python3 - "$issues_json" "$solutions_json" "$score" "$project" << 'PYEOF'
import json, sys

issues = json.loads(sys.argv[1])
solutions = json.loads(sys.argv[2]) if sys.argv[2] != "[]" else []
score = int(sys.argv[3]) if sys.argv[3].isdigit() else 0
project = sys.argv[4]

queue = {
    "project": project,
    "score": score,
    "issues": issues,
    "known_solutions": solutions,
    "source": "hook"
}
with open("/tmp/review-queue.json", "w") as f:
    json.dump(queue, f, ensure_ascii=False, indent=2)
print(f"Queue written: {len(issues)} issues, {len(solutions)} solutions")
PYEOF
}

# ── DIS: review_sessions INSERT ──

insert_review_session() {
  local project="$1" mode="$2" initial_score="$3" final_score="$4"
  local iterations="$5" score_history="$6" issues_found="$7" issues_fixed="$8"
  local critical="$9" high="${10}" medium="${11}" low="${12}"
  # NOTE: zsh では "status" は読み取り専用変数のため review_status を使用
  local review_status="${13}" models_used="${14}" duration="${15}"

  sqlite3 "$DIS_DB" << SQL
INSERT INTO review_sessions(
  project, mode, initial_score, final_score, iterations, score_history,
  issues_found, issues_fixed, critical_count, high_count, medium_count, low_count,
  status, models_used, duration_seconds
) VALUES(
  '${project}', '${mode}', ${initial_score:-0}, ${final_score:-0},
  ${iterations:-1}, '${score_history:-[]}',
  ${issues_found:-0}, ${issues_fixed:-0},
  ${critical:-0}, ${high:-0}, ${medium:-0}, ${low:-0},
  '${review_status:-completed}', '${models_used:-[]}', ${duration:-0}
);
SQL
}
