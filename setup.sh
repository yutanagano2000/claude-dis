#!/bin/bash
# DIS (Development Intelligence System) - Setup Script
# Usage: git clone <repo> && cd claude-dis && ./setup.sh
set -euo pipefail

CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo ""
echo "========================================="
echo "  DIS - Development Intelligence System"
echo "  Setup Script"
echo "========================================="
echo ""

# ─── Step 1: Check prerequisites ───

info "Checking prerequisites..."

MISSING=()
command -v python3 >/dev/null 2>&1 || MISSING+=("python3")
command -v sqlite3 >/dev/null 2>&1 || MISSING+=("sqlite3")
command -v jq      >/dev/null 2>&1 || MISSING+=("jq")
command -v git     >/dev/null 2>&1 || MISSING+=("git")
command -v bc      >/dev/null 2>&1 || MISSING+=("bc")

if [ ${#MISSING[@]} -gt 0 ]; then
  error "Missing required tools: ${MISSING[*]}"
  echo ""
  echo "  Install with:"
  echo "    macOS:  brew install ${MISSING[*]}"
  echo "    Ubuntu: sudo apt install ${MISSING[*]}"
  echo ""
  exit 1
fi
ok "All prerequisites found"

# Check Python version
PY_VER=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
PY_MAJOR=$(echo "$PY_VER" | cut -d. -f1)
PY_MINOR=$(echo "$PY_VER" | cut -d. -f2)
if [ "$PY_MAJOR" -lt 3 ] || ([ "$PY_MAJOR" -eq 3 ] && [ "$PY_MINOR" -lt 6 ]); then
  error "Python 3.6+ required (found $PY_VER)"
  exit 1
fi
ok "Python $PY_VER"

# Check optional tools
if command -v codex >/dev/null 2>&1; then
  ok "Codex CLI found (3-AI review enabled)"
else
  warn "Codex CLI not found - /review will use Claude-only mode"
  warn "  Install: npm install -g @openai/codex"
fi

if command -v gemini >/dev/null 2>&1; then
  ok "Gemini CLI found (3-AI review enabled)"
else
  warn "Gemini CLI not found - /review will use fallback mode"
  warn "  Install: npm install -g @anthropic-ai/gemini-cli  (or equivalent)"
fi

# ─── Step 2: Check Claude Code ───

if [ ! -d "$CLAUDE_HOME" ]; then
  warn "$CLAUDE_HOME does not exist. Creating it..."
  mkdir -p "$CLAUDE_HOME"
fi

# ─── Step 3: Backup existing files ───

BACKUP_DIR="$CLAUDE_HOME/.dis-backup-$(date +%Y%m%d-%H%M%S)"

has_existing() {
  [ -d "$CLAUDE_HOME/skills" ] || [ -d "$CLAUDE_HOME/hooks" ] || [ -d "$CLAUDE_HOME/intelligence" ]
}

if has_existing; then
  warn "Existing DIS files detected. Creating backup..."
  mkdir -p "$BACKUP_DIR"
  for dir in skills hooks intelligence commands; do
    if [ -d "$CLAUDE_HOME/$dir" ]; then
      cp -r "$CLAUDE_HOME/$dir" "$BACKUP_DIR/$dir" 2>/dev/null || true
    fi
  done
  ok "Backup saved to $BACKUP_DIR"
fi

# ─── Step 4: Install DIS files ───

info "Installing DIS files to $CLAUDE_HOME ..."

# Create directory structure
mkdir -p "$CLAUDE_HOME/hooks/lib"
mkdir -p "$CLAUDE_HOME/intelligence/scripts"
mkdir -p "$CLAUDE_HOME/commands"
mkdir -p "$CLAUDE_HOME/logs"

# Copy hooks
cp -r "$SCRIPT_DIR/hooks/"* "$CLAUDE_HOME/hooks/"
ok "Hooks installed"

# Copy intelligence (scripts + init)
cp "$SCRIPT_DIR/intelligence/init-db.sh" "$CLAUDE_HOME/intelligence/"
cp "$SCRIPT_DIR/intelligence/scripts/"* "$CLAUDE_HOME/intelligence/scripts/"
ok "Intelligence scripts installed"

# Copy skills
for skill_dir in "$SCRIPT_DIR/skills/"*/; do
  skill_name=$(basename "$skill_dir")
  mkdir -p "$CLAUDE_HOME/skills/$skill_name"
  cp -r "$skill_dir"* "$CLAUDE_HOME/skills/$skill_name/"
done
ok "Skills installed ($(ls -d "$SCRIPT_DIR/skills/"*/ | wc -l | tr -d ' ') skills)"

# Copy commands
cp "$SCRIPT_DIR/commands/"* "$CLAUDE_HOME/commands/" 2>/dev/null || true
ok "Commands installed"

# Copy codex-review-config
cp "$SCRIPT_DIR/codex-review-config.json" "$CLAUDE_HOME/" 2>/dev/null || true

# Make scripts executable
chmod +x "$CLAUDE_HOME/hooks/"*.sh
chmod +x "$CLAUDE_HOME/hooks/lib/"*.sh
chmod +x "$CLAUDE_HOME/intelligence/init-db.sh"
chmod +x "$CLAUDE_HOME/intelligence/scripts/"*.sh
ok "Permissions set"

# ─── Step 5: Initialize database ───

info "Initializing database..."
bash "$CLAUDE_HOME/intelligence/init-db.sh"
ok "Database ready"

# ─── Step 6: Settings merge guidance ───

echo ""
echo "========================================="
echo "  Settings Configuration"
echo "========================================="
echo ""

SETTINGS_FILE="$CLAUDE_HOME/settings.json"

if [ -f "$SETTINGS_FILE" ]; then
  info "Existing settings.json found."
  echo ""
  echo "  DIS requires hooks in settings.json to work."
  echo "  The required hooks config is in: settings.dis.json"
  echo ""
  echo "  To merge manually:"
  echo "    1. Open $SETTINGS_FILE"
  echo "    2. Add the 'hooks' section from $SCRIPT_DIR/settings.dis.json"
  echo ""
  read -rp "  Auto-merge hooks into settings.json? [y/N] " merge_answer
  if [[ "$merge_answer" =~ ^[yY]$ ]]; then
    # Merge hooks using jq
    MERGED=$(jq -s '.[0] * {hooks: .[1].hooks}' "$SETTINGS_FILE" "$SCRIPT_DIR/settings.dis.json")
    echo "$MERGED" > "$SETTINGS_FILE"
    ok "Hooks merged into settings.json"
  else
    warn "Skipped. Remember to add hooks manually."
  fi
else
  info "No settings.json found. Creating from DIS template..."
  # Create minimal settings with DIS hooks
  jq 'del(._comment)' "$SCRIPT_DIR/settings.dis.json" > "$SETTINGS_FILE"
  ok "settings.json created"
fi

# ─── Step 7: Optional — Turso cloud sync ───

echo ""
if [ ! -f "$CLAUDE_HOME/intelligence/.turso-env" ]; then
  echo "  [Optional] Cloud DB sync with Turso:"
  echo "    cp $SCRIPT_DIR/intelligence/.turso-env.sample $CLAUDE_HOME/intelligence/.turso-env"
  echo "    # Edit with your Turso credentials"
  echo ""
fi

# ─── Done ───

echo ""
echo "========================================="
echo -e "  ${GREEN}DIS Setup Complete!${NC}"
echo "========================================="
echo ""
echo "  Available skills:"
echo "    /dev <requirement>    Full dev pipeline"
echo "    /test <perspective>   Auto test generation"
echo "    /review               3-AI code review"
echo "    /feedback <note>      Record learnings"
echo "    /kb-lookup            Search past solutions"
echo "    /que <question>       Track dev questions"
echo "    /parallel-tasks       Parallel subtasks"
echo "    /industry-check       AI industry updates"
echo "    /kb-maintain          DB maintenance"
echo ""
echo "  Quick start:"
echo "    cd your-project && claude"
echo "    > /dev Add user validation"
echo ""
