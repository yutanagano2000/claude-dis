# Reference: Codebase Mapper (Deep Instructions)

## 0. Scope
- Target root: <TARGET_DIR>
- Default excludes: node_modules/, dist/, build/, .next/, .nuxt/, coverage/, vendor/, generated/, *.min.*
- Optional use cases: <USE_CASE_1>, <USE_CASE_2>

## 1. Guarantees (What this skill must deliver)
- Bird's-eye map (what it provides/depends on, where entry points are)
- Responsibility map (main modules: role / public surface / key deps)
- Dependency graph (static, top-N compressed)
- I/O and dataflow (inbound → orchestration → outbound)
- Execution path for up to 2 representative use cases
- Risk candidates (cycles, boundary breaks, god modules, duplicated I/O, config landmines)
- Practical next-step refactor suggestions (non-dogmatic)

## 2. Non-goals
- No claim of complete runtime graph
- No "correct architecture" verdicts
- No file-by-file full summaries
- No secret disclosure

## 3. Fact vs Hypothesis rule (must never mix)
### Fact
- imports/requires/exports
- explicit routes/handlers
- explicit I/O client calls
- explicit config keys used (without values)

### Hypothesis
- dynamic DI, reflection, string-based routing, plugin loading, feature flags
- label: High/Med/Low + why

## 4. Method (Top-down, compressed)
### 4.1 Entry points
- package/pyproject/go.mod/Cargo scripts
- main/index/server/app
- route definitions
- worker/cron/queue consumer roots
- tests (optional)

### 4.2 Dependencies (static)
- module imports and major call edges
- prioritize "important nodes" only

### 4.3 I/O extraction
- inbound: HTTP/CLI/cron/queue
- outbound: DB/HTTP/FS/queue
- env/config references (mask)

### 4.4 Layer classification (behavior-based)
- Pure / Orchestration / I/O
- flag "mixed responsibilities" as a risk candidate

### 4.5 Importance scoring (compress to top 20 by default)
- reachability from entry points
- in/out degree hubs
- proximity to I/O boundaries
- size/complexity proxies

## 5. Artifacts to produce
- ARCHITECTURE.md
- DEPENDENCIES.mmd
- DATAFLOW.mmd
- ONBOARDING.md
- RISKS.md

## 6. Quality gate (acceptance criteria)
- entry points listed (or reason why not)
- top modules have role + evidence
- Fact and Hypothesis are clearly separated
- diagrams are readable (compressed)
- onboarding path is actionable (30m/2h/1d)
