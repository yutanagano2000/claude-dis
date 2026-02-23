---
name: mapping-codebase-structure
description: 指定ディレクトリのアーキテクチャをマッピングし、エントリーポイント、静的依存関係、I/Oデータフローを抽出。Markdown/Mermaid形式でドキュメント（アーキテクチャ概要、依存関係グラフ、データフロー、オンボーディングパス、リスク）を生成します。ディレクトリ内のソースコードがどのように接続されているか、各部分が何をしているかを理解したい時や、オンボーディング/アーキテクチャマップを作成したい時に使用します。
---

# Mapping Codebase Structure

## Goal
Create a **fact-based** map of how code under a target directory is structured and connected:
- Structure (layers/boundaries)
- Relationships (static dependencies)
- Connections (I/O and data flow)
- A fast reading path (onboarding)
- Risk candidates (cycles, boundary violations, god modules, etc.)

## Inputs (ask only if missing)
- Target directory path (required)
- Optional: output directory (default: `docs/codebase-map/<slug-of-target>/`)
- Optional: up to 2 representative use-cases (e.g., `signup`, `payment`)

## Outputs
Generate these artifacts (write them to files if allowed; otherwise print them as copy-ready code blocks):
- `ARCHITECTURE.md`
- `DEPENDENCIES.mmd` (Mermaid graph)
- `DATAFLOW.mmd` (Mermaid flow)
- `ONBOARDING.md`
- `RISKS.md`

## Non-goals (hard boundaries)
- Do not claim a 100% accurate runtime graph (dynamic DI, feature flags, reflection, codegen).
- Do not "decide the correct domain design"; only report **risk candidates** with evidence.
- Do not summarize every file; compress to top nodes (default top 20).
- Do not output secrets/tokens/PII (only note existence, never values).

## Core rules (must follow)
1. **Separate Fact vs Hypothesis** in every doc:
   - Fact: only what can be verified statically (imports, explicit routes, explicit I/O calls).
   - Hypothesis: anything dynamic/implicit; label confidence High/Med/Low and why.
2. Every important claim must include **evidence** (file path + symbol/keyword).
3. Prefer top-down mapping: entry points → main modules → I/O boundaries → key flows.
4. If writing files, do so only inside the chosen output directory.

## Procedure (high-level)
1. Detect entry points (server/worker/cli/job/tests) under the target.
2. Build a static dependency graph and identify top modules (hub/reachability/I-O proximity).
3. Extract I/O touchpoints (HTTP/DB/Queue/FS/external APIs) and draw the data flow.
4. Classify modules into layers: Pure / Orchestration / I/O (based on actual behavior).
5. Produce the five outputs using templates under `templates/`.

For full detail, see [reference.md](reference.md).
For usage patterns, see [examples.md](examples.md).
