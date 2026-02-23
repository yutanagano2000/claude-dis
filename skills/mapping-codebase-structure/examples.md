# Examples

## Example 1: Basic mapping
User: "packages/api 以下の全ソースの関係性と役割をマップ化して。"
Assistant action:
- Target: packages/api
- Output dir: docs/codebase-map/packages-api/
- Produce 5 artifacts (ARCHITECTURE / DEPENDENCIES / DATAFLOW / ONBOARDING / RISKS)

## Example 2: With use cases
User: "apps/web の構造を理解したい。ログインと決済の経路も追って。"
Assistant action:
- Target: apps/web
- Use cases: login, payment
- Ensure key flow sections trace those paths with evidence.

## Example 3: Read-only mode
User: "変更はしないで、説明と図だけ出して。"
Assistant action:
- Do not write files; print each artifact as a code block.
