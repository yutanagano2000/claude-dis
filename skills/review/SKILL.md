---
name: review
description: Full 3-AI review loop (Codex→Gemini→Claude adversarial). Runs up to 5 iterations with stagnation detection. Integrates with DIS knowledge base for solution lookup and pattern learning. Use when user says /review, review code, full review, or 3AI review.
allowed-tools: Bash, Read, Write, Edit, Glob, Grep
---

# Unified Review System — 3-AI Loop + DIS Integration

## Scoring (80+ to pass)

| Category | Points | Focus |
|----------|--------|-------|
| Security | 25 | XSS, CSRF, SQLi, auth |
| Correctness | 25 | Bugs, logic, edge cases |
| Performance | 20 | N+1, re-renders, memory |
| Maintainability | 20 | Readability, DRY, SRP |
| Testing | 10 | Testability, coverage |

## Instructions

<review-skill>
Execute the following workflow when this skill is invoked.

### Phase 0: Initialize

1. Check for hook queue handoff:
```bash
if [ -f /tmp/review-queue.json ]; then
  cat /tmp/review-queue.json
fi
```
If queue exists, load it — display previous hook score and known solutions.

2. Load DIS patterns for the current project:
```bash
PROJECT=$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")
sqlite3 ~/.claude/intelligence/dev.db \
  "SELECT pattern, solution FROM patterns WHERE score >= 2.0 ORDER BY score DESC LIMIT 10;"
```
Display any relevant patterns as context.

3. Initialize tracking variables:
- `iteration = 0`
- `max_iterations = 5`
- `score_history = []`
- `models_used = []`
- `issues_fixed_total = 0`
- `start_time = now`

4. **DQS Baseline** — measure quality before review changes:
```bash
DQS_BASELINE=$(python3 ~/.claude/intelligence/scripts/measure-quality.py --diff --project "$PROJECT" --json 2>/dev/null || echo "[]")
```
Parse average DQS as `DQS_BEFORE`.

### Phase 1: Review & Score (per iteration)

Run review with 3-level fallback via shared library:
```bash
source ~/.claude/hooks/lib/review-utils.sh
REVIEW_OUTPUT=$(run_review "skill" 90)
```

**Fallback order:**
1. `codex review --uncommitted` (primary)
2. `gemini -p` with diff (if Codex fails/rate-limited)
3. Claude adversarial self-review (if both fail)

**For Claude adversarial mode** (when output contains `__CLAUDE_ADVERSARIAL_NEEDED__`):
Act as a HOSTILE code reviewer. Assume bugs exist. Find EVERY issue.
Score format: `Security N/25, Correctness N/25, Performance N/20, Maintainability N/20, Testing N/10`
Issues format: `[CRITICAL|HIGH|MEDIUM|LOW] file:line - description`
Score 80+ should be RARE. Be ruthless. Review the uncommitted changes.

Extract score:
```bash
SCORE_JSON=$(echo "$REVIEW_OUTPUT" | source ~/.claude/hooks/lib/review-utils.sh && extract_score_json)
```

Append score to `score_history[]`. If score >= 80 → go to Phase 4.

**Stagnation detection:** If last 2 scores are identical → stop loop, status = "stagnant".

### Phase 2: Root Cause Analysis

Delegate analysis to a DIFFERENT AI than the Phase 1 reviewer:

| Phase 1 Reviewer | Phase 2 Analyzer | Method |
|-------------------|-------------------|--------|
| Codex | Gemini | `gemini -p "Analyze these review findings..."` |
| Gemini | Claude (normal) | Claude analyzes issues directly |
| Claude adversarial | Skip | Already Claude's perspective |

Analyzer output: prioritized fix list with concrete code examples.

### Phase 3: Fix Issues (Claude native)

Fix issues in priority order: CRITICAL → HIGH → MEDIUM.

For each issue:
1. Read the target file
2. Apply the fix using Edit tool
3. Report what was changed

Track `issues_fixed_total`.

After fixing, return to Phase 1 for re-scoring.

### Phase 4: Completion & DIS Persistence

1. **Solutions INSERT** — for each issue that was fixed successfully:
```bash
sqlite3 ~/.claude/intelligence/dev.db "INSERT INTO solutions(error_pattern, solution, project, score, last_used) VALUES('<normalized_issue>', '<fix_description>', '${PROJECT}', 2.0, datetime('now'));"
```

2. **Remaining issues → events INSERT:**
```bash
source ~/.claude/hooks/lib/review-utils.sh
insert_review_events "$PROJECT" '<remaining_issues_json>'
```

3. **Review session INSERT:**
```bash
source ~/.claude/hooks/lib/review-utils.sh
insert_review_session "$PROJECT" "skill" $INITIAL_SCORE $FINAL_SCORE \
  $ITERATIONS "$SCORE_HISTORY_JSON" $ISSUES_FOUND $ISSUES_FIXED \
  $CRITICAL $HIGH $MEDIUM $LOW \
  "$STATUS" "$MODELS_USED_JSON" $DURATION_SECONDS
```

4. **Aggregate & promote check:**
```bash
python3 ~/.claude/intelligence/scripts/aggregate.py
# Check promotion candidates
sqlite3 ~/.claude/intelligence/dev.db \
  "SELECT pattern, score, frequency FROM solutions WHERE score >= 3.0 AND success_count >= 3 AND error_pattern NOT IN (SELECT pattern FROM patterns) LIMIT 5;"
```
If candidates found, promote them to patterns table.

5. **DQS After** — measure quality after review fixes:
```bash
DQS_AFTER_JSON=$(python3 ~/.claude/intelligence/scripts/measure-quality.py --diff --project "$PROJECT" --json 2>/dev/null || echo "[]")
```
Calculate `DQS_AFTER` and `DQS_DELTA = DQS_AFTER - DQS_BEFORE`.

6. **RL Reward** — compute reinforcement score:
```bash
python3 ~/.claude/intelligence/scripts/self-improve.py suggest "$PROJECT" 2>/dev/null || true
```

7. **Cleanup:**
```bash
rm -f /tmp/review-queue.json
```

8. **Final Report:**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Review Complete
   Score: {initial} → {final} | Iterations: {n}
   Issues: {found} found, {fixed} fixed
   Models: {models_used}
   Status: {pass|fail|stagnant}
   DQS: {before} → {after} (delta: {delta})
   DIS: {n} solutions recorded, {n} events logged
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### Full Codebase Mode (`/review --full`)

When `--full` flag is specified:

1. Collect all source files:
```bash
find . -type f \( -name "*.ts" -o -name "*.tsx" -o -name "*.py" -o -name "*.swift" -o -name "*.go" -o -name "*.rs" \) \
  -not -path "*/node_modules/*" -not -path "*/.next/*" -not -path "*/dist/*" -not -path "*/.git/*" \
  | head -100
```

2. Split into batches of 3 files each.

3. For each batch, run Phase 1-4 on those specific files (use `codex review <files>`).

4. Save state to `/tmp/review-state.json` after each batch for `--resume` support.

5. Final summary across all batches.

### Display Format

Each iteration:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Review Loop: Iteration {n}/5
   Previous: {prev_score} → Current: {score} | Target: 80+
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[CRITICAL] file:line - description
[HIGH] file:line - description
[MEDIUM] file:line - description
```

### Exit Conditions

| Condition | Status | Action |
|-----------|--------|--------|
| Score >= 80 | pass | Complete |
| 5 iterations | fail | Force stop, report |
| Same score 2x | stagnant | Stop, suggest manual review |
| All reviewers fail | timeout | Report, no score |

### Rules for Review Output

Every criticism MUST include:
- **Problem**: What is wrong
- **Reason**: Why it matters
- **Fix**: Concrete code suggestion

Must mention at least one positive aspect per review.
</review-skill>
