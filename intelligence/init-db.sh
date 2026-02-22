#!/bin/bash
# DIS (Development Intelligence System) - DB初期化
set -euo pipefail

DB="$HOME/.claude/intelligence/dev.db"

## Migrations (既存DBへの安全なテーブル追加)
if [ -f "$DB" ]; then
  echo "DB already exists: $DB — running migrations..."

  # test_sessions テーブル (v2: /test スキル用)
  sqlite3 "$DB" <<'MIGRATE'
CREATE TABLE IF NOT EXISTS test_sessions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ts TEXT NOT NULL DEFAULT (datetime('now')),
  project TEXT NOT NULL,
  perspective TEXT NOT NULL,
  test_type TEXT NOT NULL,
  target_files TEXT,
  test_file TEXT,
  iterations INTEGER DEFAULT 1,
  max_iterations INTEGER DEFAULT 3,
  status TEXT DEFAULT 'pending',
  pass_count INTEGER DEFAULT 0,
  fail_count INTEGER DEFAULT 0,
  error_output TEXT,
  error_pattern TEXT,
  fix_history TEXT,
  score REAL DEFAULT 1.0,
  used_past_solutions TEXT,
  duration_seconds INTEGER,
  coverage_before REAL,
  coverage_after REAL
);
CREATE INDEX IF NOT EXISTS idx_test_project ON test_sessions(project);
CREATE INDEX IF NOT EXISTS idx_test_error ON test_sessions(error_pattern);
CREATE INDEX IF NOT EXISTS idx_test_score ON test_sessions(score DESC);
MIGRATE

  # dev_sessions テーブル (v3: /dev スキル用)
  sqlite3 "$DB" <<'MIGRATE2'
CREATE TABLE IF NOT EXISTS dev_sessions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ts TEXT NOT NULL DEFAULT (datetime('now')),
  project TEXT NOT NULL,
  requirement TEXT NOT NULL,
  phase TEXT DEFAULT 'prep',
  status TEXT DEFAULT 'running',
  files_changed TEXT,
  lines_added INTEGER DEFAULT 0,
  lines_removed INTEGER DEFAULT 0,
  test_session_id INTEGER,
  test_status TEXT,
  review_score_initial INTEGER,
  review_score_final INTEGER,
  review_iterations INTEGER DEFAULT 0,
  dis_solutions_used TEXT,
  dis_feedback_used TEXT,
  dis_patterns_used TEXT,
  dis_new_feedback TEXT,
  score REAL DEFAULT 1.0,
  duration_seconds INTEGER,
  total_iterations INTEGER DEFAULT 1
);
CREATE INDEX IF NOT EXISTS idx_dev_project ON dev_sessions(project);
CREATE INDEX IF NOT EXISTS idx_dev_status ON dev_sessions(status);
CREATE INDEX IF NOT EXISTS idx_dev_score ON dev_sessions(score DESC);
MIGRATE2

  # questions テーブル (v4: /que スキル用)
  sqlite3 "$DB" <<'MIGRATE3'
CREATE TABLE IF NOT EXISTS questions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ts TEXT NOT NULL DEFAULT (datetime('now')),
  project TEXT,
  question TEXT NOT NULL,
  context TEXT,
  answer TEXT,
  tags TEXT,
  status TEXT DEFAULT 'open',
  resolved_at TEXT,
  score REAL DEFAULT 1.0,
  last_seen TEXT DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_questions_project ON questions(project);
CREATE INDEX IF NOT EXISTS idx_questions_status ON questions(status);
CREATE INDEX IF NOT EXISTS idx_questions_score ON questions(score DESC);
MIGRATE3

  # quality_metrics テーブル + dev_sessions DQSカラム (v5: DQS品質計測用)
  sqlite3 "$DB" <<'MIGRATE4'
CREATE TABLE IF NOT EXISTS quality_metrics (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ts TEXT NOT NULL DEFAULT (datetime('now')),
  project TEXT NOT NULL,
  file TEXT NOT NULL,
  loc INTEGER,
  cdi REAL,
  se REAL,
  cls_max INTEGER,
  crs REAL,
  drs REAL,
  dqs REAL,
  grade TEXT,
  metrics_json TEXT
);
CREATE INDEX IF NOT EXISTS idx_qm_project ON quality_metrics(project);
CREATE INDEX IF NOT EXISTS idx_qm_dqs ON quality_metrics(dqs);
MIGRATE4

  # dev_sessions への DQS カラム追加 (安全にALTER)
  sqlite3 "$DB" "SELECT dqs_before FROM dev_sessions LIMIT 0;" 2>/dev/null || \
    sqlite3 "$DB" "ALTER TABLE dev_sessions ADD COLUMN dqs_before REAL;"
  sqlite3 "$DB" "SELECT dqs_after FROM dev_sessions LIMIT 0;" 2>/dev/null || \
    sqlite3 "$DB" "ALTER TABLE dev_sessions ADD COLUMN dqs_after REAL;"
  sqlite3 "$DB" "SELECT dqs_delta FROM dev_sessions LIMIT 0;" 2>/dev/null || \
    sqlite3 "$DB" "ALTER TABLE dev_sessions ADD COLUMN dqs_delta REAL;"
  sqlite3 "$DB" "SELECT metrics_json FROM dev_sessions LIMIT 0;" 2>/dev/null || \
    sqlite3 "$DB" "ALTER TABLE dev_sessions ADD COLUMN metrics_json TEXT;"

  echo "Migrations complete. Tables:"
  sqlite3 "$DB" ".tables"
  exit 0
fi

sqlite3 "$DB" <<'SQL'
CREATE TABLE events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ts TEXT NOT NULL DEFAULT (datetime('now')),
  type TEXT NOT NULL,
  cmd TEXT,
  error TEXT,
  cwd TEXT,
  project TEXT,
  resolved INTEGER DEFAULT 0
);

CREATE TABLE solutions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ts TEXT NOT NULL DEFAULT (datetime('now')),
  error_pattern TEXT NOT NULL,
  solution TEXT NOT NULL,
  files TEXT,
  project TEXT,
  success_count INTEGER DEFAULT 1,
  fail_count INTEGER DEFAULT 0,
  score REAL DEFAULT 1.0,
  last_used TEXT
);

CREATE TABLE patterns (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ts TEXT NOT NULL DEFAULT (datetime('now')),
  pattern TEXT NOT NULL,
  description TEXT NOT NULL,
  solution TEXT NOT NULL,
  frequency INTEGER DEFAULT 0,
  score REAL DEFAULT 1.0,
  promoted_to_memory INTEGER DEFAULT 0,
  last_seen TEXT
);

CREATE TABLE sessions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ts TEXT NOT NULL DEFAULT (datetime('now')),
  project TEXT,
  files_changed INTEGER DEFAULT 0,
  errors_encountered INTEGER DEFAULT 0,
  errors_resolved INTEGER DEFAULT 0,
  duration_turns INTEGER DEFAULT 0
);

CREATE TABLE industry_feeds (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ts TEXT NOT NULL DEFAULT (datetime('now')),
  source TEXT NOT NULL,
  title TEXT NOT NULL,
  url TEXT NOT NULL UNIQUE,
  summary TEXT,
  fetched_at TEXT,
  analyzed INTEGER DEFAULT 0,
  relevant INTEGER DEFAULT 0,
  action_taken TEXT
);

CREATE INDEX idx_events_project ON events(project);
CREATE INDEX idx_events_type ON events(type);
CREATE INDEX idx_events_error ON events(error);
CREATE INDEX idx_solutions_pattern ON solutions(error_pattern);
CREATE INDEX idx_solutions_score ON solutions(score DESC);
CREATE INDEX idx_patterns_score ON patterns(score DESC);
CREATE TABLE feedback (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ts TEXT NOT NULL DEFAULT (datetime('now')),
  category TEXT NOT NULL,
  wrong_approach TEXT NOT NULL,
  correct_approach TEXT NOT NULL,
  context TEXT,
  project TEXT,
  scope TEXT DEFAULT 'project',
  confirmation_count INTEGER DEFAULT 1,
  score REAL DEFAULT 1.5,
  last_seen TEXT DEFAULT (datetime('now'))
);

CREATE INDEX idx_events_project ON events(project);
CREATE INDEX idx_events_type ON events(type);
CREATE INDEX idx_events_error ON events(error);
CREATE INDEX idx_solutions_pattern ON solutions(error_pattern);
CREATE INDEX idx_solutions_score ON solutions(score DESC);
CREATE INDEX idx_patterns_score ON patterns(score DESC);
CREATE INDEX idx_feeds_source ON industry_feeds(source);
CREATE INDEX idx_feeds_analyzed ON industry_feeds(analyzed);
CREATE INDEX idx_feedback_category ON feedback(category);
CREATE INDEX idx_feedback_score ON feedback(score DESC);
CREATE INDEX idx_feedback_project ON feedback(project);
SQL

echo "DB created: $DB"
sqlite3 "$DB" ".tables"
